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
trap 'rm -f "$tmp"' EXIT HUP INT TERM

if [ -f "./vp.sh" ]; then
  cp ./vp.sh "$tmp"
else
  url="https://raw.githubusercontent.com/$REPO/$REF/vp.sh"
  curl -fsSL "$url" -o "$tmp" || die "下载安装程序失败。"
fi

sh -n "$tmp" || die "脚本语法检查失败。"
chmod 755 "$tmp"
mkdir -p "$(dirname "$INSTALL_PATH")"
[ -f "$INSTALL_PATH" ] && cp "$INSTALL_PATH" "$INSTALL_PATH.previous"
mv "$tmp" "$INSTALL_PATH"
trap - EXIT HUP INT TERM

"$INSTALL_PATH" init
ok "安装完成。输入 vp 打开管理面板。"

