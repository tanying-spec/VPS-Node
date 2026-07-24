#!/bin/sh

set -u

VP_VERSION="0.2.0-dev.25"
VP_CONFIG_DIR="${VP_CONFIG_DIR:-/etc/vps-node}"
VP_DATA_DIR="${VP_DATA_DIR:-/var/lib/vps-node}"
VP_LOG_DIR="${VP_LOG_DIR:-/var/log/vps-node}"
VP_LIB_DIR="${VP_LIB_DIR:-/usr/local/lib/vps-node}"
VP_NODES_DB="$VP_CONFIG_DIR/nodes.db"
VP_ROTATIONS_DB="$VP_CONFIG_DIR/credential-rotations.db"
VP_STATE_FILE="$VP_CONFIG_DIR/state.env"
VP_SECRETS_DIR="$VP_CONFIG_DIR/secrets"
VP_GENERATED_DIR="$VP_CONFIG_DIR/generated"
VP_TX_DIR="$VP_CONFIG_DIR/transactions"
VP_TX_ACTIVE="$VP_TX_DIR/active"
VP_CORE_BIN="${VP_CORE_BIN:-$VP_LIB_DIR/bin/mihomo}"
VP_CORE_BACKUP_BIN="${VP_CORE_BACKUP_BIN:-$VP_LIB_DIR/bin/mihomo.previous}"
VP_CORE_CONFIG="$VP_GENERATED_DIR/mihomo.yaml"
VP_CORE_SERVICE="${VP_CORE_SERVICE:-vps-node-core}"
VP_CORE_ENV="$VP_CONFIG_DIR/core.env"
VP_DNS_TEST_HOST="${VP_DNS_TEST_HOST:-github.com}"
VP_DNS_PUBLIC_SERVERS="${VP_DNS_PUBLIC_SERVERS:-1.1.1.1 8.8.8.8}"
VP_DNS_QUERY_TOOL="${VP_DNS_QUERY_TOOL:-none}"
VP_CORE_RUNNER="$VP_LIB_DIR/bin/mihomo-run"
VP_MIXED_PORT_OVERRIDE="${VP_MIXED_PORT:-}"
VP_CONTROLLER_PORT_OVERRIDE="${VP_CONTROLLER_PORT:-}"
VP_MIXED_PORT_SAVED="$(awk -F= '$1=="VP_MIXED_PORT"{print $2;exit}' "$VP_STATE_FILE" 2>/dev/null || true)"
VP_CONTROLLER_PORT_SAVED="$(awk -F= '$1=="VP_CONTROLLER_PORT"{print $2;exit}' "$VP_STATE_FILE" 2>/dev/null || true)"
VP_MIXED_PORT="${VP_MIXED_PORT_OVERRIDE:-${VP_MIXED_PORT_SAVED:-17890}}"
VP_CONTROLLER_PORT="${VP_CONTROLLER_PORT_OVERRIDE:-${VP_CONTROLLER_PORT_SAVED:-19090}}"
VP_MIHOMO_API="${VP_MIHOMO_API:-https://api.github.com/repos/MetaCubeX/mihomo/releases/latest}"
VP_TUNNEL_BIN="${VP_TUNNEL_BIN:-$VP_LIB_DIR/bin/cloudflared}"
VP_TUNNEL_BACKUP_BIN="${VP_TUNNEL_BACKUP_BIN:-$VP_LIB_DIR/bin/cloudflared.previous}"
VP_TUNNEL_SERVICE="${VP_TUNNEL_SERVICE:-vps-node-tunnel}"
VP_TUNNEL_TOKEN_FILE="$VP_SECRETS_DIR/cloudflared.token"
VP_TUNNEL_RUNNER="$VP_LIB_DIR/bin/cloudflared-run"
VP_TUNNEL_METRICS_PORT="${VP_TUNNEL_METRICS_PORT:-22041}"
VP_CLOUDFLARED_API="${VP_CLOUDFLARED_API:-https://api.github.com/repos/cloudflare/cloudflared/releases/latest}"
VP_BACKUP_DIR="$VP_DATA_DIR/backups"
VP_UNINSTALL_BACKUP_DIR="${VP_UNINSTALL_BACKUP_DIR:-/root}"
VP_STABILITY_LOG="${VP_STABILITY_LOG:-$VP_LOG_DIR/stability.log}"
VP_WATCHDOG_RUNNER="${VP_WATCHDOG_RUNNER:-$VP_LIB_DIR/bin/watchdog-run}"
VP_WATCHDOG_SERVICE="${VP_WATCHDOG_SERVICE:-vps-node-watchdog}"
VP_CLI_PATH="${VP_CLI_PATH:-/usr/local/bin/vp}"
VP_CLI_BACKUP_PATH="${VP_CLI_BACKUP_PATH:-$VP_CLI_PATH.previous}"
VP_CLI_BACKUP_SHA256="${VP_CLI_BACKUP_SHA256:-$VP_CLI_BACKUP_PATH.sha256}"
VP_REPO="${VP_REPO:-tanying-spec/VPS-Node}"
VP_REF="${VP_REF:-main}"
VP_CURL_BIN="${VP_CURL_BIN:-curl}"
VP_SYSCTL_BIN="${VP_SYSCTL_BIN:-sysctl}"
VP_SYSCTL_CONFIG="${VP_SYSCTL_CONFIG:-/etc/sysctl.d/99-vps-node-network.conf}"
VP_NETWORK_SNAPSHOT="${VP_NETWORK_SNAPSHOT:-$VP_DATA_DIR/network-before.env}"
VP_OOM_STATE_FILE="${VP_OOM_STATE_FILE:-$VP_DATA_DIR/oom-kill.count}"

is_tty() { [ -t 1 ]; }
color() { is_tty && printf '\033[%sm' "$1" || true; }
reset_color() { is_tty && printf '\033[0m' || true; }
info() { color '36'; printf '[*]'; reset_color; printf ' %s\n' "$*"; }
ok() { color '32'; printf '[OK]'; reset_color; printf ' %s\n' "$*"; }
warn() { color '33'; printf '[!]'; reset_color; printf ' %s\n' "$*"; }
error() { color '31'; printf '[ERROR]'; reset_color; printf ' %s\n' "$*" >&2; }

need_root() {
  [ "$(id -u)" = "0" ] || { error "该操作需要 root 权限。"; return 1; }
}

install_packages() {
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$@" >/dev/null
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-get install -y "$@" >/dev/null
  else
    error "未找到 apk 或 apt-get，无法自动安装依赖。"
    return 1
  fi
}

ensure_runtime_dependencies() {
  missing=""
  for command_name in curl gzip openssl tar; do
    command -v "$command_name" >/dev/null 2>&1 || missing="$missing $command_name"
  done
  [ -z "$missing" ] && return 0
  info "正在安装运行依赖。"
  install_packages ca-certificates curl gzip openssl tar
}

init_layout() {
  need_root || return 1
  umask 077
  mkdir -p "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR" \
    "$VP_SECRETS_DIR" "$VP_GENERATED_DIR" "$VP_TX_DIR"
  [ -f "$VP_NODES_DB" ] || : > "$VP_NODES_DB"
  [ -f "$VP_ROTATIONS_DB" ] || : > "$VP_ROTATIONS_DB"
  [ -f "$VP_STATE_FILE" ] || printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$VP_STATE_FILE"
  chmod 700 "$VP_CONFIG_DIR" "$VP_SECRETS_DIR" "$VP_TX_DIR"
  chmod 600 "$VP_NODES_DB" "$VP_ROTATIONS_DB" "$VP_STATE_FILE"
  recover_state_transaction || return 1
  ok "VPS-Node 状态目录已初始化。"
}

pid_is_alive() {
  check_pid="$1"
  case "$check_pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$check_pid" 2>/dev/null
}

copy_path_if_present() {
  source_path="$1"
  target_root="$2"
  relative_path="${source_path#"$VP_CONFIG_DIR"/}"
  [ "$relative_path" != "$source_path" ] || return 1
  if [ -e "$source_path" ] || [ -L "$source_path" ]; then
    mkdir -p "$target_root/$(dirname "$relative_path")"
    cp -R -p "$source_path" "$target_root/$relative_path"
    printf '%s\n' "$relative_path" >> "$target_root/present.list"
  else
    printf '%s\n' "$relative_path" >> "$target_root/absent.list"
  fi
}

transaction_managed_paths() {
  printf '%s\n' "$VP_NODES_DB" "$VP_ROTATIONS_DB" "$VP_STATE_FILE" "$VP_GENERATED_DIR"
}

transaction_snapshot() {
  snapshot_root="$VP_TX_ACTIVE/snapshot"
  mkdir -p "$snapshot_root"
  : > "$snapshot_root/present.list"
  : > "$snapshot_root/absent.list"
  transaction_managed_paths | while IFS= read -r managed_path; do
    copy_path_if_present "$managed_path" "$snapshot_root"
  done
}

transaction_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  mkdir -p "$candidate_root"
  [ -f "$VP_NODES_DB" ] && cp -p "$VP_NODES_DB" "$candidate_root/nodes.db" || : > "$candidate_root/nodes.db"
  [ -f "$VP_ROTATIONS_DB" ] && cp -p "$VP_ROTATIONS_DB" "$candidate_root/credential-rotations.db" || : > "$candidate_root/credential-rotations.db"
  [ -f "$VP_STATE_FILE" ] && cp -p "$VP_STATE_FILE" "$candidate_root/state.env" || printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$candidate_root/state.env"
  [ -d "$VP_GENERATED_DIR" ] && cp -R -p "$VP_GENERATED_DIR" "$candidate_root/generated" || mkdir -p "$candidate_root/generated"
  chmod 600 "$candidate_root/nodes.db" "$candidate_root/credential-rotations.db" "$candidate_root/state.env"
}

transaction_restore() {
  snapshot_root="$VP_TX_ACTIVE/snapshot"
  [ -d "$snapshot_root" ] || return 0
  if [ -f "$snapshot_root/absent.list" ]; then
    while IFS= read -r relative_path; do
      [ -n "$relative_path" ] && rm -rf "$VP_CONFIG_DIR/$relative_path"
    done < "$snapshot_root/absent.list"
  fi
  if [ -f "$snapshot_root/present.list" ]; then
    while IFS= read -r relative_path; do
      [ -n "$relative_path" ] || continue
      rm -rf "$VP_CONFIG_DIR/$relative_path"
      mkdir -p "$(dirname "$VP_CONFIG_DIR/$relative_path")"
      cp -R -p "$snapshot_root/$relative_path" "$VP_CONFIG_DIR/$relative_path"
    done < "$snapshot_root/present.list"
  fi
}

recover_state_transaction() {
  [ -d "$VP_TX_ACTIVE" ] || return 0
  tx_pid="$(cat "$VP_TX_ACTIVE/pid" 2>/dev/null || true)"
  if [ "$tx_pid" != "$$" ] && pid_is_alive "$tx_pid"; then
    error "另一个配置操作正在进行（PID $tx_pid）。"
    return 1
  fi
  tx_stage="$(cat "$VP_TX_ACTIVE/stage" 2>/dev/null || printf preparing)"
  case "$tx_stage" in
    activated|verifying)
      transaction_restore
      warn "已恢复被中断的配置事务。"
      ;;
    *) warn "已清理未提交的配置事务。" ;;
  esac
  rm -rf "$VP_TX_ACTIVE"
}

begin_state_transaction() {
  operation="$1"
  need_root || return 1
  init_layout >/dev/null || return 1
  recover_state_transaction || return 1
  if ! mkdir "$VP_TX_ACTIVE" 2>/dev/null; then
    error "无法取得配置事务锁。"
    return 1
  fi
  printf '%s\n' "$$" > "$VP_TX_ACTIVE/pid"
  printf '%s\n' "$operation" > "$VP_TX_ACTIVE/operation"
  printf 'preparing\n' > "$VP_TX_ACTIVE/stage"
  transaction_snapshot || { rm -rf "$VP_TX_ACTIVE"; return 1; }
  transaction_candidate || { rm -rf "$VP_TX_ACTIVE"; return 1; }
}

validate_nodes_database() {
  nodes_to_validate="$1"
  awk -F'|' '
    function valid_uuid(value, parts) {
      if (value ~ /[^0-9A-Fa-f-]/ || split(value, parts, "-") != 5) return 0
      return length(parts[1]) == 8 && length(parts[2]) == 4 && length(parts[3]) == 4 &&
             length(parts[4]) == 4 && length(parts[5]) == 12
    }
    function invalid_common(name, port, uuid) {
      return name == "" || name ~ /[[:space:]\047\042]/ || port !~ /^[0-9]+$/ ||
             port + 0 < 1 || port + 0 > 65535 || !valid_uuid(uuid)
    }
    NF == 0 { next }
    {
      if (invalid_common($2, $3, $4) || seen_name[$2]++ || seen_port[$3]++) bad=1
      if ($1 == "reality") {
        if (NF != 10 || $5 == "" || $5 ~ /[[:space:]]/ || $6 == "" || $6 ~ /[[:space:]]/ ||
            $7 == "" || $7 ~ /[^A-Za-z0-9_-]/ || $8 == "" || $8 ~ /[^A-Za-z0-9_-]/ ||
            $9 == "" || $9 ~ /[^0-9A-Fa-f]/ || length($9) > 16 || length($9) % 2 != 0 ||
            ($10 != "ipv4" && $10 != "ipv6")) bad=1
      } else if ($1 == "argo") {
        if (NF != 6 || $5 !~ /^\// || $5 ~ /[[:space:]\047\042]/ ||
            $6 !~ /^[A-Za-z0-9.-]+$/ || $6 !~ /\./) bad=1
      } else {
        bad=1
      }
    }
    END { exit bad ? 1 : 0 }
  ' "$nodes_to_validate"
}

validate_rotations_database() {
  nodes_to_validate="$1"
  rotations_to_validate="$2"
  awk -F'|' '
    function valid_uuid(value, parts) {
      if (value ~ /[^0-9A-Fa-f-]/ || split(value, parts, "-") != 5) return 0
      return length(parts[1]) == 8 && length(parts[2]) == 4 && length(parts[3]) == 4 &&
             length(parts[4]) == 4 && length(parts[5]) == 12
    }
    FILENAME == ARGV[1] { if (NF) { node_proto[$2]=$1; node_uuid[$2]=$4 }; next }
    NF == 0 { next }
    {
      if (NF != 6 || !($1 in node_proto) || $2 != node_proto[$1] || seen[$1]++ ||
          !valid_uuid($3) || !valid_uuid($4) || $4 != node_uuid[$1] ||
          $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ || $5 + 0 <= $6 + 0) bad=1
    }
    END { exit bad ? 1 : 0 }
  ' "$nodes_to_validate" "$rotations_to_validate"
}

validate_state_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  [ -f "$candidate_root/state.env" ] || { error "候选状态文件不存在。"; return 1; }
  [ -f "$candidate_root/nodes.db" ] || { error "候选节点数据库不存在。"; return 1; }
  [ -f "$candidate_root/credential-rotations.db" ] || { error "候选轮换数据库不存在。"; return 1; }
  if grep -Ev '^[A-Z][A-Z0-9_]*=[A-Za-z0-9._:/+-]*$|^$' "$candidate_root/state.env" >/dev/null 2>&1; then
    error "候选状态文件格式错误。"
    return 1
  fi
  if ! validate_nodes_database "$candidate_root/nodes.db"; then
    error "候选节点数据库存在非法协议、字段、端口、UUID、密钥或重复记录。"
    return 1
  fi
  if ! validate_rotations_database "$candidate_root/nodes.db" "$candidate_root/credential-rotations.db"; then
    error "候选凭据轮换数据库格式错误或与当前节点不一致。"
    return 1
  fi
  printf 'validated\n' > "$VP_TX_ACTIVE/stage"
}

activate_state_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  validate_state_candidate || return 1
  state_tmp="$VP_CONFIG_DIR/.state.env.$$"
  nodes_tmp="$VP_CONFIG_DIR/.nodes.db.$$"
  rotations_tmp="$VP_CONFIG_DIR/.credential-rotations.db.$$"
  cp "$candidate_root/state.env" "$state_tmp" || return 1
  cp "$candidate_root/nodes.db" "$nodes_tmp" || { rm -f "$state_tmp"; return 1; }
  cp "$candidate_root/credential-rotations.db" "$rotations_tmp" || { rm -f "$state_tmp" "$nodes_tmp"; return 1; }
  chmod 600 "$state_tmp" "$nodes_tmp" "$rotations_tmp"
  mv "$state_tmp" "$VP_STATE_FILE"
  mv "$nodes_tmp" "$VP_NODES_DB"
  mv "$rotations_tmp" "$VP_ROTATIONS_DB"
  rm -rf "$VP_GENERATED_DIR"
  cp -R -p "$candidate_root/generated" "$VP_GENERATED_DIR"
  printf 'activated\n' > "$VP_TX_ACTIVE/stage"
}

commit_state_transaction() {
  [ -d "$VP_TX_ACTIVE" ] || { error "没有活动事务。"; return 1; }
  printf 'committed\n' > "$VP_TX_ACTIVE/stage"
  rm -rf "$VP_TX_ACTIVE"
}

abort_state_transaction() {
  [ -d "$VP_TX_ACTIVE" ] || return 0
  transaction_restore
  rm -rf "$VP_TX_ACTIVE"
}

debug_transaction() {
  [ "${VP_ALLOW_TEST_HOOKS:-0}" = "1" ] || { error "测试接口未启用。"; return 2; }
  action="${1:-}"
  key="${2:-TEST_VALUE}"
  value="${3:-changed}"
  case "$key" in ''|*[!A-Z0-9_]*) error "测试键格式错误。"; return 2 ;; esac
  begin_state_transaction "debug-$action" || return 1
  candidate="$VP_TX_ACTIVE/candidate/state.env"
  sed "/^$key=/d" "$candidate" > "$candidate.tmp"
  printf '%s=%s\n' "$key" "$value" >> "$candidate.tmp"
  mv "$candidate.tmp" "$candidate"
  case "$action" in
    commit) activate_state_candidate && commit_state_transaction ;;
    fail) activate_state_candidate || { abort_state_transaction; return 1; }; abort_state_transaction; return 1 ;;
    crash) activate_state_candidate || { abort_state_transaction; return 1; }; kill -9 "$$" ;;
    *) abort_state_transaction; error "未知测试动作。"; return 2 ;;
  esac
}

read_meminfo_value() {
  awk -v key="$1" '$1 == key ":" { print $2; exit }' /proc/meminfo 2>/dev/null
}

cgroup_file() {
  name="$1"
  if [ -r "/sys/fs/cgroup/$name" ]; then
    printf '/sys/fs/cgroup/%s' "$name"
    return 0
  fi
  rel="$(awk -F: '$1 == "0" { print $3; exit }' /proc/self/cgroup 2>/dev/null)"
  [ -n "$rel" ] && [ -r "/sys/fs/cgroup$rel/$name" ] && printf '/sys/fs/cgroup%s/%s' "$rel" "$name"
}

bytes_to_mib() {
  value="$1"
  case "$value" in ''|*[!0-9]*) printf '0' ;; *) awk -v n="$value" 'BEGIN { printf "%.1f", n / 1048576 }' ;; esac
}

cpuset_cpu_count() {
  cpuset_text="$1"
  [ -n "$cpuset_text" ] || return 1
  printf '%s\n' "$cpuset_text" | awk -F',' '
    {
      total=0
      for(i=1;i<=NF;i++) {
        if($i ~ /^[0-9]+$/) total++
        else if($i ~ /^[0-9]+-[0-9]+$/) {
          split($i,r,"-"); if(r[2]>=r[1]) total += r[2]-r[1]+1
        } else exit 2
      }
      if(total>0) print total; else exit 1
    }
  '
}

cpu_snapshot() {
  CPU_HOST_COUNT="${VP_CPU_COUNT_OVERRIDE:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 1)}"
  case "$CPU_HOST_COUNT" in ''|*[!0-9]*) CPU_HOST_COUNT=1 ;; esac
  [ "$CPU_HOST_COUNT" -ge 1 ] || CPU_HOST_COUNT=1
  CPU_EFFECTIVE_COUNT="$CPU_HOST_COUNT"
  CPU_QUOTA_MILLI="${VP_CPU_QUOTA_MILLI_OVERRIDE:-0}"
  CPU_SOURCE=host
  [ -n "${VP_CPU_QUOTA_MILLI_OVERRIDE:-}" ] && CPU_SOURCE=override
  if [ -z "${VP_CPU_QUOTA_MILLI_OVERRIDE:-}" ]; then
    cpu_max_file="$(cgroup_file cpu.max 2>/dev/null || true)"
    if [ -r "$cpu_max_file" ]; then
      read -r cpu_quota cpu_period < "$cpu_max_file" || true
      if [ "${cpu_quota:-max}" != max ]; then
        CPU_QUOTA_MILLI="$(awk -v q="$cpu_quota" -v p="$cpu_period" 'BEGIN{if(q>0&&p>0)printf "%d",(q*1000+p-1)/p;else print 0}')"
        CPU_SOURCE=cgroup-quota
      fi
    else
      quota_file="$(cgroup_file cpu.cfs_quota_us 2>/dev/null || true)"
      period_file="$(cgroup_file cpu.cfs_period_us 2>/dev/null || true)"
      if [ ! -r "$quota_file" ] || [ ! -r "$period_file" ]; then
        for cpu_v1_base in /sys/fs/cgroup/cpu /sys/fs/cgroup/cpu,cpuacct; do
          if [ -r "$cpu_v1_base/cpu.cfs_quota_us" ] && [ -r "$cpu_v1_base/cpu.cfs_period_us" ]; then
            quota_file="$cpu_v1_base/cpu.cfs_quota_us"
            period_file="$cpu_v1_base/cpu.cfs_period_us"
            break
          fi
        done
      fi
      if [ -r "$quota_file" ] && [ -r "$period_file" ]; then
        cpu_quota="$(cat "$quota_file" 2>/dev/null || printf -1)"
        cpu_period="$(cat "$period_file" 2>/dev/null || printf 0)"
        if [ "$cpu_quota" -gt 0 ] 2>/dev/null; then
          CPU_QUOTA_MILLI="$(awk -v q="$cpu_quota" -v p="$cpu_period" 'BEGIN{if(q>0&&p>0)printf "%d",(q*1000+p-1)/p;else print 0}')"
          CPU_SOURCE=cgroup-quota
        fi
      fi
    fi
  fi
  case "$CPU_QUOTA_MILLI" in ''|*[!0-9]*) CPU_QUOTA_MILLI=0 ;; esac
  if [ "$CPU_QUOTA_MILLI" -gt 0 ]; then
    quota_cpus=$(((CPU_QUOTA_MILLI + 999) / 1000))
    [ "$quota_cpus" -ge 1 ] || quota_cpus=1
    [ "$CPU_EFFECTIVE_COUNT" -le "$quota_cpus" ] || CPU_EFFECTIVE_COUNT="$quota_cpus"
  fi
  CPU_CPUSET_COUNT="${VP_CPUSET_COUNT_OVERRIDE:-0}"
  if [ -z "${VP_CPUSET_COUNT_OVERRIDE:-}" ]; then
    cpuset_file="$(cgroup_file cpuset.cpus.effective 2>/dev/null || cgroup_file cpuset.cpus 2>/dev/null || true)"
    if [ ! -r "$cpuset_file" ]; then
      for cpuset_v1_file in /sys/fs/cgroup/cpuset/cpuset.cpus /sys/fs/cgroup/cpuset.cpus; do
        [ -r "$cpuset_v1_file" ] && { cpuset_file="$cpuset_v1_file"; break; }
      done
    fi
    [ -r "$cpuset_file" ] && CPU_CPUSET_COUNT="$(cpuset_cpu_count "$(cat "$cpuset_file" 2>/dev/null)" 2>/dev/null || printf 0)"
  fi
  case "$CPU_CPUSET_COUNT" in ''|*[!0-9]*) CPU_CPUSET_COUNT=0 ;; esac
  if [ "$CPU_CPUSET_COUNT" -gt 0 ] && [ "$CPU_EFFECTIVE_COUNT" -gt "$CPU_CPUSET_COUNT" ]; then
    CPU_EFFECTIVE_COUNT="$CPU_CPUSET_COUNT"
    CPU_SOURCE="$CPU_SOURCE+cpuset"
  fi
  [ "$CPU_EFFECTIVE_COUNT" -ge 1 ] || CPU_EFFECTIVE_COUNT=1
}

