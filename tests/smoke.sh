#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/vps-node-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
CURRENT_VERSION="$(sh "$ROOT/vp.sh" version)"

digest64="$(printf '%064d' 1)"
compact_release="$TMP/release-compact.json"
cat > "$compact_release" <<EOF
{"tag_name":"v1.2.3","assets":[{"browser_download_url":"https:\/\/github.com\/MetaCubeX\/mihomo\/releases\/download\/v1.2.3\/mihomo-linux-amd64-compatible-v1.2.3.gz","uploader":{"name":"not-an-asset"},"digest":"sha256:$digest64","name":"mihomo-linux-amd64-compatible-v1.2.3.gz"}]}
EOF
parsed_record="$(VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-release-records "$compact_release")"
[ "$parsed_record" = "mihomo-linux-amd64-compatible-v1.2.3.gz|https://github.com/MetaCubeX/mihomo/releases/download/v1.2.3/mihomo-linux-amd64-compatible-v1.2.3.gz|$digest64" ]
VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-validate-release-record "$parsed_record" \
  'https://github.com/MetaCubeX/mihomo/releases/download/'
single_record="$TMP/release-single.txt"
printf '%s\n' "$parsed_record" > "$single_record"
[ "$(VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-select-release-record "$single_record" \
  '^mihomo-linux-amd64-compatible-v[0-9]+[.][0-9]+[.][0-9]+[.]gz[|]')" = "$parsed_record" ]
if VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-validate-release-record \
  "mihomo-linux-amd64-compatible-v1.2.3.gz|https://example.com/mihomo.gz|$digest64" \
  'https://github.com/MetaCubeX/mihomo/releases/download/'; then
  echo 'untrusted release URL was accepted' >&2
  exit 1
fi
if VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-validate-release-record \
  "mihomo-linux-amd64-compatible-v1.2.3.gz|https://github.com/MetaCubeX/mihomo/releases/download/v1.2.3/other.gz|$digest64" \
  'https://github.com/MetaCubeX/mihomo/releases/download/'; then
  echo 'release URL with a mismatched asset name was accepted' >&2
  exit 1
fi
if VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-validate-release-record \
  "mihomo-linux-amd64-compatible-v1.2.3.gz|https://github.com/MetaCubeX/mihomo/releases/download/v1.2.3/mihomo.gz|${digest64%?}" \
  'https://github.com/MetaCubeX/mihomo/releases/download/'; then
  echo 'short release digest was accepted' >&2
  exit 1
fi
duplicate_records="$TMP/release-duplicates.txt"
printf '%s\n%s\n' "$parsed_record" "$parsed_record" > "$duplicate_records"
if VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-select-release-record "$duplicate_records" \
  '^mihomo-linux-amd64-compatible-v[0-9]+[.][0-9]+[.][0-9]+[.]gz[|]'; then
  echo 'ambiguous duplicate release assets were accepted' >&2
  exit 1
fi
commit_json="$TMP/commit.json"
printf '%s\n' '{"nested":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' > "$commit_json"
[ "$(VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" _test-json-top-level "$commit_json" sha)" = \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]

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

mkdir -p "$TMP/status-bin"
cat > "$TMP/status-bin/systemctl" <<'FAKE_SYSTEMCTL'
#!/bin/sh
if [ "${1:-}" = is-active ] && { [ "${2:-}" = custom-core ] || [ "${2:-}" = custom-tunnel ]; }; then
  printf 'active\n'
  exit 0
fi
printf 'inactive\n'
exit 3
FAKE_SYSTEMCTL
chmod 755 "$TMP/status-bin/systemctl"
custom_status="$(PATH="$TMP/status-bin:$PATH" VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" \
  VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" VP_CORE_SERVICE=custom-core \
  VP_TUNNEL_SERVICE=custom-tunnel sh "$ROOT/vp.sh" status)"
printf '%s\n' "$custom_status" | grep -q '^Cloudflare Tunnel：active$'

uninstalled_status="$(VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" \
  VP_LIB_DIR="$TMP/usr-lib" sh "$ROOT/vp.sh" status)"
printf '%s\n' "$uninstalled_status" | grep -q '总体状态：尚未安装'
printf '%s\n' "$uninstalled_status" | grep -q '^下一步：请选择 1 创建 Reality 主节点'

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
  *) exec tail -f /dev/null ;;
esac
FAKE_CORE
chmod 755 "$fake_core"
mkdir -p "$TMP/collision-bin"
cat > "$TMP/collision-bin/ss" <<'FAKE_SS'
#!/bin/sh
printf 'tcp LISTEN 0 128 127.0.0.1:17890 0.0.0.0:*\n'
FAKE_SS
chmod 755 "$TMP/collision-bin/ss"
PATH="$TMP/collision-bin:$PATH" VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$fake_core" \
VP_DNS_PUBLIC_SERVERS=192.0.2.1 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" core-install >/dev/null
selected_mixed_port="$(awk -F= '$1=="VP_MIXED_PORT"{print $2;exit}' "$TMP/dns-etc/state.env")"
[ -n "$selected_mixed_port" ]
[ "$selected_mixed_port" != 17890 ]
grep -q "^mixed-port: $selected_mixed_port$" "$TMP/dns-etc/generated/mihomo.yaml"
grep -q '^VP_CONTROLLER_PORT=19090$' "$TMP/dns-etc/state.env"
grep -q '^VP_DNS_MODE=system$' "$TMP/dns-etc/core.env"
! grep -q '1\.1\.1\.1\|8\.8\.8\.8' "$TMP/dns-etc/generated/mihomo.yaml"
core_env_hash_before="$(sha256sum "$TMP/dns-etc/core.env" | awk '{print $1}')"
core_state_hash_before="$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')"
core_binary_hash_before="$(sha256sum "$TMP/dns-usr/bin/mihomo" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$fake_core" \
  VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((768 * 1048576)) VP_ALLOW_TEST_HOOKS=1 VP_TEST_CORE_RESTART_FAIL=1 \
  sh "$ROOT/vp.sh" core-install >/dev/null 2>&1; then
  printf 'core install unexpectedly succeeded despite forced restart failure\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/core.env" | awk '{print $1}')" = "$core_env_hash_before" ]
[ "$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')" = "$core_state_hash_before" ]
[ "$(sha256sum "$TMP/dns-usr/bin/mihomo" | awk '{print $1}')" = "$core_binary_hash_before" ]
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((512 * 1048576)) \
VP_CPU_COUNT_OVERRIDE=8 VP_CPU_QUOTA_MILLI_OVERRIDE=500 VP_CPUSET_COUNT_OVERRIDE=4 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" repair >/dev/null
grep -q '^VP_CPU_EFFECTIVE_COUNT=1$' "$TMP/dns-etc/core.env"
grep -q '^VP_CPU_QUOTA_MILLI=500$' "$TMP/dns-etc/core.env"
grep -q '^GOMAXPROCS=1$' "$TMP/dns-etc/core.env"
grep -q '^VP_MEMORY_PROFILE=standard-cpu-limited$' "$TMP/dns-etc/core.env"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_MEMORY_LIMIT_BYTES_OVERRIDE=$((1024 * 1048576)) \
VP_CPU_COUNT_OVERRIDE=8 VP_CPU_QUOTA_MILLI_OVERRIDE=2500 VP_CPUSET_COUNT_OVERRIDE=2 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" repair >/dev/null
grep -q '^VP_CPU_EFFECTIVE_COUNT=2$' "$TMP/dns-etc/core.env"
printf '3\n' > "$TMP/dns-lib/oom-kill.count"
oom_output="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_OOM_CURRENT_OVERRIDE=5 VP_CPU_COUNT_OVERRIDE=4 VP_CPU_QUOTA_MILLI_OVERRIDE=2000 \
  VP_CPUSET_COUNT_OVERRIDE=2 sh "$ROOT/vp.sh" status)"
printf '%s\n' "$oom_output" | grep -q '宿主可见 / 实际可用：4 / 2 核'
printf '%s\n' "$oom_output" | grep -q 'OOM Kill：新增 2 次（累计 5）'
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" reality-add numbered-node 25433 www.amd.com >/dev/null
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" rotate numbered-node 24 >/dev/null
rotation_dashboard="$(PATH="$TMP/status-bin:$PATH" VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" \
  VP_LOG_DIR="$TMP/dns-log" VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_SERVICE=custom-core VP_TUNNEL_SERVICE=custom-tunnel sh "$ROOT/vp.sh" status)"
printf '%s\n' "$rotation_dashboard" | grep -q '^总体状态：凭据轮换中$'
printf '%s\n' "$rotation_dashboard" | grep -q '下一步：先选择 3 → 选择节点 → 2.*重新选择 3 → 同一节点 → 5'
cp "$TMP/dns-etc/credential-rotations.db" "$TMP/rotations-active"
awk -F'|' 'BEGIN{OFS="|"}{$5=2;$6=1;print}' "$TMP/rotations-active" > "$TMP/dns-etc/credential-rotations.db"
expired_dashboard="$(PATH="$TMP/status-bin:$PATH" VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" \
  VP_LOG_DIR="$TMP/dns-log" VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_SERVICE=custom-core VP_TUNNEL_SERVICE=custom-tunnel sh "$ROOT/vp.sh" status)"
printf '%s\n' "$expired_dashboard" | grep -q '^总体状态：凭据轮换已到期$'
printf '%s\n' "$expired_dashboard" | grep -q '下一步：.*选择 3 → 选择节点 → 5.*FINALIZE'
mv "$TMP/rotations-active" "$TMP/dns-etc/credential-rotations.db"
mkdir -p "$TMP/status-core-only" "$TMP/dns-etc/secrets"
cat > "$TMP/status-core-only/systemctl" <<'CORE_ONLY_SYSTEMCTL'
#!/bin/sh
if [ "${1:-}" = is-active ] && [ "${2:-}" = custom-core ]; then
  printf 'active\n'
  exit 0
