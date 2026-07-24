#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MIHOMO_BIN="${VP_TEST_MIHOMO_BIN:?请通过 VP_TEST_MIHOMO_BIN 指定测试内核}"
EVIDENCE_DIR="${VP_CPU_EVIDENCE_DIR:?请通过 VP_CPU_EVIDENCE_DIR 指定证据目录}"
ACCEPT_HOST="134.209.180.134"
TMP="$(mktemp -d /tmp/vps-node-cpu.XXXXXX)"
CGROUP_BASE="/sys/fs/cgroup/vps-node-cpu-$$"
ACTIVE_PID=""
ACTIVE_CGROUP=""

file_digest() { [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf absent; }
process_ids() {
  ids="$(pidof "$1" 2>/dev/null | tr ' ' '\n' | awk 'NF' | sort -n | tr '\n' ',' | sed 's/,$//' || true)"
  printf '%s' "${ids:-none}"
}
cleanup_case() {
  if [ -n "$ACTIVE_PID" ]; then kill "$ACTIVE_PID" >/dev/null 2>&1 || true; wait "$ACTIVE_PID" 2>/dev/null || true; ACTIVE_PID=""; fi
  if [ -n "$ACTIVE_CGROUP" ] && [ -d "$ACTIVE_CGROUP" ]; then
    [ -w "$ACTIVE_CGROUP/cgroup.kill" ] && printf '1\n' > "$ACTIVE_CGROUP/cgroup.kill" 2>/dev/null || true
    rmdir "$ACTIVE_CGROUP" 2>/dev/null || true
    ACTIVE_CGROUP=""
  fi
}
cleanup_all() { cleanup_case; [ -d "$CGROUP_BASE" ] && rmdir "$CGROUP_BASE" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup_all EXIT HUP INT TERM

[ "$(id -u)" = 0 ] || { printf 'cpu profile acceptance requires root\n' >&2; exit 1; }
[ -x "$MIHOMO_BIN" ] || { printf 'mihomo binary is not executable\n' >&2; exit 1; }
case "$EVIDENCE_DIR" in /*) ;; *) printf 'cpu evidence directory must be absolute\n' >&2; exit 1 ;; esac
observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing real-core cpu test on an unauthorized host\n' >&2; exit 1; }
[ -f /sys/fs/cgroup/cgroup.controllers ] || { printf 'cgroup v2 is required for enforced cpu profiles\n' >&2; exit 1; }
mkdir "$CGROUP_BASE" 2>/dev/null || { printf 'unable to create an isolated cpu cgroup subtree\n' >&2; exit 1; }
grep -qw cpu "$CGROUP_BASE/cgroup.controllers" 2>/dev/null || { printf 'cgroup v2 cpu controller is unavailable\n' >&2; exit 1; }
printf '+cpu\n' > "$CGROUP_BASE/cgroup.subtree_control" 2>/dev/null || { printf 'unable to enable the isolated cgroup cpu controller\n' >&2; exit 1; }

expected_script_sha256="$(awk 'NR==1{print tolower($1)}' "$ROOT/vp.sh.sha256")"
case "$expected_script_sha256" in ''|*[!0-9a-f]*) printf 'vp.sh checksum is invalid\n' >&2; exit 1 ;; esac
[ "${#expected_script_sha256}" -eq 64 ] || { printf 'vp.sh checksum is incomplete\n' >&2; exit 1; }
tested_script_sha256="$(sha256sum "$ROOT/vp.sh" | awk '{print tolower($1)}')"
[ "$tested_script_sha256" = "$expected_script_sha256" ] || { printf 'vp.sh checksum mismatch\n' >&2; exit 1; }
tested_version="$(VP_CONFIG_DIR="$TMP/version-etc" VP_DATA_DIR="$TMP/version-lib" VP_LOG_DIR="$TMP/version-log" sh "$ROOT/vp.sh" version)"

host_cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 1)"
case "$host_cpus" in ''|*[!0-9]*) host_cpus=1 ;; esac
[ "$host_cpus" -ge 1 ] || host_cpus=1
quota_cases="500 999 1000"
[ "$host_cpus" -lt 2 ] || quota_cases="$quota_cases 1001 1500 2000"
[ "$host_cpus" -lt 4 ] || quota_cases="$quota_cases 2001 4000"

formal_mihomo_state_before="$(rc-service mihomo status >/dev/null 2>&1 && printf active || printf inactive)"
formal_tunnel_state_before="$(rc-service cloudflared-tunnel status >/dev/null 2>&1 && printf active || printf inactive)"
formal_mihomo_pids_before="$(process_ids mihomo)"
formal_tunnel_pids_before="$(process_ids cloudflared)"
formal_mihomo_config_before="$(file_digest /etc/mihomo/config.yaml)"
formal_mihomo_init_before="$(file_digest /etc/init.d/mihomo)"
formal_tunnel_init_before="$(file_digest /etc/init.d/cloudflared-tunnel)"
formal_mihomo_nodes_before="$(file_digest /etc/mihomo/nodes.db)"
formal_mihomo_state_file_before="$(file_digest /etc/mihomo/state.env)"
formal_tunnel_token_before="$(file_digest /etc/cloudflared/token)"
formal_mihomo_binary_before="$(file_digest "$MIHOMO_BIN")"

mkdir -p "$EVIDENCE_DIR"
csv_file="$EVIDENCE_DIR/cpu-profiles.csv"
summary_file="$EVIDENCE_DIR/cpu-profiles-summary.txt"
printf 'quota_milli,effective_count,gomaxprocs,gogc,profile,proxy_result,concurrent_success,total_bytes,throttled_events\n' > "$csv_file"

profile_count=0
tested_quotas=""
for quota_milli in $quota_cases; do
  case_dir="$TMP/$quota_milli"
  ACTIVE_CGROUP="$CGROUP_BASE/$quota_milli"
  mkdir "$ACTIVE_CGROUP"
  quota_us=$((quota_milli * 100))
  printf '%s 100000\n' "$quota_us" > "$ACTIVE_CGROUP/cpu.max"
  mkdir -p "$case_dir/runtime"
  sh -c 'printf "%s\n" "$$" > "$1/cgroup.procs"; shift; exec env "$@"' sh "$ACTIVE_CGROUP" \
    VP_CONFIG_DIR="$case_dir/etc" VP_DATA_DIR="$case_dir/lib" VP_LOG_DIR="$case_dir/log" \
    VP_LIB_DIR="$case_dir/usr-lib" VP_CORE_BIN="$case_dir/usr-lib/bin/mihomo" \
    VP_CORE_BACKUP_BIN="$case_dir/usr-lib/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$MIHOMO_BIN" \
    VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((1024 * 1048576)) VP_SKIP_SERVICE=1 \
    sh "$ROOT/vp.sh" core-install >/dev/null

  detected_quota="$(awk -F= '$1=="VP_CPU_QUOTA_MILLI"{print $2}' "$case_dir/etc/core.env")"
  effective_count="$(awk -F= '$1=="VP_CPU_EFFECTIVE_COUNT"{print $2}' "$case_dir/etc/core.env")"
  gomaxprocs="$(awk -F= '$1=="GOMAXPROCS"{print $2}' "$case_dir/etc/core.env")"
  gogc="$(awk -F= '$1=="GOGC"{print $2}' "$case_dir/etc/core.env")"
  profile="$(awk -F= '$1=="VP_MEMORY_PROFILE"{print $2}' "$case_dir/etc/core.env")"
  [ "$detected_quota" -eq "$quota_milli" ]
  expected_effective=$(((quota_milli + 999) / 1000))
  [ "$expected_effective" -le "$host_cpus" ] || expected_effective="$host_cpus"
  [ "$expected_effective" -le 4 ] || expected_effective=4
  [ "$effective_count" -eq "$expected_effective" ] && [ "$gomaxprocs" -eq "$expected_effective" ]
  if [ "$quota_milli" -lt 1000 ]; then
    [ "$gogc" -eq 120 ] && [ "$profile" = performance-cpu-limited ]
  else
    [ "$gogc" -eq 100 ] && [ "$profile" = performance ]
  fi

  port=$((25000 + profile_count * 20))
  while netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"; do port=$((port + 1)); done
  cat > "$case_dir/runtime/config.yaml" <<EOF
mixed-port: $port
allow-lan: false
mode: direct
log-level: silent
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
  "$MIHOMO_BIN" -t -d "$case_dir/runtime" -f "$case_dir/runtime/config.yaml" >/dev/null 2>&1
  sh -c 'printf "%s\n" "$$" > "$1/cgroup.procs"; export GOMEMLIMIT=512MiB GOGC="$2" GOMAXPROCS="$3"; exec "$4" -d "$5" -f "$5/config.yaml"' \
    sh "$ACTIVE_CGROUP" "$gogc" "$gomaxprocs" "$MIHOMO_BIN" "$case_dir/runtime" >"$case_dir/mihomo.log" 2>&1 &
  ACTIVE_PID=$!
  attempts=0
  proxy_result=""
  while [ "$attempts" -lt 15 ]; do
    if proxy_result="$(curl -4 -fsS --max-time 8 --proxy "http://127.0.0.1:$port" https://api.ipify.org 2>/dev/null)"; then break; fi
    kill -0 "$ACTIVE_PID" 2>/dev/null || { sed -n '1,80p' "$case_dir/mihomo.log" >&2; exit 1; }
    sleep 1
    attempts=$((attempts + 1))
  done
  [ "$proxy_result" = "$ACCEPT_HOST" ]
  transfer_pids=""
  transfer_index=1
  while [ "$transfer_index" -le 4 ]; do
    curl -4 -fsS --max-time 25 --proxy "http://127.0.0.1:$port" \
      'https://speed.cloudflare.com/__down?bytes=1048576' > "$case_dir/payload-$transfer_index.bin" &
    transfer_pids="$transfer_pids $!"
    transfer_index=$((transfer_index + 1))
  done
  concurrent_success=0
  for transfer_pid in $transfer_pids; do if wait "$transfer_pid"; then concurrent_success=$((concurrent_success + 1)); fi; done
  total_bytes="$(wc -c "$case_dir"/payload-*.bin | awk 'END{print $1}')"
  [ "$concurrent_success" -eq 4 ] && [ "$total_bytes" -eq 4194304 ]
  kill -0 "$ACTIVE_PID" 2>/dev/null
  throttled_events="$(awk '$1=="nr_throttled"{print $2;exit}' "$ACTIVE_CGROUP/cpu.stat")"
  case "${throttled_events:-0}" in *[!0-9]*) exit 1 ;; esac
  printf '%s,%s,%s,%s,%s,passed,%s,%s,%s\n' \
    "$quota_milli" "$effective_count" "$gomaxprocs" "$gogc" "$profile" \
    "$concurrent_success" "$total_bytes" "${throttled_events:-0}" >> "$csv_file"
  tested_quotas="${tested_quotas}${tested_quotas:+,}$quota_milli"
  profile_count=$((profile_count + 1))
  cleanup_case
done

[ "$formal_mihomo_state_before" = "$(rc-service mihomo status >/dev/null 2>&1 && printf active || printf inactive)" ]
[ "$formal_tunnel_state_before" = "$(rc-service cloudflared-tunnel status >/dev/null 2>&1 && printf active || printf inactive)" ]
[ "$formal_mihomo_pids_before" = "$(process_ids mihomo)" ]
[ "$formal_tunnel_pids_before" = "$(process_ids cloudflared)" ]
[ "$formal_mihomo_config_before" = "$(file_digest /etc/mihomo/config.yaml)" ]
[ "$formal_mihomo_init_before" = "$(file_digest /etc/init.d/mihomo)" ]
[ "$formal_tunnel_init_before" = "$(file_digest /etc/init.d/cloudflared-tunnel)" ]
[ "$formal_mihomo_nodes_before" = "$(file_digest /etc/mihomo/nodes.db)" ]
[ "$formal_mihomo_state_file_before" = "$(file_digest /etc/mihomo/state.env)" ]
[ "$formal_tunnel_token_before" = "$(file_digest /etc/cloudflared/token)" ]
[ "$formal_mihomo_binary_before" = "$(file_digest "$MIHOMO_BIN")" ]

{
  printf 'vps_node_version=%s\n' "$tested_version"
  printf 'tested_script_sha256=%s\n' "$tested_script_sha256"
  printf 'authorized_host=%s\n' "$ACCEPT_HOST"
  printf 'cgroup_version=2\n'
  printf 'host_cpu_count=%s\n' "$host_cpus"
  printf 'cpu_quotas_tested=%s\n' "$tested_quotas"
  printf 'profile_count=%s\n' "$profile_count"
  printf 'real_core_startups=%s\n' "$profile_count"
  printf 'concurrent_transfer_checks=%s\n' $((profile_count * 4))
  printf 'verified_transfer_bytes=%s\n' $((profile_count * 4194304))
  printf 'formal_services_and_sensitive_state_unchanged=yes\n'
} > "$summary_file"
chmod 600 "$csv_file" "$summary_file"
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$csv_file")" > "$(basename "$csv_file").sha256")
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$summary_file")" > "$(basename "$summary_file").sha256")
chmod 600 "$csv_file.sha256" "$summary_file.sha256"
printf 'cpu profiles: ok real-core-startups=%s host-cpus=%s\n' "$profile_count" "$host_cpus"
