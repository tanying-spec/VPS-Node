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

printf 'smoke: ok\n'