fi
printf 'inactive\n'
exit 3
CORE_ONLY_SYSTEMCTL
chmod 755 "$TMP/status-core-only/systemctl"
cp "$TMP/dns-etc/credential-rotations.db" "$TMP/rotations-before-token-only-dashboard"
: > "$TMP/dns-etc/credential-rotations.db"
printf 'token-present-without-argo-node\n' > "$TMP/dns-etc/secrets/cloudflared.token"
token_only_dashboard="$(PATH="$TMP/status-core-only:$PATH" VP_CONFIG_DIR="$TMP/dns-etc" \
  VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" VP_LIB_DIR="$TMP/dns-usr" \
  VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_CORE_SERVICE=custom-core VP_TUNNEL_SERVICE=custom-tunnel \
  sh "$ROOT/vp.sh" status)"
printf '%s\n' "$token_only_dashboard" | grep -q '^总体状态：主线路已就绪$'
printf '%s\n' "$token_only_dashboard" | grep -q '^下一步：可选择 2 增加 Cloudflare 备用节点'
mv "$TMP/rotations-before-token-only-dashboard" "$TMP/dns-etc/credential-rotations.db"
rm -f "$TMP/dns-etc/secrets/cloudflared.token"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" edit numbered-node renamed-node 25433 www.microsoft.com >/dev/null
grep -q '^reality|renamed-node|25433|[^|]*|www.microsoft.com|www.microsoft.com:443|' "$TMP/dns-etc/nodes.db"
grep -q '^renamed-node|reality|' "$TMP/dns-etc/credential-rotations.db"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_PUBLIC_IPV6_OVERRIDE=2001:db8::10 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" edit renamed-node renamed-node 25433 www.microsoft.com ipv6 >/dev/null
grep -q '^reality|renamed-node|25433|.*|ipv6$' "$TMP/dns-etc/nodes.db"
grep -q "listen: '::'" "$TMP/dns-etc/generated/mihomo.yaml"
ipv6_link="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_PUBLIC_IPV6_OVERRIDE=2001:db8::10 sh "$ROOT/vp.sh" link renamed-node)"
printf '%s\n' "$ipv6_link" | grep -q '@\[2001:db8::10\]:25433'
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_PUBLIC_IPV6_OVERRIDE=not-an-ip \
  VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" reality-add bad-v6 25435 www.amd.com ipv6 >/dev/null 2>&1; then
  printf 'invalid public IPv6 unexpectedly accepted\n' >&2
  exit 1
fi
! grep -q '|bad-v6|' "$TMP/dns-etc/nodes.db"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" argo-add argo-edit 25434 old.example.com /old-path >/dev/null
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" edit argo-edit argo-renamed 25434 new.example.com /new-path >/dev/null
grep -q '^argo|argo-renamed|25434|[^|]*|/new-path|new.example.com$' "$TMP/dns-etc/nodes.db"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" argo-add 'phone#backup' 25436 share.example.com '/ws?ed=2048&mode=fast' >/dev/null
special_link="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" sh "$ROOT/vp.sh" link 'phone#backup')"
printf '%s\n' "$special_link" | grep -Fq 'path=%2Fws%3Fed%3D2048%26mode%3Dfast#phone%23backup'
cp "$TMP/dns-etc/nodes.db" "$TMP/nodes-before-dashboard-check"
printf '%s\n' 'argo|bad-duplicate|25436|66666666-6666-4666-8666-666666666666|/bad|bad.example.com' >> "$TMP/dns-etc/nodes.db"
invalid_dashboard="$(PATH="$TMP/status-bin:$PATH" VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" \
  VP_LOG_DIR="$TMP/dns-log" VP_LIB_DIR="$TMP/dns-usr" VP_CORE_SERVICE=custom-core \
  VP_TUNNEL_SERVICE=custom-tunnel sh "$ROOT/vp.sh" status)"
printf '%s\n' "$invalid_dashboard" | grep -q '^总体状态：状态数据异常$'
printf '%s\n' "$invalid_dashboard" | grep -q '下一步：.*5 → 3.*7 → 5'
mv "$TMP/nodes-before-dashboard-check" "$TMP/dns-etc/nodes.db"
clean_config_hash="$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')"
printf '\n# syntactically-valid manual drift\n' >> "$TMP/dns-etc/generated/mihomo.yaml"
drift_health="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" health 2>&1 || true)"
printf '%s\n' "$drift_health" | grep -q '配置语法有效但已偏离节点状态'
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" repair >/dev/null
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$clean_config_hash" ]
printf '\n# drift that must survive failed restart rollback\n' >> "$TMP/dns-etc/generated/mihomo.yaml"
drifted_config_hash="$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_ALLOW_TEST_HOOKS=1 \
  VP_TEST_CORE_RESTART_FAIL=1 sh "$ROOT/vp.sh" repair >/dev/null 2>&1; then
  printf 'repair unexpectedly succeeded despite forced restart failure\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$drifted_config_hash" ]
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" repair >/dev/null
plain_subscription="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_PUBLIC_IPV6_OVERRIDE=2001:db8::10 sh "$ROOT/vp.sh" subscription plain)"
[ "$(printf '%s\n' "$plain_subscription" | grep -c '^vless://')" -eq 4 ]
current_uuid="$(awk -F'|' '$2=="renamed-node"{print $4}' "$TMP/dns-etc/nodes.db")"
old_uuid="$(awk -F'|' '$1=="renamed-node"{print $3}' "$TMP/dns-etc/credential-rotations.db")"
printf '%s\n' "$plain_subscription" | grep -Fq "vless://$current_uuid@"
printf '%s\n' "$plain_subscription" | grep -Fq "vless://$old_uuid@"
base64_subscription="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_PUBLIC_IPV6_OVERRIDE=2001:db8::10 sh "$ROOT/vp.sh" subscription base64)"
[ "$(printf '%s' "$base64_subscription" | base64 -d | grep -c '^vless://')" -eq 4 ]
rotation_db_before_finalize="$(sha256sum "$TMP/dns-etc/credential-rotations.db" | awk '{print $1}')"
rotation_config_before_finalize="$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')"
cp "$TMP/dns-etc/credential-rotations.db" "$TMP/rotations-before-invalid-finalize"
awk -F'|' 'BEGIN{OFS="|"} $1=="renamed-node"{$5="invalid"}{print}' \
  "$TMP/rotations-before-invalid-finalize" > "$TMP/dns-etc/credential-rotations.db"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  VP_ROTATION_FINALIZE_CONFIRM=FINALIZE sh "$ROOT/vp.sh" rotate-finalize renamed-node >/dev/null 2>&1; then
  printf 'invalid rotation expiry unexpectedly reached finalization\n' >&2
  exit 1
fi
mv "$TMP/rotations-before-invalid-finalize" "$TMP/dns-etc/credential-rotations.db"
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$rotation_config_before_finalize" ]
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" rotate-finalize renamed-node </dev/null >/dev/null 2>&1; then
  printf 'unconfirmed credential finalization unexpectedly succeeded\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/credential-rotations.db" | awk '{print $1}')" = "$rotation_db_before_finalize" ]
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$rotation_config_before_finalize" ]
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  VP_ALLOW_TEST_HOOKS=1 VP_TEST_CORE_RESTART_FAIL=1 VP_ROTATION_FINALIZE_CONFIRM=FINALIZE \
  sh "$ROOT/vp.sh" rotate-finalize renamed-node >/dev/null 2>&1; then
  printf 'credential finalization unexpectedly survived restart failure\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/credential-rotations.db" | awk '{print $1}')" = "$rotation_db_before_finalize" ]
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$rotation_config_before_finalize" ]
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
VP_ROTATION_FINALIZE_CONFIRM=FINALIZE sh "$ROOT/vp.sh" rotate-finalize renamed-node >/dev/null
! grep -q '^renamed-node|' "$TMP/dns-etc/credential-rotations.db"
! grep -Fq "$old_uuid" "$TMP/dns-etc/generated/mihomo.yaml"
printf '%s\n' 'argo|broken|25437|not-a-uuid|/broken|broken.example.com' >> "$TMP/dns-etc/nodes.db"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" sh "$ROOT/vp.sh" link broken >/dev/null 2>"$TMP/broken-link.err"; then
  printf 'malformed node unexpectedly produced a share link\n' >&2
  exit 1
fi
grep -q 'UUID 格式无效' "$TMP/broken-link.err"
sed -i '/^argo|broken|/d' "$TMP/dns-etc/nodes.db"
legacy_db="$TMP/legacy-nodes.db"
cat > "$legacy_db" <<'LEGACY_DB'
vless-reality|legacy-reality|26433|11111111-1111-4111-8111-111111111111|www.amd.com|www.amd.com:443|legacy-private|legacy-public|a1b2c3d4e5f60708
vless-ws|legacy-argo|26434|22222222-2222-4222-8222-222222222222|/legacy|legacy.example.com|argo|legacy.example.com|443
hysteria2|legacy-hy2|26435|password|www.amd.com|cert|key||
vless-ws|legacy-cdn|26436|33333333-3333-4333-8333-333333333333|/cdn|cdn.example.com|cdn|preferred.example.com|443
LEGACY_DB
legacy_hash_before="$(sha256sum "$legacy_db" | awk '{print $1}')"
migration_preview="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" migrate-mh "$legacy_db" --dry-run)"
printf '%s\n' "$migration_preview" | grep -q '可无损导入 2，协议不支持 1，字段/模式不可无损转换 1'
ln -s "$legacy_db" "$TMP/legacy-nodes-link.db"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" migrate-mh "$TMP/legacy-nodes-link.db" --dry-run >/dev/null 2>&1; then
  printf 'symlink migration source unexpectedly accepted\n' >&2
  exit 1
