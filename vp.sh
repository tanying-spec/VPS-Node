#!/bin/sh

set -u

VP_VERSION="0.1.0-dev.2"
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
VP_MIXED_PORT="${VP_MIXED_PORT:-17890}"
VP_CONTROLLER_PORT="${VP_CONTROLLER_PORT:-19090}"
VP_MIHOMO_API="${VP_MIHOMO_API:-https://api.github.com/repos/MetaCubeX/mihomo/releases/latest}"
VP_TUNNEL_BIN="${VP_TUNNEL_BIN:-$VP_LIB_DIR/bin/cloudflared}"
VP_TUNNEL_BACKUP_BIN="${VP_TUNNEL_BACKUP_BIN:-$VP_LIB_DIR/bin/cloudflared.previous}"
VP_TUNNEL_SERVICE="${VP_TUNNEL_SERVICE:-vps-node-tunnel}"
VP_TUNNEL_TOKEN_FILE="$VP_SECRETS_DIR/cloudflared.token"
VP_TUNNEL_RUNNER="$VP_LIB_DIR/bin/cloudflared-run"
VP_TUNNEL_METRICS_PORT="${VP_TUNNEL_METRICS_PORT:-22041}"
VP_CLOUDFLARED_API="${VP_CLOUDFLARED_API:-https://api.github.com/repos/cloudflare/cloudflared/releases/latest}"
VP_BACKUP_DIR="$VP_DATA_DIR/backups"

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

validate_state_candidate() {
  candidate_root="$VP_TX_ACTIVE/candidate"
  [ -f "$candidate_root/state.env" ] || { error "候选状态文件不存在。"; return 1; }
  [ -f "$candidate_root/nodes.db" ] || { error "候选节点数据库不存在。"; return 1; }
  [ -f "$candidate_root/credential-rotations.db" ] || { error "候选轮换数据库不存在。"; return 1; }
  if grep -Ev '^[A-Z][A-Z0-9_]*=[A-Za-z0-9._:/+-]*$|^$' "$candidate_root/state.env" >/dev/null 2>&1; then
    error "候选状态文件格式错误。"
    return 1
  fi
  if awk -F'|' 'NF && NF < 5 { bad=1 } END { exit bad ? 0 : 1 }' "$candidate_root/nodes.db" 2>/dev/null; then
    error "候选节点数据库存在不完整记录。"
    return 1
  fi
  if awk -F'|' 'NF && NF != 6 { bad=1 } END { exit bad ? 0 : 1 }' "$candidate_root/credential-rotations.db" 2>/dev/null; then
    error "候选凭据轮换数据库格式错误。"
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
  action="$1"
  name="$2"
  case "$(service_manager)" in
    systemd) systemctl "$action" "$name" ;;
    openrc) rc-service "$name" "$action" ;;
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

