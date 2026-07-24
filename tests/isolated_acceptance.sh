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

[ "$(id -u)" = 0 ] || { printf 'acceptance requires root\n' >&2; exit 1; }
[ -x "$MIHOMO_BIN" ] || { printf 'mihomo binary is not executable\n' >&2; exit 1; }
observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing acceptance on an unauthorized host\n' >&2; exit 1; }

service_active() {
  rc-service "$1" status >/dev/null 2>&1
}

file_digest() {
  [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf absent
}

formal_mihomo_before=inactive
formal_tunnel_before=inactive
service_active mihomo && formal_mihomo_before=active
service_active cloudflared-tunnel && formal_tunnel_before=active
formal_mihomo_config_before="$(file_digest /etc/mihomo/config.yaml)"
formal_mihomo_init_before="$(file_digest /etc/init.d/mihomo)"
formal_tunnel_init_before="$(file_digest /etc/init.d/cloudflared-tunnel)"

vp_env() {
  VP_CONFIG_DIR="$BASE/etc" VP_DATA_DIR="$BASE/lib" VP_LOG_DIR="$BASE/log" \
  VP_LIB_DIR="$BASE/usr" VP_CLI_PATH="$CLI" VP_CLI_BACKUP_PATH="$CLI.previous" \
  VP_CORE_BIN="$BASE/usr/bin/mihomo" VP_CORE_BACKUP_BIN="$BASE/usr/bin/mihomo.previous" \
  VP_CORE_SOURCE_BIN="$MIHOMO_BIN" VP_CORE_SERVICE="$CORE_SERVICE" \
  VP_TUNNEL_SERVICE="$TUNNEL_SERVICE" VP_UNINSTALL_BACKUP_DIR="$BACKUP_DIR" \
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

vp_env "$CLI" init >/dev/null
vp_env "$CLI" core-install >/dev/null
vp_env "$CLI" reality-add acceptance-reality '' www.amd.com ipv4 >/dev/null
vp_env env VP_TEST_SERVER=127.0.0.1 VP_TEST_BYTES=1048576 "$CLI" test-node acceptance-reality 2 | grep -q '2/2 路成功'
vp_env "$CLI" rotate acceptance-reality 1 >/dev/null
vp_env "$CLI" subscription plain | grep -c '^vless://' | grep -q '^2$'
vp_env "$CLI" rotate-finalize acceptance-reality >/dev/null
vp_env "$CLI" subscription plain | grep -c '^vless://' | grep -q '^1$'
vp_env "$CLI" backup "$BASE/acceptance.tar.gz" >/dev/null
[ -s "$BASE/acceptance.tar.gz" ]
[ -s "$BASE/acceptance.tar.gz.sha256" ]
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
[ "$formal_mihomo_before" = "$formal_mihomo_after" ]
[ "$formal_tunnel_before" = "$formal_tunnel_after" ]
[ "$formal_mihomo_config_before" = "$(file_digest /etc/mihomo/config.yaml)" ]
[ "$formal_mihomo_init_before" = "$(file_digest /etc/init.d/mihomo)" ]
[ "$formal_tunnel_init_before" = "$(file_digest /etc/init.d/cloudflared-tunnel)" ]

trap - EXIT HUP INT TERM
rm -rf "$BASE"
printf 'isolated-acceptance: ok host=%s formal-mihomo=%s formal-tunnel=%s\n' \
  "$ACCEPT_HOST" "$formal_mihomo_after" "$formal_tunnel_after"