fi
migration_race_db="$TMP/legacy-nodes-race.db"
cp "$legacy_db" "$migration_race_db"
migration_nodes_before="$(sha256sum "$TMP/dns-etc/nodes.db" | awk '{print $1}')"
migration_backups_before="$(find "$TMP/dns-lib/backups" -type f 2>/dev/null | wc -l | tr -d ' ')"
(sleep 1; printf '\n# changed during confirmation\n' >> "$migration_race_db") &
migration_mutator_pid=$!
if (sleep 2; printf 'MIGRATE\n') | \
  VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" migrate-mh "$migration_race_db" --apply >/dev/null 2>&1; then
  printf 'migration source change during confirmation unexpectedly accepted\n' >&2
  exit 1
fi
wait "$migration_mutator_pid"
[ "$(sha256sum "$TMP/dns-etc/nodes.db" | awk '{print $1}')" = "$migration_nodes_before" ]
[ "$(find "$TMP/dns-lib/backups" -type f 2>/dev/null | wc -l | tr -d ' ')" = "$migration_backups_before" ]
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_MIGRATE_CONFIRM=MIGRATE VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" migrate-mh "$legacy_db" --apply >/dev/null
grep -q '^reality|legacy-reality|26433|11111111-1111-4111-8111-111111111111|www.amd.com|www.amd.com:443|legacy-private|legacy-public|a1b2c3d4e5f60708|ipv4$' "$TMP/dns-etc/nodes.db"
grep -q '^argo|legacy-argo|26434|22222222-2222-4222-8222-222222222222|/legacy|legacy.example.com$' "$TMP/dns-etc/nodes.db"
! grep -q 'legacy-hy2\|legacy-cdn' "$TMP/dns-etc/nodes.db"
[ "$legacy_hash_before" = "$(sha256sum "$legacy_db" | awk '{print $1}')" ]
fake_curl="$TMP/fake-curl"
cat > "$fake_curl" <<'FAKE_CURL'
#!/bin/sh
case "$*" in
  *generate_204*) printf '204|0.010000|0.020000|0.030000' ;;
  *__down*) printf '200|1024|1048576|0.040000|0.100000' ;;
  *) exit 1 ;;
esac
FAKE_CURL
chmod 755 "$fake_curl"
concurrent_output="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$fake_curl" \
  VP_TEST_SERVER=127.0.0.1 VP_TEST_BYTES=1024 VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" test-node renamed-node 4)"
printf '%s\n' "$concurrent_output" | grep -q '4/4 路成功'
printf '%s\n' "$concurrent_output" | grep -q '聚合速度 4.00 MiB/s'
sysctl_state="$TMP/fake-sysctl.state"
printf 'CC=cubic\nQDISC=pfifo_fast\n' > "$sysctl_state"
fake_sysctl="$TMP/fake-sysctl"
cat > "$fake_sysctl" <<'FAKE_SYSCTL'
#!/bin/sh
. "$VP_FAKE_SYSCTL_STATE"
if [ "${1:-}" = "-n" ]; then
  case "${2:-}" in
    net.ipv4.tcp_congestion_control) printf '%s\n' "$CC" ;;
    net.ipv4.tcp_available_congestion_control) printf 'cubic bbr\n' ;;
    net.core.default_qdisc) printf '%s\n' "$QDISC" ;;
    *) exit 1 ;;
  esac
elif [ "${1:-}" = "-w" ]; then
  if [ -n "${VP_FAKE_SYSCTL_FAIL_ONCE_KEY:-}" ] && [ "${2%%=*}" = "$VP_FAKE_SYSCTL_FAIL_ONCE_KEY" ] && \
     [ -n "${VP_FAKE_SYSCTL_FAIL_ONCE_FILE:-}" ] && [ ! -e "$VP_FAKE_SYSCTL_FAIL_ONCE_FILE" ]; then
    : > "$VP_FAKE_SYSCTL_FAIL_ONCE_FILE"
    exit 1
  fi
  case "${2:-}" in
    net.ipv4.tcp_congestion_control=*) CC="${2#*=}" ;;
    net.core.default_qdisc=*) QDISC="${2#*=}" ;;
    *) exit 1 ;;
  esac
  printf 'CC=%s\nQDISC=%s\n' "$CC" "$QDISC" > "$VP_FAKE_SYSCTL_STATE"
else
  exit 1
fi
FAKE_SYSCTL
adaptive_curl="$TMP/adaptive-curl"
cat > "$adaptive_curl" <<'ADAPTIVE_CURL'
#!/bin/sh
. "$VP_FAKE_SYSCTL_STATE"
case "$*" in
  *generate_204*) printf '204|0.010000|0.020000|0.030000' ;;
  *__down*)
    [ "$CC" = bbr ] && speed="${VP_FAKE_BBR_SPEED:-2097152}" || speed=1048576
    printf '200|1024|%s|0.040000|0.100000' "$speed"
    ;;
  *) exit 1 ;;
esac
ADAPTIVE_CURL
chmod 755 "$fake_sysctl" "$adaptive_curl"
network_config="$TMP/99-vps-node-network.conf"
network_snapshot="$TMP/network-before.env"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$adaptive_curl" \
VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
VP_TEST_SERVER=127.0.0.1 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" network-optimize --dry-run >/dev/null
grep -q '^CC=cubic$' "$sysctl_state"
[ ! -e "$network_config" ]
for network_fail_phase in after-snapshot before-config-commit; do
  if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
    VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
    VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$adaptive_curl" \
    VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
    VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
    VP_NETWORK_CONFIRM=APPLY VP_TEST_SERVER=127.0.0.1 VP_SKIP_SERVICE=1 \
    VP_ALLOW_TEST_HOOKS=1 VP_TEST_NETWORK_PERSIST_FAIL_PHASE="$network_fail_phase" \
    sh "$ROOT/vp.sh" network-optimize renamed-node 2 >/dev/null 2>&1; then
    printf 'network persistence fault unexpectedly succeeded: %s\n' "$network_fail_phase" >&2
    exit 1
  fi
  grep -q '^CC=cubic$' "$sysctl_state"
  grep -q '^QDISC=pfifo_fast$' "$sysctl_state"
  [ ! -e "$network_config" ]
  [ ! -e "$network_snapshot" ]
  ! find "$TMP" -maxdepth 1 -name '.vps-node-network-*' -print | grep -q .
done
printf 'BROKEN=1\n' > "$network_snapshot"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$adaptive_curl" \
  VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
  VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
  VP_NETWORK_CONFIRM=APPLY VP_TEST_SERVER=127.0.0.1 VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" network-optimize renamed-node 2 >/dev/null 2>&1; then
  printf 'invalid existing network snapshot unexpectedly overwritten\n' >&2
  exit 1
fi
grep -q '^BROKEN=1$' "$network_snapshot"
grep -q '^CC=cubic$' "$sysctl_state"
grep -q '^QDISC=pfifo_fast$' "$sysctl_state"
[ ! -e "$network_config" ]
rm -f "$network_snapshot"
network_output="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$adaptive_curl" \
  VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
  VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
  VP_NETWORK_CONFIRM=APPLY VP_TEST_SERVER=127.0.0.1 VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" network-optimize renamed-node 2)"
printf '%s\n' "$network_output" | grep -q '2.00 -> 4.00 MiB/s'
grep -q '^CC=bbr$' "$sysctl_state"
grep -q '^QDISC=fq$' "$sysctl_state"
[ -s "$network_config" ]
[ -s "$network_snapshot" ]
sysctl_fail_once="$TMP/fake-sysctl-failed-once"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
  VP_FAKE_SYSCTL_FAIL_ONCE_KEY=net.core.default_qdisc VP_FAKE_SYSCTL_FAIL_ONCE_FILE="$sysctl_fail_once" \
  VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
  sh "$ROOT/vp.sh" network-rollback >/dev/null 2>&1; then
  printf 'partially failed network rollback unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q '^CC=bbr$' "$sysctl_state"
grep -q '^QDISC=fq$' "$sysctl_state"
[ -s "$network_config" ]
[ -s "$network_snapshot" ]
rm -f "$sysctl_fail_once"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" \
VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
sh "$ROOT/vp.sh" network-rollback >/dev/null
grep -q '^CC=cubic$' "$sysctl_state"
grep -q '^QDISC=pfifo_fast$' "$sysctl_state"
[ ! -e "$network_config" ]
[ ! -e "$network_snapshot" ]
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CURL_BIN="$adaptive_curl" \
  VP_SYSCTL_BIN="$fake_sysctl" VP_FAKE_SYSCTL_STATE="$sysctl_state" VP_FAKE_BBR_SPEED=524288 \
  VP_SYSCTL_CONFIG="$network_config" VP_NETWORK_SNAPSHOT="$network_snapshot" \
  VP_NETWORK_CONFIRM=APPLY VP_TEST_SERVER=127.0.0.1 VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" network-optimize renamed-node 2 >/dev/null 2>&1; then
  printf 'regressed network candidate unexpectedly accepted\n' >&2
  exit 1
fi
grep -q '^CC=cubic$' "$sysctl_state"
grep -q '^QDISC=pfifo_fast$' "$sysctl_state"
[ ! -e "$network_config" ]
[ ! -e "$network_snapshot" ]
menu_output="$(printf '3\n1\n1\n\n0\n' | \
  VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh")"
