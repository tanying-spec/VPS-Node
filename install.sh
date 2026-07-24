#!/bin/sh

set -eu

REPO="${VP_REPO:-tanying-spec/VPS-Node}"
REF="${VP_REF:-main}"
INSTALL_PATH="${VP_INSTALL_PATH:-/usr/local/bin/vp}"

die() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; }

[ "$(id -u)" = "0" ] || die "请切换到 root 后重新执行安装命令。"

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
[ -f "$INSTALL_PATH" ] && cp "$INSTALL_PATH" "$INSTALL_PATH.previous"
mv "$tmp" "$INSTALL_PATH"
rm -f "$checksum_tmp"
trap - EXIT HUP INT TERM

"$INSTALL_PATH" init
ok "安装完成。输入 vp 打开管理面板。"
