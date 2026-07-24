#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/vps-node-install-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

mkdir -p "$TMP/bin"
cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
[ "${2:-}" = "xray" ] && { printf '4321\n'; exit 0; }
exit 1
EOF
cat > "$TMP/bin/ss" <<'EOF'
#!/bin/sh
printf 'tcp LISTEN 0 128 127.0.0.1:17890 0.0.0.0:*\n'
EOF
chmod 755 "$TMP/bin/pgrep" "$TMP/bin/ss"

if (cd "$ROOT" && PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 \
  VP_INSTALL_PATH="$TMP/install/blocked-vp" sh ./install.sh --check >/dev/null 2>&1); then
  printf 'unguarded local install source unexpectedly accepted\n' >&2
  exit 1
fi
if (cd "$ROOT" && PATH="$TMP/bin:$PATH" VP_REPO=someone/else \
  VP_INSTALL_PATH="$TMP/install/blocked-vp" sh ./install.sh --check >/dev/null 2>&1); then
  printf 'unapproved custom install repository unexpectedly accepted\n' >&2
  exit 1
fi

check_output="$(cd "$ROOT" && PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 VP_ALLOW_TEST_HOOKS=1 \
  VP_INSTALL_PATH="$TMP/install/vp" sh ./install.sh --check)"
printf '%s\n' "$check_output" | grep -q '现有 xray 进程'
printf '%s\n' "$check_output" | grep -q 'Mihomo 默认内部端口 17890 已占用'
[ ! -e "$TMP/install/vp" ]

dry_output="$(cd "$ROOT" && PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 VP_ALLOW_TEST_HOOKS=1 \
  VP_INSTALL_PATH="$TMP/install/vp" sh ./install.sh --dry-run)"
printf '%s\n' "$dry_output" | grep -q '明确不会执行'
printf '%s\n' "$dry_output" | grep -q '不停止现有 Mihomo、Xray、sing-box 或 cloudflared'
[ ! -e "$TMP/install/vp" ]

cd "$ROOT"
PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 VP_ALLOW_TEST_HOOKS=1 VP_INSTALL_PATH="$TMP/install/vp" \
VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr" \
sh ./install.sh >/dev/null
[ -x "$TMP/install/vp" ]
[ -f "$TMP/etc/state.env" ]
"$TMP/install/vp" version | grep -Eq '^0\.'

first_install_hash="$(sha256sum "$TMP/install/vp" | awk '{print $1}')"
PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 VP_ALLOW_TEST_HOOKS=1 VP_INSTALL_PATH="$TMP/install/vp" \
VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr" \
sh ./install.sh >/dev/null
[ "$(sha256sum "$TMP/install/vp.previous" | awk '{print $1}')" = "$first_install_hash" ]
(cd "$TMP/install" && sha256sum -c vp.previous.sha256 >/dev/null)
[ "$(stat -c '%a' "$TMP/install/vp.previous.sha256")" = 600 ]

current_before_fail="$(sha256sum "$TMP/install/vp" | awk '{print $1}')"
backup_before_fail="$(sha256sum "$TMP/install/vp.previous" | awk '{print $1}')"
sidecar_before_fail="$(sha256sum "$TMP/install/vp.previous.sha256" | awk '{print $1}')"
if PATH="$TMP/bin:$PATH" VP_LOCAL_SOURCE=1 VP_ALLOW_TEST_HOOKS=1 VP_TEST_INIT_FAIL=1 \
  VP_INSTALL_PATH="$TMP/install/vp" VP_CONFIG_DIR="$TMP/etc" VP_DATA_DIR="$TMP/lib" \
  VP_LOG_DIR="$TMP/log" VP_LIB_DIR="$TMP/usr" sh ./install.sh >/dev/null 2>&1; then
  printf 'injected installer initialization failure unexpectedly succeeded\n' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/install/vp" | awk '{print $1}')" = "$current_before_fail" ]
[ "$(sha256sum "$TMP/install/vp.previous" | awk '{print $1}')" = "$backup_before_fail" ]
[ "$(sha256sum "$TMP/install/vp.previous.sha256" | awk '{print $1}')" = "$sidecar_before_fail" ]

printf 'install-smoke: ok\n'
