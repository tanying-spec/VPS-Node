#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MIHOMO_BIN="${VP_TEST_MIHOMO_BIN:?请通过 VP_TEST_MIHOMO_BIN 指定真实 Mihomo 内核}"
ACCEPT_HOST="134.209.180.134"
RUN_ID="$$"
BASE="/tmp/vps-node-acceptance-$RUN_ID"
CORE_SERVICE="vps-node-acceptance-core-$RUN_ID"
TUNNEL_SERVICE="vps-node-acceptance-tunnel-$RUN_ID"
CLI="$BASE/bin/vp"
BACKUP_DIR="$BASE/external-backup"
EVIDENCE_DIR="${VP_ACCEPTANCE_EVIDENCE_DIR:-/root}"
TEST_CLOUDFLARED_BIN="${VP_TEST_CLOUDFLARED_BIN:-}"
TEST_TUNNEL_TOKEN_FILE="${VP_TEST_TUNNEL_TOKEN_FILE:-}"
TEST_ARGO_HOST="${VP_TEST_ARGO_HOST:-}"
TEST_ARGO_PATH="${VP_TEST_ARGO_PATH:-}"
TEST_ARGO_ORIGIN_PORT="${VP_TEST_ARGO_ORIGIN_PORT:-}"

[ "$(id -u)" = 0 ] || { printf 'acceptance requires root\n' >&2; exit 1; }
[ -x "$MIHOMO_BIN" ] || { printf 'mihomo binary is not executable\n' >&2; exit 1; }
[ -f "$ROOT/vp.sh.sha256" ] || { printf 'vp.sh checksum file is missing\n' >&2; exit 1; }
expected_script_sha256="$(awk 'NR == 1 { print tolower($1) }' "$ROOT/vp.sh.sha256")"
case "$expected_script_sha256" in ''|*[!0-9a-f]*) printf 'vp.sh checksum is invalid\n' >&2; exit 1 ;; esac
[ "${#expected_script_sha256}" -eq 64 ] || { printf 'vp.sh checksum is incomplete\n' >&2; exit 1; }
tested_script_sha256="$(sha256sum "$ROOT/vp.sh" | awk '{print tolower($1)}')"
[ "$tested_script_sha256" = "$expected_script_sha256" ] || { printf 'vp.sh checksum mismatch\n' >&2; exit 1; }
case "$EVIDENCE_DIR" in /*) ;; *) printf 'evidence directory must be absolute\n' >&2; exit 1 ;; esac
observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing acceptance on an unauthorized host\n' >&2; exit 1; }

argo_inputs=0
for argo_input in "$TEST_CLOUDFLARED_BIN" "$TEST_TUNNEL_TOKEN_FILE" "$TEST_ARGO_HOST" "$TEST_ARGO_PATH" "$TEST_ARGO_ORIGIN_PORT"; do
  [ -n "$argo_input" ] && argo_inputs=$((argo_inputs + 1))
done
[ "$argo_inputs" -eq 0 ] || [ "$argo_inputs" -eq 5 ] || {
  printf 'independent Argo acceptance requires binary, token file, host, path and origin port together\n' >&2
  exit 1
}
if [ "$argo_inputs" -eq 5 ]; then
  [ -x "$TEST_CLOUDFLARED_BIN" ] || { printf 'test cloudflared binary is not executable\n' >&2; exit 1; }
  [ -r "$TEST_TUNNEL_TOKEN_FILE" ] || { printf 'test Tunnel token file is not readable\n' >&2; exit 1; }
  case "$TEST_ARGO_HOST" in *.*) ;; *) printf 'test Argo host is invalid\n' >&2; exit 1 ;; esac
  case "$TEST_ARGO_PATH" in /*) ;; *) printf 'test Argo path must start with /\n' >&2; exit 1 ;; esac
  case "$TEST_ARGO_ORIGIN_PORT" in ''|*[!0-9]*) printf 'test Argo origin port is invalid\n' >&2; exit 1 ;; esac
  [ "$TEST_ARGO_ORIGIN_PORT" -ge 1024 ] && [ "$TEST_ARGO_ORIGIN_PORT" -le 65535 ] || { printf 'test Argo origin port out of range\n' >&2; exit 1; }
  if [ -r /etc/cloudflared/token ] &&
     [ "$(sha256sum "$TEST_TUNNEL_TOKEN_FILE" | awk '{print $1}')" = "$(sha256sum /etc/cloudflared/token | awk '{print $1}')" ]; then
    printf 'refusing to reuse the formal Cloudflare Tunnel token\n' >&2
    exit 1
  fi
  if [ -r /etc/mihomo/nodes.db ] && grep -Fq "$TEST_ARGO_HOST" /etc/mihomo/nodes.db; then
    printf 'refusing to reuse a host present in the formal node database\n' >&2
    exit 1
  fi
fi

service_active() {
  rc-service "$1" status >/dev/null 2>&1
}

file_digest() {
  [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf absent
}

process_ids() {
  process_name="$1"
  command -v pidof >/dev/null 2>&1 || { printf unavailable; return; }
  ids="$(pidof "$process_name" 2>/dev/null | tr ' ' '\n' | awk 'NF' | sort -n | tr '\n' ',' | sed 's/,$//' || true)"
  printf '%s' "${ids:-none}"
}

process_image_digests() {
  process_name="$1"
  command -v pidof >/dev/null 2>&1 || { printf unavailable; return; }
  for process_pid in $(pidof "$process_name" 2>/dev/null || true); do
    process_image="$(readlink -f "/proc/$process_pid/exe" 2>/dev/null || true)"
    if [ -n "$process_image" ] && [ -f "$process_image" ]; then
      sha256sum "$process_image" | awk '{print $1}'
    fi
  done | sort -u | tr '\n' ',' | sed 's/,$//'
}

process_cmdline_digests() {
  process_name="$1"
  command -v pidof >/dev/null 2>&1 || { printf unavailable; return; }
  for process_pid in $(pidof "$process_name" 2>/dev/null || true); do
    [ -r "/proc/$process_pid/cmdline" ] && sha256sum "/proc/$process_pid/cmdline" | awk '{print $1}'
  done | sort -u | tr '\n' ',' | sed 's/,$//'
}

test_tunnel_pid() {
  command -v pidof >/dev/null 2>&1 || return 1
  for candidate_pid in $(pidof cloudflared 2>/dev/null); do
    candidate_cmdline="$(tr '\0' ' ' < "/proc/$candidate_pid/cmdline" 2>/dev/null || true)"
    case "$candidate_cmdline" in
      *"$BASE/usr/bin/cloudflared"*"$BASE/etc/secrets/cloudflared.token"*) printf '%s' "$candidate_pid"; return 0 ;;
    esac
  done
  return 1
}

formal_mihomo_before=inactive
formal_tunnel_before=inactive
service_active mihomo && formal_mihomo_before=active
service_active cloudflared-tunnel && formal_tunnel_before=active
formal_mihomo_config_before="$(file_digest /etc/mihomo/config.yaml)"
formal_mihomo_init_before="$(file_digest /etc/init.d/mihomo)"
formal_tunnel_init_before="$(file_digest /etc/init.d/cloudflared-tunnel)"
formal_mihomo_nodes_before="$(file_digest /etc/mihomo/nodes.db)"
formal_mihomo_state_before="$(file_digest /etc/mihomo/state.env)"
formal_tunnel_token_before="$(file_digest /etc/cloudflared/token)"
formal_mihomo_binary_before="$(file_digest "$MIHOMO_BIN")"
formal_mihomo_pids_before="$(process_ids mihomo)"
formal_tunnel_pids_before="$(process_ids cloudflared)"
formal_mihomo_images_before="$(process_image_digests mihomo)"
formal_tunnel_images_before="$(process_image_digests cloudflared)"
formal_mihomo_cmdlines_before="$(process_cmdline_digests mihomo)"
formal_tunnel_cmdlines_before="$(process_cmdline_digests cloudflared)"

vp_env() {
  VP_CONFIG_DIR="$BASE/etc" VP_DATA_DIR="$BASE/lib" VP_LOG_DIR="$BASE/log" \
  VP_LIB_DIR="$BASE/usr" VP_CLI_PATH="$CLI" VP_CLI_BACKUP_PATH="$CLI.previous" \
  VP_CORE_BIN="$BASE/usr/bin/mihomo" VP_CORE_BACKUP_BIN="$BASE/usr/bin/mihomo.previous" \
  VP_CORE_SOURCE_BIN="$MIHOMO_BIN" VP_CORE_SERVICE="$CORE_SERVICE" \
  VP_TUNNEL_SERVICE="$TUNNEL_SERVICE" VP_UNINSTALL_BACKUP_DIR="$BACKUP_DIR" \
  VP_CORE_INSTALL_CONFIRM=INSTALL VP_TUNNEL_INSTALL_CONFIRM=INSTALL \
  "$@"
}

cleanup_acceptance() {
  if [ -x "$CLI" ]; then
    VP_UNINSTALL_CONFIRM=DELETE vp_env "$CLI" uninstall >/dev/null 2>&1 || true
  fi
  rc-service "$CORE_SERVICE" stop >/dev/null 2>&1 || true
  rc-update del "$CORE_SERVICE" default >/dev/null 2>&1 || true
  rm -f "/etc/init.d/$CORE_SERVICE" "/etc/init.d/$TUNNEL_SERVICE"
  rm -rf "$BASE"
}
trap cleanup_acceptance EXIT HUP INT TERM

mkdir -p "$BASE/bin"
cp "$ROOT/vp.sh" "$CLI"
chmod 755 "$CLI"
tested_version="$(vp_env "$CLI" version)"

vp_env "$CLI" init >/dev/null
vp_env "$CLI" core-install >/dev/null
vp_env "$CLI" reality-add acceptance-reality '' www.amd.com ipv4 >/dev/null
vp_env env VP_TEST_SERVER=127.0.0.1 VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-reality 2 | grep -q '2/2 路成功'
ipv6_result=not-available
if vp_env "$CLI" network 2>/dev/null | grep -q '公网 IPv6：可用'; then
  vp_env "$CLI" reality-add acceptance-reality-v6 '' www.amd.com ipv6 >/dev/null
  vp_env env VP_TEST_SERVER=::1 VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-reality-v6 2 | grep -q '2/2 路成功'
  ipv6_result=loopback-passed
fi
argo_result=not-requested
if [ "$argo_inputs" -eq 5 ]; then
  vp_env "$CLI" argo-add acceptance-argo "$TEST_ARGO_ORIGIN_PORT" "$TEST_ARGO_HOST" "$TEST_ARGO_PATH" >/dev/null
  VP_TUNNEL_SOURCE_BIN="$TEST_CLOUDFLARED_BIN" vp_env "$CLI" tunnel-install "$TEST_TUNNEL_TOKEN_FILE" >/dev/null
  metrics_port="$(awk -F= '$1=="VP_TUNNEL_METRICS_PORT"{print $2;exit}' "$BASE/etc/state.env")"
  edges=0
  attempts=0
  while [ "$attempts" -lt 20 ]; do
    edges="$(curl -fsS --max-time 2 "http://127.0.0.1:$metrics_port/metrics" 2>/dev/null | awk '/^cloudflared_tunnel_ha_connections /{sum+=$2}END{print sum+0}')"
    [ "$edges" -gt 0 ] && break
    sleep 1
    attempts=$((attempts + 1))
  done
  [ "$edges" -gt 0 ]
  vp_env env VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-argo 2 | grep -q '2/2 路成功'
  old_test_tunnel_pid="$(test_tunnel_pid || true)"
  [ -n "$old_test_tunnel_pid" ]
  kill -9 "$old_test_tunnel_pid"
  new_test_tunnel_pid=""
  attempts=0
  while [ "$attempts" -lt 20 ]; do
    sleep 1
    new_test_tunnel_pid="$(test_tunnel_pid || true)"
    [ -n "$new_test_tunnel_pid" ] && [ "$new_test_tunnel_pid" != "$old_test_tunnel_pid" ] && break
    attempts=$((attempts + 1))
  done
  [ -n "$new_test_tunnel_pid" ] && [ "$new_test_tunnel_pid" != "$old_test_tunnel_pid" ]
  edges=0
  attempts=0
  while [ "$attempts" -lt 20 ]; do
    edges="$(curl -fsS --max-time 2 "http://127.0.0.1:$metrics_port/metrics" 2>/dev/null | awk '/^cloudflared_tunnel_ha_connections /{sum+=$2}END{print sum+0}')"
    [ "$edges" -gt 0 ] && break
    sleep 1
    attempts=$((attempts + 1))
  done
  [ "$edges" -gt 0 ]
  vp_env env VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-argo 2 | grep -q '2/2 路成功'
  argo_result=public-concurrency-and-respawn-passed
fi
vp_env "$CLI" rotate acceptance-reality 1 >/dev/null
expected_rotation_links=2
[ "$ipv6_result" = loopback-passed ] && expected_rotation_links=3
[ "$argo_result" = public-concurrency-and-respawn-passed ] && expected_rotation_links=$((expected_rotation_links + 1))
[ "$(vp_env "$CLI" subscription plain | grep -c '^vless://')" -eq "$expected_rotation_links" ]
vp_env env VP_ROTATION_FINALIZE_CONFIRM=FINALIZE "$CLI" rotate-finalize acceptance-reality >/dev/null
expected_final_links=1
[ "$ipv6_result" = loopback-passed ] && expected_final_links=2
[ "$argo_result" = public-concurrency-and-respawn-passed ] && expected_final_links=$((expected_final_links + 1))
[ "$(vp_env "$CLI" subscription plain | grep -c '^vless://')" -eq "$expected_final_links" ]
printf 'ACCEPTANCE_MARKER=original\n' >> "$BASE/etc/state.env"
vp_env "$CLI" backup "$BASE/acceptance.tar.gz" >/dev/null
[ -s "$BASE/acceptance.tar.gz" ]
[ -s "$BASE/acceptance.tar.gz.sha256" ]
sed -i 's/ACCEPTANCE_MARKER=original/ACCEPTANCE_MARKER=changed/' "$BASE/etc/state.env"
vp_env "$CLI" restore "$BASE/acceptance.tar.gz" --dry-run | grep -q '未修改任何文件或服务'
grep -q '^ACCEPTANCE_MARKER=changed$' "$BASE/etc/state.env"
VP_RESTORE_CONFIRM=RESTORE vp_env "$CLI" restore "$BASE/acceptance.tar.gz" --apply >/dev/null
grep -q '^ACCEPTANCE_MARKER=original$' "$BASE/etc/state.env"
expected_config_hash="$(file_digest "$BASE/etc/generated/mihomo.yaml")"
printf '\n# isolated acceptance drift\n' >> "$BASE/etc/generated/mihomo.yaml"
vp_env "$CLI" self-heal --quiet
[ "$expected_config_hash" = "$(file_digest "$BASE/etc/generated/mihomo.yaml")" ]
vp_env "$CLI" report "$BASE/diagnostic.txt" >/dev/null
! grep -Eq '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$BASE/diagnostic.txt"
vp_env "$CLI" network-optimize --dry-run >/dev/null

VP_UNINSTALL_CONFIRM=DELETE vp_env "$CLI" uninstall >/dev/null
[ ! -e "$BASE/etc" ]
[ ! -e "$BASE/lib" ]
find "$BACKUP_DIR" -name 'vps-node-uninstall-backup-*.tar.gz' -type f | grep -q .

formal_mihomo_after=inactive
formal_tunnel_after=inactive
service_active mihomo && formal_mihomo_after=active
service_active cloudflared-tunnel && formal_tunnel_after=active
formal_mihomo_pids_after="$(process_ids mihomo)"
formal_tunnel_pids_after="$(process_ids cloudflared)"
[ "$formal_mihomo_before" = "$formal_mihomo_after" ]
[ "$formal_tunnel_before" = "$formal_tunnel_after" ]
[ "$formal_mihomo_pids_before" = "$formal_mihomo_pids_after" ]
[ "$formal_tunnel_pids_before" = "$formal_tunnel_pids_after" ]
[ "$formal_mihomo_config_before" = "$(file_digest /etc/mihomo/config.yaml)" ]
[ "$formal_mihomo_init_before" = "$(file_digest /etc/init.d/mihomo)" ]
[ "$formal_tunnel_init_before" = "$(file_digest /etc/init.d/cloudflared-tunnel)" ]
[ "$formal_mihomo_nodes_before" = "$(file_digest /etc/mihomo/nodes.db)" ]
[ "$formal_mihomo_state_before" = "$(file_digest /etc/mihomo/state.env)" ]
[ "$formal_tunnel_token_before" = "$(file_digest /etc/cloudflared/token)" ]
[ "$formal_mihomo_binary_before" = "$(file_digest "$MIHOMO_BIN")" ]
[ "$formal_mihomo_images_before" = "$(process_image_digests mihomo)" ]
[ "$formal_tunnel_images_before" = "$(process_image_digests cloudflared)" ]
[ "$formal_mihomo_cmdlines_before" = "$(process_cmdline_digests mihomo)" ]
[ "$formal_tunnel_cmdlines_before" = "$(process_cmdline_digests cloudflared)" ]

mkdir -p "$EVIDENCE_DIR"
evidence_file="$EVIDENCE_DIR/vps-node-acceptance-$(date -u '+%Y%m%dT%H%M%SZ').txt"
{
  printf 'vps_node_version=%s\n' "$tested_version"
  printf 'tested_script_sha256=%s\n' "$tested_script_sha256"
  printf 'source_checksum_verified=yes\n'
  printf 'authorized_host=%s\n' "$ACCEPT_HOST"
  printf 'tested_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'reality_ipv4_loopback_concurrency=2/2\n'
  printf 'reality_ipv6=%s\n' "$ipv6_result"
  printf 'independent_cloudflare_tunnel=%s\n' "$argo_result"
  printf 'credential_rotation=passed\n'
  printf 'backup_restore_roundtrip=passed\n'
  printf 'config_drift_self_heal=passed\n'
  printf 'diagnostic_redaction=passed\n'
  printf 'recoverable_uninstall=passed\n'
  printf 'formal_mihomo_state=%s\n' "$formal_mihomo_after"
  printf 'formal_tunnel_state=%s\n' "$formal_tunnel_after"
  printf 'formal_mihomo_pids_unchanged=yes\n'
  printf 'formal_tunnel_pids_unchanged=yes\n'
  printf 'formal_config_and_init_digests_unchanged=yes\n'
  printf 'formal_sensitive_state_digests_unchanged=yes\n'
  printf 'formal_process_images_and_cmdlines_unchanged=yes\n'
} > "$evidence_file"
chmod 600 "$evidence_file"
sha256sum "$evidence_file" > "$evidence_file.sha256"
chmod 600 "$evidence_file.sha256"

trap - EXIT HUP INT TERM
rm -rf "$BASE"
printf 'isolated-acceptance: ok host=%s formal-mihomo=%s formal-tunnel=%s\n' \
  "$ACCEPT_HOST" "$formal_mihomo_after" "$formal_tunnel_after"
printf 'evidence=%s\n' "$evidence_file"