oom_snapshot() {
  OOM_CURRENT="${VP_OOM_CURRENT_OVERRIDE:-0}"
  OOM_PREVIOUS=0
  OOM_DELTA=0
  if [ -z "${VP_OOM_CURRENT_OVERRIDE:-}" ]; then
    memory_events="$(cgroup_file memory.events 2>/dev/null || true)"
    [ -r "$memory_events" ] && OOM_CURRENT="$(awk '$1=="oom_kill"{print $2;exit}' "$memory_events" 2>/dev/null)"
  fi
  case "$OOM_CURRENT" in ''|*[!0-9]*) OOM_CURRENT=0 ;; esac
  if [ -r "$VP_OOM_STATE_FILE" ]; then
    OOM_PREVIOUS="$(cat "$VP_OOM_STATE_FILE" 2>/dev/null || printf 0)"
  else
    OOM_PREVIOUS="$OOM_CURRENT"
  fi
  case "$OOM_PREVIOUS" in ''|*[!0-9]*) OOM_PREVIOUS=0 ;; esac
  [ "$OOM_CURRENT" -ge "$OOM_PREVIOUS" ] && OOM_DELTA=$((OOM_CURRENT - OOM_PREVIOUS))
}

remember_oom_snapshot() {
  mkdir -p "$(dirname "$VP_OOM_STATE_FILE")" 2>/dev/null || return 0
  printf '%s\n' "$OOM_CURRENT" > "$VP_OOM_STATE_FILE" 2>/dev/null || return 0
  chmod 600 "$VP_OOM_STATE_FILE" 2>/dev/null || true
}

dns_server_query_probe() {
  dns_server="$1"
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$VP_DNS_TEST_HOST" "$dns_server" >/dev/null 2>&1
  elif command -v dig >/dev/null 2>&1; then
    dig +time=2 +tries=1 +short @"$dns_server" "$VP_DNS_TEST_HOST" A >/dev/null 2>&1
  else
    return 2
  fi
}

dns_server_tcp_probe() {
  dns_server="$1"
  command -v nc >/dev/null 2>&1 || return 2
  nc -z -w 2 "$dns_server" 53 >/dev/null 2>&1
}

detect_dns_profile() {
  VP_DNS_MODE=system
  VP_DNS_SERVERS=""
  VP_DNS_PUBLIC_OK=0
  VP_DNS_SYSTEM_OK=0
  VP_DNS_QUERY_TOOL=none
  VP_DNS_TCP_CHECK=skipped
  if command -v nslookup >/dev/null 2>&1; then
    VP_DNS_QUERY_TOOL=nslookup
  elif command -v dig >/dev/null 2>&1; then
    VP_DNS_QUERY_TOOL=dig
  fi

  if [ "$VP_DNS_QUERY_TOOL" != none ]; then
    for dns_server in $VP_DNS_PUBLIC_SERVERS; do
      dns_server_query_probe "$dns_server" || continue
      if dns_server_tcp_probe "$dns_server" >/dev/null 2>&1; then
        VP_DNS_TCP_CHECK=passed
      elif [ "$?" -eq 2 ]; then
        VP_DNS_TCP_CHECK=skipped
      else
        continue
      fi
      if [ -n "$VP_DNS_SERVERS" ]; then
        VP_DNS_SERVERS="$VP_DNS_SERVERS,$dns_server"
      else
        VP_DNS_SERVERS="$dns_server"
      fi
    done
  fi

  if [ -n "$VP_DNS_SERVERS" ]; then
    VP_DNS_MODE=public
    VP_DNS_PUBLIC_OK=1
  elif dns_probe >/dev/null 2>&1; then
    VP_DNS_SYSTEM_OK=1
    VP_DNS_SERVERS="$(awk '/^[[:space:]]*nameserver[[:space:]]+/{if (n++) printf ","; printf $2} END{print ""}' /etc/resolv.conf 2>/dev/null || true)"
    [ -n "$VP_DNS_SERVERS" ] || VP_DNS_SERVERS=system
  fi
}

dns_profile_probe() {
  dns_mode="$1"
  dns_servers="$2"
  case "$dns_mode" in
    public|system)
      [ -n "$dns_servers" ] || return 1
      [ "$dns_servers" = system ] && dns_probe && return 0
      if ! command -v nslookup >/dev/null 2>&1 && ! command -v dig >/dev/null 2>&1; then
        dns_probe
        return $?
      fi
      for dns_server in $(printf '%s' "$dns_servers" | tr ',' ' '); do
        dns_server_query_probe "$dns_server" || return 1
      done
      return 0
      ;;
    *) dns_probe ;;
  esac
}

memory_snapshot() {
  current_file="$(cgroup_file memory.current 2>/dev/null || true)"
  max_file="$(cgroup_file memory.max 2>/dev/null || true)"
  stat_file="$(cgroup_file memory.stat 2>/dev/null || true)"
  swap_file="$(cgroup_file memory.swap.current 2>/dev/null || true)"

  if [ -n "$current_file" ]; then
    MEM_TOTAL_BYTES="$(cat "$current_file" 2>/dev/null || printf 0)"
    MEM_LIMIT_BYTES="${VP_MEMORY_LIMIT_BYTES_OVERRIDE:-$(cat "$max_file" 2>/dev/null || printf 0)}"
    [ "$MEM_LIMIT_BYTES" = "max" ] && MEM_LIMIT_BYTES=0
    MEM_ANON_BYTES="$(awk '$1=="anon"{print $2;exit}' "$stat_file" 2>/dev/null)"
    MEM_FILE_BYTES="$(awk '$1=="file"{print $2;exit}' "$stat_file" 2>/dev/null)"
    MEM_KERNEL_BYTES="$(awk '$1=="kernel"{print $2;exit}' "$stat_file" 2>/dev/null)"
    MEM_SWAP_BYTES="$(cat "$swap_file" 2>/dev/null || printf 0)"
    MEM_SOURCE="cgroup"
  else
    total_kib="$(read_meminfo_value MemTotal)"
    available_kib="$(read_meminfo_value MemAvailable)"
    cached_kib="$(read_meminfo_value Cached)"
    buffers_kib="$(read_meminfo_value Buffers)"
    swap_total_kib="$(read_meminfo_value SwapTotal)"
    swap_free_kib="$(read_meminfo_value SwapFree)"
    MEM_LIMIT_BYTES=$((total_kib * 1024))
    MEM_TOTAL_BYTES=$(((total_kib - available_kib) * 1024))
    MEM_FILE_BYTES=$(((cached_kib + buffers_kib) * 1024))
    MEM_ANON_BYTES=$((MEM_TOTAL_BYTES - MEM_FILE_BYTES))
    [ "$MEM_ANON_BYTES" -ge 0 ] || MEM_ANON_BYTES=0
    MEM_KERNEL_BYTES=0
    MEM_SWAP_BYTES=$(((swap_total_kib - swap_free_kib) * 1024))
    MEM_SOURCE="meminfo"
  fi
  [ -n "${MEM_ANON_BYTES:-}" ] || MEM_ANON_BYTES=0
  [ -n "${MEM_FILE_BYTES:-}" ] || MEM_FILE_BYTES=0
  [ -n "${MEM_KERNEL_BYTES:-}" ] || MEM_KERNEL_BYTES=0
  MEM_WORKING_BYTES=$((MEM_ANON_BYTES + MEM_KERNEL_BYTES))
}

service_state() {
  service_state_name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$service_state_name" 2>/dev/null || printf 'not-installed'
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$service_state_name" status >/dev/null 2>&1 && printf 'active' || printf 'not-installed'
  else
    printf 'unsupported'
  fi
}

service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    printf 'systemd'
  elif command -v rc-service >/dev/null 2>&1; then
    printf 'openrc'
  else
    printf 'none'
  fi
}

service_action() {
  service_action_verb="$1"
  service_action_name="$2"
  case "$(service_manager)" in
    systemd) systemctl "$service_action_verb" "$service_action_name" ;;
    openrc) rc-service "$service_action_name" "$service_action_verb" ;;
    *) error "当前系统不支持 systemd 或 OpenRC。"; return 1 ;;
  esac
}

core_process_running() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$VP_CORE_BIN.*$VP_CORE_CONFIG" >/dev/null 2>&1
  else
    ps 2>/dev/null | grep -F "$VP_CORE_BIN" | grep -F "$VP_CORE_CONFIG" | grep -v grep >/dev/null 2>&1
  fi
}

core_service_restart() {
  if [ "${VP_ALLOW_TEST_HOOKS:-0}" = "1" ] && [ "${VP_TEST_CORE_RESTART_FAIL:-0}" = "1" ]; then
    return 1
  fi
  [ "${VP_SKIP_SERVICE:-0}" = "1" ] && return 0
  service_action restart "$VP_CORE_SERVICE" >/dev/null 2>&1 || return 1
  attempts=0
  while [ "$attempts" -lt 10 ]; do
    core_process_running && return 0
    sleep 1
    attempts=$((attempts + 1))
  done
  return 1
}

detect_arch() {
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7) printf 'armv7' ;;
    riscv64) printf 'riscv64' ;;
    *) error "不支持当前 CPU 架构：$(uname -m 2>/dev/null)"; return 1 ;;
  esac
}

release_asset_records() {
  printf '%s\n' "$1" | awk '
    /"name"[[:space:]]*:/ {
      value=$0; sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", value); sub(/".*$/, "", value); name=value
    }
    /"digest"[[:space:]]*:/ {
      value=$0; sub(/^.*"digest"[[:space:]]*:[[:space:]]*"sha256:/, "", value); sub(/".*$/, "", value); digest=value
    }
    /"browser_download_url"[[:space:]]*:/ {
      value=$0; sub(/^.*"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", value); sub(/".*$/, "", value)
      if (name != "") print name "|" value "|" digest
      name=""; digest=""
    }
  '
}

mihomo_asset_record() {
  arch="$(detect_arch)" || return 1
  release_json="$(curl -fsSL --max-time 30 "$VP_MIHOMO_API")" || { error "无法访问 Mihomo Release API。"; return 1; }
  records="$(release_asset_records "$release_json")"
  record="$(printf '%s\n' "$records" | grep -Ei "^mihomo-linux-${arch}.*compatible.*\.gz\|" | head -n 1 || true)"
  [ -n "$record" ] || record="$(printf '%s\n' "$records" | grep -Ei "^mihomo-linux-${arch}.*\.gz\|" | head -n 1 || true)"
  [ -n "$record" ] || { error "Release 中没有 linux-$arch 内核。"; return 1; }
  printf '%s' "$record"
}

install_core_binary() {
  need_root || return 1
  mkdir -p "$(dirname "$VP_CORE_BIN")"
  binary_tmp="$(mktemp /tmp/vp-mihomo-bin.XXXXXX)" || return 1
  archive_tmp="$(mktemp /tmp/vp-mihomo.XXXXXX)" || { rm -f "$binary_tmp"; return 1; }
  if [ -n "${VP_CORE_SOURCE_BIN:-}" ]; then
    cp "$VP_CORE_SOURCE_BIN" "$binary_tmp" || { rm -f "$binary_tmp" "$archive_tmp"; return 1; }
  else
    command -v curl >/dev/null 2>&1 || { error "缺少 curl。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    command -v gzip >/dev/null 2>&1 || { error "缺少 gzip。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    asset="$(mihomo_asset_record)" || { rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    asset_name="${asset%%|*}"; asset_rest="${asset#*|}"; download_url="${asset_rest%%|*}"; expected_digest="${asset_rest#*|}"
    case "$expected_digest" in ''|*[!0-9a-fA-F]*) error "GitHub 未提供有效的 Mihomo SHA-256。"; rm -f "$binary_tmp" "$archive_tmp"; return 1 ;; esac
    info "正在下载 Mihomo 内核。"
    curl -fL --max-time 180 "$download_url" -o "$archive_tmp" || { error "Mihomo 下载失败。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    actual_digest="$(sha256_file "$archive_tmp" 2>/dev/null | tr 'A-F' 'a-f')"
    [ "$(printf '%s' "$expected_digest" | tr 'A-F' 'a-f')" = "$actual_digest" ] || { error "Mihomo SHA-256 校验失败。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    gzip -dc "$archive_tmp" > "$binary_tmp" || { error "Mihomo 解压失败。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
  fi
  rm -f "$archive_tmp"
  chmod 755 "$binary_tmp"
  "$binary_tmp" -v >/dev/null 2>&1 || { error "下载的内核无法运行。"; rm -f "$binary_tmp"; return 1; }
  [ -x "$VP_CORE_BIN" ] && cp "$VP_CORE_BIN" "$VP_CORE_BACKUP_BIN"
  mv "$binary_tmp" "$VP_CORE_BIN"
  chmod 755 "$VP_CORE_BIN"
}

write_core_runtime_env() {
  memory_snapshot
  cpu_snapshot
  detect_dns_profile
  limit_mib=$((MEM_LIMIT_BYTES / 1048576))
  case "$limit_mib" in ''|*[!0-9]*) limit_mib=0 ;; esac
  [ "$limit_mib" -gt 0 ] || limit_mib=1024
  budget_mib=$((limit_mib * 60 / 100))
  [ "$budget_mib" -ge 32 ] || budget_mib=32
  [ "$budget_mib" -le 512 ] || budget_mib=512
  if [ "$limit_mib" -le 96 ]; then
    gogc=50; gomaxprocs=1; profile=ultra-compact
  elif [ "$limit_mib" -le 160 ]; then
    gogc=60; gomaxprocs=1; profile=compact
  elif [ "$limit_mib" -le 320 ]; then
    gogc=80; gomaxprocs=2; profile=balanced
  elif [ "$limit_mib" -le 640 ]; then
    gogc=100; gomaxprocs=2; profile=standard
  else
    gogc=100; gomaxprocs="$CPU_EFFECTIVE_COUNT"; [ "$gomaxprocs" -le 4 ] || gomaxprocs=4; profile=performance
  fi
  [ "$gomaxprocs" -le "$CPU_EFFECTIVE_COUNT" ] || gomaxprocs="$CPU_EFFECTIVE_COUNT"
  if [ "$CPU_QUOTA_MILLI" -gt 0 ] && [ "$CPU_QUOTA_MILLI" -lt 1000 ] && [ "$limit_mib" -gt 160 ]; then
    gogc=$((gogc + 20)); [ "$gogc" -le 120 ] || gogc=120
    profile="$profile-cpu-limited"
  fi
  gomemlimit="${budget_mib}MiB"
  {
    printf 'VP_MEMORY_PROFILE=%s\n' "$profile"
    printf 'VP_MEMORY_LIMIT_MIB=%s\n' "$limit_mib"
    printf 'VP_CORE_BUDGET_MIB=%s\n' "$budget_mib"
    printf 'GOMEMLIMIT=%s\n' "$gomemlimit"
    printf 'GOGC=%s\n' "$gogc"
    printf 'GOMAXPROCS=%s\n' "$gomaxprocs"
    printf 'VP_CPU_SOURCE=%s\n' "$CPU_SOURCE"
    printf 'VP_CPU_HOST_COUNT=%s\n' "$CPU_HOST_COUNT"
    printf 'VP_CPU_EFFECTIVE_COUNT=%s\n' "$CPU_EFFECTIVE_COUNT"
    printf 'VP_CPU_QUOTA_MILLI=%s\n' "$CPU_QUOTA_MILLI"
    printf 'VP_CPUSET_COUNT=%s\n' "$CPU_CPUSET_COUNT"
    printf 'VP_MIXED_PORT=%s\n' "$VP_MIXED_PORT"
    printf 'VP_CONTROLLER_PORT=%s\n' "$VP_CONTROLLER_PORT"
    printf 'VP_DNS_MODE=%s\n' "$VP_DNS_MODE"
    printf 'VP_DNS_SERVERS=%s\n' "$VP_DNS_SERVERS"
    printf 'VP_DNS_PUBLIC_OK=%s\n' "$VP_DNS_PUBLIC_OK"
    printf 'VP_DNS_SYSTEM_OK=%s\n' "$VP_DNS_SYSTEM_OK"
    printf 'VP_DNS_QUERY_TOOL=%s\n' "$VP_DNS_QUERY_TOOL"
    printf 'VP_DNS_TCP_CHECK=%s\n' "$VP_DNS_TCP_CHECK"
  } > "$VP_CORE_ENV"
  chmod 600 "$VP_CORE_ENV"
}

yaml_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

render_mihomo_config() {
  nodes_file="$1"
  output_file="$2"
  rotations_file="${3:-$VP_ROTATIONS_DB}"
  render_now="$(date +%s 2>/dev/null || printf 0)"
  mkdir -p "$(dirname "$output_file")"
  dns_mode="$(awk -F= '$1=="VP_DNS_MODE"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || true)"
  dns_servers="$(awk -F= '$1=="VP_DNS_SERVERS"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || true)"
  config_ipv6=false
  awk -F'|' '$1=="reality" && $10=="ipv6"{found=1}END{exit found?0:1}' "$nodes_file" 2>/dev/null && config_ipv6=true
  {
    printf 'mixed-port: %s\n' "$VP_MIXED_PORT"
    printf "external-controller: '127.0.0.1:%s'\n" "$VP_CONTROLLER_PORT"
    printf 'allow-lan: false\nmode: rule\nlog-level: warning\nipv6: %s\n' "$config_ipv6"
    case "$dns_mode" in
      public|system)
        if [ -n "$dns_servers" ] && [ "$dns_servers" != system ]; then
          printf 'dns:\n  enable: true\n  ipv6: %s\n  nameserver:\n' "$config_ipv6"
          for dns_server in $(printf '%s' "$dns_servers" | tr ',' ' '); do
            printf '    - %s\n' "$dns_server"
          done
        fi
        ;;
    esac
    printf 'listeners:\n'
    while IFS='|' read -r proto name port uuid sni dest private_key public_key short_id address_family; do
      [ -n "$proto" ] || continue
      old_uuid="$(awk -F'|' -v n="$name" -v now="$render_now" '$1==n && $5+0>now {print $3; exit}' "$rotations_file" 2>/dev/null)"
      case "$proto" in
        reality)
          [ "$address_family" = ipv6 ] && listen_address='::' || listen_address='0.0.0.0'
          printf "  - name: '%s'\n" "$(yaml_quote "$name")"
          printf "    type: vless\n    port: %s\n    listen: '%s'\n" "$port" "$listen_address"
          printf "    users:\n      - username: '%s'\n        uuid: '%s'\n" "$(yaml_quote "$name")" "$(yaml_quote "$uuid")"
          [ -n "$old_uuid" ] && printf "      - username: '%s-old'\n        uuid: '%s'\n" "$(yaml_quote "$name")" "$(yaml_quote "$old_uuid")"
          printf '    tls: true\n    reality-config:\n'
          printf "      dest: '%s'\n      private-key: '%s'\n" "$(yaml_quote "$dest")" "$(yaml_quote "$private_key")"
          printf "      short-id:\n        - '%s'\n      server-names:\n        - '%s'\n" "$(yaml_quote "$short_id")" "$(yaml_quote "$sni")"
          ;;
        argo)
          printf "  - name: '%s'\n" "$(yaml_quote "$name")"
          printf '    type: vless\n    port: %s\n    listen: 127.0.0.1\n    allow-insecure: true\n' "$port"
          printf "    users:\n      - username: '%s'\n        uuid: '%s'\n" "$(yaml_quote "$name")" "$(yaml_quote "$uuid")"
          [ -n "$old_uuid" ] && printf "      - username: '%s-old'\n        uuid: '%s'\n" "$(yaml_quote "$name")" "$(yaml_quote "$old_uuid")"
          printf "    ws-path: '%s'\n" "$(yaml_quote "$sni")"
          ;;
      esac
    done < "$nodes_file"
    printf 'proxies: []\nproxy-groups:\n  - name: Proxy\n    type: select\n    proxies:\n      - DIRECT\nrules:\n  - MATCH,DIRECT\n'
  } > "$output_file"
  chmod 600 "$output_file"
}

generated_config_matches_state() {
  [ -r "$VP_NODES_DB" ] && [ -r "$VP_ROTATIONS_DB" ] && [ -r "$VP_CORE_CONFIG" ] || return 1
  expected_config="$(mktemp /tmp/vp-expected-config.XXXXXX)" || return 1
  render_mihomo_config "$VP_NODES_DB" "$expected_config" "$VP_ROTATIONS_DB"
  cmp -s "$expected_config" "$VP_CORE_CONFIG"
  matches=$?
  rm -f "$expected_config"
  return "$matches"
}