printf '%s\n' "$menu_output" | grep -q 'vless://'

mkdir -p "$TMP/dns-etc/secrets"
printf 'sensitive-test-token-should-not-leak\n' > "$TMP/dns-etc/secrets/cloudflared.token"
chmod 600 "$TMP/dns-etc/secrets/cloudflared.token"
diagnostic="$TMP/redacted-diagnostic.txt"
interrupted_diagnostic="$TMP/interrupted-diagnostic.txt"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
  VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
  VP_ALLOW_TEST_HOOKS=1 VP_TEST_DIAGNOSTIC_FAIL_PHASE=after-report \
  sh "$ROOT/vp.sh" report "$interrupted_diagnostic" >/dev/null 2>&1; then
  printf 'interrupted diagnostic report unexpectedly succeeded\n' >&2
  exit 1
fi
[ ! -e "$interrupted_diagnostic" ]
[ ! -e "$interrupted_diagnostic.sha256" ]
protected_report_target="$TMP/protected-report-target"
printf 'do-not-overwrite\n' > "$protected_report_target"
ln -s "$protected_report_target" "$TMP/symlink-diagnostic.txt"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" report "$TMP/symlink-diagnostic.txt" >/dev/null 2>&1; then
  printf 'symlink diagnostic destination unexpectedly accepted\n' >&2
  exit 1
fi
grep -q '^do-not-overwrite$' "$protected_report_target"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" report "$diagnostic" >/dev/null
[ "$(stat -c '%a' "$diagnostic")" = "600" ]
[ -s "$diagnostic.sha256" ]
(cd "$TMP" && sha256sum -c "$(basename "$diagnostic").sha256" >/dev/null)
grep -q '^redacted_nodes:' "$diagnostic"
grep -q 'credentials=<redacted>' "$diagnostic"
! grep -Fq 'sensitive-test-token-should-not-leak' "$diagnostic"
! grep -Fq 'www.microsoft.com' "$diagnostic"
! grep -Fq 'new.example.com' "$diagnostic"
node_uuid="$(awk -F'|' 'NR==1{print $4}' "$TMP/dns-etc/nodes.db")"
! grep -Fq "$node_uuid" "$diagnostic"
diagnostic_hash_before="$(sha256sum "$diagnostic" | awk '{print $1}')"
diagnostic_sidecar_hash_before="$(sha256sum "$diagnostic.sha256" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" report "$diagnostic" >/dev/null 2>&1; then
  printf 'existing diagnostic report unexpectedly overwritten\n' >&2
  exit 1
fi
[ "$(sha256sum "$diagnostic" | awk '{print $1}')" = "$diagnostic_hash_before" ]
[ "$(sha256sum "$diagnostic.sha256" | awk '{print $1}')" = "$diagnostic_sidecar_hash_before" ]

tunnel_tx="$TMP/tunnel-transaction"
mkdir -p "$tunnel_tx/usr/bin" "$tunnel_tx/etc/secrets"
cat > "$tunnel_tx/usr/bin/cloudflared" <<'OLD_TUNNEL'
#!/bin/sh
[ "${1:-}" = version ] && { printf 'old-cloudflared\n'; exit 0; }
exit 0
OLD_TUNNEL
cat > "$tunnel_tx/new-cloudflared" <<'NEW_TUNNEL'
#!/bin/sh
[ "${1:-}" = version ] && { printf 'new-cloudflared\n'; exit 0; }
exit 0
NEW_TUNNEL
chmod 755 "$tunnel_tx/usr/bin/cloudflared" "$tunnel_tx/new-cloudflared"
printf 'old.transaction.token\n' > "$tunnel_tx/etc/secrets/cloudflared.token"
printf 'new.transaction.token\n' > "$tunnel_tx/new.token"
old_tunnel_hash="$(sha256sum "$tunnel_tx/usr/bin/cloudflared" | awk '{print $1}')"
set +e
VP_CONFIG_DIR="$tunnel_tx/etc" VP_DATA_DIR="$tunnel_tx/lib" VP_LOG_DIR="$tunnel_tx/log" \
VP_LIB_DIR="$tunnel_tx/usr" VP_TUNNEL_BIN="$tunnel_tx/usr/bin/cloudflared" \
VP_TUNNEL_BACKUP_BIN="$tunnel_tx/usr/bin/cloudflared.previous" \
VP_TUNNEL_SOURCE_BIN="$tunnel_tx/new-cloudflared" VP_SKIP_SERVICE=1 VP_ALLOW_TEST_HOOKS=1 \
VP_TEST_TUNNEL_RESTART_FAIL=1 sh "$ROOT/vp.sh" tunnel-install "$tunnel_tx/new.token" >/dev/null 2>&1
tunnel_failure_code=$?
set -e
[ "$tunnel_failure_code" -ne 0 ]
[ "$(sha256sum "$tunnel_tx/usr/bin/cloudflared" | awk '{print $1}')" = "$old_tunnel_hash" ]
[ "$(cat "$tunnel_tx/etc/secrets/cloudflared.token")" = 'old.transaction.token' ]
[ "$(stat -c '%a' "$tunnel_tx/etc/secrets/cloudflared.token")" = 600 ]
! grep -q '^VP_TUNNEL_METRICS_PORT=' "$tunnel_tx/etc/state.env"
fresh_tunnel="$TMP/tunnel-fresh-failure"
mkdir -p "$fresh_tunnel"
set +e
VP_CONFIG_DIR="$fresh_tunnel/etc" VP_DATA_DIR="$fresh_tunnel/lib" VP_LOG_DIR="$fresh_tunnel/log" \
VP_LIB_DIR="$fresh_tunnel/usr" VP_TUNNEL_SOURCE_BIN="$tunnel_tx/new-cloudflared" \
VP_SKIP_SERVICE=1 VP_ALLOW_TEST_HOOKS=1 VP_TEST_TUNNEL_RESTART_FAIL=1 \
sh "$ROOT/vp.sh" tunnel-install "$tunnel_tx/new.token" >/dev/null 2>&1
fresh_tunnel_code=$?
set -e
[ "$fresh_tunnel_code" -ne 0 ]
[ ! -e "$fresh_tunnel/usr/bin/cloudflared" ]
[ ! -e "$fresh_tunnel/etc/secrets/cloudflared.token" ]
! grep -q '^VP_TUNNEL_METRICS_PORT=' "$fresh_tunnel/etc/state.env"

metrics_tunnel="$TMP/tunnel-metrics-conflict"
mkdir -p "$metrics_tunnel/bin"
cat > "$metrics_tunnel/bin/ss" <<'METRICS_SS'
#!/bin/sh
printf 'tcp LISTEN 0 128 127.0.0.1:22041 0.0.0.0:*\n'
METRICS_SS
chmod 755 "$metrics_tunnel/bin/ss"
PATH="$metrics_tunnel/bin:$PATH" VP_CONFIG_DIR="$metrics_tunnel/etc" VP_DATA_DIR="$metrics_tunnel/lib" \
VP_LOG_DIR="$metrics_tunnel/log" VP_LIB_DIR="$metrics_tunnel/usr" \
VP_TUNNEL_SOURCE_BIN="$tunnel_tx/new-cloudflared" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" tunnel-install "$tunnel_tx/new.token" >/dev/null
selected_metrics_port="$(awk -F= '$1=="VP_TUNNEL_METRICS_PORT"{print $2;exit}' "$metrics_tunnel/etc/state.env")"
[ -n "$selected_metrics_port" ]
[ "$selected_metrics_port" != 22041 ]
[ "$selected_metrics_port" != 17890 ]
[ "$selected_metrics_port" != 19090 ]

printf 'BACKUP_TEST_MARKER=original\n' >> "$TMP/dns-etc/state.env"
printf 'HOST_LOCAL_MARKER=preserve\n' > "$TMP/dns-lib/host-local.state"
printf 'BEFORE_CC=cubic\nBEFORE_QDISC=pfifo_fast\n' > "$TMP/dns-lib/network-before.env"
portable_backup="$TMP/portable-backup.tar.gz"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" backup "$portable_backup" >/dev/null
[ -s "$portable_backup" ]
[ -s "$portable_backup.sha256" ]
if tar -tzf "$portable_backup" | grep -Eq '^data/.+'; then
  printf 'portable backup unexpectedly contains host-bound runtime data\n' >&2
  exit 1
fi
managed_data="$TMP/managed-lib"
managed_backups="$managed_data/backups"
mkdir -p "$managed_backups"
for backup_index in 1 2 3 4 5 6 7; do
  managed_target="$managed_backups/vps-node-20260101-00000${backup_index}.tar.gz"
  VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" backup "$managed_target" >/dev/null
done
first_managed_hash="$(sha256sum "$managed_backups/vps-node-20260101-000001.tar.gz" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" backup "$managed_backups/vps-node-20260101-000001.tar.gz" >/dev/null 2>&1; then
  printf 'existing backup unexpectedly overwritten\n' >&2
  exit 1
fi
[ "$(sha256sum "$managed_backups/vps-node-20260101-000001.tar.gz" | awk '{print $1}')" = "$first_managed_hash" ]
printf 'unrelated\n' > "$managed_backups/notes.tar.gz"
printf 'invalid\n' > "$managed_backups/vps-node-20250101-000000.tar.gz"
printf '%064d  vps-node-20250101-000000.tar.gz\n' 0 > "$managed_backups/vps-node-20250101-000000.tar.gz.sha256"
backup_list_output="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" backups "$managed_backups")"
[ "$(printf '%s\n' "$backup_list_output" | grep -c '| 可恢复$')" = 7 ]
printf '%s\n' "$backup_list_output" | grep -q '异常-不会自动删除'
prune_preview="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/managed-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" backup-prune --keep 3 --dry-run)"
printf '%s\n' "$prune_preview" | grep -q '计划删除最早 4 个'
[ -e "$managed_backups/vps-node-20260101-000001.tar.gz" ]
mkdir -p "$TMP/symlink-data"
ln -s "$managed_backups" "$TMP/symlink-data/backups"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/symlink-data" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" backup-prune --keep 3 --dry-run >/dev/null 2>&1; then
  printf 'symlinked backup directory unexpectedly accepted for pruning\n' >&2
  exit 1
