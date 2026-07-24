#!/bin/sh

set -eu

REPO="${VP_REPO:-tanying-spec/VPS-Node}"
REF="${VP_REF:-main}"
INSTALL_PATH="${VP_INSTALL_PATH:-/usr/local/bin/vp}"
INSTALL_BACKUP_PATH="${VP_INSTALL_BACKUP_PATH:-$INSTALL_PATH.previous}"
INSTALL_BACKUP_SHA256="${VP_INSTALL_BACKUP_SHA256:-$INSTALL_BACKUP_PATH.sha256}"
MODE=install

die() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
info() { printf '\033[36m[*]\033[0m %s\n' "$*"; }

case "${1:-}" in
  '') ;;
  --check) MODE=check ;;
  --dry-run) MODE=dry-run ;;
  -h|--help)
    printf '用法：install.sh [--check|--dry-run]\n'
    printf '  --check    只检查系统、网络、进程和端口冲突\n'
    printf '  --dry-run  显示检查结果和安装计划，不写入文件\n'
    exit 0
    ;;
  *) die "未知参数：$1" ;;
esac
[ "$#" -le 1 ] || die "安装脚本只接受一个参数。"

PREFLIGHT_ERRORS=0
PREFLIGHT_WARNINGS=0

preflight_error() { warn "阻止安装：$*"; PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1)); }
preflight_warn() { warn "$*"; PREFLIGHT_WARNINGS=$((PREFLIGHT_WARNINGS + 1)); }

process_count() {
  process_name="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x "$process_name" 2>/dev/null | awk 'NF{n++}END{print n+0}'
  else
    ps 2>/dev/null | awk -v n="$process_name" '$0 ~ n && $0 !~ /awk/{c++}END{print c+0}'
  fi
}

port_in_use_install() {
  probe_port="$1"
  command -v ss >/dev/null 2>&1 || return 2
  ss -H -lntu 2>/dev/null | awk -v p=":$probe_port" '$5 ~ p "$"{found=1}END{exit found?0:1}'
}