cloudflared_asset_record() {
  case "$(detect_arch)" in
    amd64) cf_arch=amd64 ;;
    arm64) cf_arch=arm64 ;;
    armv7) cf_arch=arm ;;
    *) error "cloudflared 不支持当前架构。"; return 1 ;;
  esac
  release_json="$(curl -fsSL --max-time 30 "$VP_CLOUDFLARED_API")" || { error "无法访问 cloudflared Release API。"; return 1; }
  record="$(release_asset_records "$release_json" | grep -E "^cloudflared-linux-${cf_arch}\|" | head -n 1 || true)"
  [ -n "$record" ] || { error "Release 中没有适配的 cloudflared。"; return 1; }
  printf '%s' "$record"
}

install_tunnel_binary() {
  mkdir -p "$(dirname "$VP_TUNNEL_BIN")"
  tunnel_tmp="$(mktemp /tmp/vp-cloudflared.XXXXXX)" || return 1
  if [ -n "${VP_TUNNEL_SOURCE_BIN:-}" ]; then
    cp "$VP_TUNNEL_SOURCE_BIN" "$tunnel_tmp" || { rm -f "$tunnel_tmp"; return 1; }
  else
    asset="$(cloudflared_asset_record)" || { rm -f "$tunnel_tmp"; return 1; }
    asset_name="${asset%%|*}"; asset_rest="${asset#*|}"; url="${asset_rest%%|*}"; expected_digest="${asset_rest#*|}"
    case "$expected_digest" in ''|*[!0-9a-fA-F]*) error "GitHub 未提供有效的 cloudflared SHA-256。"; rm -f "$tunnel_tmp"; return 1 ;; esac
    info "正在下载 cloudflared。"
    curl -fL --max-time 180 "$url" -o "$tunnel_tmp" || { rm -f "$tunnel_tmp"; error "cloudflared 下载失败。"; return 1; }
    actual_digest="$(sha256_file "$tunnel_tmp" 2>/dev/null | tr 'A-F' 'a-f')"
    [ "$(printf '%s' "$expected_digest" | tr 'A-F' 'a-f')" = "$actual_digest" ] || { rm -f "$tunnel_tmp"; error "cloudflared SHA-256 校验失败。"; return 1; }
  fi
  chmod 755 "$tunnel_tmp"
  "$tunnel_tmp" version >/dev/null 2>&1 || { rm -f "$tunnel_tmp"; error "cloudflared 无法运行。"; return 1; }
  [ -x "$VP_TUNNEL_BIN" ] && cp "$VP_TUNNEL_BIN" "$VP_TUNNEL_BACKUP_BIN"
  mv "$tunnel_tmp" "$VP_TUNNEL_BIN"
}

install_tunnel_service() {
  [ "${VP_SKIP_SERVICE:-0}" = "1" ] && return 0
  cat > "$VP_TUNNEL_RUNNER" <<EOF
#!/bin/sh
exec "$VP_TUNNEL_BIN" tunnel --no-autoupdate --protocol http2 --metrics "127.0.0.1:$VP_TUNNEL_METRICS_PORT" run --token-file "$VP_TUNNEL_TOKEN_FILE"
EOF
  chmod 700 "$VP_TUNNEL_RUNNER"
  case "$(service_manager)" in
    systemd)
      cat > "/etc/systemd/system/${VP_TUNNEL_SERVICE}.service" <<EOF
[Unit]
Description=VPS-Node Cloudflare Tunnel
After=network-online.target $VP_CORE_SERVICE.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$VP_TUNNEL_RUNNER
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable "$VP_TUNNEL_SERVICE" >/dev/null
      ;;
    openrc)
      cat > "/etc/init.d/$VP_TUNNEL_SERVICE" <<EOF
#!/sbin/openrc-run
description="VPS-Node Cloudflare Tunnel"
command="$VP_TUNNEL_RUNNER"
supervisor="supervise-daemon"
output_log="$VP_LOG_DIR/tunnel.log"
error_log="$VP_LOG_DIR/tunnel.log"
respawn_delay=5
respawn_max=0
depend() { need net; after $VP_CORE_SERVICE; }
EOF
      chmod 755 "/etc/init.d/$VP_TUNNEL_SERVICE"
      rc-update add "$VP_TUNNEL_SERVICE" default >/dev/null
      ;;
    *) error "无法安装 Tunnel 服务。"; return 1 ;;
  esac
}

tunnel_service_restart() {
  if [ "${VP_ALLOW_TEST_HOOKS:-0}" = "1" ] && [ "${VP_TEST_TUNNEL_RESTART_FAIL:-0}" = "1" ]; then
    return 1
  fi
  [ "${VP_SKIP_SERVICE:-0}" = "1" ] && return 0
  service_action restart "$VP_TUNNEL_SERVICE" >/dev/null 2>&1 || return 1
  attempts=0
  while [ "$attempts" -lt 15 ]; do
    service_state "$VP_TUNNEL_SERVICE" | grep -Eq 'active|started' && return 0
    sleep 1
    attempts=$((attempts + 1))
  done
  return 1
}

rollback_tunnel_install() {
  had_binary="$1"
  had_token="$2"
  token_backup="$3"
  was_running="$4"
  if [ "$had_binary" = "1" ] && [ -x "$VP_TUNNEL_BACKUP_BIN" ]; then
    cp "$VP_TUNNEL_BACKUP_BIN" "$VP_TUNNEL_BIN" && chmod 755 "$VP_TUNNEL_BIN"
  elif [ "$had_binary" = "0" ]; then
    rm -f "$VP_TUNNEL_BIN"
  fi
  if [ "$had_token" = "1" ] && [ -r "$token_backup" ]; then
    cp "$token_backup" "$VP_TUNNEL_TOKEN_FILE" && chmod 600 "$VP_TUNNEL_TOKEN_FILE"
  elif [ "$had_token" = "0" ]; then
    rm -f "$VP_TUNNEL_TOKEN_FILE"
  fi
  if [ "${VP_SKIP_SERVICE:-0}" != "1" ]; then
    if [ "$was_running" = "1" ]; then
      service_action restart "$VP_TUNNEL_SERVICE" >/dev/null 2>&1 || true
    else
      service_action stop "$VP_TUNNEL_SERVICE" >/dev/null 2>&1 || true
    fi
  fi
}

tunnel_install() {
  need_root || return 1
  command -v curl >/dev/null 2>&1 || install_packages ca-certificates curl || return 1
  init_layout >/dev/null || return 1
  token_source="${1:-}"
  if [ -n "$token_source" ] && [ -r "$token_source" ]; then
    token="$(cat "$token_source")"
  elif [ -n "${VP_TUNNEL_TOKEN:-}" ]; then
    token="$VP_TUNNEL_TOKEN"
  else
    printf '请输入 Cloudflare Tunnel Token：' >&2
    stty -echo 2>/dev/null || true
    read -r token || true
    stty echo 2>/dev/null || true
    printf '\n' >&2
  fi
  [ -n "${token:-}" ] || { error "Token 不能为空。"; return 1; }
  case "$token" in *[!A-Za-z0-9._-]*) error "Token 格式无效。"; return 1 ;; esac
  tunnel_had_binary=0
  tunnel_had_token=0
  tunnel_was_running=0
  [ -x "$VP_TUNNEL_BIN" ] && tunnel_had_binary=1
  [ -s "$VP_TUNNEL_TOKEN_FILE" ] && tunnel_had_token=1
  case "$(service_state "$VP_TUNNEL_SERVICE")" in active|started) tunnel_was_running=1 ;; esac
  token_backup="$(mktemp /tmp/vp-tunnel-token.XXXXXX)" || return 1
  if [ "$tunnel_had_token" = "1" ]; then
    cp "$VP_TUNNEL_TOKEN_FILE" "$token_backup" || { rm -f "$token_backup"; return 1; }
    chmod 600 "$token_backup"
  fi
  install_tunnel_binary || { rm -f "$token_backup"; return 1; }
  token_candidate="$(mktemp "$VP_SECRETS_DIR/.cloudflared-token.XXXXXX")" || {
    rollback_tunnel_install "$tunnel_had_binary" "$tunnel_had_token" "$token_backup" "$tunnel_was_running"
    rm -f "$token_backup"
    return 1
  }
  printf '%s\n' "$token" > "$token_candidate" || {
    rm -f "$token_candidate"
    rollback_tunnel_install "$tunnel_had_binary" "$tunnel_had_token" "$token_backup" "$tunnel_was_running"
    rm -f "$token_backup"
    return 1
  }
  chmod 600 "$token_candidate"
  mv "$token_candidate" "$VP_TUNNEL_TOKEN_FILE"
  if ! install_tunnel_service || ! tunnel_service_restart; then
    rollback_tunnel_install "$tunnel_had_binary" "$tunnel_had_token" "$token_backup" "$tunnel_was_running"
    rm -f "$token_backup"
    error "Tunnel 更新启动失败，已恢复旧二进制、Token 和服务状态。"
    return 1
  fi
  rm -f "$token_backup"
  ok "Cloudflare Tunnel 已安装。"
}

