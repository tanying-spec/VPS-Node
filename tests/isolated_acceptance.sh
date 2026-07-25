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
TEST_CDN_TOKEN_FILE="${VP_TEST_CDN_TOKEN_FILE:-}"
TEST_CDN_HOST="${VP_TEST_CDN_HOST:-}"
TEST_CDN_PATH="${VP_TEST_CDN_PATH:-}"
TEST_CDN_ORIGIN_PORT="${VP_TEST_CDN_ORIGIN_PORT:-}"
TEST_CDN_EXTERNAL_PORT="${VP_TEST_CDN_EXTERNAL_PORT:-}"
TEST_CDN_ALTERNATE_PORT="${VP_TEST_CDN_ALTERNATE_PORT:-}"
TEST_CDN_UNMAPPED_PORT="${VP_TEST_CDN_UNMAPPED_PORT:-}"

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

cdn_inputs=0
for cdn_input in "$TEST_CDN_TOKEN_FILE" "$TEST_CDN_HOST" "$TEST_CDN_PATH" "$TEST_CDN_ORIGIN_PORT" \
  "$TEST_CDN_EXTERNAL_PORT" "$TEST_CDN_ALTERNATE_PORT" "$TEST_CDN_UNMAPPED_PORT"; do
  [ -n "$cdn_input" ] && cdn_inputs=$((cdn_inputs + 1))
done
[ "$cdn_inputs" -eq 0 ] || [ "$cdn_inputs" -eq 7 ] || {
  printf 'independent CDN acceptance requires all seven inputs together\n' >&2
  exit 1
}
if [ "$cdn_inputs" -eq 7 ]; then
  case "$TEST_CDN_TOKEN_FILE" in /*) ;; *) printf 'test CDN token file must be absolute\n' >&2; exit 1 ;; esac
  [ -r "$TEST_CDN_TOKEN_FILE" ] || { printf 'test CDN token file is not readable\n' >&2; exit 1; }
  case "$TEST_CDN_HOST" in *.*) ;; *) printf 'test CDN host is invalid\n' >&2; exit 1 ;; esac
  case "$TEST_CDN_PATH" in /*) ;; *) printf 'test CDN path must start with /\n' >&2; exit 1 ;; esac
  for cdn_port in "$TEST_CDN_ORIGIN_PORT" "$TEST_CDN_EXTERNAL_PORT" "$TEST_CDN_ALTERNATE_PORT" "$TEST_CDN_UNMAPPED_PORT"; do
    case "$cdn_port" in ''|*[!0-9]*) printf 'test CDN port is invalid\n' >&2; exit 1 ;; esac
    [ "$cdn_port" -ge 1024 ] && [ "$cdn_port" -le 65535 ] || { printf 'test CDN port out of range\n' >&2; exit 1; }
  done
  [ "$TEST_CDN_EXTERNAL_PORT" != "$TEST_CDN_ALTERNATE_PORT" ] &&
    [ "$TEST_CDN_EXTERNAL_PORT" != "$TEST_CDN_UNMAPPED_PORT" ] &&
    [ "$TEST_CDN_ALTERNATE_PORT" != "$TEST_CDN_UNMAPPED_PORT" ] || { printf 'test CDN external ports must be distinct\n' >&2; exit 1; }
  ss -ltnH 2>/dev/null | awk -v p="$TEST_CDN_ORIGIN_PORT" '$4 ~ (":" p "$") { found=1 } END { exit found ? 0 : 1 }' && { printf 'test CDN origin port is already occupied\n' >&2; exit 1; }
  for formal_token in /etc/vps-node/secrets/cloudflare-api-token /etc/mihomo/secrets/cloudflare-api-token; do
    if [ -r "$formal_token" ] && [ "$(sha256sum "$TEST_CDN_TOKEN_FILE" | awk '{print $1}')" = "$(sha256sum "$formal_token" | awk '{print $1}')" ]; then
      printf 'refusing to reuse a formal Cloudflare API token\n' >&2
      exit 1
    fi
  done
  for formal_nodes in /etc/vps-node/nodes.db /etc/mihomo/nodes.db; do
    [ ! -r "$formal_nodes" ] || ! grep -Fq "$TEST_CDN_HOST" "$formal_nodes" || { printf 'refusing to reuse a host present in a formal node database\n' >&2; exit 1; }
  done
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
  VP_ROTATION_START_CONFIRM=ROTATE VP_NODE_CREATE_CONFIRM=CREATE \
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

update_candidate_dir="$BASE/update-candidate"
mkdir -p "$update_candidate_dir"
sed 's/^VP_VERSION=.*/VP_VERSION="0.2.0-dev.999999"/' "$CLI" > "$update_candidate_dir/vp.sh"
chmod 755 "$update_candidate_dir/vp.sh"
printf '%s  vp.sh\n' "$(sha256sum "$update_candidate_dir/vp.sh" | awk '{print $1}')" > "$update_candidate_dir/vp.sh.sha256"

