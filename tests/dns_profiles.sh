#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MIHOMO_BIN="${VP_TEST_MIHOMO_BIN:?请通过 VP_TEST_MIHOMO_BIN 指定测试内核}"
EVIDENCE_DIR="${VP_DNS_EVIDENCE_DIR:?请通过 VP_DNS_EVIDENCE_DIR 指定证据目录}"
ACCEPT_HOST="134.209.180.134"
TMP="$(mktemp -d /tmp/vps-node-dns.XXXXXX)"
ACTIVE_PID=""

file_digest() { [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf absent; }
process_ids() {
  ids="$(pidof "$1" 2>/dev/null | tr ' ' '\n' | awk 'NF' | sort -n | tr '\n' ',' | sed 's/,$//' || true)"
  printf '%s' "${ids:-none}"
}
cleanup_core() {
  if [ -n "$ACTIVE_PID" ]; then kill "$ACTIVE_PID" >/dev/null 2>&1 || true; wait "$ACTIVE_PID" 2>/dev/null || true; ACTIVE_PID=""; fi
}
cleanup_all() { cleanup_core; rm -rf "$TMP"; }
trap cleanup_all EXIT HUP INT TERM

[ "$(id -u)" = 0 ] || { printf 'dns profile acceptance requires root\n' >&2; exit 1; }
[ -x "$MIHOMO_BIN" ] || { printf 'mihomo binary is not executable\n' >&2; exit 1; }
case "$EVIDENCE_DIR" in /*) ;; *) printf 'dns evidence directory must be absolute\n' >&2; exit 1 ;; esac
observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing real-core dns test on an unauthorized host\n' >&2; exit 1; }
if command -v nslookup >/dev/null 2>&1; then query_tool=nslookup; elif command -v dig >/dev/null 2>&1; then query_tool=dig; else printf 'dns query tool is required\n' >&2; exit 1; fi
command -v nc >/dev/null 2>&1 || { printf 'nc is required for TCP 53 verification\n' >&2; exit 1; }
if [ "$query_tool" = nslookup ]; then nslookup github.com >/dev/null 2>&1; else dig +time=3 +tries=1 +short github.com A | grep -q .; fi

expected_script_sha256="$(awk 'NR==1{print tolower($1)}' "$ROOT/vp.sh.sha256")"
case "$expected_script_sha256" in ''|*[!0-9a-f]*) printf 'vp.sh checksum is invalid\n' >&2; exit 1 ;; esac
[ "${#expected_script_sha256}" -eq 64 ] || { printf 'vp.sh checksum is incomplete\n' >&2; exit 1; }
tested_script_sha256="$(sha256sum "$ROOT/vp.sh" | awk '{print tolower($1)}')"
[ "$tested_script_sha256" = "$expected_script_sha256" ] || { printf 'vp.sh checksum mismatch\n' >&2; exit 1; }
tested_version="$(VP_CONFIG_DIR="$TMP/version-etc" VP_DATA_DIR="$TMP/version-lib" VP_LOG_DIR="$TMP/version-log" sh "$ROOT/vp.sh" version)"

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
csv_file="$EVIDENCE_DIR/dns-profiles.csv"
summary_file="$EVIDENCE_DIR/dns-profiles-summary.txt"
printf 'scenario,mode,public_ok,system_ok,tcp_check,selected_count,proxy_result\n' > "$csv_file"

scenario_count=0
actual_mode=""
for scenario in actual-default forced-public-failure; do
  case_dir="$TMP/$scenario"
  public_servers="1.1.1.1 8.8.8.8"
  [ "$scenario" = actual-default ] || public_servers="192.0.2.1"
  VP_CONFIG_DIR="$case_dir/etc" VP_DATA_DIR="$case_dir/lib" VP_LOG_DIR="$case_dir/log" \
  VP_LIB_DIR="$case_dir/usr-lib" VP_CORE_BIN="$case_dir/usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$case_dir/usr-lib/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$MIHOMO_BIN" \
  VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((512 * 1048576)) VP_CPU_COUNT_OVERRIDE=2 \
  VP_DNS_PUBLIC_SERVERS="$public_servers" VP_SKIP_SERVICE=1 VP_CORE_INSTALL_CONFIRM=INSTALL \
  sh "$ROOT/vp.sh" core-install >/dev/null

  mode="$(awk -F= '$1=="VP_DNS_MODE"{print $2}' "$case_dir/etc/core.env")"
  servers="$(awk -F= '$1=="VP_DNS_SERVERS"{print $2}' "$case_dir/etc/core.env")"
  public_ok="$(awk -F= '$1=="VP_DNS_PUBLIC_OK"{print $2}' "$case_dir/etc/core.env")"
  system_ok="$(awk -F= '$1=="VP_DNS_SYSTEM_OK"{print $2}' "$case_dir/etc/core.env")"
  tcp_check="$(awk -F= '$1=="VP_DNS_TCP_CHECK"{print $2}' "$case_dir/etc/core.env")"
  [ -n "$servers" ]
  selected_count="$(printf '%s' "$servers" | awk -F, '{print NF}')"
  if [ "$scenario" = forced-public-failure ]; then
    [ "$mode" = system ] && [ "$public_ok" -eq 0 ] && [ "$system_ok" -eq 1 ]
  else
    actual_mode="$mode"
    if [ "$public_ok" -eq 1 ]; then [ "$mode" = public ] && [ "$tcp_check" = passed ]; else [ "$mode" = system ] && [ "$system_ok" -eq 1 ]; fi
  fi

  port=$((26000 + scenario_count * 20))
  while netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"; do port=$((port + 1)); done
  mkdir -p "$case_dir/runtime"
  {
    printf 'mixed-port: %s\nallow-lan: false\nmode: direct\nlog-level: silent\n' "$port"
    printf 'dns:\n  enable: true\n  ipv6: false\n  nameserver:\n'
    if [ "$servers" = system ]; then
      printf '    - system://\n'
    else
      for dns_server in $(printf '%s' "$servers" | tr ',' ' '); do
        case "$dns_server" in *[!0-9a-fA-F.:]*) printf 'invalid selected DNS server\n' >&2; exit 1 ;; esac
        printf '    - "%s"\n' "$dns_server"
      done
    fi
    printf 'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n'
  } > "$case_dir/runtime/config.yaml"
  "$MIHOMO_BIN" -t -d "$case_dir/runtime" -f "$case_dir/runtime/config.yaml" >/dev/null 2>&1
  "$MIHOMO_BIN" -d "$case_dir/runtime" -f "$case_dir/runtime/config.yaml" >"$case_dir/mihomo.log" 2>&1 &
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
  printf '%s,%s,%s,%s,%s,%s,passed\n' "$scenario" "$mode" "$public_ok" "$system_ok" "$tcp_check" "$selected_count" >> "$csv_file"
  scenario_count=$((scenario_count + 1))
  cleanup_core
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
  printf 'query_tool=%s\n' "$query_tool"
  printf 'actual_default_mode=%s\n' "$actual_mode"
  printf 'scenario_count=%s\n' "$scenario_count"
  printf 'real_core_startups=%s\n' "$scenario_count"
  printf 'real_proxy_dns_checks=%s\n' "$scenario_count"
  printf 'forced_public_failure_fallback=passed\n'
  printf 'formal_services_and_sensitive_state_unchanged=yes\n'
} > "$summary_file"
chmod 600 "$csv_file" "$summary_file"
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$csv_file")" > "$(basename "$csv_file").sha256")
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$summary_file")" > "$(basename "$summary_file").sha256")
chmod 600 "$csv_file.sha256" "$summary_file.sha256"
printf 'dns profiles: ok actual=%s fallback=system\n' "$actual_mode"