fi
[ -e "$managed_backups/vps-node-20260101-000001.tar.gz" ]
prune_replacement="$managed_backups/vps-node-20260101-000007.tar.gz"
prune_replacement_hash="$(sha256sum "$prune_replacement" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/managed-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_BACKUP_PRUNE_CONFIRM=PRUNE VP_SKIP_SERVICE=1 \
  VP_ALLOW_TEST_HOOKS=1 VP_TEST_BACKUP_PRUNE_REPLACEMENT="$prune_replacement" \
  sh "$ROOT/vp.sh" backup-prune --keep 3 --apply >/dev/null 2>&1; then
  printf 'backup prune deleted a valid recovery point replaced after confirmation\n' >&2
  exit 1
fi
[ "$(sha256sum "$managed_backups/vps-node-20260101-000001.tar.gz" | awk '{print $1}')" = "$prune_replacement_hash" ]
for preserved_backup_index in 2 3 4 5 6 7; do
  [ -e "$managed_backups/vps-node-20260101-00000${preserved_backup_index}.tar.gz" ]
done
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/managed-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_BACKUP_PRUNE_CONFIRM=PRUNE VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" backup-prune --keep 3 --apply >/dev/null
[ ! -e "$managed_backups/vps-node-20260101-000001.tar.gz" ]
[ ! -e "$managed_backups/vps-node-20260101-000001.tar.gz.sha256" ]
[ -e "$managed_backups/vps-node-20260101-000005.tar.gz" ]
[ -e "$managed_backups/vps-node-20260101-000006.tar.gz" ]
[ -e "$managed_backups/vps-node-20260101-000007.tar.gz" ]
[ -e "$managed_backups/vps-node-20250101-000000.tar.gz" ]
[ -e "$managed_backups/notes.tar.gz" ]
sed -i 's/BACKUP_TEST_MARKER=original/BACKUP_TEST_MARKER=changed/' "$TMP/dns-etc/state.env"
restore_preview="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$portable_backup" --dry-run)"
printf '%s\n' "$restore_preview" | grep -q '^恢复预览：'
printf '%s\n' "$restore_preview" | grep -q '未修改任何文件或服务'
grep -q '^BACKUP_TEST_MARKER=changed$' "$TMP/dns-etc/state.env"
for restore_race_phase in after-extract after-confirm; do
  restore_race_backup="$TMP/restore-race-$restore_race_phase.tar.gz"
  cp "$portable_backup" "$restore_race_backup"
  printf '%s  %s\n' "$(sha256sum "$restore_race_backup" | awk '{print $1}')" "$(basename "$restore_race_backup")" > "$restore_race_backup.sha256"
  restore_race_state_hash="$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')"
  restore_race_sidecar_hash="$(sha256sum "$restore_race_backup.sha256" | awk '{print $1}')"
  if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
    VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
    VP_RESTORE_CONFIRM=RESTORE VP_ALLOW_TEST_HOOKS=1 VP_TEST_RESTORE_SOURCE_RACE="$restore_race_phase" \
    sh "$ROOT/vp.sh" restore "$restore_race_backup" --apply >/dev/null 2>&1; then
    printf 'restore accepted source mutation: %s\n' "$restore_race_phase" >&2
    exit 1
  fi
  [ "$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')" = "$restore_race_state_hash" ]
  [ "$(sha256sum "$restore_race_backup.sha256" | awk '{print $1}')" = "$restore_race_sidecar_hash" ]
  tail -c 64 "$restore_race_backup" | grep -q "changed-$restore_race_phase"
done
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
VP_RESTORE_CONFIRM=RESTORE sh "$ROOT/vp.sh" restore "$portable_backup" --apply >/dev/null
grep -q '^BACKUP_TEST_MARKER=original$' "$TMP/dns-etc/state.env"
grep -q '^HOST_LOCAL_MARKER=preserve$' "$TMP/dns-lib/host-local.state"
grep -q '^BEFORE_CC=cubic$' "$TMP/dns-lib/network-before.env"

legacy_data_package="$TMP/legacy-data-package"
legacy_data_backup="$TMP/legacy-data-backup.tar.gz"
mkdir -p "$legacy_data_package"
tar -xzf "$portable_backup" -C "$legacy_data_package"
printf 'HOST_LOCAL_MARKER=foreign-host\n' > "$legacy_data_package/data/host-local.state"
printf 'BEFORE_CC=foreign\nBEFORE_QDISC=foreign\n' > "$legacy_data_package/data/network-before.env"
tar -czf "$legacy_data_backup" -C "$legacy_data_package" manifest.env config data
printf '%s  %s\n' "$(sha256sum "$legacy_data_backup" | awk '{print $1}')" "$(basename "$legacy_data_backup")" > "$legacy_data_backup.sha256"
sed -i 's/BACKUP_TEST_MARKER=original/BACKUP_TEST_MARKER=changed-again/' "$TMP/dns-etc/state.env"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
VP_RESTORE_CONFIRM=RESTORE sh "$ROOT/vp.sh" restore "$legacy_data_backup" --apply >/dev/null
grep -q '^BACKUP_TEST_MARKER=original$' "$TMP/dns-etc/state.env"
grep -q '^HOST_LOCAL_MARKER=preserve$' "$TMP/dns-lib/host-local.state"
grep -q '^BEFORE_CC=cubic$' "$TMP/dns-lib/network-before.env"

unverified_backup="$TMP/unverified-backup.tar.gz"
cp "$portable_backup" "$unverified_backup"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$unverified_backup" --dry-run >/dev/null 2>&1; then
  printf 'backup without checksum unexpectedly accepted by default\n' >&2
  exit 1
fi
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" restore "$unverified_backup" --allow-unverified --dry-run >/dev/null
ln -s "$portable_backup.sha256" "$unverified_backup.sha256"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$unverified_backup" --dry-run >/dev/null 2>&1; then
  printf 'symlinked backup checksum unexpectedly accepted\n' >&2
  exit 1
fi
rm -f "$unverified_backup.sha256"

malicious_package="$TMP/malicious-package"
mkdir -p "$malicious_package/config" "$malicious_package/data"
printf 'FORMAT_VERSION=1\n' > "$malicious_package/manifest.env"
printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$malicious_package/config/state.env"
: > "$malicious_package/config/nodes.db"
ln -s "$TMP/outside-target" "$malicious_package/config/secrets"
tar -czf "$TMP/malicious-backup.tar.gz" -C "$malicious_package" manifest.env config data
if VP_CONFIG_DIR="$TMP/malicious-restore/etc" VP_DATA_DIR="$TMP/malicious-restore/lib" \
  VP_LOG_DIR="$TMP/malicious-restore/log" VP_LIB_DIR="$TMP/malicious-restore/usr" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$TMP/malicious-backup.tar.gz" --allow-unverified >/dev/null 2>&1; then
  printf 'symlink backup unexpectedly accepted\n' >&2
  exit 1
fi
[ ! -e "$TMP/outside-target" ]

invalid_state="$TMP/invalid-state-package"
mkdir -p "$invalid_state/config" "$invalid_state/data"
printf 'FORMAT_VERSION=1\n' > "$invalid_state/manifest.env"
printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$invalid_state/config/state.env"
cat > "$invalid_state/config/nodes.db" <<'INVALID_NODES'
argo|duplicate-a|24443|11111111-1111-4111-8111-111111111111|/a|a.example.com
argo|duplicate-b|24443|22222222-2222-4222-8222-222222222222|/b|b.example.com
INVALID_NODES
: > "$invalid_state/config/credential-rotations.db"
tar -czf "$TMP/invalid-state.tar.gz" -C "$invalid_state" manifest.env config data
state_hash_before="$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$TMP/invalid-state.tar.gz" --allow-unverified >/dev/null 2>&1; then
  printf 'duplicate listener backup unexpectedly accepted\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')" = "$state_hash_before" ]

rotation_state="$TMP/invalid-rotation-package"
mkdir -p "$rotation_state/config" "$rotation_state/data"
printf 'FORMAT_VERSION=1\n' > "$rotation_state/manifest.env"
printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$rotation_state/config/state.env"
printf '%s\n' 'argo|rotation-node|24444|33333333-3333-4333-8333-333333333333|/ws|rotation.example.com' > "$rotation_state/config/nodes.db"
printf '%s\n' 'rotation-node|argo|44444444-4444-4444-8444-444444444444|55555555-5555-4555-8555-555555555555|200|100' > "$rotation_state/config/credential-rotations.db"
tar -czf "$TMP/invalid-rotation.tar.gz" -C "$rotation_state" manifest.env config data
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" restore "$TMP/invalid-rotation.tar.gz" --allow-unverified >/dev/null 2>&1; then
  printf 'orphan rotation backup unexpectedly accepted\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/state.env" | awk '{print $1}')" = "$state_hash_before" ]

VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal >/dev/null
grep -q '|recovered|core|service restarted$' "$TMP/dns-log/stability.log"
mkdir -p "$TMP/dns-lib/self-heal.lock"
printf '%s\n' "$$" > "$TMP/dns-lib/self-heal.lock/pid"
stability_lines_before="$(wc -l < "$TMP/dns-log/stability.log")"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal --quiet
[ "$(wc -l < "$TMP/dns-log/stability.log")" = "$stability_lines_before" ]
[ -d "$TMP/dns-lib/self-heal.lock" ]
printf '0\n' > "$TMP/dns-lib/self-heal.lock/start"
reused_pid_status="$(VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" sh "$ROOT/vp.sh" stability)"
printf '%s\n' "$reused_pid_status" | grep -q '发现过期锁'
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal --quiet
[ ! -e "$TMP/dns-lib/self-heal.lock" ]
mkdir -p "$TMP/dns-lib/self-heal.lock"
printf '99999999\n' > "$TMP/dns-lib/self-heal.lock/pid"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal --quiet
[ ! -e "$TMP/dns-lib/self-heal.lock" ]

self_heal_clean_hash="$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')"
printf '\n# drift repaired by periodic self-heal\n' >> "$TMP/dns-etc/generated/mihomo.yaml"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal --quiet
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$self_heal_clean_hash" ]
grep -q '|recovered|core|configuration rebuilt from authoritative state$' "$TMP/dns-log/stability.log"
cp "$TMP/dns-etc/nodes.db" "$TMP/nodes-before-invalid-self-heal"
printf '%s\n' 'argo|self-heal-bad|25436|77777777-7777-4777-8777-777777777777|/bad|bad.example.com' >> "$TMP/dns-etc/nodes.db"
invalid_db_hash="$(sha256sum "$TMP/dns-etc/nodes.db" | awk '{print $1}')"
config_before_invalid_heal="$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
  VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" self-heal --quiet; then
  printf 'invalid node database unexpectedly self-healed\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/dns-etc/nodes.db" | awk '{print $1}')" = "$invalid_db_hash" ]
[ "$(sha256sum "$TMP/dns-etc/generated/mihomo.yaml" | awk '{print $1}')" = "$config_before_invalid_heal" ]
grep -q '|failed|state|node or rotation database invalid; automatic rebuild refused$' "$TMP/dns-log/stability.log"
mv "$TMP/nodes-before-invalid-self-heal" "$TMP/dns-etc/nodes.db"

dedupe_root="$TMP/self-heal-dedupe"
VP_CONFIG_DIR="$dedupe_root/etc" VP_DATA_DIR="$dedupe_root/lib" VP_LOG_DIR="$dedupe_root/log" \
VP_LIB_DIR="$dedupe_root/usr" VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" self-heal --quiet
VP_CONFIG_DIR="$dedupe_root/etc" VP_DATA_DIR="$dedupe_root/lib" VP_LOG_DIR="$dedupe_root/log" \
VP_LIB_DIR="$dedupe_root/usr" VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" self-heal --quiet
[ "$(grep -c '|healthy|check|no action required$' "$dedupe_root/log/stability.log")" -eq 1 ]
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CLI_PATH="$ROOT/vp.sh" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" monitor-install >/dev/null
[ -x "$TMP/dns-usr/bin/watchdog-run" ]
grep -Fq "exec \"$ROOT/vp.sh\" self-heal --quiet" "$TMP/dns-usr/bin/watchdog-run"

delete_race_root="$TMP/delete-race"
VP_CONFIG_DIR="$delete_race_root/etc" VP_DATA_DIR="$delete_race_root/lib" \
VP_LOG_DIR="$delete_race_root/log" VP_LIB_DIR="$delete_race_root/usr" \
VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" init >/dev/null
printf '%s\n' 'argo|delete-target|29990|88888888-8888-4888-8888-888888888888|/target|target.example.com' \
  > "$delete_race_root/etc/nodes.db"
delete_race_state_hash="$(sha256sum "$delete_race_root/etc/state.env" | awk '{print $1}')"
delete_race_rotations_hash="$(sha256sum "$delete_race_root/etc/credential-rotations.db" | awk '{print $1}')"
if VP_CONFIG_DIR="$delete_race_root/etc" VP_DATA_DIR="$delete_race_root/lib" \
  VP_LOG_DIR="$delete_race_root/log" VP_LIB_DIR="$delete_race_root/usr" VP_SKIP_SERVICE=1 \
  VP_DELETE_CONFIRM=DELETE VP_ALLOW_TEST_HOOKS=1 VP_TEST_DELETE_NODE_RACE=1 \
  sh "$ROOT/vp.sh" delete delete-target >/dev/null 2>&1; then
  printf 'node deletion accepted a database changed after confirmation\n' >&2
  exit 1
fi
grep -q '^argo|delete-target|' "$delete_race_root/etc/nodes.db"
grep -q '^argo|concurrent-node|' "$delete_race_root/etc/nodes.db"
[ "$(sha256sum "$delete_race_root/etc/state.env" | awk '{print $1}')" = "$delete_race_state_hash" ]
[ "$(sha256sum "$delete_race_root/etc/credential-rotations.db" | awk '{print $1}')" = "$delete_race_rotations_hash" ]
[ ! -e "$delete_race_root/etc/transactions/active" ]

uninstall_fail_root="$TMP/uninstall-stop-failure"
mkdir -p "$uninstall_fail_root"
: > "$uninstall_fail_root/vp"
: > "$uninstall_fail_root/vp.previous"
printf '%064d  vp.previous\n' 0 > "$uninstall_fail_root/vp.previous.sha256"
VP_CONFIG_DIR="$uninstall_fail_root/etc" VP_DATA_DIR="$uninstall_fail_root/lib" \
VP_LOG_DIR="$uninstall_fail_root/log" VP_LIB_DIR="$uninstall_fail_root/usr" \
VP_CLI_PATH="$uninstall_fail_root/vp" VP_CLI_BACKUP_PATH="$uninstall_fail_root/vp.previous" \
VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" init >/dev/null
printf 'UNINSTALL_FAILURE_MARKER=preserve\n' >> "$uninstall_fail_root/etc/state.env"
printf 'BEFORE_CC=cubic\nBEFORE_QDISC=fq\n' > "$uninstall_fail_root/lib/network-before.env"
printf 'net.core.default_qdisc=fq\n' > "$uninstall_fail_root/sysctl.conf"
find "$uninstall_fail_root/etc" "$uninstall_fail_root/lib" "$uninstall_fail_root/log" "$uninstall_fail_root/usr" \
  "$uninstall_fail_root/vp" "$uninstall_fail_root/vp.previous" "$uninstall_fail_root/vp.previous.sha256" \
  "$uninstall_fail_root/sysctl.conf" -type f -exec sha256sum {} \; | sort > "$uninstall_fail_root/before.sha256"
if uninstall_fail_output="$(VP_CONFIG_DIR="$uninstall_fail_root/etc" VP_DATA_DIR="$uninstall_fail_root/lib" \
  VP_LOG_DIR="$uninstall_fail_root/log" VP_LIB_DIR="$uninstall_fail_root/usr" \
  VP_CLI_PATH="$uninstall_fail_root/vp" VP_CLI_BACKUP_PATH="$uninstall_fail_root/vp.previous" \
  VP_UNINSTALL_BACKUP_DIR="$uninstall_fail_root/recovery" \
  VP_SYSCTL_CONFIG="$uninstall_fail_root/sysctl.conf" \
  VP_NETWORK_SNAPSHOT="$uninstall_fail_root/lib/network-before.env" \
  VP_UNINSTALL_CONFIRM=DELETE VP_ALLOW_TEST_HOOKS=1 VP_TEST_UNINSTALL_STOP_FAIL=1 \
  sh "$ROOT/vp.sh" uninstall 2>&1)"; then
  printf 'uninstall unexpectedly continued after service stop failure\n' >&2
  exit 1
fi
printf '%s\n' "$uninstall_fail_output" | grep -q '未回滚网络或删除文件'
find "$uninstall_fail_root/etc" "$uninstall_fail_root/lib" "$uninstall_fail_root/log" "$uninstall_fail_root/usr" \
  "$uninstall_fail_root/vp" "$uninstall_fail_root/vp.previous" "$uninstall_fail_root/vp.previous.sha256" \
  "$uninstall_fail_root/sysctl.conf" -type f -exec sha256sum {} \; | sort > "$uninstall_fail_root/after.sha256"
cmp "$uninstall_fail_root/before.sha256" "$uninstall_fail_root/after.sha256"
uninstall_fail_backup="$(find "$uninstall_fail_root/recovery" -name 'vps-node-uninstall-backup-*.tar.gz' -type f | head -n 1)"
[ -s "$uninstall_fail_backup" ]
[ -s "$uninstall_fail_backup.sha256" ]
(cd "$(dirname "$uninstall_fail_backup")" && sha256sum -c "$(basename "$uninstall_fail_backup").sha256" >/dev/null)

if VP_CONFIG_DIR="$uninstall_fail_root/etc" VP_DATA_DIR="$uninstall_fail_root/lib" \
  VP_LOG_DIR="$uninstall_fail_root/log" VP_LIB_DIR="$uninstall_fail_root/usr" \
  VP_CLI_PATH="$uninstall_fail_root/vp" VP_CLI_BACKUP_PATH="$uninstall_fail_root/vp.previous" \
  VP_UNINSTALL_BACKUP_DIR="$uninstall_fail_root/recovery-orphan" VP_UNINSTALL_CONFIRM=DELETE \
  VP_ALLOW_TEST_HOOKS=1 VP_TEST_TUNNEL_PROCESS_RUNNING=1 sh "$ROOT/vp.sh" uninstall >/dev/null 2>&1; then
  printf 'uninstall unexpectedly continued while tunnel process was running\n' >&2
  exit 1
fi
[ -e "$uninstall_fail_root/etc/state.env" ]
[ -e "$uninstall_fail_root/vp" ]