argo_add() {
  need_root || return 1
  [ -x "$VP_CORE_BIN" ] || { error "请先安装代理核心。"; return 1; }
  name="${1:-argo-1}"
  requested_port="${2:-}"
  host="${3:-}"
  path="${4:-/$(random_hex 8)}"
  [ -n "$host" ] || { error "请提供 Tunnel 公网域名。"; return 1; }
  case "$name$host$path" in *'|'*|*' '*|*\"*|*\'*) error "参数包含非法字符。"; return 1 ;; esac
  case "$path" in /*) ;; *) path="/$path" ;; esac
  port="$(choose_port "$requested_port")" || { error "本地端口不可用。"; return 1; }
  created_name="$name"
  uuid="$(new_uuid)"
  begin_state_transaction argo-add || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  if awk -F'|' -v n="$name" '$2==n{found=1} END{exit found?0:1}' "$candidate_root/nodes.db"; then
    abort_state_transaction; error "节点名称已存在。"; return 1
  fi
  printf 'argo|%s|%s|%s|%s|%s\n' "$name" "$port" "$uuid" "$path" "$host" >> "$candidate_root/nodes.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "Argo 候选配置验证失败。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "Argo 本地入口启动失败，已恢复原配置。"; return 1
  fi
  commit_state_transaction
  ok "Argo 备用节点已创建：$created_name。"
  warn "请确认 Cloudflare Tunnel 公网主机名的服务指向 http://127.0.0.1:$port。"
}

install_core_service() {
  [ "${VP_SKIP_SERVICE:-0}" = "1" ] && return 0
  cat > "$VP_CORE_RUNNER" <<EOF
#!/bin/sh
set -a
. "$VP_CORE_ENV"
set +a
exec "$VP_CORE_BIN" -d "$VP_CONFIG_DIR" -f "$VP_CORE_CONFIG"
EOF
  chmod 700 "$VP_CORE_RUNNER"
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      cat > "/etc/systemd/system/${VP_CORE_SERVICE}.service" <<EOF
[Unit]
Description=VPS-Node proxy core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$VP_CORE_RUNNER
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable "$VP_CORE_SERVICE" >/dev/null
      ;;
    openrc)
      cat > "/etc/init.d/$VP_CORE_SERVICE" <<EOF
#!/sbin/openrc-run
description="VPS-Node proxy core"
command="$VP_CORE_RUNNER"
supervisor="supervise-daemon"
output_log="$VP_LOG_DIR/core.log"
error_log="$VP_LOG_DIR/core.err"
respawn_delay=2
respawn_max=0
rc_ulimit="-n 1048576"
depend() { need net; }
EOF
      chmod 755 "/etc/init.d/$VP_CORE_SERVICE"
      rc-update add "$VP_CORE_SERVICE" default >/dev/null
      ;;
    *) error "无法安装服务：系统不支持 systemd 或 OpenRC。"; return 1 ;;
  esac
}

rollback_core_binary() {
  had_binary="$1"
  if [ "$had_binary" = "1" ] && [ -x "$VP_CORE_BACKUP_BIN" ]; then
    cp "$VP_CORE_BACKUP_BIN" "$VP_CORE_BIN"
    chmod 755 "$VP_CORE_BIN"
  elif [ "$had_binary" = "0" ]; then
    rm -f "$VP_CORE_BIN"
  fi
}

restore_core_env_backup() {
  had_env="$1"
  env_backup="$2"
  if [ "$had_env" = "1" ] && [ -r "$env_backup" ]; then
    cp -p "$env_backup" "$VP_CORE_ENV"
    chmod 600 "$VP_CORE_ENV"
  elif [ "$had_env" = "0" ]; then
    rm -f "$VP_CORE_ENV"
  fi
}

core_internal_port_owned() {
  port_kind="$1"
  port_value="$2"
  [ -r "$VP_CORE_CONFIG" ] && core_process_running || return 1
  case "$port_kind" in
    mixed) grep -Eq "^mixed-port:[[:space:]]*$port_value$" "$VP_CORE_CONFIG" ;;
    controller) grep -Eq "^external-controller:[[:space:]]*'127\\.0\\.0\\.1:$port_value'$" "$VP_CORE_CONFIG" ;;
    *) return 1 ;;
  esac
}

prepare_core_internal_ports() {
  case "$VP_MIXED_PORT" in ''|*[!0-9]*) error "Mihomo 内部混合端口无效：$VP_MIXED_PORT。"; return 1 ;; esac
  case "$VP_CONTROLLER_PORT" in ''|*[!0-9]*) error "Mihomo 控制端口无效：$VP_CONTROLLER_PORT。"; return 1 ;; esac
  [ "$VP_MIXED_PORT" -ge 1024 ] && [ "$VP_MIXED_PORT" -le 65535 ] || { error "Mihomo 内部混合端口必须为 1024-65535。"; return 1; }
  [ "$VP_CONTROLLER_PORT" -ge 1024 ] && [ "$VP_CONTROLLER_PORT" -le 65535 ] || { error "Mihomo 控制端口必须为 1024-65535。"; return 1; }
  if port_in_use "$VP_MIXED_PORT" && ! core_internal_port_owned mixed "$VP_MIXED_PORT"; then
    [ -z "$VP_MIXED_PORT_OVERRIDE" ] || { error "指定的内部混合端口 $VP_MIXED_PORT 已被其他任务占用。"; return 1; }
    old_internal_port="$VP_MIXED_PORT"
    VP_MIXED_PORT="$(choose_port)" || return 1
    warn "内部混合端口 $old_internal_port 已占用，自动改用 $VP_MIXED_PORT。"
  fi
  if [ "$VP_CONTROLLER_PORT" = "$VP_MIXED_PORT" ] ||
     { port_in_use "$VP_CONTROLLER_PORT" && ! core_internal_port_owned controller "$VP_CONTROLLER_PORT"; }; then
    [ -z "$VP_CONTROLLER_PORT_OVERRIDE" ] || { error "指定的控制端口 $VP_CONTROLLER_PORT 不可用。"; return 1; }
    old_internal_port="$VP_CONTROLLER_PORT"
    attempts=0
    while [ "$attempts" -lt 20 ]; do
      VP_CONTROLLER_PORT="$(choose_port)" || return 1
      [ "$VP_CONTROLLER_PORT" != "$VP_MIXED_PORT" ] && break
      attempts=$((attempts + 1))
    done
    [ "$VP_CONTROLLER_PORT" != "$VP_MIXED_PORT" ] || { error "无法为 Mihomo 控制端口找到空闲端口。"; return 1; }
    warn "控制端口 $old_internal_port 不可用，自动改用 $VP_CONTROLLER_PORT。"
  fi
}

core_binary_rollback() {
  need_root || return 1
  [ -x "$VP_CORE_BACKUP_BIN" ] || { error "没有可回滚的 Mihomo 内核。"; return 1; }
  candidate="$(mktemp /tmp/vp-core-rollback.XXXXXX)" || return 1
  cp "$VP_CORE_BACKUP_BIN" "$candidate" || { rm -f "$candidate"; return 1; }
  chmod 755 "$candidate"
  "$candidate" -v >/dev/null 2>&1 || { rm -f "$candidate"; error "备份内核无法运行。"; return 1; }
  [ -f "$VP_CORE_CONFIG" ] && "$candidate" -t -d "$VP_CONFIG_DIR" -f "$VP_CORE_CONFIG" >/dev/null 2>&1 || { rm -f "$candidate"; error "备份内核无法加载当前配置。"; return 1; }
  current="$(mktemp /tmp/vp-core-current.XXXXXX)" || { rm -f "$candidate"; return 1; }
  cp "$VP_CORE_BIN" "$current"
  mv "$candidate" "$VP_CORE_BIN"
  chmod 755 "$VP_CORE_BIN"
  if core_service_restart; then
    mv "$current" "$VP_CORE_BACKUP_BIN"
    chmod 755 "$VP_CORE_BACKUP_BIN"
    ok "Mihomo 内核已回滚。"
    return 0
  fi
  mv "$current" "$VP_CORE_BIN"
  chmod 755 "$VP_CORE_BIN"
  core_service_restart >/dev/null 2>&1 || true
  error "备份内核启动失败，已恢复回滚前版本。"
  return 1
}

tunnel_binary_rollback() {
  need_root || return 1
  [ -x "$VP_TUNNEL_BACKUP_BIN" ] || { error "没有可回滚的 cloudflared。"; return 1; }
  "$VP_TUNNEL_BACKUP_BIN" version >/dev/null 2>&1 || { error "备份 cloudflared 无法运行。"; return 1; }
  current="$(mktemp /tmp/vp-tunnel-current.XXXXXX)" || return 1
  cp "$VP_TUNNEL_BIN" "$current"
  cp "$VP_TUNNEL_BACKUP_BIN" "$VP_TUNNEL_BIN"
  chmod 755 "$VP_TUNNEL_BIN"
  if tunnel_service_restart; then
    mv "$current" "$VP_TUNNEL_BACKUP_BIN"
    chmod 755 "$VP_TUNNEL_BACKUP_BIN"
    ok "cloudflared 已回滚。"
    return 0
  fi
  mv "$current" "$VP_TUNNEL_BIN"
  chmod 755 "$VP_TUNNEL_BIN"
  tunnel_service_restart >/dev/null 2>&1 || true
  error "备份 cloudflared 启动失败，已恢复回滚前版本。"
  return 1
}

core_install() {
  need_root || return 1
  ensure_runtime_dependencies || return 1
  init_layout >/dev/null || return 1
  prepare_core_internal_ports || return 1
  core_had_binary=0
  [ -x "$VP_CORE_BIN" ] && core_had_binary=1
  core_had_env=0
  [ -f "$VP_CORE_ENV" ] && core_had_env=1
  core_env_backup="$(mktemp /tmp/vp-core-env.XXXXXX)" || return 1
  [ "$core_had_env" = "0" ] || cp -p "$VP_CORE_ENV" "$core_env_backup" || { rm -f "$core_env_backup"; return 1; }
  install_core_binary || { rm -f "$core_env_backup"; return 1; }
  write_core_runtime_env || { rollback_core_binary "$core_had_binary"; restore_core_env_backup "$core_had_env" "$core_env_backup"; rm -f "$core_env_backup"; return 1; }
  begin_state_transaction core-install || { rollback_core_binary "$core_had_binary"; restore_core_env_backup "$core_had_env" "$core_env_backup"; rm -f "$core_env_backup"; return 1; }
  candidate_root="$VP_TX_ACTIVE/candidate"
  sed '/^ACTIVE_CORE=/d;/^VP_MIXED_PORT=/d;/^VP_CONTROLLER_PORT=/d' "$candidate_root/state.env" > "$candidate_root/state.env.tmp"
  printf 'ACTIVE_CORE=mihomo\n' >> "$candidate_root/state.env.tmp"
  printf 'VP_MIXED_PORT=%s\n' "$VP_MIXED_PORT" >> "$candidate_root/state.env.tmp"
  printf 'VP_CONTROLLER_PORT=%s\n' "$VP_CONTROLLER_PORT" >> "$candidate_root/state.env.tmp"
  mv "$candidate_root/state.env.tmp" "$candidate_root/state.env"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction
    rollback_core_binary "$core_had_binary"
    restore_core_env_backup "$core_had_env" "$core_env_backup"
    rm -f "$core_env_backup"
    error "Mihomo 候选配置验证失败。"
    return 1
  fi
  activate_state_candidate || { abort_state_transaction; rollback_core_binary "$core_had_binary"; restore_core_env_backup "$core_had_env" "$core_env_backup"; rm -f "$core_env_backup"; return 1; }
  install_core_service || { abort_state_transaction; rollback_core_binary "$core_had_binary"; restore_core_env_backup "$core_had_env" "$core_env_backup"; rm -f "$core_env_backup"; return 1; }
  if ! core_service_restart; then
    abort_state_transaction
    rollback_core_binary "$core_had_binary"
    restore_core_env_backup "$core_had_env" "$core_env_backup"
    rm -f "$core_env_backup"
    core_service_restart >/dev/null 2>&1 || true
    error "内核服务启动失败，已恢复旧状态。"
    return 1
  fi
  commit_state_transaction
  rm -f "$core_env_backup"
  ok "Mihomo 内核已安装。"
}

random_hex() {
  bytes="${1:-8}"
  od -An -N "$bytes" -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

new_uuid() {
  [ -r /proc/sys/kernel/random/uuid ] && { cat /proc/sys/kernel/random/uuid; return; }
  hex="$(random_hex 16)"
  printf '%s-%s-%s-%s-%s\n' "$(printf '%s' "$hex" | cut -c1-8)" "$(printf '%s' "$hex" | cut -c9-12)" "$(printf '%s' "$hex" | cut -c13-16)" "$(printf '%s' "$hex" | cut -c17-20)" "$(printf '%s' "$hex" | cut -c21-32)"
}

reality_keypair() {
  command -v openssl >/dev/null 2>&1 || { error "缺少 openssl。"; return 1; }
  key_tmp="$(mktemp /tmp/vp-reality-key.XXXXXX)" || return 1
  openssl genpkey -algorithm X25519 -out "$key_tmp" >/dev/null 2>&1 || { rm -f "$key_tmp"; return 1; }
  private="$(openssl pkey -in "$key_tmp" -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=\n')"
  public="$(openssl pkey -in "$key_tmp" -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=\n')"
  rm -f "$key_tmp"
  [ -n "$private" ] && [ -n "$public" ] || return 1
  printf '%s|%s' "$private" "$public"
}

port_in_use() {
  check_listen_port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -lntu 2>/dev/null | awk -v p=":$check_listen_port" '$5 ~ p "$" {found=1} END{exit !found}'
  else
    return 1
  fi
}

choose_port() {
  candidate="${1:-}"
  if [ -n "$candidate" ]; then
    case "$candidate" in *[!0-9]*|'') return 1 ;; esac
    [ "$candidate" -ge 1024 ] && [ "$candidate" -le 65535 ] && ! port_in_use "$candidate" && { printf '%s' "$candidate"; return; }
    return 1
  fi
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    candidate=$((20000 + 0x$(random_hex 2) % 40000))
    ! port_in_use "$candidate" && { printf '%s' "$candidate"; return; }
    attempts=$((attempts + 1))
  done
  return 1
}

reality_add() {
  need_root || return 1
  [ -x "$VP_CORE_BIN" ] || { error "请先安装代理核心。"; return 1; }
  name="${1:-reality-1}"
  requested_port="${2:-}"
  sni="${3:-www.amd.com}"
  address_family="${4:-ipv4}"
  case "$address_family" in ipv4|ipv6) ;; *) error "地址族只能是 ipv4 或 ipv6。"; return 1 ;; esac
  if [ "$address_family" = ipv6 ] && ! public_ipv6 >/dev/null 2>&1; then
    error "未检测到可用公网 IPv6，拒绝创建不可达的 IPv6 节点。"
    return 1
  fi
  case "$name$sni" in *'|'*|*' '*|*\"*|*\'*) error "名称或 SNI 包含非法字符。"; return 1 ;; esac
  port="$(choose_port "$requested_port")" || { error "端口不可用。"; return 1; }
  created_name="$name"
  created_port="$port"
  uuid="$(new_uuid)"
  pair="$(reality_keypair)" || { error "Reality 密钥生成失败。"; return 1; }
  private="${pair%%|*}"
  public="${pair#*|}"
  short_id="$(random_hex 8)"
  begin_state_transaction reality-add || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  if awk -F'|' -v n="$name" '$2==n{found=1} END{exit found?0:1}' "$candidate_root/nodes.db"; then
    abort_state_transaction; error "节点名称已存在。"; return 1
  fi
  printf 'reality|%s|%s|%s|%s|%s:443|%s|%s|%s|%s\n' "$name" "$port" "$uuid" "$sni" "$sni" "$private" "$public" "$short_id" "$address_family" >> "$candidate_root/nodes.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "Reality 候选配置验证失败。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "新节点启动失败，已恢复原配置。"; return 1
  fi
  commit_state_transaction
  ok "Reality 节点已创建：$created_name（端口 $created_port）。"
}

public_ipv4() {
  if [ -n "${VP_PUBLIC_IPV4_OVERRIDE:-}" ]; then
    case "$VP_PUBLIC_IPV4_OVERRIDE" in *.*) printf '%s' "$VP_PUBLIC_IPV4_OVERRIDE"; return 0 ;; *) return 1 ;; esac
  fi
  address="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  case "$address" in *.*) printf '%s' "$address" ;; *) return 1 ;; esac
}

public_ipv6() {
  if [ -n "${VP_PUBLIC_IPV6_OVERRIDE:-}" ]; then
    case "$VP_PUBLIC_IPV6_OVERRIDE" in *:*) printf '%s' "$VP_PUBLIC_IPV6_OVERRIDE"; return 0 ;; *) return 1 ;; esac
  fi
  address="$(curl -6 -fsS --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
  case "$address" in *:*) printf '%s' "$address" ;; *) return 1 ;; esac
}

public_address() {
  case "${1:-ipv4}" in
    ipv6) public_ipv6 || printf 'YOUR_SERVER_IPV6' ;;
    *) public_ipv4 || printf 'YOUR_SERVER_IP' ;;
  esac
}

link_address() {
  link_family="${1:-ipv4}"
  link_value="$(public_address "$link_family")"
  [ "$link_family" = ipv6 ] && printf '[%s]' "$link_value" || printf '%s' "$link_value"
}

public_ip() {
  public_address ipv4
}

show_nodes() {
  [ -s "$VP_NODES_DB" ] || { warn "当前没有节点。"; return 0; }
  awk -F'|' '{family=$1=="reality"?($10?$10:"ipv4"):"tunnel";printf "%d. %s  协议=%s  端口=%s  地址=%s\n",NR,$2,$1,$3,family}' "$VP_NODES_DB"
}

resolve_node_selector() {
  selector="$1"
  [ -n "$selector" ] || return 1
  resolved="$(awk -F'|' -v n="$selector" '$2==n{print $2;exit}' "$VP_NODES_DB")"
  if [ -n "$resolved" ]; then
    printf '%s' "$resolved"
    return 0
  fi
  case "$selector" in *[!0-9]*) return 1 ;; esac
  awk -F'|' -v row="$selector" 'NR==row{print $2;exit}' "$VP_NODES_DB"
}

edit_node() {
  need_root || return 1
  target="${1:-}"
  new_name="${2:-}"
  requested_port="${3:-}"
  endpoint="${4:-}"
  new_path="${5:-}"
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点：$target。"; return 1; }
  IFS='|' read -r proto old_name old_port f4 f5 f6 f7 f8 f9 f10 <<EOF
$record
EOF
  [ -n "$new_name" ] || new_name="$old_name"
  [ -n "$requested_port" ] || requested_port="$old_port"
  case "$new_name$endpoint$new_path" in *'|'*|*' '*|*\"*|*\'*) error "节点参数包含非法字符。"; return 1 ;; esac
  if [ "$new_name" != "$old_name" ] && awk -F'|' -v n="$new_name" '$2==n{found=1} END{exit found?0:1}' "$VP_NODES_DB"; then
    error "节点名称已存在：$new_name。"
    return 1
  fi
  if [ "$requested_port" != "$old_port" ]; then
    new_port="$(choose_port "$requested_port")" || { error "新端口不可用。"; return 1; }
  else
    new_port="$old_port"
  fi
  case "$proto" in
    reality)
      [ -n "$endpoint" ] || endpoint="$f5"
      address_family="${new_path:-${f10:-ipv4}}"
      case "$address_family" in ipv4|ipv6) ;; *) error "地址族只能是 ipv4 或 ipv6。"; return 1 ;; esac
      if [ "$address_family" = ipv6 ] && [ "${f10:-ipv4}" != ipv6 ] && ! public_ipv6 >/dev/null 2>&1; then
        error "未检测到可用公网 IPv6，未修改节点。"
        return 1
      fi
      case "$endpoint" in *.*) ;; *) error "Reality SNI 格式无效。"; return 1 ;; esac
      updated_record="reality|$new_name|$new_port|$f4|$endpoint|$endpoint:443|$f7|$f8|$f9|$address_family"
      ;;
    argo)
      [ -n "$endpoint" ] || endpoint="$f6"
      [ -n "$new_path" ] || new_path="$f5"
      case "$endpoint" in *.*) ;; *) error "Tunnel 公网域名格式无效。"; return 1 ;; esac
      case "$new_path" in /*) ;; *) new_path="/$new_path" ;; esac
      updated_record="argo|$new_name|$new_port|$f4|$new_path|$endpoint"
      ;;
    *) error "不支持修改的节点协议：$proto。"; return 1 ;;
  esac
  begin_state_transaction node-edit || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  awk -F'|' -v n="$old_name" -v replacement="$updated_record" '$2==n{print replacement;next}{print}' \
    "$candidate_root/nodes.db" > "$candidate_root/nodes.db.tmp"
  mv "$candidate_root/nodes.db.tmp" "$candidate_root/nodes.db"
  if [ "$new_name" != "$old_name" ]; then
    awk -F'|' -v old="$old_name" -v new="$new_name" 'BEGIN{OFS="|"}$1==old{$1=new}{print}' \
      "$candidate_root/credential-rotations.db" > "$candidate_root/credential-rotations.db.tmp"
    mv "$candidate_root/credential-rotations.db.tmp" "$candidate_root/credential-rotations.db"
  fi
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "修改后的节点配置验证失败，未应用任何变更。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "修改后服务启动失败，已恢复原节点配置。"
    return 1
  fi
  commit_state_transaction
  ok "节点已更新：$old_name -> $new_name（端口 $new_port）。"
}

delete_node() {
  need_root || return 1
  target="${1:-}"
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  if [ "${VP_DELETE_CONFIRM:-}" != "DELETE" ]; then
    printf '删除节点 %s？请输入 DELETE：' "$target"
    read -r answer || true
    [ "$answer" = "DELETE" ] || { warn "已取消。"; return 0; }
  fi
  begin_state_transaction node-delete || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  awk -F'|' -v n="$target" '$2!=n' "$candidate_root/nodes.db" > "$candidate_root/nodes.db.tmp"
  mv "$candidate_root/nodes.db.tmp" "$candidate_root/nodes.db"
  awk -F'|' -v n="$target" '$1!=n' "$candidate_root/credential-rotations.db" > "$candidate_root/credential-rotations.db.tmp"
  mv "$candidate_root/credential-rotations.db.tmp" "$candidate_root/credential-rotations.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "删除后的候选配置验证失败。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "删除节点后服务启动失败，已恢复原配置。"
    return 1
  fi
  commit_state_transaction
  ok "节点 $target 已删除。"
}

rotate_credential() {
  need_root || return 1
  target="${1:-}"
  grace_hours="${2:-24}"
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  case "$grace_hours" in ''|*[!0-9]*) error "宽限期必须是小时数。"; return 1 ;; esac
  [ "$grace_hours" -ge 1 ] && [ "$grace_hours" -le 168 ] || { error "宽限期范围为 1-168 小时。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  IFS='|' read -r proto name port old_uuid rest <<EOF
$record
EOF
  case "$proto" in reality|argo) ;; *) error "该协议暂不支持凭据轮换。"; return 1 ;; esac
  now="$(date +%s)"
  if awk -F'|' -v n="$target" -v now="$now" '$1==n && $5+0>now{found=1} END{exit found?0:1}' "$VP_ROTATIONS_DB" 2>/dev/null; then
    error "该节点已有进行中的轮换，请先验证并正式切换。"
    return 1
  fi
  new_uuid="$(new_uuid)"
  expires=$((now + grace_hours * 3600))
  begin_state_transaction credential-rotate || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  awk -F'|' -v OFS='|' -v n="$target" -v value="$new_uuid" '$2==n{$4=value}{print}' "$candidate_root/nodes.db" > "$candidate_root/nodes.db.tmp"
  mv "$candidate_root/nodes.db.tmp" "$candidate_root/nodes.db"
  awk -F'|' -v n="$target" -v now="$now" '!($1==n || $5+0<=now)' "$candidate_root/credential-rotations.db" > "$candidate_root/credential-rotations.db.tmp"
  mv "$candidate_root/credential-rotations.db.tmp" "$candidate_root/credential-rotations.db"
  printf '%s|%s|%s|%s|%s|%s\n' "$target" "$proto" "$old_uuid" "$new_uuid" "$expires" "$now" >> "$candidate_root/credential-rotations.db"
  chmod 600 "$candidate_root/nodes.db" "$candidate_root/credential-rotations.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "轮换候选配置验证失败。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "轮换配置启动失败，已恢复旧凭据。"
    return 1
  fi
  commit_state_transaction
  ok "节点 $target 已进入凭据轮换期，新旧凭据将同时有效 $grace_hours 小时。"
  warn "请执行 vp link $target 获取新链接，并用 vp test-node $target 验证；确认后执行 vp rotate-finalize $target。"
}

show_rotations() {
  now="$(date +%s)"
  count=0
  while IFS='|' read -r name proto old_uuid new_uuid expires created; do
    [ -n "$name" ] || continue
    remaining=$((expires - now))
    if [ "$remaining" -gt 0 ]; then
      printf '%s  协议=%s  剩余=%s分钟\n' "$name" "$proto" "$((remaining / 60))"
    else
      printf '%s  协议=%s  状态=已到期待清理\n' "$name" "$proto"
    fi
    count=$((count + 1))
  done < "$VP_ROTATIONS_DB" 2>/dev/null
  [ "$count" -gt 0 ] || warn "当前没有凭据轮换记录。"
}

finalize_rotation() {
  need_root || return 1
  target="${1:-}"
  [ -n "$target" ] || { error "请指定节点名称，或使用 --expired。"; return 1; }
  now="$(date +%s)"
  if [ "$target" = "--expired" ]; then
    match_count="$(awk -F'|' -v now="$now" '$5+0<=now{n++}END{print n+0}' "$VP_ROTATIONS_DB" 2>/dev/null)"
  else
    match_count="$(awk -F'|' -v n="$target" '$1==n{c++}END{print c+0}' "$VP_ROTATIONS_DB" 2>/dev/null)"
  fi
  [ "$match_count" -gt 0 ] || { warn "没有需要完成的轮换。"; return 0; }
  begin_state_transaction credential-finalize || return 1
  candidate_root="$VP_TX_ACTIVE/candidate"
  if [ "$target" = "--expired" ]; then
    awk -F'|' -v now="$now" '$5+0>now' "$candidate_root/credential-rotations.db" > "$candidate_root/credential-rotations.db.tmp"
  else
    awk -F'|' -v n="$target" '$1!=n' "$candidate_root/credential-rotations.db" > "$candidate_root/credential-rotations.db.tmp"
  fi
  mv "$candidate_root/credential-rotations.db.tmp" "$candidate_root/credential-rotations.db"
  chmod 600 "$candidate_root/credential-rotations.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "正式切换候选配置验证失败。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "正式切换失败，已恢复宽限期配置。"
    return 1
  fi
  commit_state_transaction
  ok "已完成 $match_count 项凭据轮换，旧凭据不再有效。"
}

urlencode_component() {
  LC_ALL=C od -An -tx1 | awk '
    BEGIN {
      ORS=""
      for (n = 0; n < 256; n++) value_by_hex[sprintf("%02x", n)] = n
    }
    {
      for (i = 1; i <= NF; i++) {
        byte = tolower($i)
        value = value_by_hex[byte]
        if ((value >= 48 && value <= 57) || (value >= 65 && value <= 90) ||
            (value >= 97 && value <= 122) || value == 45 || value == 46 ||
            value == 95 || value == 126) {
          printf "%c", value
        } else {
          printf "%%%s", toupper(byte)
        }
      }
    }
  '
}

valid_uuid() {
  printf '%s\n' "$1" | awk -F- '
    NF == 5 && length($1) == 8 && length($2) == 4 && length($3) == 4 &&
    length($4) == 4 && length($5) == 12 && $0 !~ /[^0-9A-Fa-f-]/ { ok=1 }
    END { exit ok ? 0 : 1 }
  '
}

validate_node_share_record() {
  share_record="$1"
  IFS='|' read -r share_proto share_name share_port share_uuid share_sni share_dest share_private share_public share_sid share_family share_extra <<EOF
$share_record
EOF
  [ -z "$share_extra" ] || { error "节点记录字段数量异常，无法生成可靠链接。"; return 1; }
  [ -n "$share_name" ] || { error "节点名称为空，无法生成链接。"; return 1; }
  valid_uuid "$share_uuid" || { error "节点 $share_name 的 UUID 格式无效。"; return 1; }
  case "$share_proto" in
    reality)
      case "$share_port" in ''|*[!0-9]*) error "节点 $share_name 的端口无效。"; return 1 ;; esac
      [ "$share_port" -ge 1 ] && [ "$share_port" -le 65535 ] || { error "节点 $share_name 的端口超出范围。"; return 1; }
      [ -n "$share_sni" ] && [ -n "$share_public" ] && [ -n "$share_sid" ] || {
        error "节点 $share_name 缺少 Reality SNI、公钥或 Short ID。"; return 1;
      }
      case "${share_family:-ipv4}" in ipv4|ipv6) ;; *) error "节点 $share_name 的地址族无效。"; return 1 ;; esac
      ;;
    argo)
      [ -n "$share_dest" ] || { error "节点 $share_name 缺少 Tunnel 公网域名。"; return 1; }
      case "$share_sni" in /*) ;; *) error "节点 $share_name 的 WebSocket 路径必须以 / 开头。"; return 1 ;; esac
      ;;
    *) error "暂不支持该协议的分享链接。"; return 1 ;;
  esac
}

node_share_link() {
  record="$1"
  credential_override="${2:-}"
  label_suffix="${3:-}"
  IFS='|' read -r proto name port uuid sni dest private public short_id address_family <<EOF
$record
EOF
  [ -n "$credential_override" ] && uuid="$credential_override"
  validate_node_share_record "$(printf '%s\n' "$record" | awk -F'|' -v OFS='|' -v credential="$uuid" '{$4=credential; print}')" || return 1
  label="$name$label_suffix"
  encoded_label="$(printf '%s' "$label" | urlencode_component)" || return 1
  case "$proto" in
    reality)
      address="$(link_address "${address_family:-ipv4}")"
      [ -n "$address" ] || { error "无法取得节点 $name 的公网 ${address_family:-ipv4} 地址，未输出残缺链接。"; return 1; }
      printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s\n' \
        "$uuid" "$address" "$port" "$sni" "$public" "$short_id" "$encoded_label"
      ;;
    argo)
      path="$sni"
      host="$dest"
      encoded_path="$(printf '%s' "$path" | urlencode_component)" || return 1
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&fp=chrome&type=ws&host=%s&path=%s#%s\n' "$uuid" "$host" "$host" "$host" "$encoded_path" "$encoded_label"
      ;;
    *) error "暂不支持该协议的分享链接。"; return 1 ;;
  esac
}

show_node_link() {
  target="${1:-}"
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  node_share_link "$record"
}

export_subscription() {
  mode="${1:-base64}"
  case "$mode" in plain|base64) ;; *) error "订阅格式只能是 plain 或 base64。"; return 2 ;; esac
  [ -s "$VP_NODES_DB" ] || { error "当前没有节点。"; return 1; }
  subscription_tmp="$(mktemp /tmp/vp-subscription.XXXXXX)" || return 1
  now="$(date +%s)"
  while IFS= read -r subscription_record; do
    [ -n "$subscription_record" ] || continue
    subscription_name="$(printf '%s\n' "$subscription_record" | awk -F'|' '{print $2}')"
    node_share_link "$subscription_record" >> "$subscription_tmp" || { rm -f "$subscription_tmp"; return 1; }
    old_uuid="$(awk -F'|' -v n="$subscription_name" -v now="$now" '$1==n && $5+0>now{print $3;exit}' "$VP_ROTATIONS_DB" 2>/dev/null)"
    [ -n "$old_uuid" ] && node_share_link "$subscription_record" "$old_uuid" '-old' >> "$subscription_tmp"
  done < "$VP_NODES_DB"
  if [ "$mode" = plain ]; then
    cat "$subscription_tmp"
  else
    base64 < "$subscription_tmp" | tr -d '\n'
    printf '\n'
  fi
  rm -f "$subscription_tmp"
}

test_node_end_to_end() {
  target="${1:-}"
  concurrency="${2:-${VP_TEST_CONCURRENCY:-1}}"
  case "$concurrency" in ''|*[!0-9]*) error "并发数必须是 1-8。"; return 2 ;; esac
  [ "$concurrency" -ge 1 ] && [ "$concurrency" -le 8 ] || { error "并发数必须是 1-8。"; return 2; }
  [ -x "$VP_CORE_BIN" ] || { error "代理核心尚未安装。"; return 1; }
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  IFS='|' read -r proto name port uuid value1 value2 private public short_id address_family <<EOF
$record
EOF
  client_port="$(choose_port)" || { error "无法分配测试端口。"; return 1; }
  test_dir="$(mktemp -d /tmp/vp-node-test.XXXXXX)" || return 1
  client_pid=""
  cleanup_node_test() {
    if [ -n "$client_pid" ]; then
      kill "$client_pid" 2>/dev/null || true
      wait "$client_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
  }
  trap cleanup_node_test EXIT HUP INT TERM
  mkdir -p "$test_dir/data"
  {
    printf 'mixed-port: %s\nallow-lan: false\nmode: rule\nlog-level: warning\n' "$client_port"
    printf 'proxies:\n'
    case "$proto" in
      reality)
        server="${VP_TEST_SERVER:-$(public_address "${address_family:-ipv4}")}"
        printf "  - name: 'target'\n    type: vless\n    server: '%s'\n    port: %s\n" "$(yaml_quote "$server")" "$port"
        printf "    uuid: '%s'\n    network: tcp\n    tls: true\n" "$(yaml_quote "$uuid")"
        printf "    servername: '%s'\n    client-fingerprint: chrome\n" "$(yaml_quote "$value1")"
        printf "    reality-opts:\n      public-key: '%s'\n      short-id: '%s'\n" "$(yaml_quote "$public")" "$(yaml_quote "$short_id")"
        ;;
      argo)
        path="$value1"; host="$value2"
        printf "  - name: 'target'\n    type: vless\n    server: '%s'\n    port: 443\n" "$(yaml_quote "$host")"
        printf "    uuid: '%s'\n    network: ws\n    tls: true\n    servername: '%s'\n    client-fingerprint: chrome\n" "$(yaml_quote "$uuid")" "$(yaml_quote "$host")"
        printf "    ws-opts:\n      path: '%s'\n      headers:\n        Host: '%s'\n" "$(yaml_quote "$path")" "$(yaml_quote "$host")"
        ;;
      *) cleanup_node_test; trap - EXIT HUP INT TERM; error "暂不支持测试该协议。"; return 1 ;;
    esac
    printf "proxy-groups:\n  - name: 'FINAL'\n    type: select\n    proxies:\n      - target\nrules:\n  - MATCH,FINAL\n"
  } > "$test_dir/client.yaml"
  chmod 600 "$test_dir/client.yaml"
  if ! "$VP_CORE_BIN" -t -d "$test_dir/data" -f "$test_dir/client.yaml" >/dev/null 2>&1; then
    cleanup_node_test; trap - EXIT HUP INT TERM
    error "测试客户端配置生成失败。"
    return 1
  fi
  "$VP_CORE_BIN" -d "$test_dir/data" -f "$test_dir/client.yaml" > "$test_dir/client.log" 2>&1 &
  client_pid=$!
  sleep 2
  result="$("$VP_CURL_BIN" -sS -o /dev/null -w '%{http_code}|%{time_connect}|%{time_starttransfer}|%{time_total}' --max-time 25 --proxy "http://127.0.0.1:$client_port" https://cp.cloudflare.com/generate_204 2>/dev/null || true)"
  IFS='|' read -r http_code connect_time first_byte_time total_time <<EOF
$result
EOF
  if [ "$http_code" = "204" ]; then
    test_bytes="${VP_TEST_BYTES:-5242880}"
    case "$test_bytes" in ''|*[!0-9]*) test_bytes=5242880 ;; esac
    speed_pids=""
    stream=1
    while [ "$stream" -le "$concurrency" ]; do
      "$VP_CURL_BIN" -sS -o /dev/null -w '%{http_code}|%{size_download}|%{speed_download}|%{time_starttransfer}|%{time_total}' \
        --max-time 45 --proxy "http://127.0.0.1:$client_port" \
        "https://speed.cloudflare.com/__down?bytes=$test_bytes&stream=$stream" \
        > "$test_dir/speed-$stream.result" 2>/dev/null &
      speed_pids="$speed_pids $!"
      stream=$((stream + 1))
    done
    for speed_pid in $speed_pids; do
      wait "$speed_pid" 2>/dev/null || true
    done
    speed_summary="$(awk -F'|' '
      $1==200 {ok++; bytes+=$2; bps+=$3; ttfb+=$4; total+=$5}
      END {printf "%d|%.0f|%.0f|%.6f|%.6f",ok+0,bytes+0,bps+0,ok?ttfb/ok:0,ok?total/ok:0}
    ' "$test_dir"/speed-*.result 2>/dev/null)"
    IFS='|' read -r speed_success speed_size speed_bps average_ttfb average_total <<EOF
$speed_summary
EOF
    cleanup_node_test
    trap - EXIT HUP INT TERM
    ok "节点 $name 协议认证成功：连接 ${connect_time}s，首包 ${first_byte_time}s，总耗时 ${total_time}s。"
    if [ "${speed_success:-0}" -gt 0 ] && [ -n "$speed_bps" ]; then
      speed_mib="$(awk -v n="$speed_bps" 'BEGIN { printf "%.2f", n / 1048576 }')"
      size_mib="$(awk -v n="${speed_size:-0}" 'BEGIN { printf "%.1f", n / 1048576 }')"
      printf '并发测速：%s/%s 路成功，下载 %s MiB，聚合速度 %s MiB/s，平均首包 %ss。\n' \
        "$speed_success" "$concurrency" "$size_mib" "$speed_mib" "$average_ttfb"
      if [ -n "${VP_TEST_RESULT_FILE:-}" ]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$proto" "$speed_success" "$concurrency" "$speed_bps" "$connect_time" "$first_byte_time" "$average_total" >> "$VP_TEST_RESULT_FILE"
      fi
      [ "$speed_success" -eq "$concurrency" ] || warn "部分并发流失败；节点可连接，但高并发稳定性不足。"
    else
      warn "协议认证成功，但测速数据下载失败。"
    fi
    return 0
  fi
  cleanup_node_test
  trap - EXIT HUP INT TERM
  if [ "$proto" = "reality" ] && [ -z "${VP_TEST_SERVER:-}" ]; then
    if VP_TEST_SERVER=127.0.0.1 VP_TEST_RESULT_FILE= VP_TEST_BYTES=1 VP_TEST_CONCURRENCY=1 test_node_end_to_end "$target" 1 >/dev/null 2>&1; then
      warn "节点 $name 的本地协议认证正常，但 VPS 无法通过自身公网 IP 回环验证；请从外部网络确认公网端口可达。"
      return 2
    fi
  fi
  error "节点 $name 端到端测试失败（HTTP ${http_code:-无响应}）。"
  return 1
}

test_all_nodes() {
  concurrency="${1:-4}"
  case "$concurrency" in ''|*[!0-9]*) error "并发数必须是 1-8。"; return 2 ;; esac
  [ "$concurrency" -ge 1 ] && [ "$concurrency" -le 8 ] || { error "并发数必须是 1-8。"; return 2; }
  [ -s "$VP_NODES_DB" ] || { warn "当前没有节点。"; return 1; }
  results="$(mktemp /tmp/vp-benchmark.XXXXXX)" || return 1
  : > "$results"
  printf '\n全部节点真实并发测试（每个节点 %s 路）\n' "$concurrency"
  printf '%s\n' '----------------------------------------'
  for benchmark_name in $(awk -F'|' 'NF{print $2}' "$VP_NODES_DB"); do
    printf '\n[%s]\n' "$benchmark_name"
    VP_TEST_RESULT_FILE="$results" test_node_end_to_end "$benchmark_name" "$concurrency" || true
  done
  printf '\n测试汇总\n'
  printf '%s\n' '----------------------------------------'
  if [ -s "$results" ]; then
    awk -F'|' '{printf "%s  协议=%s  成功=%s/%s  聚合速度=%.2f MiB/s  首包=%ss\n",$1,$2,$3,$4,$5/1048576,$7}' "$results"
    best="$(awk -F'|' '$3>0 && $5+0>max{max=$5+0;name=$1;proto=$2;success=$3;streams=$4}END{if(name)printf "%s|%s|%.0f|%s|%s",name,proto,max,success,streams}' "$results")"
    if [ -n "$best" ]; then
      IFS='|' read -r best_name best_proto best_bps best_success best_streams <<EOF
$best
EOF
      best_mib="$(awk -v n="$best_bps" 'BEGIN{printf "%.2f",n/1048576}')"
      printf '实测建议：当前吞吐最高的是 %s（%s，%s MiB/s，成功 %s/%s）。\n' \
        "$best_name" "$best_proto" "$best_mib" "$best_success" "$best_streams"
      printf '说明：该结论只代表本次服务器到测试站点的结果，不会自动修改客户端或默认线路。\n'
    fi
  else
    warn "没有节点完成并发下载，未生成排名。"
  fi
  rm -f "$results"
}

show_network_status() {
  congestion="$("$VP_SYSCTL_BIN" -n net.ipv4.tcp_congestion_control 2>/dev/null || printf unknown)"
  available="$("$VP_SYSCTL_BIN" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf unknown)"
  qdisc="$("$VP_SYSCTL_BIN" -n net.core.default_qdisc 2>/dev/null || printf unknown)"
  printf '\n当前网络状态\n'
  printf '%s\n' '----------------------------------------'
  printf 'TCP 拥塞控制：%s\n' "$congestion"
  printf '可用拥塞算法：%s\n' "$available"
  printf '默认队列规则：%s\n' "$qdisc"
  if [ -r "$VP_NETWORK_SNAPSHOT" ] && [ -r "$VP_SYSCTL_CONFIG" ]; then
    printf 'VPS-Node 已验证优化：已应用（可执行 vp network-rollback）\n'
  else
    printf 'VPS-Node 已验证优化：未应用\n'
  fi
  printf '默认测试并发：%s 路\n' "${VP_TEST_CONCURRENCY:-4}"
  public_ipv4 >/dev/null 2>&1 && printf '公网 IPv4：可用\n' || printf '公网 IPv4：未检测到\n'
  public_ipv6 >/dev/null 2>&1 && printf '公网 IPv6：可用\n' || printf '公网 IPv6：未检测到\n'
  if command -v ss >/dev/null 2>&1; then
    established="$(ss -H -tn state established 2>/dev/null | awk 'END{print NR+0}')"
    listening="$(ss -H -ltn 2>/dev/null | awk 'END{print NR+0}')"
    printf 'TCP 已连接 / 监听：%s / %s\n' "$established" "$listening"
  else
    printf 'TCP 连接统计：缺少 ss\n'
  fi
  if [ "$congestion" = bbr ]; then
    printf '建议：BBR 已启用，先通过并发测速验证实际效果，不需要重复套用参数。\n'
  elif printf '%s\n' "$available" | grep -qw bbr; then
    printf '建议：系统支持 BBR，但必须经过启用前后实测再决定是否保留。\n'
  else
    printf '建议：当前内核未提供 BBR，不建议强制写入无效配置。\n'
  fi
}

network_sysctl_value() {
  "$VP_SYSCTL_BIN" -n "$1" 2>/dev/null || return 1
}

network_restore_values() {
  restore_cc="$1"
  restore_qdisc="$2"
  "$VP_SYSCTL_BIN" -w "net.ipv4.tcp_congestion_control=$restore_cc" >/dev/null 2>&1 || return 1
  "$VP_SYSCTL_BIN" -w "net.core.default_qdisc=$restore_qdisc" >/dev/null 2>&1 || return 1
}

network_rollback() {
  need_root || return 1
  quiet=0
  [ "${1:-}" = "--quiet" ] && quiet=1
  if [ ! -r "$VP_NETWORK_SNAPSHOT" ]; then
    [ ! -e "$VP_SYSCTL_CONFIG" ] || { error "发现网络配置但缺少回滚记录，拒绝自动删除。"; return 1; }
    [ "$quiet" -eq 1 ] || warn "没有可回滚的网络优化记录。"
    return 0
  fi
  before_cc="$(awk -F= '$1=="BEFORE_CC"{print $2;exit}' "$VP_NETWORK_SNAPSHOT")"
  before_qdisc="$(awk -F= '$1=="BEFORE_QDISC"{print $2;exit}' "$VP_NETWORK_SNAPSHOT")"
  case "$before_cc$before_qdisc" in *[!A-Za-z0-9_-]*) error "网络回滚记录格式无效。"; return 1 ;; esac
  network_restore_values "$before_cc" "$before_qdisc" || { error "无法恢复原网络参数。"; return 1; }
  rm -f "$VP_SYSCTL_CONFIG" "$VP_NETWORK_SNAPSHOT"
  stability_event recovered network "saved network tuning rolled back"
  [ "$quiet" -eq 1 ] || ok "已恢复网络优化前参数：$before_cc / $before_qdisc。"
}

network_optimize_verified() {
  need_root || return 1
  mode="${1:-}"
  if [ "$mode" = "--dry-run" ]; then
    shift
  else
    mode=apply
  fi
  target="${1:-}"
  concurrency="${2:-4}"
  case "$concurrency" in ''|*[!0-9]*) error "并发数必须是 1-8。"; return 2 ;; esac
  [ "$concurrency" -ge 1 ] && [ "$concurrency" -le 8 ] || { error "并发数必须是 1-8。"; return 2; }
  current_cc="$(network_sysctl_value net.ipv4.tcp_congestion_control || printf unknown)"
  current_qdisc="$(network_sysctl_value net.core.default_qdisc || printf unknown)"
  available_cc="$(network_sysctl_value net.ipv4.tcp_available_congestion_control || printf unknown)"
  printf '当前参数：拥塞控制=%s，队列规则=%s\n' "$current_cc" "$current_qdisc"
  if printf '%s\n' "$available_cc" | grep -qw bbr; then
    candidate_cc=bbr
  else
    warn "当前内核没有提供 BBR，不会写入无效参数。"
    return 0
  fi
  candidate_qdisc=fq
  printf '候选参数：拥塞控制=%s，队列规则=%s\n' "$candidate_cc" "$candidate_qdisc"
  printf '验证门槛：前后并发全部成功；复测吞吐不低于基线 98%%；首包时间不高于基线 125%%。\n'
  printf '影响范围：这是主机全局 TCP 参数，可能影响 VPS 上的其他网络任务。\n'
  if [ "$mode" = "--dry-run" ]; then
    ok "网络优化预览完成，未测速、未修改参数。"
    return 0
  fi
  [ "$current_cc" != unknown ] && [ "$current_qdisc" != unknown ] || { error "无法读取当前网络参数。"; return 1; }
  if [ "$current_cc" = "$candidate_cc" ] && [ "$current_qdisc" = "$candidate_qdisc" ]; then
    ok "候选网络参数已经生效，无需重复应用。"
    return 0
  fi
  if [ -z "$target" ]; then
    target="$(awk -F'|' '$1=="reality"{print $2;exit} END{if(!NR)exit}' "$VP_NODES_DB" 2>/dev/null)"
    [ -n "$target" ] || target="$(awk -F'|' 'NF{print $2;exit}' "$VP_NODES_DB" 2>/dev/null)"
  else
    target="$(resolve_node_selector "$target")"
  fi
  [ -n "$target" ] || { error "没有可用于前后对比的节点。"; return 1; }
  if [ "${VP_NETWORK_CONFIRM:-}" != "APPLY" ]; then
    printf '将使用节点 %s 做前后对比。请输入 APPLY 继续：' "$target"
    read -r answer || true
    [ "$answer" = APPLY ] || { warn "已取消。"; return 2; }
  fi
  benchmark_dir="$(mktemp -d /tmp/vp-network-verify.XXXXXX)" || return 1
  before_result="$benchmark_dir/before.result"
  after_result="$benchmark_dir/after.result"
  printf '\n[1/3] 基线测速\n'
  if ! VP_TEST_RESULT_FILE="$before_result" test_node_end_to_end "$target" "$concurrency"; then
    rm -rf "$benchmark_dir"
    error "基线测速失败，未修改网络参数。"
    return 1
  fi
  [ -s "$before_result" ] || { rm -rf "$benchmark_dir"; error "基线测速没有有效结果，未修改网络参数。"; return 1; }
  printf '\n[2/3] 临时应用候选参数\n'
  if ! "$VP_SYSCTL_BIN" -w "net.ipv4.tcp_congestion_control=$candidate_cc" >/dev/null 2>&1 || \
     ! "$VP_SYSCTL_BIN" -w "net.core.default_qdisc=$candidate_qdisc" >/dev/null 2>&1; then
    network_restore_values "$current_cc" "$current_qdisc" >/dev/null 2>&1 || true
    rm -rf "$benchmark_dir"
    error "候选参数无法完整应用，已恢复原参数。"
    return 1
  fi
  printf '\n[3/3] 同节点同并发复测\n'
  VP_TEST_RESULT_FILE="$after_result" test_node_end_to_end "$target" "$concurrency" || true
  accepted=0
  if [ -s "$after_result" ] && awk -F'|' '
    NR==FNR{bs=$3+0;bn=$4+0;bb=$5+0;bt=$7+0;next}
    {as=$3+0;an=$4+0;ab=$5+0;at=$7+0}
    END{exit (bs==bn && as==an && as>=bs && ab>=bb*0.98 && (bt<=0 || at<=bt*1.25))?0:1}
  ' "$before_result" "$after_result"; then
    accepted=1
  fi
  if [ "$accepted" -ne 1 ]; then
    network_restore_values "$current_cc" "$current_qdisc" >/dev/null 2>&1 || true
    rm -rf "$benchmark_dir"
    stability_event rejected network "candidate failed benchmark gate"
    error "复测未通过性能门槛，已自动恢复原网络参数。"
    return 1
  fi
  if ! mkdir -p "$(dirname "$VP_SYSCTL_CONFIG")" "$(dirname "$VP_NETWORK_SNAPSHOT")"; then
    network_restore_values "$current_cc" "$current_qdisc" >/dev/null 2>&1 || true
    rm -rf "$benchmark_dir"
    error "无法创建网络优化持久化目录，已恢复原参数。"
    return 1
  fi
  snapshot_created=0
  if [ ! -r "$VP_NETWORK_SNAPSHOT" ]; then
    if ! {
      printf 'BEFORE_CC=%s\n' "$current_cc"
      printf 'BEFORE_QDISC=%s\n' "$current_qdisc"
    } > "$VP_NETWORK_SNAPSHOT"; then
      network_restore_values "$current_cc" "$current_qdisc" >/dev/null 2>&1 || true
      rm -rf "$benchmark_dir" "$VP_NETWORK_SNAPSHOT"
      error "无法保存网络回滚点，已恢复原参数。"
      return 1
    fi
    chmod 600 "$VP_NETWORK_SNAPSHOT"
    snapshot_created=1
  fi
  if ! {
    printf '# Managed by VPS-Node after verified before/after benchmark\n'
    printf 'net.ipv4.tcp_congestion_control=%s\n' "$candidate_cc"
    printf 'net.core.default_qdisc=%s\n' "$candidate_qdisc"
  } > "$VP_SYSCTL_CONFIG"; then
    network_restore_values "$current_cc" "$current_qdisc" >/dev/null 2>&1 || true
    rm -rf "$benchmark_dir" "$VP_SYSCTL_CONFIG"
    [ "$snapshot_created" -eq 1 ] && rm -f "$VP_NETWORK_SNAPSHOT"
    error "无法保存网络参数，已恢复原参数。"
    return 1
  fi
  chmod 600 "$VP_SYSCTL_CONFIG"
  before_bps="$(awk -F'|' 'NR==1{print $5}' "$before_result")"
  after_bps="$(awk -F'|' 'NR==1{print $5}' "$after_result")"
  rm -rf "$benchmark_dir"
  stability_event accepted network "candidate passed benchmark gate"
  before_mib="$(awk -v n="$before_bps" 'BEGIN{printf "%.2f",n/1048576}')"
  after_mib="$(awk -v n="$after_bps" 'BEGIN{printf "%.2f",n/1048576}')"
  ok "网络候选参数通过验证并已保存：${before_mib} -> ${after_mib} MiB/s。"
  printf '如需恢复：vp network-rollback\n'
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

create_backup() {
  need_root || return 1
  init_layout >/dev/null || return 1
  recover_state_transaction || return 1
  destination="${1:-$VP_BACKUP_DIR}"
  case "$destination" in *.tar.gz) archive="$destination"; mkdir -p "$(dirname "$archive")" ;; *) mkdir -p "$destination"; archive="$destination/vps-node-$(date '+%Y%m%d-%H%M%S').tar.gz" ;; esac
  package="$(mktemp -d /tmp/vp-backup.XXXXXX)" || return 1
  cleanup_backup() { rm -rf "$package"; }
  trap cleanup_backup EXIT HUP INT TERM
  mkdir -p "$package/config" "$package/data"
  if [ -d "$VP_CONFIG_DIR" ]; then
    cp -R -p "$VP_CONFIG_DIR/." "$package/config/"
    rm -rf "$package/config/transactions"
  fi
  if [ -d "$VP_DATA_DIR" ]; then
    cp -R -p "$VP_DATA_DIR/." "$package/data/"
    rm -rf "$package/data/backups"
  fi
  {
    printf 'FORMAT_VERSION=1\n'
    printf 'VP_VERSION=%s\n' "$VP_VERSION"
    printf 'CREATED_AT=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$package/manifest.env"
  chmod 600 "$package/manifest.env"
  tar -czf "$archive" -C "$package" manifest.env config data || { rm -f "$archive"; cleanup_backup; trap - EXIT HUP INT TERM; return 1; }
  chmod 600 "$archive"
  checksum="$(sha256_file "$archive" 2>/dev/null || true)"
  [ -n "$checksum" ] && { printf '%s  %s\n' "$checksum" "$(basename "$archive")" > "$archive.sha256"; chmod 600 "$archive.sha256"; }
  cleanup_backup
  trap - EXIT HUP INT TERM
  ok "备份已创建：$archive"
}

backup_archive_safe() {
  archive_to_check="$1"
  tar -tzf "$archive_to_check" 2>/dev/null | awk '
    /^\// { bad=1 }
    /(^|\/)\.\.($|\/)/ { bad=1 }
    !/^(manifest\.env|config\/?|config\/.*|data\/?|data\/.*)$/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' || return 1
  tar -tvzf "$archive_to_check" 2>/dev/null | awk '
    {
      entry_type=substr($1,1,1)
      if (entry_type != "-" && entry_type != "d") bad=1
    }
    END { exit bad ? 1 : 0 }
  '
}

restore_extra_snapshot() {
  extra="$VP_TX_ACTIVE/restore-extra"
  [ -d "$extra" ] || return 0
  rm -rf "$VP_SECRETS_DIR" "$VP_DATA_DIR"
  rm -f "$VP_CORE_ENV"
  [ -d "$extra/secrets" ] && cp -R -p "$extra/secrets" "$VP_SECRETS_DIR"
  [ -d "$extra/data" ] && { mkdir -p "$VP_DATA_DIR"; cp -R -p "$extra/data/." "$VP_DATA_DIR/"; }
  [ -f "$extra/core.env" ] && cp -p "$extra/core.env" "$VP_CORE_ENV"
}

restore_backup() {
  need_root || return 1
  archive="${1:-}"
  restore_mode="${2:---apply}"
  case "$restore_mode" in --dry-run|--apply) ;; *) error "恢复模式只能是 --dry-run 或 --apply。"; return 2 ;; esac
  [ -r "$archive" ] || { error "备份文件不存在。"; return 1; }
  if [ -r "$archive.sha256" ]; then
    expected_archive_hash="$(awk 'NR==1{print tolower($1)}' "$archive.sha256" 2>/dev/null)"
    actual_archive_hash="$(sha256_file "$archive" 2>/dev/null | tr 'A-F' 'a-f')"
    [ -n "$expected_archive_hash" ] && [ "$expected_archive_hash" = "$actual_archive_hash" ] || { error "备份 SHA-256 校验失败。"; return 1; }
  else
    warn "备份旁路 SHA-256 文件不存在，将继续进行内容和配置验证。"
  fi
  backup_archive_safe "$archive" || { error "备份包含不安全路径。"; return 1; }
  package="$(mktemp -d /tmp/vp-restore.XXXXXX)" || return 1
  cleanup_restore() { rm -rf "$package"; }
  trap cleanup_restore EXIT HUP INT TERM
  tar -xzf "$archive" -C "$package" || { cleanup_restore; trap - EXIT HUP INT TERM; error "备份无法解压。"; return 1; }
  [ -f "$package/manifest.env" ] && grep -q '^FORMAT_VERSION=1$' "$package/manifest.env" || { cleanup_restore; trap - EXIT HUP INT TERM; error "不支持该备份格式。"; return 1; }
  [ -f "$package/config/nodes.db" ] && [ -f "$package/config/state.env" ] || { cleanup_restore; trap - EXIT HUP INT TERM; error "备份缺少必要状态文件。"; return 1; }
  [ -f "$package/config/credential-rotations.db" ] || : > "$package/config/credential-rotations.db"
  if grep -Ev '^[A-Z][A-Z0-9_]*=[A-Za-z0-9._:/+-]*$|^$' "$package/config/state.env" >/dev/null 2>&1 ||
     ! validate_nodes_database "$package/config/nodes.db" ||
     ! validate_rotations_database "$package/config/nodes.db" "$package/config/credential-rotations.db"; then
    cleanup_restore; trap - EXIT HUP INT TERM
    error "备份状态数据库未通过完整性与关联约束检查。"
    return 1
  fi
  if [ -x "$VP_CORE_BIN" ] && [ -f "$package/config/generated/mihomo.yaml" ] &&
     ! "$VP_CORE_BIN" -t -d "$package/config" -f "$package/config/generated/mihomo.yaml" >/dev/null 2>&1; then
    cleanup_restore; trap - EXIT HUP INT TERM
    error "备份中的 Mihomo 配置未通过当前内核验证。"
    return 1
  fi
  backup_version="$(awk -F= '$1=="VP_VERSION"{print $2;exit}' "$package/manifest.env" 2>/dev/null)"
  backup_created="$(awk -F= '$1=="CREATED_AT"{print $2;exit}' "$package/manifest.env" 2>/dev/null)"
  backup_nodes="$(awk 'NF{n++}END{print n+0}' "$package/config/nodes.db")"
  backup_reality="$(awk -F'|' '$1=="reality"{n++}END{print n+0}' "$package/config/nodes.db")"
  backup_argo="$(awk -F'|' '$1=="argo"{n++}END{print n+0}' "$package/config/nodes.db")"
  backup_rotations="$(awk 'NF{n++}END{print n+0}' "$package/config/credential-rotations.db")"
  backup_token=no
  [ -s "$package/config/secrets/cloudflared.token" ] && backup_token=yes
  printf '恢复预览：版本=%s，创建时间=%s\n' "${backup_version:-未知}" "${backup_created:-未知}"
  printf '  节点：%s（Reality %s / Argo %s）\n' "$backup_nodes" "$backup_reality" "$backup_argo"
  printf '  凭据轮换记录：%s；Tunnel Token：%s（内容不显示）\n' "$backup_rotations" "$backup_token"
  printf '  将替换：VPS-Node 节点、轮换、运行参数、Token 与项目数据。\n'
  printf '  不会修改：SSH、防火墙、其他代理项目或非 VPS-Node 文件。\n'
  if [ "$restore_mode" = --dry-run ]; then
    cleanup_restore; trap - EXIT HUP INT TERM
    ok "恢复预览完成，未修改任何文件或服务。"
    return 0
  fi
  if [ "${VP_RESTORE_CONFIRM:-}" != RESTORE ]; then
    printf '请输入 RESTORE 确认覆盖当前 VPS-Node 状态：'
    read -r restore_answer || true
    [ "$restore_answer" = RESTORE ] || {
      cleanup_restore; trap - EXIT HUP INT TERM
      warn "已取消恢复，当前状态未改变。"
      return 2
    }
  fi

  init_layout >/dev/null || { cleanup_restore; trap - EXIT HUP INT TERM; return 1; }
  begin_state_transaction backup-restore || { cleanup_restore; trap - EXIT HUP INT TERM; return 1; }
  extra="$VP_TX_ACTIVE/restore-extra"
  mkdir -p "$extra"
  [ -d "$VP_SECRETS_DIR" ] && cp -R -p "$VP_SECRETS_DIR" "$extra/secrets"
  [ -d "$VP_DATA_DIR" ] && cp -R -p "$VP_DATA_DIR/." "$extra/data"
  [ -f "$VP_CORE_ENV" ] && cp -p "$VP_CORE_ENV" "$extra/core.env"
  cp -p "$package/config/nodes.db" "$VP_TX_ACTIVE/candidate/nodes.db"
  if [ -f "$package/config/credential-rotations.db" ]; then
    cp -p "$package/config/credential-rotations.db" "$VP_TX_ACTIVE/candidate/credential-rotations.db"
  else
    : > "$VP_TX_ACTIVE/candidate/credential-rotations.db"
  fi
  cp -p "$package/config/state.env" "$VP_TX_ACTIVE/candidate/state.env"
  rm -rf "$VP_TX_ACTIVE/candidate/generated"
  [ -d "$package/config/generated" ] && cp -R -p "$package/config/generated" "$VP_TX_ACTIVE/candidate/generated" || mkdir -p "$VP_TX_ACTIVE/candidate/generated"
  if ! validate_state_candidate; then
    abort_state_transaction; cleanup_restore; trap - EXIT HUP INT TERM; return 1
  fi
  if [ -x "$VP_CORE_BIN" ] && [ -f "$VP_TX_ACTIVE/candidate/generated/mihomo.yaml" ] && ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$VP_TX_ACTIVE/candidate/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; cleanup_restore; trap - EXIT HUP INT TERM; error "备份中的 Mihomo 配置无效。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; cleanup_restore; trap - EXIT HUP INT TERM; return 1; }
  rm -rf "$VP_SECRETS_DIR" "$VP_DATA_DIR"
  [ -d "$package/config/secrets" ] && cp -R -p "$package/config/secrets" "$VP_SECRETS_DIR" || mkdir -p "$VP_SECRETS_DIR"
  [ -f "$package/config/core.env" ] && cp -p "$package/config/core.env" "$VP_CORE_ENV"
  mkdir -p "$VP_DATA_DIR"
  [ -d "$package/data" ] && cp -R -p "$package/data/." "$VP_DATA_DIR/"
  chmod 700 "$VP_SECRETS_DIR"
  find "$VP_SECRETS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true

  restore_failed=0
  [ -x "$VP_CORE_BIN" ] && ! core_service_restart && restore_failed=1
  [ -s "$VP_TUNNEL_TOKEN_FILE" ] && [ -x "$VP_TUNNEL_BIN" ] && ! tunnel_service_restart && restore_failed=1
  if [ "$restore_failed" -ne 0 ]; then
    transaction_restore
    restore_extra_snapshot
    rm -rf "$VP_TX_ACTIVE"
    core_service_restart >/dev/null 2>&1 || true
    tunnel_service_restart >/dev/null 2>&1 || true
    cleanup_restore; trap - EXIT HUP INT TERM
    error "恢复后的服务验证失败，已回滚恢复前状态。"
    return 1
  fi
  commit_state_transaction
  cleanup_restore
  trap - EXIT HUP INT TERM
  ok "备份恢复完成。"
}

migrate_from_mihomo_lite() {
  need_root || return 1
  source_db="${1:-/etc/mihomo/nodes.db}"
  mode="${2:---dry-run}"
  case "$source_db" in /*) ;; *) error "旧项目数据库必须使用绝对路径。"; return 2 ;; esac
  case "$mode" in --dry-run|--apply) ;; *) error "迁移模式只能是 --dry-run 或 --apply。"; return 2 ;; esac
  [ -r "$source_db" ] || { error "无法读取旧项目节点数据库：$source_db"; return 1; }
  [ "$source_db" != "$VP_NODES_DB" ] || { error "源数据库不能是当前 VPS-Node 数据库。"; return 1; }
  import_tmp="$(mktemp /tmp/vp-migrate-mh.XXXXXX)" || return 1
  : > "$import_tmp"
  supported=0
  skipped_protocol=0
  skipped_lossy=0
  skipped_conflict=0
  runtime_conflict=0
  while IFS='|' read -r old_proto old_name old_port old_v1 old_v2 old_v3 old_v4 old_v5 old_v6 extra; do
    [ -n "$old_proto" ] || continue
    [ -z "$extra" ] || { skipped_lossy=$((skipped_lossy + 1)); continue; }
    import_record=""
    case "$old_proto" in
      vless-reality)
        if [ -n "$old_name" ] && [ -n "$old_port" ] && [ -n "$old_v1" ] && [ -n "$old_v2" ] && \
           [ -n "$old_v3" ] && [ -n "$old_v4" ] && [ -n "$old_v5" ] && [ -n "$old_v6" ]; then
          import_record="reality|$old_name|$old_port|$old_v1|$old_v2|$old_v3|$old_v4|$old_v5|$old_v6|ipv4"
        else
          skipped_lossy=$((skipped_lossy + 1))
        fi
        ;;
      vless-ws)
        if [ "$old_v4" = argo ] && [ -n "$old_name" ] && [ -n "$old_port" ] && [ -n "$old_v1" ] && \
           [ -n "$old_v2" ] && [ -n "$old_v3" ] && { [ -z "$old_v5" ] || [ "$old_v5" = "$old_v3" ]; } && \
           { [ -z "$old_v6" ] || [ "$old_v6" = 443 ]; }; then
          import_record="argo|$old_name|$old_port|$old_v1|$old_v2|$old_v3"
        else
          skipped_lossy=$((skipped_lossy + 1))
        fi
        ;;
      *) skipped_protocol=$((skipped_protocol + 1)) ;;
    esac
    [ -n "$import_record" ] || continue
    case "$old_name" in *'|'*|*' '*|*\"*|*\'*)
      skipped_lossy=$((skipped_lossy + 1)); continue ;;
    esac
    case "$old_port" in ''|*[!0-9]*) skipped_lossy=$((skipped_lossy + 1)); continue ;; esac
    [ "$old_port" -ge 1024 ] && [ "$old_port" -le 65535 ] || { skipped_lossy=$((skipped_lossy + 1)); continue; }
    if awk -F'|' -v n="$old_name" -v p="$old_port" '$2==n || $3==p{found=1}END{exit found?0:1}' "$VP_NODES_DB" "$import_tmp" 2>/dev/null; then
      skipped_conflict=$((skipped_conflict + 1))
      continue
    fi
    port_in_use "$old_port" && runtime_conflict=$((runtime_conflict + 1))
    printf '%s\n' "$import_record" >> "$import_tmp"
    supported=$((supported + 1))
  done < "$source_db"
  printf '旧项目迁移预览：可无损导入 %s，协议不支持 %s，字段/模式不可无损转换 %s，名称或端口冲突 %s。\n' \
    "$supported" "$skipped_protocol" "$skipped_lossy" "$skipped_conflict"
  [ "$runtime_conflict" -gt 0 ] && warn "$runtime_conflict 个待导入端口当前正在监听；应用前必须停止旧项目对应服务。"
  printf '仅支持：VLESS-Reality；入口地址等于 Host 且入口端口为 443 的 Argo VLESS-WS。\n'
  printf '不会迁移：Hysteria2、AnyTLS、直连/CDN WS、多用户、流量规则、cron、Token 或 sysctl。\n'
  if [ "$mode" = --dry-run ]; then
    rm -f "$import_tmp"
    ok "迁移预览完成，未修改任何文件或服务。"
    return 0
  fi
  [ "$supported" -gt 0 ] || { rm -f "$import_tmp"; error "没有可无损导入的节点。"; return 1; }
  [ "$runtime_conflict" -eq 0 ] || { rm -f "$import_tmp"; error "待导入端口仍被占用，未执行迁移。"; return 1; }
  [ -x "$VP_CORE_BIN" ] || { rm -f "$import_tmp"; error "请先安装 VPS-Node Mihomo 内核，再执行迁移。"; return 1; }
  if [ "${VP_MIGRATE_CONFIRM:-}" != MIGRATE ]; then
    printf '请输入 MIGRATE 确认导入 %s 个节点：' "$supported"
    read -r answer || true
    [ "$answer" = MIGRATE ] || { rm -f "$import_tmp"; warn "已取消。"; return 2; }
  fi
  create_backup "$VP_BACKUP_DIR" >/dev/null || { rm -f "$import_tmp"; error "迁移前备份失败。"; return 1; }
  begin_state_transaction migrate-mihomo-lite || { rm -f "$import_tmp"; return 1; }
  candidate_root="$VP_TX_ACTIVE/candidate"
  cat "$import_tmp" >> "$candidate_root/nodes.db"
  rm -f "$import_tmp"
  chmod 600 "$candidate_root/nodes.db"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction; error "迁移候选配置验证失败，已保留原状态。"; return 1
  fi
  activate_state_candidate || { abort_state_transaction; return 1; }
  if ! core_service_restart; then
    abort_state_transaction; core_service_restart >/dev/null 2>&1 || true
    error "迁移后服务启动失败，已恢复迁移前状态。"
    return 1
  fi
  commit_state_transaction
  ok "已从 Mihomo-lite-argo 无损导入 $supported 个节点。"
  warn "Cloudflare Tunnel Token 不会迁移；如导入了 Argo 节点，请单独执行 Tunnel 配置。"
}

trim_log_file() {
  log_file="$1"
  max_bytes="${2:-1048576}"
  [ -f "$log_file" ] || return 0
  size="$(wc -c < "$log_file" 2>/dev/null || printf 0)"
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt "$max_bytes" ]; then
    tail -c "$max_bytes" "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
    chmod 600 "$log_file" 2>/dev/null || true
  fi
}

maintenance_mode() {
  need_root || return 1
  init_layout >/dev/null || return 1
  info "安全维护开始：先创建恢复点。"
  create_backup "$VP_BACKUP_DIR" || { error "备份失败，维护已停止。"; return 1; }
  recover_state_transaction || return 1
  safe_repair || return 1
  finalize_rotation --expired || return 1

  trimmed=0
  if [ -d "$VP_LOG_DIR" ]; then
    for log_file in "$VP_LOG_DIR"/*.log "$VP_LOG_DIR"/*.err; do
      [ -f "$log_file" ] || continue
      before="$(wc -c < "$log_file" 2>/dev/null || printf 0)"
      trim_log_file "$log_file" 1048576
      after="$(wc -c < "$log_file" 2>/dev/null || printf 0)"
      [ "$after" -lt "$before" ] && trimmed=$((trimmed + 1))
    done
  fi

  temp_removed=0
  for temp_path in /tmp/vp-node-test.* /tmp/vp-benchmark.* /tmp/vp-network-verify.* /tmp/vp-subscription.* /tmp/vp-backup.* /tmp/vp-restore.* /tmp/vp-repair-config.* /tmp/vp-repair-config-old.* /tmp/vp-expected-config.* /tmp/vp-core-env.* /tmp/vp-reality-key.*; do
    [ -e "$temp_path" ] || continue
    if find "$temp_path" -maxdepth 0 -mmin +60 >/dev/null 2>&1 && [ -n "$(find "$temp_path" -maxdepth 0 -mmin +60 -print 2>/dev/null)" ]; then
      rm -rf "$temp_path"
      temp_removed=$((temp_removed + 1))
    fi
  done
  ok "维护清理完成：截断 $trimmed 个过大日志，删除 $temp_removed 个过期临时项。"
  layered_health_check
}

stability_event() {
  event_status="$1"
  event_action="$2"
  event_detail="$3"
  mkdir -p "$VP_LOG_DIR" || return 1
  printf '%s|%s|%s|%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$event_status" "$event_action" "$event_detail" >> "$VP_STABILITY_LOG"
  chmod 600 "$VP_STABILITY_LOG"
  event_lines="$(wc -l < "$VP_STABILITY_LOG" 2>/dev/null || printf 0)"
  case "$event_lines" in ''|*[!0-9]*) event_lines=0 ;; esac
  if [ "$event_lines" -gt 200 ]; then
    tail -n 200 "$VP_STABILITY_LOG" > "$VP_STABILITY_LOG.tmp" && mv "$VP_STABILITY_LOG.tmp" "$VP_STABILITY_LOG"
    chmod 600 "$VP_STABILITY_LOG"
  fi
}

self_heal_once() {
  need_root || return 1
  quiet=0
  [ "${1:-}" = "--quiet" ] && quiet=1
  had_transaction=0
  [ -d "$VP_TX_ACTIVE" ] && had_transaction=1
  init_layout >/dev/null || return 1
  repaired=0
  failures=0
  oom_snapshot
  if [ "$OOM_DELTA" -gt 0 ]; then
    stability_event warning memory "new oom kill detected"
    remember_oom_snapshot
  fi
  if [ "$had_transaction" -eq 1 ]; then
    stability_event recovered transaction "interrupted configuration restored"
    repaired=$((repaired + 1))
  fi
  if [ -x "$VP_CORE_BIN" ] && [ -s "$VP_NODES_DB" ]; then
    if [ ! -f "$VP_CORE_CONFIG" ] || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$VP_CORE_CONFIG" >/dev/null 2>&1; then
      stability_event failed core "configuration invalid; restart skipped"
      failures=$((failures + 1))
    elif ! core_process_running; then
      if core_service_restart; then
        stability_event recovered core "service restarted"
        repaired=$((repaired + 1))
      else
        stability_event failed core "restart failed"
        failures=$((failures + 1))
      fi
    fi
  fi
  if [ -s "$VP_TUNNEL_TOKEN_FILE" ] && [ -x "$VP_TUNNEL_BIN" ]; then
    if [ "$(service_state "$VP_TUNNEL_SERVICE")" != "active" ] && [ "$(service_state "$VP_TUNNEL_SERVICE")" != "started" ]; then
      if tunnel_service_restart; then
        stability_event recovered tunnel "service restarted"
        repaired=$((repaired + 1))
      else
        stability_event failed tunnel "restart failed"
        failures=$((failures + 1))
      fi
    fi
  fi
  if [ "$repaired" -eq 0 ] && [ "$failures" -eq 0 ]; then
    stability_event healthy check "no action required"
  fi
  if [ "$quiet" -eq 0 ]; then
    [ "$failures" -eq 0 ] && ok "自愈检查完成：修复 $repaired 项。" || error "自愈检查完成：修复 $repaired 项，失败 $failures 项。"
  fi
  [ "$failures" -eq 0 ]
}

install_stability_monitor() {
  need_root || return 1
  init_layout >/dev/null || return 1
  mkdir -p "$(dirname "$VP_WATCHDOG_RUNNER")"
  cat > "$VP_WATCHDOG_RUNNER" <<EOF
#!/bin/sh
exec "$VP_CLI_PATH" self-heal --quiet
EOF
  chmod 700 "$VP_WATCHDOG_RUNNER"
  if [ "${VP_SKIP_SERVICE:-0}" = "1" ]; then
    ok "后台自愈运行器已在隔离模式生成。"
    return 0
  fi
  case "$(service_manager)" in
    systemd)
      cat > "/etc/systemd/system/${VP_WATCHDOG_SERVICE}.service" <<EOF
[Unit]
Description=VPS-Node low-overhead self-heal check

[Service]
Type=oneshot
ExecStart=$VP_WATCHDOG_RUNNER
EOF
      cat > "/etc/systemd/system/${VP_WATCHDOG_SERVICE}.timer" <<EOF
[Unit]
Description=Run VPS-Node self-heal every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
      systemctl daemon-reload
      systemctl enable --now "${VP_WATCHDOG_SERVICE}.timer" >/dev/null || return 1
      ;;
    openrc)
      mkdir -p /etc/periodic/15min
      cat > "/etc/periodic/15min/$VP_WATCHDOG_SERVICE" <<EOF
#!/bin/sh
exec "$VP_WATCHDOG_RUNNER"
EOF
      chmod 700 "/etc/periodic/15min/$VP_WATCHDOG_SERVICE"
      rc-service crond start >/dev/null 2>&1 || true
      rc-update add crond default >/dev/null 2>&1 || true
      ;;
    *) error "当前系统无法安装定时自愈。"; return 1 ;;
  esac
  stability_event enabled monitor "periodic self-heal installed"
  ok "低开销后台自愈已启用。"
}

show_stability() {
  printf '后台自愈运行器：%s\n' "$([ -x "$VP_WATCHDOG_RUNNER" ] && printf '已安装' || printf '未安装')"
  if [ -r "$VP_STABILITY_LOG" ]; then
    printf '最近稳定性事件：\n'
    tail -n 20 "$VP_STABILITY_LOG"
  else
    printf '最近稳定性事件：暂无\n'
  fi
}

diagnostic_report() {
  need_root || return 1
  destination="${1:-/root/vps-node-diagnostic-$(date '+%Y%m%d-%H%M%S').txt}"
  case "$destination" in /*) ;; *) error "诊断报告必须使用绝对路径。"; return 1 ;; esac
  mkdir -p "$(dirname "$destination")" || return 1
  memory_snapshot
  cpu_snapshot
  oom_snapshot
  dns_result=failed
  dns_probe >/dev/null 2>&1 && dns_result=ok
  config_result=missing
  if [ -x "$VP_CORE_BIN" ] && [ -f "$VP_CORE_CONFIG" ]; then
    "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$VP_CORE_CONFIG" >/dev/null 2>&1 && config_result=valid || config_result=invalid
  fi
  ipv4_result=unavailable; public_ipv4 >/dev/null 2>&1 && ipv4_result=available
  ipv6_result=unavailable; public_ipv6 >/dev/null 2>&1 && ipv6_result=available
  umask 077
  {
    printf 'VPS-Node redacted diagnostic report\n'
    printf 'generated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'vp_version=%s\n' "$VP_VERSION"
    printf 'architecture=%s\n' "$(uname -m 2>/dev/null || printf unknown)"
    printf 'service_manager=%s\n' "$(service_manager)"
    printf 'core_state=%s\n' "$(service_state "$VP_CORE_SERVICE")"
    printf 'tunnel_state=%s\n' "$(service_state "$VP_TUNNEL_SERVICE")"
    printf 'core_config=%s\n' "$config_result"
    printf 'dns_probe=%s\n' "$dns_result"
    printf 'public_ipv4=%s\n' "$ipv4_result"
    printf 'public_ipv6=%s\n' "$ipv6_result"
    printf 'transaction=%s\n' "$([ -d "$VP_TX_ACTIVE" ] && printf interrupted || printf clean)"
    printf 'memory_source=%s\n' "$MEM_SOURCE"
    printf 'memory_working_mib=%s\n' "$(bytes_to_mib "$MEM_WORKING_BYTES")"
    printf 'memory_total_mib=%s\n' "$(bytes_to_mib "$MEM_TOTAL_BYTES")"
    printf 'memory_limit_mib=%s\n' "$(bytes_to_mib "$MEM_LIMIT_BYTES")"
    printf 'swap_used_mib=%s\n' "$(bytes_to_mib "$MEM_SWAP_BYTES")"
    printf 'cpu_source=%s\n' "$CPU_SOURCE"
    printf 'cpu_host_count=%s\n' "$CPU_HOST_COUNT"
    printf 'cpu_effective_count=%s\n' "$CPU_EFFECTIVE_COUNT"
    printf 'cpu_quota_milli=%s\n' "$CPU_QUOTA_MILLI"
    printf 'oom_kill_total=%s\n' "$OOM_CURRENT"
    printf 'oom_kill_new=%s\n' "$OOM_DELTA"
    printf 'nodes_total=%s\n' "$(node_count)"
    printf 'rotations_active=%s\n' "$(rotation_count active)"
    printf 'rotations_expired=%s\n' "$(rotation_count expired)"
    printf '\nredacted_nodes:\n'
    awk -F'|' 'NF{printf "node_%d protocol=%s port=%s endpoint=<redacted> credentials=<redacted>\n",++n,$1,$3}' "$VP_NODES_DB" 2>/dev/null
    printf '\nprotected_file_modes:\n'
    for protected in "$VP_NODES_DB" "$VP_ROTATIONS_DB" "$VP_STATE_FILE" "$VP_CORE_ENV" "$VP_TUNNEL_TOKEN_FILE"; do
      [ -e "$protected" ] || continue
      printf '%s=%s\n' "$(basename "$protected")" "$(file_mode "$protected")"
    done
    printf '\nrecent_stability_events:\n'
    [ -r "$VP_STABILITY_LOG" ] && tail -n 20 "$VP_STABILITY_LOG" || printf 'none\n'
  } > "$destination" || { rm -f "$destination"; return 1; }
  chmod 600 "$destination"
  report_hash="$(sha256_file "$destination" 2>/dev/null || true)"
  [ -n "$report_hash" ] || { rm -f "$destination"; error "无法校验诊断报告。"; return 1; }
  printf '%s  %s\n' "$report_hash" "$(basename "$destination")" > "$destination.sha256"
  chmod 600 "$destination.sha256"
  ok "脱敏诊断报告已创建：$destination"
}

resolve_repo_commit() {
  commit_json="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$VP_REPO/commits/$VP_REF")" || return 1
  commit_sha="$(printf '%s\n' "$commit_json" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]\{40\}\)".*/\1/p' | head -n 1)"
  case "$commit_sha" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
  [ "${#commit_sha}" -eq 40 ] || return 1
  printf '%s' "$commit_sha"
}

