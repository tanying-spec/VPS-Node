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

printf 'smoke: ok\n'
