#!/bin/sh

set -u

VP_VERSION="0.1.0-dev.2"
VP_CONFIG_DIR="${VP_CONFIG_DIR:-/etc/vps-node}"
VP_DATA_DIR="${VP_DATA_DIR:-/var/lib/vps-node}"
VP_LOG_DIR="${VP_LOG_DIR:-/var/log/vps-node}"
VP_LIB_DIR="${VP_LIB_DIR:-/usr/local/lib/vps-node}"
VP_NODES_DB="$VP_CONFIG_DIR/nodes.db"
VP_STATE_FILE="$VP_CONFIG_DIR/state.env"
VP_SECRETS_DIR="$VP_CONFIG_DIR/secrets"
VP_GENERATED_DIR="$VP_CONFIG_DIR/generated"
VP_TX_DIR="$VP_CONFIG_DIR/transactions"
VP_TX_ACTIVE="$VP_TX_DIR/active"

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

init_layout() {
  need_root || return 1
  umask 077
  mkdir -p "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR" \
    "$VP_SECRETS_DIR" "$VP_GENERATED_DIR" "$VP_TX_DIR"
  [ -f "$VP_NODES_DB" ] || : > "$VP_NODES_DB"
  [ -f "$VP_STATE_FILE" ] || printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$VP_STATE_FILE"
  chmod 700 "$VP_CONFIG_DIR" "$VP_SECRETS_DIR" "$VP_TX_DIR"
  chmod 600 "$VP_NODES_DB" "$VP_STATE_FILE"
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
  printf '%s\n' "$VP_NODES_DB" "$VP_STATE_FILE" "$VP_GENERATED_DIR"
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
  [ -f "$VP_STATE_FILE" ] && cp -p "$VP_STATE_FILE" "$candidate_root/state.env" || printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$candidate_root/state.env"
  [ -d "$VP_GENERATED_DIR" ] && cp -R -p "$VP_GENERATED_DIR" "$candidate_root/generated" || mkdir -p "$candidate_root/generated"
  chmod 600 "$candidate_root/nodes.db" "$candidate_root/state.env"
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

validate_state_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  [ -f "$candidate_root/state.env" ] || { error "候选状态文件不存在。"; return 1; }
  [ -f "$candidate_root/nodes.db" ] || { error "候选节点数据库不存在。"; return 1; }
  if grep -Ev '^[A-Z][A-Z0-9_]*=[A-Za-z0-9._:/+-]*$|^$' "$candidate_root/state.env" >/dev/null 2>&1; then
    error "候选状态文件格式错误。"
    return 1
  fi
  if awk -F'|' 'NF && NF < 5 { bad=1 } END { exit bad ? 0 : 1 }' "$candidate_root/nodes.db" 2>/dev/null; then
    error "候选节点数据库存在不完整记录。"
    return 1
  fi
  printf 'validated\n' > "$VP_TX_ACTIVE/stage"
}

activate_state_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  validate_state_candidate || return 1
  state_tmp="$VP_CONFIG_DIR/.state.env.$$"
  nodes_tmp="$VP_CONFIG_DIR/.nodes.db.$$"
  cp "$candidate_root/state.env" "$state_tmp" || return 1
  cp "$candidate_root/nodes.db" "$nodes_tmp" || { rm -f "$state_tmp"; return 1; }
  chmod 600 "$state_tmp" "$nodes_tmp"
  mv "$state_tmp" "$VP_STATE_FILE"
  mv "$nodes_tmp" "$VP_NODES_DB"
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

memory_snapshot() {
  current_file="$(cgroup_file memory.current 2>/dev/null || true)"
  max_file="$(cgroup_file memory.max 2>/dev/null || true)"
  stat_file="$(cgroup_file memory.stat 2>/dev/null || true)"
  swap_file="$(cgroup_file memory.swap.current 2>/dev/null || true)"

  if [ -n "$current_file" ]; then
    MEM_TOTAL_BYTES="$(cat "$current_file" 2>/dev/null || printf 0)"
    MEM_LIMIT_BYTES="$(cat "$max_file" 2>/dev/null || printf 0)"
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
  name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$name" 2>/dev/null || printf 'not-installed'
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$name" status >/dev/null 2>&1 && printf 'active' || printf 'not-installed'
  else
    printf 'unsupported'
  fi
}

node_count() {
  if [ -r "$VP_NODES_DB" ]; then
    awk 'NF { n++ } END { print n + 0 }' "$VP_NODES_DB" 2>/dev/null
  else
    printf '0'
  fi
}

show_status() {
  memory_snapshot
  printf '\nVPS-Node %s\n' "$VP_VERSION"
  printf '%s\n' '----------------------------------------'
  printf '代理核心：%s\n' "$(service_state vps-node-core)"
  printf 'Cloudflare Tunnel：%s\n' "$(service_state vps-node-tunnel)"
  printf '节点数量：%s\n' "$(node_count)"
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
  printf '%s\n\n' '----------------------------------------'
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

uninstall_project() {
  need_root || return 1
  warn "该操作将删除 VPS-Node 的状态和凭据。"
  printf '请输入 DELETE 确认：'
  read -r answer || true
  [ "$answer" = "DELETE" ] || { warn "已取消。"; return 0; }
  rm -rf "$VP_CONFIG_DIR" "$VP_DATA_DIR" "$VP_LOG_DIR" "$VP_LIB_DIR"
  rm -f /usr/local/bin/vp /usr/local/bin/vp.previous
  ok "VPS-Node 已卸载。"
}

menu() {
  while true; do
    show_status
    printf '1. 刷新状态\n'
    printf '2. 基础健康检查\n'
    printf '3. 初始化状态目录\n'
    printf '0. 退出\n'
    printf '请选择：'
    read -r choice || return 0
    case "$choice" in
      1) ;;
      2) doctor; printf '按回车继续...'; read -r _ || true ;;
      3) init_layout; printf '按回车继续...'; read -r _ || true ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

case "${1:-}" in
  init) init_layout ;;
  status) show_status ;;
  doctor|health|check) doctor ;;
  version|--version|-V) printf '%s\n' "$VP_VERSION" ;;
  uninstall) uninstall_project ;;
  debug-tx) shift; debug_transaction "$@" ;;
  help|-h|--help)
    printf '用法：vp [status|doctor|init|uninstall|version]\n'
    ;;
  '') menu ;;
  *) error "未知命令：$1"; exit 2 ;;
esac