uninstall_residual_root="$TMP/uninstall-residual"
mkdir -p "$uninstall_residual_root"
: > "$uninstall_residual_root/vp"
: > "$uninstall_residual_root/vp.previous"
printf '%064d  vp.previous\n' 0 > "$uninstall_residual_root/vp.previous.sha256"
VP_CONFIG_DIR="$uninstall_residual_root/etc" VP_DATA_DIR="$uninstall_residual_root/lib" \
VP_LOG_DIR="$uninstall_residual_root/log" VP_LIB_DIR="$uninstall_residual_root/usr" \
VP_CLI_PATH="$uninstall_residual_root/vp" VP_CLI_BACKUP_PATH="$uninstall_residual_root/vp.previous" \
VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" init >/dev/null
printf 'RESIDUAL_MARKER=must-report\n' > "$uninstall_residual_root/lib/residual-marker"
if uninstall_residual_output="$(VP_CONFIG_DIR="$uninstall_residual_root/etc" \
  VP_DATA_DIR="$uninstall_residual_root/lib" VP_LOG_DIR="$uninstall_residual_root/log" \
  VP_LIB_DIR="$uninstall_residual_root/usr" VP_CLI_PATH="$uninstall_residual_root/vp" \
  VP_CLI_BACKUP_PATH="$uninstall_residual_root/vp.previous" \
  VP_UNINSTALL_BACKUP_DIR="$uninstall_residual_root/recovery" VP_SKIP_SERVICE=1 \
  VP_UNINSTALL_CONFIRM=DELETE VP_ALLOW_TEST_HOOKS=1 VP_TEST_UNINSTALL_REMOVE_FAIL=1 \
  sh "$ROOT/vp.sh" uninstall 2>&1)"; then
  printf 'partial uninstall unexpectedly reported success\n' >&2
  exit 1
fi
printf '%s\n' "$uninstall_residual_output" | grep -Fq "残留：$uninstall_residual_root/lib"
printf '%s\n' "$uninstall_residual_output" | grep -q '卸载未完整完成'
! printf '%s\n' "$uninstall_residual_output" | grep -q 'VPS-Node 已卸载'
[ -e "$uninstall_residual_root/lib/residual-marker" ]
[ ! -e "$uninstall_residual_root/etc" ]
[ ! -e "$uninstall_residual_root/vp" ]
uninstall_residual_backup="$(find "$uninstall_residual_root/recovery" -name 'vps-node-uninstall-backup-*.tar.gz' -type f | head -n 1)"
[ -s "$uninstall_residual_backup" ]
[ -s "$uninstall_residual_backup.sha256" ]
(cd "$(dirname "$uninstall_residual_backup")" && sha256sum -c "$(basename "$uninstall_residual_backup").sha256" >/dev/null)

uninstall_root="$TMP/uninstall"
mkdir -p "$uninstall_root"
: > "$uninstall_root/vp"
: > "$uninstall_root/vp.previous"
printf '%064d  vp.previous\n' 0 > "$uninstall_root/vp.previous.sha256"
VP_CONFIG_DIR="$uninstall_root/etc" VP_DATA_DIR="$uninstall_root/lib" \
VP_LOG_DIR="$uninstall_root/log" VP_LIB_DIR="$uninstall_root/usr" \
VP_CLI_PATH="$uninstall_root/vp" VP_CLI_BACKUP_PATH="$uninstall_root/vp.previous" \
VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" init >/dev/null
printf 'RECOVERY_MARKER=keep-me\n' >> "$uninstall_root/etc/state.env"
VP_CONFIG_DIR="$uninstall_root/etc" VP_DATA_DIR="$uninstall_root/lib" \
VP_LOG_DIR="$uninstall_root/log" VP_LIB_DIR="$uninstall_root/usr" \
VP_CLI_PATH="$uninstall_root/vp" VP_CLI_BACKUP_PATH="$uninstall_root/vp.previous" \
VP_UNINSTALL_BACKUP_DIR="$uninstall_root/recovery" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" uninstall --dry-run >/dev/null
[ -e "$uninstall_root/etc/state.env" ]
printf '11\nDELETE\n' | \
  VP_CONFIG_DIR="$uninstall_root/etc" VP_DATA_DIR="$uninstall_root/lib" \
  VP_LOG_DIR="$uninstall_root/log" VP_LIB_DIR="$uninstall_root/usr" \
  VP_CLI_PATH="$uninstall_root/vp" VP_CLI_BACKUP_PATH="$uninstall_root/vp.previous" \
  VP_UNINSTALL_BACKUP_DIR="$uninstall_root/recovery" \
  VP_SKIP_SERVICE=1 sh "$ROOT/vp.sh" >/dev/null 2>&1
[ ! -e "$uninstall_root/etc" ]
[ ! -e "$uninstall_root/lib" ]
[ ! -e "$uninstall_root/vp" ]
[ ! -e "$uninstall_root/vp.previous" ]
[ ! -e "$uninstall_root/vp.previous.sha256" ]
uninstall_backup="$(find "$uninstall_root/recovery" -name 'vps-node-uninstall-backup-*.tar.gz' -type f | head -n 1)"
[ -s "$uninstall_backup" ]
[ -s "$uninstall_backup.sha256" ]
(cd "$(dirname "$uninstall_backup")" && sha256sum -c "$(basename "$uninstall_backup").sha256" >/dev/null)
tar -xOf "$uninstall_backup" config/state.env | grep -q '^RECOVERY_MARKER=keep-me$'

if VP_CONFIG_DIR=/etc VP_DATA_DIR="$TMP/safe-lib" VP_LOG_DIR="$TMP/safe-log" \
  VP_LIB_DIR="$TMP/safe-usr" VP_CLI_PATH="$TMP/safe-vp" \
  VP_CLI_BACKUP_PATH="$TMP/safe-vp.previous" VP_SKIP_SERVICE=1 \
  sh "$ROOT/vp.sh" uninstall --dry-run >/dev/null 2>&1; then
  printf 'dangerous uninstall path unexpectedly accepted\n' >&2
  exit 1
fi

update_root="$TMP/update"
mkdir -p "$update_root/good" "$update_root/bad" "$update_root/lower" "$update_root/same"
cp "$ROOT/vp.sh" "$update_root/installed-vp"
chmod 755 "$update_root/installed-vp"
initial_version_status="$(VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" sh "$ROOT/vp.sh" version-status)"
printf '%s\n' "$initial_version_status" | grep -q "管理脚本：当前 $CURRENT_VERSION"
printf '%s\n' "$initial_version_status" | grep -q '回滚版本：无'
sed 's/^VP_VERSION=.*/VP_VERSION="0.2.0-dev.99"/' "$ROOT/vp.sh" > "$update_root/good/vp.sh"
printf '%s  vp.sh\n' "$(sha256sum "$update_root/good/vp.sh" | awk '{print $1}')" > "$update_root/good/vp.sh.sha256"
cp "$update_root/good/vp.sh" "$update_root/bad/vp.sh"
printf '%064d  vp.sh\n' 0 > "$update_root/bad/vp.sh.sha256"
sed 's/^VP_VERSION=.*/VP_VERSION="0.2.0-dev.1"/' "$ROOT/vp.sh" > "$update_root/lower/vp.sh"
printf '%s  vp.sh\n' "$(sha256sum "$update_root/lower/vp.sh" | awk '{print $1}')" > "$update_root/lower/vp.sh.sha256"
cp "$ROOT/vp.sh" "$update_root/same/vp.sh"
printf '\n# same-version-different-content\n' >> "$update_root/same/vp.sh"
printf '%s  vp.sh\n' "$(sha256sum "$update_root/same/vp.sh" | awk '{print $1}')" > "$update_root/same/vp.sh.sha256"
installed_hash="$(sha256sum "$update_root/installed-vp" | awk '{print $1}')"
preview_output="$(VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
  VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" update --check)"
printf '%s\n' "$preview_output" | grep -q "当前版本：$CURRENT_VERSION"
printf '%s\n' "$preview_output" | grep -q '候选版本：0.2.0-dev.99'
printf '%s\n' "$preview_output" | grep -q '变更类型：升级'
printf '%s\n' "$preview_output" | grep -q '只读检查完成，未修改管理脚本或回滚文件'
[ "$(sha256sum "$update_root/installed-vp" | awk '{print $1}')" = "$installed_hash" ]
[ ! -e "$update_root/installed-vp.previous" ]
[ ! -e "$update_root/installed-vp.previous.sha256" ]

for update_race_kind in target existing; do
  update_race_cli="$update_root/race-$update_race_kind/vp"
  mkdir -p "$(dirname "$update_race_cli")"
  cp "$ROOT/vp.sh" "$update_race_cli"
  cp "$update_root/lower/vp.sh" "$update_race_cli.previous"
  printf '%s  vp.previous\n' "$(sha256sum "$update_race_cli.previous" | awk '{print $1}')" > "$update_race_cli.previous.sha256"
  update_race_backup_hash="$(sha256sum "$update_race_cli.previous" | awk '{print $1}')"
  update_race_sidecar_hash="$(sha256sum "$update_race_cli.previous.sha256" | awk '{print $1}')"
  if [ "$update_race_kind" = target ]; then
    update_race_hook=VP_TEST_CLI_UPDATE_TARGET_RACE=1
    update_race_marker=changed-after-update-check
  else
    update_race_hook=VP_TEST_CLI_UPDATE_EXISTING_RACE=1
    update_race_marker=changed-during-update-backup
  fi
  if env "$update_race_hook" VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_race_cli" \
    VP_CLI_BACKUP_PATH="$update_race_cli.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
    VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
    printf 'CLI update accepted concurrent target change: %s\n' "$update_race_kind" >&2
    exit 1
  fi
  grep -q "^$update_race_marker$" "$update_race_cli"
  [ "$(sha256sum "$update_race_cli.previous" | awk '{print $1}')" = "$update_race_backup_hash" ]
  [ "$(sha256sum "$update_race_cli.previous.sha256" | awk '{print $1}')" = "$update_race_sidecar_hash" ]