download_update_candidate() {
  script_target="$1"
  checksum_target="$2"
  if [ -n "${VP_UPDATE_SOURCE_DIR:-}" ]; then
    cp "$VP_UPDATE_SOURCE_DIR/vp.sh" "$script_target" || return 1
    cp "$VP_UPDATE_SOURCE_DIR/vp.sh.sha256" "$checksum_target" || return 1
    printf 'local-test-source'
    return 0
  fi
  commit_sha="$(resolve_repo_commit)" || { error "无法解析 $VP_REPO/$VP_REF 的精确提交。"; return 1; }
  raw_base="https://raw.githubusercontent.com/$VP_REPO/$commit_sha"
  curl -fsSL --max-time 30 "$raw_base/vp.sh" -o "$script_target" || return 1
  curl -fsSL --max-time 15 "$raw_base/vp.sh.sha256" -o "$checksum_target" || return 1
  printf '%s' "$commit_sha"
}

verify_script_sidecar() {
  script_file="$1"
  sidecar_file="$2"
  expected="$(awk 'NR==1{print tolower($1)}' "$sidecar_file" 2>/dev/null)"
  actual="$(sha256_file "$script_file" 2>/dev/null | tr 'A-F' 'a-f')"
  case "$expected" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#expected}" -eq 64 ] && [ "$expected" = "$actual" ]
}

