#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MIHOMO_BIN="${VP_TEST_MIHOMO_BIN:?请通过 VP_TEST_MIHOMO_BIN 指定测试内核}"
EVIDENCE_DIR="${VP_MEMORY_EVIDENCE_DIR:?请通过 VP_MEMORY_EVIDENCE_DIR 指定证据目录}"
ACCEPT_HOST="134.209.180.134"
TMP="$(mktemp -d /tmp/vps-node-memory.XXXXXX)"
CGROUP_BASE="/sys/fs/cgroup/vps-node-memory-$$"
ACTIVE_PID=""
ACTIVE_CGROUP=""

file_digest() {
  [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf absent
}

process_ids() {
  ids="$(pidof "$1" 2>/dev/null | tr ' ' '\n' | awk 'NF' | sort -n | tr '\n' ',' | sed 's/,$//' || true)"
  printf '%s' "${ids:-none}"
}

process_image_digests() {
  for process_pid in $(pidof "$1" 2>/dev/null || true); do
    process_image="$(readlink -f "/proc/$process_pid/exe" 2>/dev/null || true)"
    [ -n "$process_image" ] && [ -f "$process_image" ] && sha256sum "$process_image" | awk '{print $1}'
  done | sort -u | tr '\n' ',' | sed 's/,$//'
}

process_cmdline_digests() {
  for process_pid in $(pidof "$1" 2>/dev/null || true); do
    [ -r "/proc/$process_pid/cmdline" ] && sha256sum "/proc/$process_pid/cmdline" | awk '{print $1}'
  done | sort -u | tr '\n' ',' | sed 's/,$//'
}

cleanup_case() {
  if [ -n "$ACTIVE_PID" ]; then
    kill "$ACTIVE_PID" >/dev/null 2>&1 || true
    wait "$ACTIVE_PID" 2>/dev/null || true
    ACTIVE_PID=""
  fi
  if [ -n "$ACTIVE_CGROUP" ] && [ -d "$ACTIVE_CGROUP" ]; then
    [ -w "$ACTIVE_CGROUP/cgroup.kill" ] && printf '1\n' > "$ACTIVE_CGROUP/cgroup.kill" 2>/dev/null || true
    rmdir "$ACTIVE_CGROUP" 2>/dev/null || true
    ACTIVE_CGROUP=""
  fi
}

cleanup_all() {
  cleanup_case
  [ -d "$CGROUP_BASE" ] && rmdir "$CGROUP_BASE" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup_all EXIT HUP INT TERM

[ "$(id -u)" = 0 ] || { printf 'memory profile acceptance requires root\n' >&2; exit 1; }
[ -x "$MIHOMO_BIN" ] || { printf 'mihomo binary is not executable\n' >&2; exit 1; }
case "$EVIDENCE_DIR" in /*) ;; *) printf 'memory evidence directory must be absolute\n' >&2; exit 1 ;; esac
observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing real-core memory test on an unauthorized host\n' >&2; exit 1; }
[ -f /sys/fs/cgroup/cgroup.controllers ] || { printf 'cgroup v2 is required for enforced memory profiles\n' >&2; exit 1; }
mkdir "$CGROUP_BASE" 2>/dev/null || { printf 'unable to create an isolated cgroup v2 subtree\n' >&2; exit 1; }
[ -w "$CGROUP_BASE/memory.max" ] || { printf 'cgroup v2 memory controller is not delegated to the test process\n' >&2; exit 1; }
grep -qw memory "$CGROUP_BASE/cgroup.controllers" 2>/dev/null || { printf 'cgroup v2 memory controller is unavailable\n' >&2; exit 1; }
printf '+memory\n' > "$CGROUP_BASE/cgroup.subtree_control" 2>/dev/null || { printf 'unable to enable the isolated cgroup memory controller\n' >&2; exit 1; }

expected_script_sha256="$(awk 'NR == 1 { print tolower($1) }' "$ROOT/vp.sh.sha256")"
case "$expected_script_sha256" in ''|*[!0-9a-f]*) printf 'vp.sh checksum is invalid\n' >&2; exit 1 ;; esac
[ "${#expected_script_sha256}" -eq 64 ] || { printf 'vp.sh checksum is incomplete\n' >&2; exit 1; }
tested_script_sha256="$(sha256sum "$ROOT/vp.sh" | awk '{print tolower($1)}')"
[ "$tested_script_sha256" = "$expected_script_sha256" ] || { printf 'vp.sh checksum mismatch\n' >&2; exit 1; }
tested_version="$(VP_CONFIG_DIR="$TMP/version-etc" VP_DATA_DIR="$TMP/version-lib" VP_LOG_DIR="$TMP/version-log" sh "$ROOT/vp.sh" version)"

formal_mihomo_state_before="$(rc-service mihomo status >/dev/null 2>&1 && printf active || printf inactive)"
formal_tunnel_state_before="$(rc-service cloudflared-tunnel status >/dev/null 2>&1 && printf active || printf inactive)"
formal_mihomo_pids_before="$(process_ids mihomo)"
formal_tunnel_pids_before="$(process_ids cloudflared)"
formal_mihomo_images_before="$(process_image_digests mihomo)"
formal_tunnel_images_before="$(process_image_digests cloudflared)"
formal_mihomo_cmdlines_before="$(process_cmdline_digests mihomo)"
formal_tunnel_cmdlines_before="$(process_cmdline_digests cloudflared)"
formal_mihomo_config_before="$(file_digest /etc/mihomo/config.yaml)"
formal_mihomo_init_before="$(file_digest /etc/init.d/mihomo)"
formal_tunnel_init_before="$(file_digest /etc/init.d/cloudflared-tunnel)"
formal_mihomo_nodes_before="$(file_digest /etc/mihomo/nodes.db)"
formal_mihomo_state_file_before="$(file_digest /etc/mihomo/state.env)"
formal_tunnel_token_before="$(file_digest /etc/cloudflared/token)"
formal_mihomo_binary_before="$(file_digest "$MIHOMO_BIN")"

mkdir -p "$EVIDENCE_DIR"
csv_file="$EVIDENCE_DIR/memory-profiles.csv"
summary_file="$EVIDENCE_DIR/memory-profiles-summary.txt"
printf 'limit_mib,budget_mib,profile,gomemlimit,gogc,gomaxprocs,peak_mib,oom_kill,proxy_result,concurrent_success,total_bytes\n' > "$csv_file"

previous_budget=0
profile_count=0
max_peak_mib=0
for limit_mib in 64 96 97 128 160 161 192 256 320 321 512 640 641 1024 2048; do
  case_dir="$TMP/$limit_mib"
  VP_CONFIG_DIR="$case_dir/etc" VP_DATA_DIR="$case_dir/lib" VP_LOG_DIR="$case_dir/log" \
  VP_LIB_DIR="$case_dir/usr-lib" VP_CORE_BIN="$case_dir/usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$case_dir/usr-lib/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$MIHOMO_BIN" \
  VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((limit_mib * 1048576)) VP_CPU_COUNT_OVERRIDE=8 VP_SKIP_SERVICE=1 \
  VP_CORE_INSTALL_CONFIRM=INSTALL \
  sh "$ROOT/vp.sh" core-install >/dev/null

  budget="$(awk -F= '$1=="VP_CORE_BUDGET_MIB"{print $2}' "$case_dir/etc/core.env")"
  profile="$(awk -F= '$1=="VP_MEMORY_PROFILE"{print $2}' "$case_dir/etc/core.env")"
  gomemlimit="$(awk -F= '$1=="GOMEMLIMIT"{print $2}' "$case_dir/etc/core.env")"
  gogc="$(awk -F= '$1=="GOGC"{print $2}' "$case_dir/etc/core.env")"
  gomaxprocs="$(awk -F= '$1=="GOMAXPROCS"{print $2}' "$case_dir/etc/core.env")"
  [ "$budget" -ge 32 ] && [ "$budget" -le 512 ] && [ "$budget" -lt "$limit_mib" ]
  [ "$budget" -ge "$previous_budget" ]
  previous_budget="$budget"

  port=$((24000 + profile_count * 20))
  attempts=0
  while netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"; do
    port=$((port + 1))
    attempts=$((attempts + 1))
    [ "$attempts" -lt 20 ] || { printf 'unable to find a free memory-test port\n' >&2; exit 1; }
  done
  mkdir -p "$case_dir/runtime"
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

  ACTIVE_CGROUP="$CGROUP_BASE/$limit_mib"
  mkdir "$ACTIVE_CGROUP"
  printf '%s\n' $((limit_mib * 1048576)) > "$ACTIVE_CGROUP/memory.max"
  [ -w "$ACTIVE_CGROUP/memory.swap.max" ] && printf '0\n' > "$ACTIVE_CGROUP/memory.swap.max" || true
  sh -c 'printf "%s\n" "$$" > "$1/cgroup.procs"; export GOMEMLIMIT="$2" GOGC="$3" GOMAXPROCS="$4"; exec "$5" -d "$6" -f "$6/config.yaml"' \
    sh "$ACTIVE_CGROUP" "$gomemlimit" "$gogc" "$gomaxprocs" "$MIHOMO_BIN" "$case_dir/runtime" \
    >"$case_dir/mihomo.log" 2>&1 &
  ACTIVE_PID=$!

  proxy_result=""
  attempts=0
  while [ "$attempts" -lt 15 ]; do
    if proxy_result="$(curl -4 -fsS --max-time 8 --proxy "http://127.0.0.1:$port" https://api.ipify.org 2>/dev/null)"; then
      break
    fi
    kill -0 "$ACTIVE_PID" 2>/dev/null || { sed -n '1,80p' "$case_dir/mihomo.log" >&2; printf 'mihomo exited in %s MiB cgroup\n' "$limit_mib" >&2; exit 1; }
    sleep 1
    attempts=$((attempts + 1))
  done
  [ "$proxy_result" = "$ACCEPT_HOST" ] || { printf 'proxy verification failed in %s MiB cgroup\n' "$limit_mib" >&2; exit 1; }
  transfer_pids=""
  transfer_index=1
  while [ "$transfer_index" -le 4 ]; do
    curl -4 -fsS --max-time 20 --proxy "http://127.0.0.1:$port" \
      'https://speed.cloudflare.com/__down?bytes=1048576' > "$case_dir/payload-$transfer_index.bin" &
    transfer_pids="$transfer_pids $!"
    transfer_index=$((transfer_index + 1))
  done
  concurrent_success=0
  for transfer_pid in $transfer_pids; do
    if wait "$transfer_pid"; then concurrent_success=$((concurrent_success + 1)); fi
  done
  [ "$concurrent_success" -eq 4 ]
  total_bytes="$(wc -c "$case_dir"/payload-*.bin | awk 'END{print $1}')"
  [ "$total_bytes" -eq 4194304 ]
  kill -0 "$ACTIVE_PID" 2>/dev/null || { printf 'mihomo did not survive traffic in %s MiB cgroup\n' "$limit_mib" >&2; exit 1; }

  peak_bytes="$(cat "$ACTIVE_CGROUP/memory.peak" 2>/dev/null || cat "$ACTIVE_CGROUP/memory.current")"
  peak_mib=$(((peak_bytes + 1048575) / 1048576))
  oom_kill="$(awk '$1=="oom_kill"{print $2;exit}' "$ACTIVE_CGROUP/memory.events")"
  [ "${oom_kill:-0}" -eq 0 ]
  [ "$peak_mib" -gt 0 ] && [ "$peak_mib" -le "$limit_mib" ]
  [ "$peak_mib" -le "$max_peak_mib" ] || max_peak_mib="$peak_mib"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,passed,%s,%s\n' \
    "$limit_mib" "$budget" "$profile" "$gomemlimit" "$gogc" "$gomaxprocs" "$peak_mib" "${oom_kill:-0}" \
    "$concurrent_success" "$total_bytes" >> "$csv_file"
  profile_count=$((profile_count + 1))
  cleanup_case
done

formal_mihomo_state_after="$(rc-service mihomo status >/dev/null 2>&1 && printf active || printf inactive)"
formal_tunnel_state_after="$(rc-service cloudflared-tunnel status >/dev/null 2>&1 && printf active || printf inactive)"
[ "$formal_mihomo_state_before" = "$formal_mihomo_state_after" ]
[ "$formal_tunnel_state_before" = "$formal_tunnel_state_after" ]
[ "$formal_mihomo_pids_before" = "$(process_ids mihomo)" ]
[ "$formal_tunnel_pids_before" = "$(process_ids cloudflared)" ]
[ "$formal_mihomo_images_before" = "$(process_image_digests mihomo)" ]
[ "$formal_tunnel_images_before" = "$(process_image_digests cloudflared)" ]
[ "$formal_mihomo_cmdlines_before" = "$(process_cmdline_digests mihomo)" ]
[ "$formal_tunnel_cmdlines_before" = "$(process_cmdline_digests cloudflared)" ]
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
  printf 'memory_limits_tested=64,96,97,128,160,161,192,256,320,321,512,640,641,1024,2048\n'
  printf 'profile_count=%s\n' "$profile_count"
  printf 'real_core_startups=%s\n' "$profile_count"
  printf 'functional_proxy_checks=%s\n' "$profile_count"
  printf 'traffic_survival_checks=%s\n' "$profile_count"
  printf 'concurrent_transfer_checks=%s\n' $((profile_count * 4))
  printf 'verified_transfer_bytes=%s\n' $((profile_count * 4194304))
  printf 'oom_kill_total=0\n'
  printf 'max_observed_peak_mib=%s\n' "$max_peak_mib"
  printf 'formal_services_and_sensitive_state_unchanged=yes\n'
} > "$summary_file"

chmod 600 "$csv_file" "$summary_file"
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$csv_file")" > "$(basename "$csv_file").sha256")
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$summary_file")" > "$(basename "$summary_file").sha256")
chmod 600 "$csv_file.sha256" "$summary_file.sha256"
printf 'memory profiles: ok real-core-startups=%s max-peak=%sMiB\n' "$profile_count" "$max_peak_mib"
