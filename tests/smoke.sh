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

VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr-lib" \
sh "$ROOT/vp.sh" status | grep -q '总体状态：尚未安装'

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
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CORE_SOURCE_BIN="$fake_core" \
VP_DNS_PUBLIC_SERVERS=192.0.2.1 VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" core-install >/dev/null
grep -q '^VP_DNS_MODE=system$' "$TMP/dns-etc/core.env"
! grep -q '1\.1\.1\.1\|8\.8\.8\.8' "$TMP/dns-etc/generated/mihomo.yaml"
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

VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" self-heal >/dev/null
grep -q '|recovered|core|service restarted$' "$TMP/dns-log/stability.log"
VP_CONFIG_DIR="$TMP/dns-etc" VP_DATA_DIR="$TMP/dns-lib" VP_LOG_DIR="$TMP/dns-log" \
VP_LIB_DIR="$TMP/dns-usr" VP_CORE_BIN="$TMP/dns-usr/bin/mihomo" \
VP_CORE_BACKUP_BIN="$TMP/dns-usr/bin/mihomo.previous" VP_CLI_PATH="$ROOT/vp.sh" VP_SKIP_SERVICE=1 \
sh "$ROOT/vp.sh" monitor-install >/dev/null
[ -x "$TMP/dns-usr/bin/watchdog-run" ]
grep -Fq "exec \"$ROOT/vp.sh\" self-heal --quiet" "$TMP/dns-usr/bin/watchdog-run"

uninstall_root="$TMP/uninstall"
mkdir -p "$uninstall_root"
: > "$uninstall_root/vp"
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