cli_before_update_hash="$(file_digest "$CLI")"
isolated_state_before_update="$(file_digest "$BASE/etc/state.env")"
isolated_nodes_before_update="$(file_digest "$BASE/etc/nodes.db")"
isolated_config_before_update="$(file_digest "$BASE/etc/generated/mihomo.yaml")"
all_mihomo_pids_before_update="$(process_ids mihomo)"
VP_ALLOW_TEST_HOOKS=1 VP_UPDATE_SOURCE_DIR="$update_candidate_dir" \
  vp_env "$CLI" update --check >/dev/null
[ "$cli_before_update_hash" = "$(file_digest "$CLI")" ]
[ ! -e "$CLI.previous" ]
[ ! -e "$CLI.previous.sha256" ]

VP_ALLOW_TEST_HOOKS=1 VP_UPDATE_SOURCE_DIR="$update_candidate_dir" VP_UPDATE_CONFIRM=UPDATE \
  vp_env "$CLI" update >/dev/null
[ "$(vp_env "$CLI" version)" = '0.2.0-dev.999999' ]
[ "$(vp_env "$CLI.previous" version)" = "$tested_version" ]
(cd "$(dirname "$CLI.previous")" && sha256sum -c "$(basename "$CLI.previous.sha256")" >/dev/null)
[ "$isolated_state_before_update" = "$(file_digest "$BASE/etc/state.env")" ]
[ "$isolated_nodes_before_update" = "$(file_digest "$BASE/etc/nodes.db")" ]
[ "$isolated_config_before_update" = "$(file_digest "$BASE/etc/generated/mihomo.yaml")" ]
[ "$all_mihomo_pids_before_update" = "$(process_ids mihomo)" ]

VP_ROLLBACK_CONFIRM=ROLLBACK vp_env "$CLI" rollback >/dev/null
[ "$(vp_env "$CLI" version)" = "$tested_version" ]
[ "$(vp_env "$CLI.previous" version)" = '0.2.0-dev.999999' ]
(cd "$(dirname "$CLI.previous")" && sha256sum -c "$(basename "$CLI.previous.sha256")" >/dev/null)
cli_after_rollback_hash="$(file_digest "$CLI")"
printf '\n# isolated acceptance tamper\n' >> "$CLI.previous"
if VP_ROLLBACK_CONFIRM=ROLLBACK vp_env "$CLI" rollback >/dev/null 2>&1; then
  printf 'tampered CLI rollback point unexpectedly accepted\n' >&2
  exit 1