update_cli() {
  need_root || return 1
  command -v curl >/dev/null 2>&1 || { error "缺少 curl。"; return 1; }
  candidate="$(mktemp /tmp/vp-update.XXXXXX)" || return 1
  sidecar="$(mktemp /tmp/vp-update-sha.XXXXXX)" || { rm -f "$candidate"; return 1; }
  cleanup_update() { rm -f "$candidate" "$sidecar"; }
  trap cleanup_update EXIT HUP INT TERM
  source_revision="$(download_update_candidate "$candidate" "$sidecar")" || { cleanup_update; trap - EXIT HUP INT TERM; error "更新文件下载失败。"; return 1; }
  verify_script_sidecar "$candidate" "$sidecar" || { cleanup_update; trap - EXIT HUP INT TERM; error "更新脚本 SHA-256 校验失败。"; return 1; }
  sh -n "$candidate" || { cleanup_update; trap - EXIT HUP INT TERM; error "更新脚本语法检查失败。"; return 1; }
  candidate_version="$(VP_CONFIG_DIR="$VP_CONFIG_DIR" sh "$candidate" version 2>/dev/null)"
  [ -n "$candidate_version" ] || { cleanup_update; trap - EXIT HUP INT TERM; error "无法读取候选版本。"; return 1; }
  if [ -f "$VP_CLI_PATH" ] && [ "$(sha256_file "$VP_CLI_PATH" 2>/dev/null)" = "$(sha256_file "$candidate" 2>/dev/null)" ]; then
    cleanup_update; trap - EXIT HUP INT TERM
    ok "当前已经是最新版本 $candidate_version。"
    return 0
  fi
  mkdir -p "$(dirname "$VP_CLI_PATH")"
  if [ -f "$VP_CLI_PATH" ]; then
    cp -p "$VP_CLI_PATH" "$VP_CLI_BACKUP_PATH" || { cleanup_update; trap - EXIT HUP INT TERM; return 1; }
    previous_hash="$(sha256_file "$VP_CLI_BACKUP_PATH" 2>/dev/null)"
    [ -n "$previous_hash" ] || { rm -f "$VP_CLI_BACKUP_PATH"; cleanup_update; trap - EXIT HUP INT TERM; error "无法校验当前管理脚本，更新已取消。"; return 1; }
    printf '%s  %s\n' "$previous_hash" "$(basename "$VP_CLI_BACKUP_PATH")" > "$VP_CLI_BACKUP_SHA256"
    chmod 600 "$VP_CLI_BACKUP_SHA256"
  else
    rm -f "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256"
  fi
  chmod 755 "$candidate"
  mv "$candidate" "$VP_CLI_PATH"
  rm -f "$sidecar"
  trap - EXIT HUP INT TERM
  ok "管理脚本已更新到 $candidate_version（来源 $source_revision）。"
}