system_preflight() {
  info "安装前环境预检"
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64|aarch64|arm64|armv7l|armv7|riscv64) ok "CPU 架构受支持。" ;;
    *) preflight_error "不支持的 CPU 架构：$(uname -m 2>/dev/null || printf unknown)。" ;;
  esac

  if [ -r /etc/os-release ]; then
    os_name="$(awk -F= '$1=="PRETTY_NAME"{gsub(/^"|"$/, "", $2);print $2;exit}' /etc/os-release)"
    ok "系统：${os_name:-Linux}"
  else
    preflight_warn "无法读取系统版本，仍将按通用 Linux 检查。"
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    ok "服务管理器：systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    ok "服务管理器：OpenRC"
  else
    preflight_warn "未检测到正在工作的 systemd 或 OpenRC；管理脚本可以安装，但节点服务需要手动处理。"
  fi

  memory_kib="$(awk '$1=="MemTotal:"{print $2;exit}' /proc/meminfo 2>/dev/null || printf 0)"
  case "$memory_kib" in ''|*[!0-9]*) memory_kib=0 ;; esac
  memory_mib=$((memory_kib / 1024))
  if [ "$memory_mib" -gt 0 ] && [ "$memory_mib" -lt 32 ]; then
    preflight_error "可识别内存仅 ${memory_mib} MiB，低于最低安全值 32 MiB。"
  elif [ "$memory_mib" -gt 0 ] && [ "$memory_mib" -lt 64 ]; then
    preflight_warn "内存仅 ${memory_mib} MiB，建议至少 64 MiB。"
  else
    ok "内存：${memory_mib:-未知} MiB"
  fi

  install_parent="$(dirname "$INSTALL_PATH")"
  [ -d "$install_parent" ] || install_parent=/usr/local
  [ -d "$install_parent" ] || install_parent=/
  disk_kib="$(df -Pk "$install_parent" 2>/dev/null | awk 'NR==2{print $4;exit}')"
  case "$disk_kib" in ''|*[!0-9]*) disk_kib=0 ;; esac
  if [ "$disk_kib" -gt 0 ] && [ "$disk_kib" -lt 16384 ]; then
    preflight_error "安装位置可用空间不足 16 MiB。"
  else
    ok "安装位置可用空间：$((disk_kib / 1024)) MiB"
  fi

  if command -v curl >/dev/null 2>&1; then
    ok "下载工具 curl 已存在。"
  elif command -v apk >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
    preflight_warn "尚未安装 curl；正式安装时会自动安装。"
  else
    preflight_error "缺少 curl，且没有 apk/apt-get 可用于安装。"
  fi

  for existing_process in mihomo xray sing-box cloudflared; do
    existing_count="$(process_count "$existing_process")"
    case "$existing_count" in ''|*[!0-9]*) existing_count=0 ;; esac
    if [ "$existing_count" -gt 0 ]; then
      preflight_warn "检测到 $existing_count 个现有 $existing_process 进程；VPS-Node 不会停止或修改它们。"
    fi
  done

  port_tool=available
  for reserved_port in 17890 19090 22041; do
    if port_in_use_install "$reserved_port"; then
      case "$reserved_port" in
        17890|19090) preflight_warn "Mihomo 默认内部端口 $reserved_port 已占用；安装核心时会自动选择并保存空闲端口。" ;;
        *) preflight_warn "Cloudflare Tunnel 指标端口 $reserved_port 已占用；安装 Tunnel 时会自动选择并保存空闲端口。" ;;
      esac
    else
      probe_status=$?
      [ "$probe_status" -eq 2 ] && port_tool=missing
    fi
  done
  [ "$port_tool" = available ] || preflight_warn "缺少 ss，暂时无法检查默认保留端口。"

  if [ -e "$INSTALL_PATH" ]; then
    preflight_warn "检测到现有管理脚本；正式安装会先备份为 $INSTALL_BACKUP_PATH 并校验。"
  else
    ok "未发现旧的 VPS-Node 管理脚本。"
  fi
  printf '预检结果：%s 个阻止项，%s 个提醒。\n' "$PREFLIGHT_ERRORS" "$PREFLIGHT_WARNINGS"
}

network_preflight() {
  if [ "${VP_LOCAL_SOURCE:-0}" = "1" ]; then
    [ -f "./vp.sh" ] && [ -f "./vp.sh.sha256" ] || { preflight_error "本地测试源缺少 vp.sh 或 SHA-256。"; return 0; }
    ok "本地测试源文件存在；跳过 GitHub 连通性测试。"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    preflight_warn "没有 curl，未执行 GitHub 连通性测试。"
    return 0
  fi
  if curl -fsSL --max-time 12 "https://api.github.com/repos/$REPO/commits/$REF" -o /dev/null; then
    ok "GitHub API 与项目仓库可访问。"
  else
    preflight_error "无法连接 GitHub API 或项目仓库。"
  fi
}

show_install_plan() {
  printf '\n安装计划：\n'
  printf '  1. 从 GitHub 解析 %s/%s 的精确提交\n' "$REPO" "$REF"
  printf '  2. 下载 vp.sh 与 SHA-256 并执行语法校验\n'
  printf '  3. 将管理脚本安装到 %s\n' "$INSTALL_PATH"
  printf '  4. 如存在旧脚本，保留为 %s 并生成 SHA-256\n' "$INSTALL_BACKUP_PATH"
  printf '  5. 初始化 VPS-Node 自己的状态目录\n'
  printf '\n明确不会执行：\n'
  printf '  - 不安装或启动 Mihomo/cloudflared 内核\n'
  printf '  - 不停止现有 Mihomo、Xray、sing-box 或 cloudflared\n'
  printf '  - 不修改防火墙、SSH、系统 DNS 或现有代理配置\n'
}