fi
[ "$cli_after_rollback_hash" = "$(file_digest "$CLI")" ]
[ "$(vp_env "$CLI" version)" = "$tested_version" ]
[ "$isolated_state_before_update" = "$(file_digest "$BASE/etc/state.env")" ]
[ "$isolated_nodes_before_update" = "$(file_digest "$BASE/etc/nodes.db")" ]
[ "$isolated_config_before_update" = "$(file_digest "$BASE/etc/generated/mihomo.yaml")" ]
[ "$all_mihomo_pids_before_update" = "$(process_ids mihomo)" ]

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
cdn_result=not-requested
if [ "$cdn_inputs" -eq 7 ]; then
  vp_env "$CLI" cf-token-set "$TEST_CDN_TOKEN_FILE" >/dev/null
  VP_CDN_CREATE_CONFIRM=CREATE VP_CDN_TEST_CONCURRENCY=2 \
    vp_env "$CLI" cdn-add acceptance-cdn "$TEST_CDN_ORIGIN_PORT" "$TEST_CDN_HOST" "$TEST_CDN_PATH" nat "$TEST_CDN_EXTERNAL_PORT" >/dev/null
  vp_env env VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-cdn 2 | grep -q '2/2'
  cdn_mihomo_pids_before_update="$(process_ids mihomo)"
  VP_NAT_UPDATE_CONFIRM=APPLY VP_CDN_TEST_CONCURRENCY=2 \
    vp_env "$CLI" cdn-port-update acceptance-cdn "$TEST_CDN_ALTERNATE_PORT" >/dev/null
  [ "$cdn_mihomo_pids_before_update" = "$(process_ids mihomo)" ]
  vp_env env VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-cdn 2 | grep -q '2/2'
  cdn_nodes_before_failed_update="$(file_digest "$BASE/etc/nodes.db")"
  cdn_state_before_failed_update="$(file_digest "$BASE/etc/cloudflare-cdn.db")"
  if VP_NAT_UPDATE_CONFIRM=APPLY VP_CDN_TEST_CONCURRENCY=2 \
    vp_env "$CLI" cdn-port-update acceptance-cdn "$TEST_CDN_UNMAPPED_PORT" >/dev/null 2>&1; then
    printf 'unmapped CDN port unexpectedly passed public verification\n' >&2
    exit 1
  fi
  [ "$cdn_nodes_before_failed_update" = "$(file_digest "$BASE/etc/nodes.db")" ]
  [ "$cdn_state_before_failed_update" = "$(file_digest "$BASE/etc/cloudflare-cdn.db")" ]
  [ "$cdn_mihomo_pids_before_update" = "$(process_ids mihomo)" ]
  [ "$(awk -F'|' '$1=="cdn"&&$2=="acceptance-cdn"{print $8}' "$BASE/etc/nodes.db")" = "$TEST_CDN_ALTERNATE_PORT" ]
  vp_env env VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-cdn 2 | grep -q '2/2'

  cdn_restore_record="$(awk -F'|' '$1=="acceptance-cdn"{print;exit}' "$BASE/etc/cloudflare-cdn.db")"
  IFS='|' read -r _cdn_name cdn_zone_id cdn_dns_id cdn_dns_disposition cdn_previous_type cdn_previous_content \
    cdn_previous_proxied cdn_ruleset_id cdn_rule_id cdn_ruleset_disposition _cdn_host <<EOF
$cdn_restore_record
EOF
  VP_DELETE_CONFIRM=DELETE vp_env "$CLI" delete acceptance-cdn >/dev/null
  ! grep -q '^cdn|acceptance-cdn|' "$BASE/etc/nodes.db"
  ! grep -q '^acceptance-cdn|' "$BASE/etc/cloudflare-cdn.db"
  cdn_api_token="$(awk 'NR==1{print;exit}' "$TEST_CDN_TOKEN_FILE")"
  cdn_api() {
    curl -fsS --max-time 25 -H "Authorization: Bearer $cdn_api_token" -H 'Content-Type: application/json' \
      "https://api.cloudflare.com/client/v4$1"
  }
  cdn_dns_after="$(cdn_api "/zones/$cdn_zone_id/dns_records/$cdn_dns_id" 2>/dev/null || true)"
  if [ "$cdn_dns_disposition" = created ]; then
    ! printf '%s' "$cdn_dns_after" | jq -e '.success == true' >/dev/null 2>&1
  else
    printf '%s' "$cdn_dns_after" | jq -e --arg type "$cdn_previous_type" --arg content "$cdn_previous_content" \
      --argjson proxied "$cdn_previous_proxied" '.success and .result.type==$type and .result.content==$content and .result.proxied==$proxied' >/dev/null
  fi
  cdn_rules_after="$(cdn_api "/zones/$cdn_zone_id/rulesets/$cdn_ruleset_id" 2>/dev/null || true)"
  if [ "$cdn_ruleset_disposition" = created ]; then
    ! printf '%s' "$cdn_rules_after" | jq -e '.success == true' >/dev/null 2>&1
  else
    ! printf '%s' "$cdn_rules_after" | jq -e --arg id "$cdn_rule_id" '.success and any(.result.rules[]?; .id==$id)' >/dev/null 2>&1
  fi
  unset cdn_api_token
  cdn_result=create-switch-rollback-restore-passed
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
vp_env "$CLI" network-optimize --dry-run >/dev/null