rollback_cli() {
  need_root || return 1
  [ -f "$VP_CLI_BACKUP_PATH" ] || { error "没有可回滚的管理脚本。"; return 1; }
  if [ -r "$VP_CLI_BACKUP_SHA256" ]; then
    verify_script_sidecar "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256" || {
      error "备份管理脚本 SHA-256 校验失败，拒绝回滚。"
      return 1
    }
  else
    warn "旧版回滚文件没有 SHA-256；本次将执行语法与版本检查，成功交换后自动补齐校验。"
  fi
  sh -n "$VP_CLI_BACKUP_PATH" || { error "备份脚本语法检查失败。"; return 1; }
  current_tmp="$(mktemp /tmp/vp-current.XXXXXX)" || return 1
  [ -f "$VP_CLI_PATH" ] && cp -p "$VP_CLI_PATH" "$current_tmp" || : > "$current_tmp"
  cp -p "$VP_CLI_BACKUP_PATH" "$VP_CLI_PATH" || { rm -f "$current_tmp"; return 1; }
  chmod 755 "$VP_CLI_PATH"
  if ! VP_CONFIG_DIR="$VP_CONFIG_DIR" sh "$VP_CLI_PATH" version >/dev/null 2>&1; then
    [ -s "$current_tmp" ] && cp -p "$current_tmp" "$VP_CLI_PATH"
    rm -f "$current_tmp"
    error "回滚版本无法运行，已恢复当前版本。"
    return 1
  fi
  if [ -s "$current_tmp" ]; then
    replacement_hash="$(sha256_file "$current_tmp" 2>/dev/null)"
    [ -n "$replacement_hash" ] || {
      cp -p "$current_tmp" "$VP_CLI_PATH"
      rm -f "$current_tmp"
      error "无法为交换后的回滚版本生成 SHA-256，已恢复当前版本。"
      return 1
    }
    mv "$current_tmp" "$VP_CLI_BACKUP_PATH"
    printf '%s  %s\n' "$replacement_hash" "$(basename "$VP_CLI_BACKUP_PATH")" > "$VP_CLI_BACKUP_SHA256"
    chmod 600 "$VP_CLI_BACKUP_SHA256"
  else
    rm -f "$current_tmp" "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256"
  fi
  ok "管理脚本已回滚到 $(sh "$VP_CLI_PATH" version)。"
}

node_count() {
  if [ -r "$VP_NODES_DB" ]; then
    awk 'NF { n++ } END { print n + 0 }' "$VP_NODES_DB" 2>/dev/null
  else
    printf '0'
  fi
}

rotation_count() {
  mode="${1:-active}"
  [ -r "$VP_ROTATIONS_DB" ] || { printf '0'; return; }
  now="$(date +%s)"
  case "$mode" in
    expired) awk -F'|' -v now="$now" '$5+0<=now{n++}END{print n+0}' "$VP_ROTATIONS_DB" ;;
    *) awk -F'|' -v now="$now" '$5+0>now{n++}END{print n+0}' "$VP_ROTATIONS_DB" ;;
  esac
}

show_dashboard_summary() {
  total_nodes="$(node_count)"
  reality_nodes="$(awk -F'|' '$1=="reality"{n++}END{print n+0}' "$VP_NODES_DB" 2>/dev/null)"
  argo_nodes="$(awk -F'|' '$1=="argo"{n++}END{print n+0}' "$VP_NODES_DB" 2>/dev/null)"
  ipv6_nodes="$(awk -F'|' '$1=="reality" && $10=="ipv6"{n++}END{print n+0}' "$VP_NODES_DB" 2>/dev/null)"
  core_state="$(service_state "$VP_CORE_SERVICE")"
  tunnel_state="$(service_state "$VP_TUNNEL_SERVICE")"
  active_rotations="$(rotation_count active)"
  expired_rotations="$(rotation_count expired)"
  if [ -d "$VP_TX_ACTIVE" ]; then
    overall="需要修复"
    next_action="发现未完成的配置事务，请选择 5 执行健康检查与安全修复。"
  elif { [ -r "$VP_NODES_DB" ] && ! validate_nodes_database "$VP_NODES_DB" >/dev/null 2>&1; } ||
       { [ -r "$VP_ROTATIONS_DB" ] && ! validate_rotations_database "$VP_NODES_DB" "$VP_ROTATIONS_DB" >/dev/null 2>&1; }; then
    overall="状态数据异常"
    next_action="节点或轮换记录未通过完整性检查，请选择 5 导出诊断，再选择 7 从可信备份恢复。"
  elif [ ! -x "$VP_CORE_BIN" ]; then
    overall="尚未安装"
    next_action="请选择 1 创建 Reality 主节点，程序会引导安装内核。"
  elif [ "$total_nodes" -eq 0 ]; then
    overall="待创建节点"
    next_action="请选择 1 创建 Reality 主节点。"
  elif [ "$core_state" != "active" ] && [ "$core_state" != "started" ]; then
    overall="需要修复"
    next_action="代理内核未运行，请选择 5 检查并修复。"
  elif [ "$reality_nodes" -eq 0 ]; then
    overall="缺少主线路"
    next_action="当前只有备用节点，请选择 1 创建 Reality 主节点。"
  elif [ "$argo_nodes" -gt 0 ] && [ ! -s "$VP_TUNNEL_TOKEN_FILE" ]; then
    overall="备用线路未完成"
    next_action="已有 Cloudflare 备用节点但缺少 Tunnel 凭据，请选择 2 完成配置。"
  elif [ -s "$VP_TUNNEL_TOKEN_FILE" ] && [ "$tunnel_state" != "active" ] && [ "$tunnel_state" != "started" ]; then
    overall="主线路可用，备用异常"
    next_action="Cloudflare 备用线路未运行，请选择 5 检查并修复。"
  elif [ "$expired_rotations" -gt 0 ]; then
    overall="凭据轮换已到期"
    next_action="有 $expired_rotations 个旧凭据等待移除，请选择 3 完成凭据切换。"
  elif [ "$active_rotations" -gt 0 ]; then
    overall="凭据轮换中"
    next_action="请先用新链接完成测试，再选择 3 正式切换并移除旧凭据。"
  elif [ ! -s "$VP_TUNNEL_TOKEN_FILE" ]; then
    overall="主线路已就绪"
    next_action="可选择 2 增加 Cloudflare 备用节点，或选择 3 查看和测试节点。"
  else
    overall="主备线路已就绪"
    next_action="请选择 3 查看链接或执行真实节点测试。"
  fi
  printf '总体状态：%s\n' "$overall"
  printf '节点组成：Reality %s 个（IPv6 %s）/ Cloudflare 备用 %s 个\n' "$reality_nodes" "$ipv6_nodes" "$argo_nodes"
  printf '下一步：%s\n' "$next_action"
  printf '%s\n' '----------------------------------------'
}

show_status() {
  memory_snapshot
  cpu_snapshot
  oom_snapshot
  printf '\nVPS-Node %s\n' "$VP_VERSION"
  printf '%s\n' '----------------------------------------'
  show_dashboard_summary
  printf '代理核心：%s\n' "$(service_state "$VP_CORE_SERVICE")"
  printf 'Cloudflare Tunnel：%s\n' "$(service_state "$VP_TUNNEL_SERVICE")"
  printf '节点数量：%s\n' "$(node_count)"
  printf '进行中凭据轮换：%s\n' "$(rotation_count active)"
  printf '已到期凭据轮换：%s\n' "$(rotation_count expired)"
  printf '\n内存（%s）：\n' "$MEM_SOURCE"
  printf '  实际工作内存：%s MiB\n' "$(bytes_to_mib "$MEM_WORKING_BYTES")"
  printf '  可回收文件缓存：%s MiB\n' "$(bytes_to_mib "$MEM_FILE_BYTES")"
  printf '  总计占用：%s MiB\n' "$(bytes_to_mib "$MEM_TOTAL_BYTES")"
  if [ "$MEM_LIMIT_BYTES" -gt 0 ] 2>/dev/null; then
    printf '  内存限制：%s MiB\n' "$(bytes_to_mib "$MEM_LIMIT_BYTES")"
  else
    printf '  内存限制：宿主机管理\n'
  fi
  printf '  Swap：%s MiB\n' "$(bytes_to_mib "$MEM_SWAP_BYTES")"
  printf '\nCPU（%s）：\n' "$CPU_SOURCE"
  printf '  宿主可见 / 实际可用：%s / %s 核\n' "$CPU_HOST_COUNT" "$CPU_EFFECTIVE_COUNT"
  if [ "$CPU_QUOTA_MILLI" -gt 0 ]; then
    printf '  cgroup CPU 配额：%s 核\n' "$(awk -v n="$CPU_QUOTA_MILLI" 'BEGIN{printf "%.3f",n/1000}')"
  else
    printf '  cgroup CPU 配额：无限制或未识别\n'
  fi
  if [ "$OOM_DELTA" -gt 0 ]; then
    printf '  OOM Kill：新增 %s 次（累计 %s）\n' "$OOM_DELTA" "$OOM_CURRENT"
  elif [ "$OOM_CURRENT" -gt 0 ]; then
    printf '  OOM Kill：无新增（累计 %s）\n' "$OOM_CURRENT"
  else
    printf '  OOM Kill：0\n'
  fi
  if [ -r "$VP_CORE_ENV" ]; then
    printf '\n已应用的优化参数：\n'
    printf '  内存档位：%s\n' "$(awk -F= '$1=="VP_MEMORY_PROFILE"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  核心预算：%s MiB\n' "$(awk -F= '$1=="VP_CORE_BUDGET_MIB"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  GOMEMLIMIT：%s\n' "$(awk -F= '$1=="GOMEMLIMIT"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  GOGC / GOMAXPROCS：%s / %s\n' \
      "$(awk -F= '$1=="GOGC"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')" \
      "$(awk -F= '$1=="GOMAXPROCS"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  CPU 实际档位：%s 核（配额 %s/1000）\n' \
      "$(awk -F= '$1=="VP_CPU_EFFECTIVE_COUNT"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')" \
      "$(awk -F= '$1=="VP_CPU_QUOTA_MILLI"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  内部代理 / 控制端口：%s / %s\n' \
      "$(awk -F= '$1=="VP_MIXED_PORT"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')" \
      "$(awk -F= '$1=="VP_CONTROLLER_PORT"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')"
    printf '  DNS 策略：%s（%s）\n' \
      "$(awk -F= '$1=="VP_DNS_MODE"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未知')" \
      "$(awk -F= '$1=="VP_DNS_SERVERS"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || printf '未检测')"
  fi
  printf '%s\n\n' '----------------------------------------'
}

optimize_and_verify() {
  need_root || return 1
  init_layout >/dev/null || return 1
  info "正在检测当前内存限制、配置和服务状态。"
  if ! doctor; then
    warn "基础检查发现问题，将只应用不会改变节点凭据的安全优化。"
  fi
  safe_repair || return 1
  layered_health_check
}

dns_probe() {
  if command -v getent >/dev/null 2>&1; then
    getent ahosts github.com >/dev/null 2>&1
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup github.com >/dev/null 2>&1
  else
    return 2
  fi
}

doctor() {
  errors=0
  warnings=0
  info "开始基础环境检查。"
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64|aarch64|arm64) ok "CPU 架构受支持。" ;;
    *) error "当前 CPU 架构尚未支持。"; errors=$((errors + 1)) ;;
  esac
  if [ -r /etc/os-release ]; then
    os_name="$(awk -F= '$1=="PRETTY_NAME"{gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release)"
    ok "系统：${os_name:-Linux}"
  else
    warn "无法读取系统版本。"; warnings=$((warnings + 1))
  fi
  if cgroup_file memory.current >/dev/null 2>&1; then
    ok "已识别 cgroup 内存限制。"
  else
    warn "未识别 cgroup v2，将使用 /proc/meminfo。"; warnings=$((warnings + 1))
  fi
  dns_probe
  case "$?" in
    0) ok "系统 DNS 解析正常。" ;;
    2) warn "缺少 DNS 检测工具。"; warnings=$((warnings + 1)) ;;
    *) error "系统 DNS 当前无法解析。"; errors=$((errors + 1)) ;;
  esac
  for cmd in awk sed grep curl; do
    command -v "$cmd" >/dev/null 2>&1 || { warn "缺少命令：$cmd"; warnings=$((warnings + 1)); }
  done
  [ -d "$VP_CONFIG_DIR" ] && ok "状态目录存在。" || { warn "尚未初始化，请执行 vp init。"; warnings=$((warnings + 1)); }
  if [ -f "$VP_NODES_DB" ]; then
    mode="$(stat -c '%a' "$VP_NODES_DB" 2>/dev/null || stat -f '%Lp' "$VP_NODES_DB" 2>/dev/null)"
    [ "$mode" = "600" ] && ok "节点数据库权限正确。" || { warn "节点数据库权限应为 600。"; warnings=$((warnings + 1)); }
  fi
  printf '\n检查完成：%s 个错误，%s 个警告。\n' "$errors" "$warnings"
  [ "$errors" -eq 0 ]
}

health_ok() {
  ok "$*"
}

health_warn() {
  warn "$*"
  HEALTH_WARNINGS=$((HEALTH_WARNINGS + 1))
}

health_error() {
  error "$*"
  HEALTH_ERRORS=$((HEALTH_ERRORS + 1))
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

tunnel_connection_count() {
  curl -fsS --max-time 3 "http://127.0.0.1:$VP_TUNNEL_METRICS_PORT/metrics" 2>/dev/null |
    awk '/^cloudflared_tunnel_ha_connections / {sum += $2} END {print sum + 0}'
}

layered_health_check() {
  HEALTH_ERRORS=0
  HEALTH_WARNINGS=0
  printf '\nVPS-Node 分层健康检查\n'
  printf '%s\n' '----------------------------------------'

  if [ -d "$VP_TX_ACTIVE" ]; then
    tx_pid="$(cat "$VP_TX_ACTIVE/pid" 2>/dev/null || true)"
    if pid_is_alive "$tx_pid"; then
      health_warn "配置层：存在正在运行的事务。"
    else
      health_error "配置层：发现被中断的事务，执行 vp repair 可恢复。"
    fi
  else
    health_ok "配置层：没有未完成事务。"
  fi

  permission_bad=0
  for protected in "$VP_NODES_DB" "$VP_ROTATIONS_DB" "$VP_STATE_FILE" "$VP_CORE_ENV" "$VP_TUNNEL_TOKEN_FILE"; do
    [ -e "$protected" ] || continue
    [ "$(file_mode "$protected")" = "600" ] || permission_bad=$((permission_bad + 1))
  done
  if [ "$permission_bad" -eq 0 ]; then
    health_ok "权限层：敏感状态权限正常。"
  else
    health_error "权限层：$permission_bad 个文件权限不安全。"
  fi
  active_rotations="$(rotation_count active)"
  expired_rotations="$(rotation_count expired)"
  [ "$active_rotations" -gt 0 ] && health_warn "凭据层：$active_rotations 个节点处于新旧凭据宽限期。"
  [ "$expired_rotations" -gt 0 ] && health_warn "凭据层：$expired_rotations 个到期旧凭据等待清理。"

  if [ -x "$VP_CORE_BIN" ]; then
    if [ -f "$VP_CORE_CONFIG" ] && "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$VP_CORE_CONFIG" >/dev/null 2>&1; then
      if generated_config_matches_state; then
        health_ok "内核配置层：Mihomo 配置有效且与节点状态一致。"
      else
        health_error "内核配置层：配置语法有效但已偏离节点状态，执行 vp repair 可事务化重建。"
      fi
    else
      health_error "内核配置层：Mihomo 配置无效或缺失。"
    fi
    if [ "${VP_SKIP_SERVICE:-0}" = "1" ]; then
      health_warn "进程层：隔离模式未检查常驻服务。"
    elif core_process_running; then
      health_ok "进程层：代理核心正在运行。"
    else
      health_error "进程层：代理核心未运行。"
    fi
    memory_snapshot
    current_limit_mib=$((MEM_LIMIT_BYTES / 1048576))
    saved_limit_mib="$(awk -F= '$1=="VP_MEMORY_LIMIT_MIB"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null)"
    case "$saved_limit_mib" in ''|*[!0-9]*) saved_limit_mib=0 ;; esac
    if [ "$saved_limit_mib" -gt 0 ] && [ "$current_limit_mib" -ne "$saved_limit_mib" ]; then
      health_warn "资源配置层：内存限制已从 ${saved_limit_mib} MiB 变为 ${current_limit_mib} MiB，执行 vp repair 可重新适配。"
    else
      profile="$(awk -F= '$1=="VP_MEMORY_PROFILE"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null)"
      health_ok "资源配置层：内存档位 ${profile:-未知} 与当前限制一致。"
    fi
  else
    health_warn "内核配置层：尚未安装代理核心。"
  fi

  node_total=0
  node_listening=0
  if [ -r "$VP_NODES_DB" ]; then
    while IFS='|' read -r proto name port rest; do
      [ -n "$proto" ] || continue
      node_total=$((node_total + 1))
      port_in_use "$port" && node_listening=$((node_listening + 1))
    done < "$VP_NODES_DB"
  fi
  if [ "$node_total" -eq 0 ]; then
    health_warn "监听层：当前没有节点。"
  elif [ "$node_listening" -eq "$node_total" ]; then
    health_ok "监听层：$node_total 个节点端口均已监听。"
  else
    health_error "监听层：$node_listening/$node_total 个节点端口正在监听。"
  fi
  ipv6_node_total="$(awk -F'|' '$1=="reality" && $10=="ipv6"{n++}END{print n+0}' "$VP_NODES_DB" 2>/dev/null)"
  if [ "$ipv6_node_total" -gt 0 ]; then
    if public_ipv6 >/dev/null 2>&1; then
      health_ok "IPv6 层：$ipv6_node_total 个 IPv6 Reality 节点具有公网 IPv6。"
    else
      health_error "IPv6 层：配置了 $ipv6_node_total 个 IPv6 Reality 节点，但当前无法取得公网 IPv6。"
    fi
  fi

  dns_mode="$(awk -F= '$1=="VP_DNS_MODE"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || true)"
  dns_servers="$(awk -F= '$1=="VP_DNS_SERVERS"{print $2;exit}' "$VP_CORE_ENV" 2>/dev/null || true)"
  if dns_profile_probe "${dns_mode:-system}" "${dns_servers:-system}"; then
    health_ok "DNS 层：${dns_mode:-系统} 上游解析正常。"
  else
    if [ "$dns_mode" = public ]; then
      health_error "DNS 上游不可达：公共 DNS（$dns_servers）解析失败；这不等同于节点协议故障。"
    else
      health_error "DNS 上游不可达：系统 DNS 无法解析；节点协议尚未判定为故障。"
    fi
  fi
  if command -v curl >/dev/null 2>&1 && [ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://cp.cloudflare.com/generate_204 2>/dev/null)" = "204" ]; then
    health_ok "公网层：服务器直接出站正常。"
  else
    health_error "公网层：服务器无法完成 HTTPS 出站。"
  fi

  if [ -s "$VP_TUNNEL_TOKEN_FILE" ]; then
    if [ "$(service_state "$VP_TUNNEL_SERVICE")" = "active" ]; then
      health_ok "Tunnel 进程层：服务正在运行。"
    else
      health_error "Tunnel 进程层：已配置 Token，但服务未运行。"
    fi
    edge_connections="$(tunnel_connection_count 2>/dev/null || printf 0)"
    case "$edge_connections" in ''|*[!0-9]*) edge_connections=0 ;; esac
    if [ "$edge_connections" -gt 0 ]; then
      health_ok "Tunnel 边缘层：$edge_connections 条连接。"
    else
      health_error "Tunnel 边缘层：没有 Cloudflare 边缘连接。"
    fi
  else
    health_warn "Tunnel 层：尚未配置备用线路。"
  fi

  oom_snapshot
  if [ "$OOM_DELTA" -gt 0 ]; then
    health_error "资源层：自上次确认后新增 $OOM_DELTA 次 OOM Kill（累计 $OOM_CURRENT）。"
  elif [ "$OOM_CURRENT" -gt 0 ]; then
    health_warn "资源层：没有新增 OOM Kill，历史累计 $OOM_CURRENT 次。"
  else
    health_ok "资源层：未记录 OOM Kill。"
  fi
  remember_oom_snapshot

  printf '%s\n' '----------------------------------------'
  if [ "$HEALTH_ERRORS" -eq 0 ]; then
    ok "健康检查完成：0 个错误，$HEALTH_WARNINGS 个警告。"
    return 0
  fi
  error "健康检查完成：$HEALTH_ERRORS 个错误，$HEALTH_WARNINGS 个警告。"
  return 1
}