mihomo_download_url() {
  arch="$(detect_arch)" || return 1
  release_json="$(curl -fsSL --max-time 30 "$VP_MIHOMO_API")" || { error "无法访问 Mihomo Release API。"; return 1; }
  urls="$(printf '%s\n' "$release_json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${arch}.*compatible.*\.gz$" | head -n 1 || true)"
  [ -n "$url" ] || url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${arch}.*\.gz$" | head -n 1 || true)"
  [ -n "$url" ] || { error "Release 中没有 linux-$arch 内核。"; return 1; }
  printf '%s' "$url"
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
    download_url="$(mihomo_download_url)" || { rm -f "$binary_tmp" "$archive_tmp"; return 1; }
    info "正在下载 Mihomo 内核。"
    curl -fL --max-time 180 "$download_url" -o "$archive_tmp" || { error "Mihomo 下载失败。"; rm -f "$binary_tmp" "$archive_tmp"; return 1; }
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
  limit_mib="$(bytes_to_mib "$MEM_LIMIT_BYTES" | awk -F. '{print $1}')"
  case "$limit_mib" in ''|*[!0-9]*) limit_mib=0 ;; esac
  if [ "$limit_mib" -gt 0 ] && [ "$limit_mib" -le 160 ]; then
    gomemlimit=64MiB; gogc=60; gomaxprocs=1; profile=compact
  elif [ "$limit_mib" -gt 0 ] && [ "$limit_mib" -le 320 ]; then
    gomemlimit=128MiB; gogc=80; gomaxprocs=2; profile=balanced
  elif [ "$limit_mib" -gt 0 ] && [ "$limit_mib" -le 640 ]; then
    gomemlimit=256MiB; gogc=100; gomaxprocs=2; profile=standard
  else
    gomemlimit=512MiB; gogc=100; gomaxprocs=4; profile=performance
  fi
  {
    printf 'VP_MEMORY_PROFILE=%s\n' "$profile"
    printf 'GOMEMLIMIT=%s\n' "$gomemlimit"
    printf 'GOGC=%s\n' "$gogc"
    printf 'GOMAXPROCS=%s\n' "$gomaxprocs"
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
  {
    printf 'mixed-port: %s\n' "$VP_MIXED_PORT"
    printf "external-controller: '127.0.0.1:%s'\n" "$VP_CONTROLLER_PORT"
    printf 'allow-lan: false\nmode: rule\nlog-level: warning\nipv6: false\n'
    printf 'listeners:\n'
    while IFS='|' read -r proto name port uuid sni dest private_key public_key short_id; do
      [ -n "$proto" ] || continue
      old_uuid="$(awk -F'|' -v n="$name" -v now="$render_now" '$1==n && $5+0>now {print $3; exit}' "$rotations_file" 2>/dev/null)"
      case "$proto" in
        reality)
          printf "  - name: '%s'\n" "$(yaml_quote "$name")"
          printf '    type: vless\n    port: %s\n    listen: 0.0.0.0\n' "$port"
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

cloudflared_download_url() {
  case "$(detect_arch)" in
    amd64) cf_arch=amd64 ;;
    arm64) cf_arch=arm64 ;;
    armv7) cf_arch=arm ;;
    *) error "cloudflared 不支持当前架构。"; return 1 ;;
  esac
  release_json="$(curl -fsSL --max-time 30 "$VP_CLOUDFLARED_API")" || { error "无法访问 cloudflared Release API。"; return 1; }
  url="$(printf '%s\n' "$release_json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | grep -E "cloudflared-linux-${cf_arch}$" | head -n 1 || true)"
  [ -n "$url" ] || { error "Release 中没有适配的 cloudflared。"; return 1; }
  printf '%s' "$url"
}