done

update_commit_race_cli="$update_root/race-commit/vp"
mkdir -p "$(dirname "$update_commit_race_cli")"
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_commit_race_cli" \
  VP_CLI_BACKUP_PATH="$update_commit_race_cli.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
  VP_ALLOW_TEST_HOOKS=1 VP_TEST_CLI_UPDATE_COMMIT_RACE=1 \
  sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
  printf 'CLI update overwrote a target created at commit time\n' >&2
  exit 1
fi
grep -q '^created-at-update-commit$' "$update_commit_race_cli"
[ ! -e "$update_commit_race_cli.previous" ]
[ ! -e "$update_commit_race_cli.previous.sha256" ]

if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
  sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
  printf 'unguarded local update source unexpectedly accepted\n' >&2
  exit 1
fi
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/same" \
  VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
  printf 'same-version different update unexpectedly accepted\n' >&2
  exit 1
fi
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/lower" \
  VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
  printf 'implicit downgrade unexpectedly accepted\n' >&2
  exit 1
fi
[ "$(sha256sum "$update_root/installed-vp" | awk '{print $1}')" = "$installed_hash" ]
downgrade_cli="$update_root/downgrade-vp"
cp "$ROOT/vp.sh" "$downgrade_cli"
chmod 755 "$downgrade_cli"
VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$downgrade_cli" \
VP_CLI_BACKUP_PATH="$downgrade_cli.previous" VP_UPDATE_SOURCE_DIR="$update_root/lower" \
VP_ALLOW_TEST_HOOKS=1 sh "$ROOT/vp.sh" update --allow-downgrade >/dev/null
[ "$(sh "$downgrade_cli" version)" = '0.2.0-dev.1' ]
(cd "$update_root" && sha256sum -c downgrade-vp.previous.sha256 >/dev/null)
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/bad" \
  VP_ALLOW_TEST_HOOKS=1 \
  sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
  printf 'bad update checksum unexpectedly accepted\n' >&2
  exit 1
fi
[ "$(sha256sum "$update_root/installed-vp" | awk '{print $1}')" = "$installed_hash" ]
cp "$update_root/lower/vp.sh" "$update_root/installed-vp.previous"
printf '%s  installed-vp.previous\n' "$(sha256sum "$update_root/installed-vp.previous" | awk '{print $1}')" > "$update_root/installed-vp.previous.sha256"
prior_update_backup_hash="$(sha256sum "$update_root/installed-vp.previous" | awk '{print $1}')"
prior_update_sidecar_hash="$(sha256sum "$update_root/installed-vp.previous.sha256" | awk '{print $1}')"
for update_fail_phase in after-backup after-sidecar; do
  if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
    VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
    VP_ALLOW_TEST_HOOKS=1 VP_TEST_CLI_UPDATE_FAIL_PHASE="$update_fail_phase" \
    sh "$ROOT/vp.sh" update >/dev/null 2>&1; then
    printf 'injected CLI update failure unexpectedly succeeded: %s\n' "$update_fail_phase" >&2
    exit 1
  fi
  [ "$(sha256sum "$update_root/installed-vp" | awk '{print $1}')" = "$installed_hash" ]
  [ "$(sha256sum "$update_root/installed-vp.previous" | awk '{print $1}')" = "$prior_update_backup_hash" ]
  [ "$(sha256sum "$update_root/installed-vp.previous.sha256" | awk '{print $1}')" = "$prior_update_sidecar_hash" ]
done
VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
VP_ALLOW_TEST_HOOKS=1 \
sh "$ROOT/vp.sh" update >/dev/null
[ "$(sh "$update_root/installed-vp" version)" = '0.2.0-dev.99' ]
(cd "$update_root" && sha256sum -c installed-vp.previous.sha256 >/dev/null)
ready_version_status="$(VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" sh "$ROOT/vp.sh" version-status)"
printf '%s\n' "$ready_version_status" | grep -q '管理脚本：当前 0.2.0-dev.99'
printf '%s\n' "$ready_version_status" | grep -q "回滚版本：$CURRENT_VERSION（校验通过）"
rollback_cli_hash="$(sha256sum "$update_root/installed-vp" | awk '{print $1}')"
rollback_backup_hash="$(sha256sum "$update_root/installed-vp.previous" | awk '{print $1}')"
rollback_sidecar_hash="$(sha256sum "$update_root/installed-vp.previous.sha256" | awk '{print $1}')"

rollback_source_race_cli="$update_root/rollback-source-race/vp"
mkdir -p "$(dirname "$rollback_source_race_cli")"
cp "$update_root/installed-vp" "$rollback_source_race_cli"
cp "$update_root/installed-vp.previous" "$rollback_source_race_cli.previous"
printf '%s  vp.previous\n' "$(sha256sum "$rollback_source_race_cli.previous" | awk '{print $1}')" > "$rollback_source_race_cli.previous.sha256"
rollback_source_current_hash="$(sha256sum "$rollback_source_race_cli" | awk '{print $1}')"
rollback_source_sidecar_hash="$(sha256sum "$rollback_source_race_cli.previous.sha256" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$rollback_source_race_cli" \
  VP_CLI_BACKUP_PATH="$rollback_source_race_cli.previous" VP_ALLOW_TEST_HOOKS=1 \
  VP_TEST_CLI_ROLLBACK_SOURCE_RACE=1 sh "$ROOT/vp.sh" rollback >/dev/null 2>&1; then
  printf 'CLI rollback accepted a source changed after validation\n' >&2
  exit 1
fi
[ "$(sha256sum "$rollback_source_race_cli" | awk '{print $1}')" = "$rollback_source_current_hash" ]
grep -q '^changed-after-rollback-validation$' "$rollback_source_race_cli.previous"
[ "$(sha256sum "$rollback_source_race_cli.previous.sha256" | awk '{print $1}')" = "$rollback_source_sidecar_hash" ]

rollback_commit_race_cli="$update_root/rollback-commit-race/vp"
mkdir -p "$(dirname "$rollback_commit_race_cli")"
cp "$update_root/installed-vp.previous" "$rollback_commit_race_cli.previous"
printf '%s  vp.previous\n' "$(sha256sum "$rollback_commit_race_cli.previous" | awk '{print $1}')" > "$rollback_commit_race_cli.previous.sha256"
rollback_commit_backup_hash="$(sha256sum "$rollback_commit_race_cli.previous" | awk '{print $1}')"
rollback_commit_sidecar_hash="$(sha256sum "$rollback_commit_race_cli.previous.sha256" | awk '{print $1}')"
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$rollback_commit_race_cli" \
  VP_CLI_BACKUP_PATH="$rollback_commit_race_cli.previous" VP_ALLOW_TEST_HOOKS=1 \
  VP_TEST_CLI_ROLLBACK_COMMIT_RACE=1 sh "$ROOT/vp.sh" rollback >/dev/null 2>&1; then
  printf 'CLI rollback overwrote a target created at commit time\n' >&2
  exit 1
fi
grep -q '^created-at-rollback-commit$' "$rollback_commit_race_cli"
[ "$(sha256sum "$rollback_commit_race_cli.previous" | awk '{print $1}')" = "$rollback_commit_backup_hash" ]
[ "$(sha256sum "$rollback_commit_race_cli.previous.sha256" | awk '{print $1}')" = "$rollback_commit_sidecar_hash" ]

for rollback_fail_phase in after-cli after-backup; do
  if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
    VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_ALLOW_TEST_HOOKS=1 \
    VP_TEST_CLI_ROLLBACK_FAIL_PHASE="$rollback_fail_phase" sh "$ROOT/vp.sh" rollback >/dev/null 2>&1; then
    printf 'injected CLI rollback failure unexpectedly succeeded: %s\n' "$rollback_fail_phase" >&2
    exit 1
  fi
  [ "$(sha256sum "$update_root/installed-vp" | awk '{print $1}')" = "$rollback_cli_hash" ]
  [ "$(sha256sum "$update_root/installed-vp.previous" | awk '{print $1}')" = "$rollback_backup_hash" ]
  [ "$(sha256sum "$update_root/installed-vp.previous.sha256" | awk '{print $1}')" = "$rollback_sidecar_hash" ]
done
VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" sh "$ROOT/vp.sh" rollback >/dev/null
[ "$(sh "$update_root/installed-vp" version)" = "$CURRENT_VERSION" ]
VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" VP_UPDATE_SOURCE_DIR="$update_root/good" \
VP_ALLOW_TEST_HOOKS=1 \
sh "$ROOT/vp.sh" update >/dev/null
printf '\n# harmless syntax-preserving corruption\n' >> "$update_root/installed-vp.previous"
bad_version_status="$(VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" sh "$ROOT/vp.sh" version-status)"
printf '%s\n' "$bad_version_status" | grep -q '回滚版本：校验失败，已禁止回滚'
if VP_CONFIG_DIR="$TMP/etc" VP_CLI_PATH="$update_root/installed-vp" \
  VP_CLI_BACKUP_PATH="$update_root/installed-vp.previous" sh "$ROOT/vp.sh" rollback >/dev/null 2>&1; then
  printf 'corrupted rollback script unexpectedly accepted\n' >&2
  exit 1
fi
[ "$(sh "$update_root/installed-vp" version)" = '0.2.0-dev.99' ]

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