safe_repair() {
  need_root || return 1
  repaired=0
  runtime_changed=0
  config_changed=0
  if [ -d "$VP_TX_ACTIVE" ]; then
    recover_state_transaction || return 1
    repaired=$((repaired + 1))
  fi
  for protected in "$VP_NODES_DB" "$VP_ROTATIONS_DB" "$VP_STATE_FILE" "$VP_CORE_ENV" "$VP_TUNNEL_TOKEN_FILE"; do
    [ -e "$protected" ] || continue
    if [ "$(file_mode "$protected")" != "600" ]; then
      chmod 600 "$protected"
      repaired=$((repaired + 1))
    fi
  done
  if [ -r "$VP_NODES_DB" ]; then
    validate_nodes_database "$VP_NODES_DB" || { error "节点数据库无效，拒绝从损坏状态重建配置。"; return 1; }
    validate_rotations_database "$VP_NODES_DB" "$VP_ROTATIONS_DB" || { error "凭据轮换数据库无效，拒绝重建配置。"; return 1; }
  fi
  if [ -x "$VP_CORE_BIN" ]; then
    runtime_existed=0
    [ -f "$VP_CORE_ENV" ] && runtime_existed=1
    old_runtime="$(cat "$VP_CORE_ENV" 2>/dev/null || true)"
    write_core_runtime_env || return 1
    new_runtime="$(cat "$VP_CORE_ENV" 2>/dev/null || true)"
    if [ "$old_runtime" != "$new_runtime" ]; then
      runtime_changed=1
      repaired=$((repaired + 1))
    fi
  fi
  if [ -x "$VP_CORE_BIN" ] && [ -r "$VP_NODES_DB" ]; then
    repair_tmp="$(mktemp /tmp/vp-repair-config.XXXXXX)" || return 1
    render_mihomo_config "$VP_NODES_DB" "$repair_tmp"
    if "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$repair_tmp" >/dev/null 2>&1; then
      if ! cmp -s "$repair_tmp" "$VP_CORE_CONFIG" 2>/dev/null; then
        config_backup="$(mktemp /tmp/vp-repair-config-old.XXXXXX)" || { rm -f "$repair_tmp"; return 1; }
        config_existed=0
        if [ -f "$VP_CORE_CONFIG" ]; then
          cp -p "$VP_CORE_CONFIG" "$config_backup" || { rm -f "$repair_tmp" "$config_backup"; return 1; }
          config_existed=1
        fi
        mkdir -p "$VP_GENERATED_DIR"
        mv "$repair_tmp" "$VP_CORE_CONFIG"
        chmod 600 "$VP_CORE_CONFIG"
        config_changed=1
        repaired=$((repaired + 1))
      else
        rm -f "$repair_tmp"
      fi
      if [ "${VP_SKIP_SERVICE:-0}" != "1" ] &&
         { ! core_process_running || [ "$runtime_changed" = "1" ] || [ "$config_changed" = "1" ]; }; then
        if core_service_restart; then
          repaired=$((repaired + 1))
        else
          if [ "$config_changed" = "1" ]; then
            if [ "$config_existed" = "1" ]; then
              cp -p "$config_backup" "$VP_CORE_CONFIG"
            else
              rm -f "$VP_CORE_CONFIG"
            fi
          fi
          if [ "$runtime_changed" = "1" ]; then
            if [ "$runtime_existed" = "1" ]; then
              printf '%s\n' "$old_runtime" > "$VP_CORE_ENV"
              chmod 600 "$VP_CORE_ENV"
            else
              rm -f "$VP_CORE_ENV"
            fi
          fi
          [ -z "${config_backup:-}" ] || rm -f "$config_backup"
          core_service_restart >/dev/null 2>&1 || true
          error "修复后的核心无法启动，已恢复修复前配置与运行参数。"
          return 1
        fi
      fi
      [ -z "${config_backup:-}" ] || rm -f "$config_backup"
    else
      rm -f "$repair_tmp"
      error "根据节点数据库重新生成的配置仍然无效，未覆盖当前配置。"
      return 1
    fi
  fi
  if [ -s "$VP_TUNNEL_TOKEN_FILE" ] && [ "${VP_SKIP_SERVICE:-0}" != "1" ] && [ "$(service_state "$VP_TUNNEL_SERVICE")" != "active" ]; then
    tunnel_service_restart && repaired=$((repaired + 1))
  fi
  ok "安全修复完成：执行了 $repaired 项修改。"
}

uninstall_path_safe() {
  path="${1:-}"
  case "$path" in
    ''|/|/etc|/var|/usr|/usr/local|/var/lib|/var/log|.|..|*/../*|*/..|*/./*|*/.) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

uninstall_path_contains() {
  parent="${1%/}"
  child="${2%/}"
  [ "$child" = "$parent" ] || [ "${child#"$parent"/}" != "$child" ]
}

uninstall_plan() {
  printf '将停止并移除服务：%s、%s、%s\n' "$VP_CORE_SERVICE" "$VP_TUNNEL_SERVICE" "$VP_WATCHDOG_SERVICE"
  printf '将删除项目路径：\n'
  printf '  %s\n' "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR" "$VP_CLI_PATH" "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256"
}

uninstall_project() {
  need_root || return 1
  [ "$#" -le 1 ] || { error "卸载命令只接受 --dry-run 参数。"; return 2; }
  mode="${1:-}"
  case "$mode" in ''|--dry-run) ;; *) error "不支持的卸载参数：$mode"; return 2 ;; esac
  for target in "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR" "$VP_CLI_PATH" "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256"; do
    uninstall_path_safe "$target" || { error "拒绝卸载：检测到危险路径 $target"; return 1; }
  done
  uninstall_plan
  [ "$mode" = "--dry-run" ] && { ok "预览完成，未修改任何文件或服务。"; return 0; }
  uninstall_path_safe "$VP_UNINSTALL_BACKUP_DIR" || { error "卸载备份目录不安全：$VP_UNINSTALL_BACKUP_DIR"; return 1; }
  for target in "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR"; do
    uninstall_path_contains "$target" "$VP_UNINSTALL_BACKUP_DIR" && { error "卸载备份目录位于待删除路径内：$VP_UNINSTALL_BACKUP_DIR"; return 1; }
  done
  warn "该操作将删除 VPS-Node；继续前会创建外部恢复包。"
  if [ -n "${VP_UNINSTALL_CONFIRM:-}" ]; then
    answer="$VP_UNINSTALL_CONFIRM"
  else
    printf '请输入 DELETE 确认：'
    read -r answer || true
  fi
  [ "$answer" = "DELETE" ] || { warn "已取消。"; return 2; }
  mkdir -p "$VP_UNINSTALL_BACKUP_DIR" || { error "无法创建卸载备份目录。"; return 1; }
  backup_archive="$VP_UNINSTALL_BACKUP_DIR/vps-node-uninstall-backup-$(date '+%Y%m%d-%H%M%S').tar.gz"
  create_backup "$backup_archive" || { error "卸载前备份失败，已中止卸载。"; return 1; }
  [ -s "$backup_archive" ] && [ -s "$backup_archive.sha256" ] || { error "卸载备份或 SHA-256 文件缺失，已中止卸载。"; return 1; }
  expected_backup_hash="$(awk 'NR==1{print tolower($1)}' "$backup_archive.sha256" 2>/dev/null)"
  actual_backup_hash="$(sha256_file "$backup_archive" 2>/dev/null | tr 'A-F' 'a-f')"
  [ -n "$actual_backup_hash" ] && [ "$expected_backup_hash" = "$actual_backup_hash" ] || { error "卸载备份校验失败，已中止卸载。"; return 1; }
  network_rollback --quiet || { error "无法恢复项目应用前的网络参数，已中止卸载。"; return 1; }
  if [ "${VP_SKIP_SERVICE:-0}" != "1" ]; then
    case "$(service_manager)" in
      systemd)
        systemctl disable --now "${VP_WATCHDOG_SERVICE}.timer" >/dev/null 2>&1 || true
        systemctl disable --now "$VP_TUNNEL_SERVICE" >/dev/null 2>&1 || true
        systemctl disable --now "$VP_CORE_SERVICE" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${VP_WATCHDOG_SERVICE}.timer" "/etc/systemd/system/${VP_WATCHDOG_SERVICE}.service" \
          "/etc/systemd/system/${VP_TUNNEL_SERVICE}.service" "/etc/systemd/system/${VP_CORE_SERVICE}.service"
        systemctl daemon-reload >/dev/null 2>&1 || true
        ;;
      openrc)
        rc-service "$VP_TUNNEL_SERVICE" stop >/dev/null 2>&1 || true
        rc-service "$VP_CORE_SERVICE" stop >/dev/null 2>&1 || true
        rc-update del "$VP_TUNNEL_SERVICE" default >/dev/null 2>&1 || true
        rc-update del "$VP_CORE_SERVICE" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/$VP_TUNNEL_SERVICE" "/etc/init.d/$VP_CORE_SERVICE"
        rm -f "/etc/periodic/15min/$VP_WATCHDOG_SERVICE"
        ;;
    esac
  fi
  rm -rf "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR"
  rm -f "$VP_CLI_PATH" "$VP_CLI_BACKUP_PATH" "$VP_CLI_BACKUP_SHA256"
  ok "VPS-Node 已卸载。"
  printf '恢复包：%s\n' "$backup_archive"
  printf '重新安装后恢复：vp restore %s\n' "$backup_archive"
}

pause_screen() {
  printf '按回车继续...'
  read -r _ || true
}

ensure_core_interactive() {
  [ -x "$VP_CORE_BIN" ] && return 0
  warn "尚未安装代理核心。"
  printf '现在安装 Mihomo？[Y/n]：'
  read -r answer || true
  case "$answer" in n|N|no|NO) return 1 ;; esac
  core_install
}

interactive_reality_add() {
  ensure_core_interactive || return 1
  printf '节点名称（默认 reality-1）：'
  read -r name || true
  [ -n "$name" ] || name=reality-1
  printf '监听端口（留空自动选择）：'
  read -r port || true
  printf 'Reality SNI（默认 www.amd.com）：'
  read -r sni || true
  [ -n "$sni" ] || sni=www.amd.com
  printf '地址族（默认 ipv4，可选 ipv6）：'
  read -r address_family || true
  reality_add "$name" "$port" "$sni" "${address_family:-ipv4}"
  printf '是否显示新节点链接？[y/N]：'
  read -r answer || true
  case "$answer" in y|Y|yes|YES) show_node_link "$name" ;; esac
}

interactive_argo_setup() {
  ensure_core_interactive || return 1
  if [ ! -x "$VP_TUNNEL_BIN" ] || [ ! -s "$VP_TUNNEL_TOKEN_FILE" ]; then
    tunnel_install || return 1
  fi
  printf '备用节点名称（默认 argo-1）：'
  read -r name || true
  [ -n "$name" ] || name=argo-1
  printf 'Cloudflare 公网域名：'
  read -r host || true
  [ -n "$host" ] || { error "域名不能为空。"; return 1; }
  printf '本地端口（留空自动选择）：'
  read -r port || true
  printf 'WebSocket 路径（留空自动生成）：'
  read -r path || true
  argo_add "$name" "$port" "$host" "$path"
}

interactive_node_action() {
  show_nodes
  [ -s "$VP_NODES_DB" ] || return 0
  printf '请输入节点编号或名称；输入 A 导出全部节点订阅：'
  read -r selector || true
  [ -n "$selector" ] || return 0
  case "$selector" in
    a|A)
      printf '订阅格式（默认 base64，可选 plain）：'; read -r format || true
      export_subscription "${format:-base64}"
      return
      ;;
  esac
  target="$(resolve_node_selector "$selector")"
  [ -n "$target" ] || { error "未找到节点：$selector。"; return 1; }
  printf '1. 显示链接\n2. 端到端测试\n3. 修改节点\n4. 轮换凭据\n5. 完成凭据切换\n6. 删除节点\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in
    1) show_node_link "$target" ;;
    2) test_node_end_to_end "$target" ;;
    3)
      record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB")"
      IFS='|' read -r proto old_name old_port f4 f5 f6 f7 f8 f9 f10 <<EOF
$record
EOF
      printf '新名称（默认 %s）：' "$old_name"; read -r new_name || true
      printf '新端口（默认 %s）：' "$old_port"; read -r new_port || true
      if [ "$proto" = reality ]; then
        printf '新 Reality SNI（默认 %s）：' "$f5"; read -r endpoint || true
        printf '地址族（默认 %s，可选 ipv4/ipv6）：' "${f10:-ipv4}"; read -r address_family || true
        edit_node "$target" "${new_name:-$old_name}" "${new_port:-$old_port}" "${endpoint:-$f5}" "${address_family:-${f10:-ipv4}}"
      else
        printf '新 Tunnel 公网域名（默认 %s）：' "$f6"; read -r endpoint || true
        printf '新 WebSocket 路径（默认 %s）：' "$f5"; read -r path || true
        edit_node "$target" "${new_name:-$old_name}" "${new_port:-$old_port}" "${endpoint:-$f6}" "${path:-$f5}"
      fi
      ;;
    4)
      printf '新旧凭据并存小时数（默认 24）：'
      read -r hours || true
      rotate_credential "$target" "${hours:-24}"
      ;;
    5) finalize_rotation "$target" ;;
    6) delete_node "$target" ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

interactive_health() {
  printf '1. 分层健康检查\n2. 安全修复并复检\n3. 导出脱敏诊断报告\n4. 立即执行一次自愈\n5. 启用低开销后台自愈\n6. 查看稳定性记录\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in
    1) layered_health_check ;;
    2) safe_repair && layered_health_check ;;
    3) diagnostic_report ;;
    4) self_heal_once ;;
    5) install_stability_monitor ;;
    6) show_stability ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

interactive_backup() {
  printf '1. 创建备份\n2. 预览并恢复 VPS-Node 备份\n3. 预览旧 Mihomo-lite-argo 迁移\n4. 应用旧项目无损迁移\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in
    1) create_backup "$VP_BACKUP_DIR" ;;
    2) printf '请输入备份文件完整路径：'; read -r archive || true; restore_backup "$archive" ;;
    3) printf '旧项目 nodes.db 路径（默认 /etc/mihomo/nodes.db）：'; read -r source_db || true; migrate_from_mihomo_lite "${source_db:-/etc/mihomo/nodes.db}" --dry-run ;;
    4) printf '旧项目 nodes.db 路径（默认 /etc/mihomo/nodes.db）：'; read -r source_db || true; migrate_from_mihomo_lite "${source_db:-/etc/mihomo/nodes.db}" --apply ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

interactive_update() {
  printf '1. 检查并更新管理脚本\n2. 回滚上一个管理脚本\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in 1) update_cli ;; 2) rollback_cli ;; 0) return 0 ;; *) warn "无效选择。" ;; esac
}

advanced_menu() {
  printf '1. 基础环境检查\n2. 初始化状态目录\n3. 安装/更新 Mihomo 内核\n4. 安装/更新 Cloudflare Tunnel\n5. 查看凭据轮换状态\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in
    1) doctor ;;
    2) init_layout ;;
    3) core_install ;;
    4) tunnel_install ;;
    5) show_rotations ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

interactive_network() {
  printf '1. 一键测试全部节点（并发）\n2. 查看当前网络状态\n3. 预览候选网络优化\n4. 基线测试后应用并复测\n5. 回滚已应用网络优化\n6. 应用资源与 DNS 自适应并验证\n0. 返回\n请选择：'
  read -r action || true
  case "$action" in
    1)
      printf '每个节点并发连接数（默认 4，范围 1-8）：'
      read -r concurrency || true
      test_all_nodes "${concurrency:-4}"
      ;;
    2) show_network_status ;;
    3) network_optimize_verified --dry-run ;;
    4)
      printf '用于验证的节点编号或名称（留空优先 Reality）：'; read -r target || true
      printf '并发连接数（默认 4）：'; read -r concurrency || true
      network_optimize_verified "$target" "${concurrency:-4}"
      ;;
    5) network_rollback ;;
    6) optimize_and_verify ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

menu() {
  while true; do
    show_status
    printf '1. 创建 Reality 主节点\n'
    printf '2. 配置 Cloudflare 备用节点\n'
    printf '3. 查看与管理节点\n'
    printf '4. 网络状态、并发测速与自适应\n'
    printf '5. 健康检查与安全修复\n'
    printf '6. 一键安全维护\n'
    printf '7. 备份与迁移\n'
    printf '8. 更新与回滚\n'
    printf '9. 高级设置\n'
    printf '10. 刷新状态\n'
    printf '11. 卸载 VPS-Node\n'
    printf '0. 退出\n'
    printf '请选择：'
    read -r choice || return 0
    case "$choice" in
      1) interactive_reality_add; pause_screen ;;
      2) interactive_argo_setup; pause_screen ;;
      3) interactive_node_action; pause_screen ;;
      4) interactive_network; pause_screen ;;
      5) interactive_health; pause_screen ;;
      6) maintenance_mode; pause_screen ;;
      7) interactive_backup; pause_screen ;;
      8) interactive_update; pause_screen ;;
      9) advanced_menu; pause_screen ;;
      10) ;;
      11)
        if uninstall_project; then
          return 0
        fi
        pause_screen
        ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

case "${1:-}" in
  init) init_layout ;;
  core-install|install-core) core_install ;;
  reality-add|add-reality) shift; reality_add "$@" ;;
  tunnel-install|install-tunnel) shift; tunnel_install "$@" ;;
  argo-add|add-argo) shift; argo_add "$@" ;;
  nodes|list) show_nodes ;;
  subscription|sub) shift; export_subscription "$@" ;;
  delete|remove) shift; delete_node "$@" ;;
  edit|edit-node) shift; edit_node "$@" ;;
  link) shift; show_node_link "$@" ;;
  test-node|test) shift; test_node_end_to_end "$@" ;;
  test-all|benchmark) shift; test_all_nodes "$@" ;;
  network|network-status) show_network_status ;;
  network-optimize) shift; network_optimize_verified "$@" ;;
  network-rollback) shift; network_rollback "$@" ;;
  rotate|rotate-credential) shift; rotate_credential "$@" ;;
  rotations|rotation-status) show_rotations ;;
  rotate-finalize|rotation-finalize) shift; finalize_rotation "$@" ;;
  backup) shift; create_backup "$@" ;;
  restore) shift; restore_backup "$@" ;;
  migrate-mh|migrate-from-mh) shift; migrate_from_mihomo_lite "$@" ;;
  maintain|maintenance) maintenance_mode ;;
  report|diagnostic) shift; diagnostic_report "$@" ;;
  self-heal|selfheal) shift; self_heal_once "$@" ;;
  monitor-install|watchdog-install) install_stability_monitor ;;
  stability|monitor-status) show_stability ;;
  update) update_cli ;;
  rollback) rollback_cli ;;
  core-rollback) core_binary_rollback ;;
  tunnel-rollback) tunnel_binary_rollback ;;
  status) show_status ;;
  doctor) doctor ;;
  health|check) layered_health_check ;;
  repair|fix) safe_repair ;;
  optimize|optimization) optimize_and_verify ;;
  version|--version|-V) printf '%s\n' "$VP_VERSION" ;;
  uninstall) shift; uninstall_project "$@" ;;
  debug-tx) shift; debug_transaction "$@" ;;
  help|-h|--help)
    printf '用法：vp [status|doctor|health|repair|report|self-heal|monitor-install|stability|network|network-optimize|network-rollback|test-all|optimize|maintain|update|rollback|init|core-install|reality-add|tunnel-install|argo-add|nodes|subscription|edit|delete|link|test-node|rotate|rotations|rotate-finalize|backup|restore|migrate-mh|uninstall|version]\n'
    ;;
  '') menu ;;
  *) error "未知命令：$1"; exit 2 ;;
esac
