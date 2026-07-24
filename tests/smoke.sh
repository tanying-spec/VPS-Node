#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/vps-node-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

VP_CONFIG_DIR="$TMP/etc" \
VP_DATA_DIR="$TMP/lib" \
VP_LOG_DIR="$TMP/log" \
VP_LIB_DIR="$TMP/usr-lib" \
sh "$ROOT/vp.sh" version | grep -Eq '^0\.'

VP_CONFIG_DIR="$TMP/etc" \
VP_DATA_DIR="$TMP/lib" \
VP_LOG_DIR="$TMP/log" \
VP_LIB_DIR="$TMP/usr-lib" \
sh "$ROOT/vp.sh" init >/dev/null

[ "$(stat -c '%a' "$TMP/etc/nodes.db")" = "600" ]

VP_CONFIG_DIR="$TMP/etc" \
VP_DATA_DIR="$TMP/lib" \
VP_LOG_DIR="$TMP/log" \
VP_LIB_DIR="$TMP/usr-lib" \
sh "$ROOT/vp.sh" status | grep -q '实际工作内存'

VP_CONFIG_DIR="$TMP/etc" \
VP_DATA_DIR="$TMP/lib" \
VP_LOG_DIR="$TMP/log" \
VP_LIB_DIR="$TMP/usr-lib" \
VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" optimize >/dev/null

fake_core="$TMP/fake-mihomo"
cat > "$fake_core" <<'FAKE_CORE'
#!/bin/sh
case "${1:-}" in
  -v|-t) exit 0 ;;
  *) exit 0 ;;
esac
FAKE_CORE
chmod 755 "$fake_core"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$fake_core" \
VP_DNS_PUBLIC_SERVERS=192.0.2.1 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" core-install >/dev/null
grep -q '^VP_DNS_MODE=system$' "$TMP/dns-etc/core.env"
! grep -q '1\.1\.1\.1\|8\.8\.8\.8' "$TMP/dns-etc/generated/mihomo.yaml"

printf 'TEST_VALUE=before\n' >> "$TMP/etc/state.env"
VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" \
VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" debug-tx commit TEST_VALUE committed
grep -q '^TEST_VALUE=committed$' "$TMP/etc/state.env"
[ ! -e "$TMP/etc/transactions/active" ]

if VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" \
  VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" debug-tx fail TEST_VALUE rejected; then
  printf 'failed transaction unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q '^TEST_VALUE=committed$' "$TMP/etc/state.env"
[ ! -e "$TMP/etc/transactions/active" ]

set +e
VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" \
VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" debug-tx crash TEST_VALUE interrupted >/dev/null 2>&1
crash_code=$?
set -e
[ "$crash_code" -ne 0 ]
grep -q '^TEST_VALUE=interrupted$' "$TMP/etc/state.env"
[ -d "$TMP/etc/transactions/active" ]
VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" \
sh "$ROOT/vp.sh" init >/dev/null
grep -q '^TEST_VALUE=committed$' "$TMP/etc/state.env"
[ ! -e "$TMP/etc/transactions/active" ]

if [ -n "${VP_TEST_MIHOMO_BIN:-}" ]; then
  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/core-usr-lib/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$VP_TEST_MIHOMO_BIN" \
  VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" core-install >/dev/null
  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/core-usr-lib/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" reality-add test-reality 25432 www.amd.com >/dev/null
  grep -q '^reality|test-reality|25432|' "$TMP/core-etc/nodes.db"
  "$TMP/core-usr-lib/bin/mihomo" -t -d "$TMP/core-etc" -f "$TMP/core-etc/generated/mihomo.yaml" >/dev/null
  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  sh "$ROOT/vp.sh" link test-reality | grep -q '^vless://'

  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/core-usr-lib/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" argo-add test-argo 25434 tunnel.example.com /private-path >/dev/null
  grep -q '^argo|test-argo|25434|' "$TMP/core-etc/nodes.db"
  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  sh "$ROOT/vp.sh" link test-argo | grep -q '^vless://'
  VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
  VP_LIB_DIR="$TMP/core-usr-lib" VP_CORE_BIN="$TMP/core-usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/core-usr-lib/bin/mihomo.previous" VP_SKIP_SERVICE=1 VP_DELETE_CONFIRM=DELETE \
  sh "$ROOT/vp.sh" delete test-argo >/dev/null
  ! grep -q '^argo|test-argo|' "$TMP/core-etc/nodes.db"

  if [ -n "${VP_TEST_CLOUDFLARED_BIN:-}" ]; then
    printf 'test.token_value-123\n' > "$TMP/tunnel.token"
    VP_CONFIG_DIR="$TMP/core-etc" VP_DATA_DIR="$TMP/core-lib" VP_LOG_DIR="$TMP/core-log" \
    VP_LIB_DIR="$TMP/core-usr-lib" VP_TUNNEL_BIN="$TMP/core-usr-lib/bin/cloudflared" \
    VP_TUNNEL_BACKUP_BIN="$TMP/core-usr-lib/bin/cloudflared.previous" \
    VP_TUNNEL_SOURCE_BIN="$VP_TEST_CLOUDFLARED_BIN" VP_SKIP_SERVICE=1 \
    sh "$ROOT/vp.sh" tunnel-install "$TMP/tunnel.token" >/dev/null
    [ "$(stat -c '%a' "$TMP/core-etc/secrets/cloudflared.token")" = "600" ]
  fi
fi

printf 'smoke: ok\n'