install_tunnel_binary() {
  mkdir -p "$(dirname "$VP_TUNNEL_BIN")"
  tunnel_tmp="$(mktemp /tmp/vp-cloudflared.XXXXXX)" || return 1
  if [ -n "${VP_TUNNEL_SOURCE_BIN:-}" ]; then
    cp "$VP_TUNNEL_SOURCE_BIN" "$tunnel_tmp" || { rm -f "$tunnel_tmp"; return 1; }
  else
    url="$(cloudflared_download_url)" || { rm -f "$tunnel_tmp"; return 1; }
    info "正在下载 cloudflared。"
    curl -fL --max-time 180 "$url" -o "$tunnel_tmp" || { rm -f "$tunnel_tmp"; error "cloudflared 下载失败。"; return 1; }
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

tunnel_install() {
  need_root || return 1
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
  install_tunnel_binary || return 1
  printf '%s\n' "$token" > "$VP_TUNNEL_TOKEN_FILE"
  chmod 600 "$VP_TUNNEL_TOKEN_FILE"
  install_tunnel_service || return 1
  tunnel_service_restart || { error "Tunnel 启动失败。"; return 1; }
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
  ok "Argo 备用节点已创建：$name。"
  warn "请确认 Cloudflare Tunnel 公网主机名的服务指向 http://127.0.0.1:$port。"
}

install_core_service() {
  [ "${VP_SKIP_SERVICE:-0}" = "1" ] && return 0
  GOMEMLIMIT="$(awk -F= '$1=="GOMEMLIMIT"{print $2;exit}' "$VP_CORE_ENV")"
  GOGC="$(awk -F= '$1=="GOGC"{print $2;exit}' "$VP_CORE_ENV")"
  GOMAXPROCS="$(awk -F= '$1=="GOMAXPROCS"{print $2;exit}' "$VP_CORE_ENV")"
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
EnvironmentFile=$VP_CORE_ENV
ExecStart=$VP_CORE_BIN -d $VP_CONFIG_DIR -f $VP_CORE_CONFIG
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
command="$VP_CORE_BIN"
command_args="-d $VP_CONFIG_DIR -f $VP_CORE_CONFIG"
supervisor="supervise-daemon"
output_log="$VP_LOG_DIR/core.log"
error_log="$VP_LOG_DIR/core.err"
respawn_delay=2
respawn_max=0
rc_ulimit="-n 1048576"
export GOMEMLIMIT="$GOMEMLIMIT"
export GOGC="$GOGC"
export GOMAXPROCS="$GOMAXPROCS"
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

core_install() {
  need_root || return 1
  init_layout >/dev/null || return 1
  core_had_binary=0
  [ -x "$VP_CORE_BIN" ] && core_had_binary=1
  install_core_binary || return 1
  write_core_runtime_env || { rollback_core_binary "$core_had_binary"; return 1; }
  begin_state_transaction core-install || { rollback_core_binary "$core_had_binary"; return 1; }
  candidate_root="$VP_TX_ACTIVE/candidate"
  sed '/^ACTIVE_CORE=/d' "$candidate_root/state.env" > "$candidate_root/state.env.tmp"
  printf 'ACTIVE_CORE=mihomo\n' >> "$candidate_root/state.env.tmp"
  mv "$candidate_root/state.env.tmp" "$candidate_root/state.env"
  render_mihomo_config "$candidate_root/nodes.db" "$candidate_root/generated/mihomo.yaml" "$candidate_root/credential-rotations.db"
  if ! validate_state_candidate || ! "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$candidate_root/generated/mihomo.yaml" >/dev/null 2>&1; then
    abort_state_transaction
    rollback_core_binary "$core_had_binary"
    error "Mihomo 候选配置验证失败。"
    return 1
  fi
  activate_state_candidate || { abort_state_transaction; rollback_core_binary "$core_had_binary"; return 1; }
  install_core_service || { abort_state_transaction; rollback_core_binary "$core_had_binary"; return 1; }
  if ! core_service_restart; then
    abort_state_transaction
    rollback_core_binary "$core_had_binary"
    core_service_restart >/dev/null 2>&1 || true
    error "内核服务启动失败，已恢复旧状态。"
    return 1
  fi
  commit_state_transaction
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
  port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -lntu 2>/dev/null | awk -v p=":$port" '$5 ~ p "$" {found=1} END{exit !found}'
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
  case "$name$sni" in *'|'*|*' '*|*\"*|*\'*) error "名称或 SNI 包含非法字符。"; return 1 ;; esac
  port="$(choose_port "$requested_port")" || { error "端口不可用。"; return 1; }
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
  printf 'reality|%s|%s|%s|%s|%s:443|%s|%s|%s\n' "$name" "$port" "$uuid" "$sni" "$sni" "$private" "$public" "$short_id" >> "$candidate_root/nodes.db"
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
  ok "Reality 节点已创建：$name（端口 $port）。"
}

public_ip() {
  curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || printf 'YOUR_SERVER_IP'
}

show_nodes() {
  [ -s "$VP_NODES_DB" ] || { warn "当前没有节点。"; return 0; }
  awk -F'|' '{printf "%d. %s  协议=%s  端口=%s\n", NR,$2,$1,$3}' "$VP_NODES_DB"
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

show_node_link() {
  target="${1:-}"
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  IFS='|' read -r proto name port uuid sni dest private public short_id <<EOF
$record
EOF
  case "$proto" in
    reality)
      printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s\n' "$uuid" "$(public_ip)" "$port" "$sni" "$public" "$short_id" "$name"
      ;;
    argo)
      path="$sni"
      host="$dest"
      encoded_path="$(printf '%s' "$path" | sed 's#/#%2F#g')"
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&fp=chrome&type=ws&host=%s&path=%s#%s\n' "$uuid" "$host" "$host" "$host" "$encoded_path" "$name"
      ;;
    *) error "暂不支持该协议的分享链接。"; return 1 ;;
  esac
}

