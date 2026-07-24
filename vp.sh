#!/bin/sh

set -u

VP_VERSION="0.1.0-dev.1"
VP_CONFIG_DIR="${VP_CONFIG_DIR:-/etc/vps-node}"
VP_DATA_DIR="${VP_DATA_DIR:-/var/lib/vps-node}"
VP_LOG_DIR="${VP_LOG_DIR:-/var/log/vps-node}"
VP_LIB_DIR="${VP_LIB_DIR:-/usr/local/lib/vps-node}"
VP_NODES_DB="$VP_CONFIG_DIR/nodes.db"
VP_STATE_FILE="$VP_CONFIG_DIR/state.env"
VP_SECRETS_DIR="$VP_CONFIG_DIR/secrets"
VP_GENERATED_DIR="$VP_CONFIG_DIR/generated"
VP_TX_DIR="$VP_CONFIG_DIR/transactions"

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
  : > "$VP_NODES_DB" 2>/dev/null || true
  [ -f "$VP_STATE_FILE" ] || printf 'SCHEMA_VERSION=1\nACTIVE_CORE=none\n' > "$VP_STATE_FILE"
  chmod 700 "$VP_CONFIG_DIR" "$VP_SECRETS_DIR" "$VP_TX_DIR"
  chmod 600 "$VP_NODES_DB" "$VP_STATE_FILE"
  ok "VPS-Node 状态目录已初始化。"
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
  help|-h|--help)
    printf '用法：vp [status|doctor|init|uninstall|version]\n'
    ;;
  '') menu ;;
  *) error "未知命令：$1"; exit 2 ;;
esac
