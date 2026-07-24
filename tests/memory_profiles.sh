#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MIHOMO_BIN="${VP_TEST_MIHOMO_BIN:?请通过 VP_TEST_MIHOMO_BIN 指定测试内核}"
ACCEPT_HOST="134.209.180.134"
TMP="$(mktemp -d /tmp/vps-node-memory.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

observed_host="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
[ "$observed_host" = "$ACCEPT_HOST" ] || { printf 'refusing real-core memory test on an unauthorized host\n' >&2; exit 1; }

previous_budget=0
for limit_mib in 64 96 128 192 256 512 1024 2048; do
  case_dir="$TMP/$limit_mib"
  VP_CONFIG_DIR="$case_dir/etc" VP_DATA_DIR="$case_dir/lib" VP_LOG_DIR="$case_dir/log" \
  VP_LIB_DIR="$case_dir/usr-lib" VP_CORE_BIN="$case_dir/usr-lib/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$case_dir/usr-lib/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$MIHOMO_BIN" \
  VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((limit_mib * 1048576)) VP_CPU_COUNT_OVERRIDE=8 VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" core-install >/dev/null

  budget="$(awk -F= '$1=="VP_CORE_BUDGET_MIB"{print $2}' "$case_dir/etc/core.env")"
  profile="$(awk -F= '$1=="VP_MEMORY_PROFILE"{print $2}' "$case_dir/etc/core.env")"
  [ "$budget" -ge 32 ]
  [ "$budget" -le 512 ]
  [ "$budget" -lt "$limit_mib" ]
  [ "$budget" -ge "$previous_budget" ]
  previous_budget="$budget"
  printf '%sMiB -> %sMiB (%s)\n' "$limit_mib" "$budget" "$profile"
done

printf 'memory profiles: ok\n'