test_node_end_to_end() {
  target="${1:-}"
  [ -x "$VP_CORE_BIN" ] || { error "代理核心尚未安装。"; return 1; }
  [ -n "$target" ] || { error "请指定节点名称。"; return 1; }
  record="$(awk -F'|' -v n="$target" '$2==n{print;exit}' "$VP_NODES_DB" 2>/dev/null)"
  [ -n "$record" ] || { error "未找到节点。"; return 1; }
  IFS='|' read -r proto name port uuid value1 value2 private public short_id <<EOF
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
        server="${VP_TEST_SERVER:-$(public_ip)}"
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
  result="$(curl -sS -o /dev/null -w '%{http_code}|%{time_connect}|%{time_total}' --max-time 25 --proxy "http://127.0.0.1:$client_port" https://cp.cloudflare.com/generate_204 2>/dev/null || true)"
  IFS='|' read -r http_code connect_time total_time <<EOF
$result
EOF
  cleanup_node_test
  trap - EXIT HUP INT TERM
  if [ "$http_code" = "204" ]; then
    ok "节点 $name 端到端测试成功：连接 ${connect_time}s，总耗时 ${total_time}s。"
    return 0
  fi
  error "节点 $name 端到端测试失败（HTTP ${http_code:-无响应}）。"
  return 1
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
  tar -tzf "$1" 2>/dev/null | awk '
    /^\// {bad=1}
    /(^|\/)\.\.($|\/)/ {bad=1}
    END {exit bad ? 1 : 0}
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
  [ -r "$archive" ] || { error "备份文件不存在。"; return 1; }
  backup_archive_safe "$archive" || { error "备份包含不安全路径。"; return 1; }
  package="$(mktemp -d /tmp/vp-restore.XXXXXX)" || return 1
  cleanup_restore() { rm -rf "$package"; }
  trap cleanup_restore EXIT HUP INT TERM
  tar -xzf "$archive" -C "$package" || { cleanup_restore; trap - EXIT HUP INT TERM; error "备份无法解压。"; return 1; }
  [ -f "$package/manifest.env" ] && grep -q '^FORMAT_VERSION=1$' "$package/manifest.env" || { cleanup_restore; trap - EXIT HUP INT TERM; error "不支持该备份格式。"; return 1; }
  [ -f "$package/config/nodes.db" ] && [ -f "$package/config/state.env" ] || { cleanup_restore; trap - EXIT HUP INT TERM; error "备份缺少必要状态文件。"; return 1; }

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
  for temp_path in /tmp/vp-node-test.* /tmp/vp-backup.* /tmp/vp-restore.* /tmp/vp-repair-config.* /tmp/vp-reality-key.*; do
    [ -e "$temp_path" ] || continue
    if find "$temp_path" -maxdepth 0 -mmin +60 >/dev/null 2>&1 && [ -n "$(find "$temp_path" -maxdepth 0 -mmin +60 -print 2>/dev/null)" ]; then
      rm -rf "$temp_path"
      temp_removed=$((temp_removed + 1))
    fi
  done
  ok "维护清理完成：截断 $trimmed 个过大日志，删除 $temp_removed 个过期临时项。"
  layered_health_check
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

show_status() {
  memory_snapshot
  printf '\nVPS-Node %s\n' "$VP_VERSION"
  printf '%s\n' '----------------------------------------'
  printf '代理核心：%s\n' "$(service_state "$VP_CORE_SERVICE")"
  printf 'Cloudflare Tunnel：%s\n' "$(service_state vps-node-tunnel)"
  printf '节点数量：%s\n' "$(node_count)"
  printf '进行中凭据轮换：%s\n' "$(rotation_count active)"
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
      health_ok "内核配置层：Mihomo 配置有效。"
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

  if dns_probe; then
    health_ok "DNS 层：系统解析正常。"
  else
    health_error "DNS 层：系统 DNS 无法解析。"
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

  memory_events="$(cgroup_file memory.events 2>/dev/null || true)"
  oom_kills="$(awk '$1=="oom_kill"{print $2;exit}' "$memory_events" 2>/dev/null)"
  case "$oom_kills" in ''|*[!0-9]*) oom_kills=0 ;; esac
  if [ "$oom_kills" -gt 0 ]; then
    health_warn "资源层：cgroup 历史累计发生 $oom_kills 次 OOM Kill。"
  else
    health_ok "资源层：未记录 OOM Kill。"
  fi

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
  if [ -x "$VP_CORE_BIN" ] && [ -r "$VP_NODES_DB" ]; then
    repair_tmp="$(mktemp /tmp/vp-repair-config.XXXXXX)" || return 1
    render_mihomo_config "$VP_NODES_DB" "$repair_tmp"
    if "$VP_CORE_BIN" -t -d "$VP_CONFIG_DIR" -f "$repair_tmp" >/dev/null 2>&1; then
      if ! cmp -s "$repair_tmp" "$VP_CORE_CONFIG" 2>/dev/null; then
        mkdir -p "$VP_GENERATED_DIR"
        mv "$repair_tmp" "$VP_CORE_CONFIG"
        chmod 600 "$VP_CORE_CONFIG"
        repaired=$((repaired + 1))
      else
        rm -f "$repair_tmp"
      fi
      if [ "${VP_SKIP_SERVICE:-0}" != "1" ] && ! core_process_running; then
        core_service_restart && repaired=$((repaired + 1))
      fi
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
  core-install|install-core) core_install ;;
  reality-add|add-reality) shift; reality_add "$@" ;;
  tunnel-install|install-tunnel) shift; tunnel_install "$@" ;;
  argo-add|add-argo) shift; argo_add "$@" ;;
  nodes|list) show_nodes ;;
  link) shift; show_node_link "$@" ;;
  test-node|test) shift; test_node_end_to_end "$@" ;;
  rotate|rotate-credential) shift; rotate_credential "$@" ;;
  rotations|rotation-status) show_rotations ;;
  rotate-finalize|rotation-finalize) shift; finalize_rotation "$@" ;;
  backup) shift; create_backup "$@" ;;
  restore) shift; restore_backup "$@" ;;
  maintain|maintenance) maintenance_mode ;;
  status) show_status ;;
  doctor) doctor ;;
  health|check) layered_health_check ;;
  repair|fix) safe_repair ;;
  version|--version|-V) printf '%s\n' "$VP_VERSION" ;;
  uninstall) uninstall_project ;;
  debug-tx) shift; debug_transaction "$@" ;;
  help|-h|--help)
    printf '用法：vp [status|doctor|health|repair|maintain|init|core-install|reality-add|tunnel-install|argo-add|nodes|link|test-node|rotate|rotations|rotate-finalize|backup|restore|uninstall|version]\n'
    ;;
  '') menu ;;
  *) error "未知命令：$1"; exit 2 ;;
esac