system_preflight
network_preflight

if [ "$MODE" = check ]; then
  [ "$PREFLIGHT_ERRORS" -eq 0 ] || exit 1
  ok "检查完成，未写入任何文件。"
  exit 0
fi

if [ "$MODE" = dry-run ]; then
  show_install_plan
  [ "$PREFLIGHT_ERRORS" -eq 0 ] || exit 1
  ok "预览完成，未写入任何文件。"
  exit 0
fi

[ "$(id -u)" = "0" ] || die "请切换到 root 后重新执行安装命令。"
[ "$PREFLIGHT_ERRORS" -eq 0 ] || die "安装前检查未通过，未修改系统。"
show_install_plan

if ! command -v curl >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl
  else
    die "未找到 apk 或 apt-get，无法自动安装 curl。"
  fi
fi

tmp="$(mktemp /tmp/vp-install.XXXXXX)" || die "无法创建临时文件。"
checksum_tmp="$(mktemp /tmp/vp-install-sha.XXXXXX)" || { rm -f "$tmp"; die "无法创建校验临时文件。"; }
trap 'rm -f "$tmp" "$checksum_tmp"' EXIT HUP INT TERM

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

if [ "${VP_LOCAL_SOURCE:-0}" = "1" ] && [ -f "./vp.sh" ]; then
  cp ./vp.sh "$tmp"
  [ -f "./vp.sh.sha256" ] && cp ./vp.sh.sha256 "$checksum_tmp" || printf '%s  vp.sh\n' "$(sha256_file "$tmp")" > "$checksum_tmp"
else
  commit_json="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$REPO/commits/$REF")" || die "无法取得精确提交。"
  commit_sha="$(printf '%s\n' "$commit_json" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]\{40\}\)".*/\1/p' | head -n 1)"
  case "$commit_sha" in ''|*[!0-9a-fA-F]*) die "GitHub 返回的提交 SHA 无效。" ;; esac
  [ "${#commit_sha}" -eq 40 ] || die "GitHub 返回的提交 SHA 长度无效。"
  url="https://raw.githubusercontent.com/$REPO/$commit_sha"
  curl -fsSL --max-time 30 "$url/vp.sh" -o "$tmp" || die "下载安装程序失败。"
  curl -fsSL --max-time 15 "$url/vp.sh.sha256" -o "$checksum_tmp" || die "下载 SHA-256 文件失败。"
fi

expected="$(awk 'NR==1{print tolower($1)}' "$checksum_tmp")"
actual="$(sha256_file "$tmp" 2>/dev/null | tr 'A-F' 'a-f')"
case "$expected" in ''|*[!0-9a-f]*) die "SHA-256 文件格式无效。" ;; esac
[ "${#expected}" -eq 64 ] && [ "$expected" = "$actual" ] || die "vp.sh SHA-256 校验失败。"
sh -n "$tmp" || die "脚本语法检查失败。"
chmod 755 "$tmp"
mkdir -p "$(dirname "$INSTALL_PATH")"
if [ -f "$INSTALL_PATH" ]; then
  cp "$INSTALL_PATH" "$INSTALL_BACKUP_PATH" || die "无法备份现有管理脚本。"
  backup_hash="$(sha256_file "$INSTALL_BACKUP_PATH")" || die "无法校验现有管理脚本备份。"
  printf '%s  %s\n' "$backup_hash" "$(basename "$INSTALL_BACKUP_PATH")" > "$INSTALL_BACKUP_SHA256"
  chmod 600 "$INSTALL_BACKUP_SHA256"
else
  rm -f "$INSTALL_BACKUP_PATH" "$INSTALL_BACKUP_SHA256"
fi
mv "$tmp" "$INSTALL_PATH"
rm -f "$checksum_tmp"
trap - EXIT HUP INT TERM

"$INSTALL_PATH" init
ok "安装完成。输入 vp 打开管理面板。"