mkdir -p "$BASE/maintenance-tmp"
dd if=/dev/zero of="$BASE/log/maintenance-large.log" bs=1024 count=1100 >/dev/null 2>&1
printf 'expired isolated maintenance data\n' > "$BASE/maintenance-tmp/vp-node-test.acceptance"
touch -t 202001010000 "$BASE/maintenance-tmp/vp-node-test.acceptance"
maintenance_log_hash="$(file_digest "$BASE/log/maintenance-large.log")"
maintenance_nodes_hash="$(file_digest "$BASE/etc/nodes.db")"
vp_env env VP_MAINTENANCE_TMP_ROOT="$BASE/maintenance-tmp" "$CLI" maintain --dry-run >/dev/null
[ "$maintenance_log_hash" = "$(file_digest "$BASE/log/maintenance-large.log")" ]
[ "$maintenance_nodes_hash" = "$(file_digest "$BASE/etc/nodes.db")" ]
vp_env env VP_MAINTENANCE_TMP_ROOT="$BASE/maintenance-tmp" VP_MAINTENANCE_CONFIRM=MAINTAIN "$CLI" maintain >/dev/null
[ "$(wc -c < "$BASE/log/maintenance-large.log")" -eq 1048576 ]
[ ! -e "$BASE/maintenance-tmp/vp-node-test.acceptance" ]
find "$BASE/lib/backups" -name 'vps-node-*.tar.gz' -type f | grep -q .

VP_MONITOR_INSTALL_CONFIRM=ENABLE vp_env env VP_SKIP_SERVICE=1 "$CLI" monitor-install >/dev/null
[ -x "$BASE/usr/bin/watchdog-run" ]
monitor_status="$(vp_env env VP_SKIP_SERVICE=1 "$CLI" stability)"
printf '%s\n' "$monitor_status" | grep -q '后台自愈运行器：已安装且所有权有效'
printf '%s\n' "$monitor_status" | grep -q '定时调度：仅隔离运行器，未注册系统定时任务'
vp_env env VP_SKIP_SERVICE=1 "$CLI" report "$BASE/diagnostic.txt" >/dev/null
! grep -Eq '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$BASE/diagnostic.txt"
grep -q '^watchdog_runner_state=ready$' "$BASE/diagnostic.txt"
grep -q '^watchdog_schedule_state=isolated$' "$BASE/diagnostic.txt"
[ -s "$BASE/diagnostic.txt.sha256" ]
(cd "$BASE" && sha256sum -c diagnostic.txt.sha256 >/dev/null)

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
  printf 'independent_cloudflare_cdn=%s\n' "$cdn_result"
  printf 'credential_rotation=passed\n'
  printf 'backup_restore_roundtrip=passed\n'
  printf 'config_drift_self_heal=passed\n'
  printf 'diagnostic_redaction=passed\n'
  printf 'diagnostic_watchdog_state=passed\n'
  printf 'isolated_watchdog_definition=passed\n'
  printf 'safe_maintenance_preview_backup_and_cleanup=passed\n'
  printf 'cli_update_check_zero_write=passed\n'
  printf 'cli_update_and_rollback=passed\n'
  printf 'tampered_rollback_rejected=passed\n'
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
(cd "$EVIDENCE_DIR" && sha256sum "$(basename "$evidence_file")" > "$(basename "$evidence_file").sha256")
chmod 600 "$evidence_file.sha256"

trap - EXIT HUP INT TERM
rm -rf "$BASE"
printf 'isolated-acceptance: ok host=%s formal-mihomo=%s formal-tunnel=%s\n' \
  "$ACCEPT_HOST" "$formal_mihomo_after" "$formal_tunnel_after"
printf 'evidence=%s\n' "$evidence_file"
