#!/bin/sh

set -eu

SRC="${1:-/tmp/vps-node-pressure-src}"
project_installed=0
client_pid=""
monitor_pid=""
restore() {
  [ -n "$monitor_pid" ] && kill "$monitor_pid" 2>/dev/null || true
  [ -n "$client_pid" ] && kill "$client_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  wait "$client_pid" 2>/dev/null || true
  if [ "$project_installed" = 1 ] && [ -x /usr/local/bin/vp ]; then
    VP_UNINSTALL_CONFIRM=DELETE /usr/local/bin/vp uninstall >/dev/null 2>&1 || true
  fi
  rm -rf "$SRC"
}
trap restore EXIT HUP INT TERM

cd "$SRC"
sh install.sh >/dev/null
project_installed=1
VP_CORE_SOURCE_BIN=/usr/local/bin/mihomo vp core-install >/dev/null
vp reality-add pressure-test 25445 www.amd.com >/dev/null
vp_pid="$(pidof mihomo | tr ' ' '\n' | while read p; do cmdline="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"; case "$cmdline" in *'/etc/vps-node'*) echo "$p"; break ;; esac; done)"
[ -n "$vp_pid" ]

IFS='|' read -r proto name port uuid sni dest private public sid < /etc/vps-node/nodes.db
cat > "$SRC/client.yaml" <<EOF
mixed-port: 27904
allow-lan: false
mode: rule
log-level: warning
proxies:
  - name: pressure
    type: vless
    server: 127.0.0.1
    port: $port
    uuid: $uuid
    network: tcp
    tls: true
    servername: $sni
    client-fingerprint: chrome
    reality-opts:
      public-key: $public
      short-id: $sid
proxy-groups:
  - name: FINAL
    type: select
    proxies: [pressure]
rules:
  - MATCH,FINAL
EOF
mkdir -p "$SRC/client-data"
/usr/local/lib/vps-node/bin/mihomo -d "$SRC/client-data" -f "$SRC/client.yaml" > "$SRC/client.log" 2>&1 &
client_pid=$!
sleep 2

peak_file="$SRC/peak"
printf '0\n' > "$peak_file"
(
  while kill -0 "$client_pid" 2>/dev/null; do
    current="$(cat /sys/fs/cgroup/memory.current 2>/dev/null || printf 0)"
    peak="$(cat "$peak_file")"
    [ "$current" -gt "$peak" ] && printf '%s\n' "$current" > "$peak_file"
    sleep .1
  done
) &
monitor_pid=$!

curl_pids=""
for n in 1 2 3 4; do
  curl -fsS --max-time 45 --proxy http://127.0.0.1:27904 \
    -o /dev/null "https://speed.cloudflare.com/__down?bytes=10485760" > "$SRC/curl-$n.log" 2>&1 &
  curl_pids="$curl_pids $!"
done
for curl_pid in $curl_pids; do wait "$curl_pid"; done
sleep 1
peak="$(cat "$peak_file")"
printf 'pressure-peak-bytes=%s\n' "$peak"
printf 'pressure-peak-mib=%.1f\n' "$(awk -v n="$peak" 'BEGIN{print n/1048576}')"
printf 'pressure-result=4x10MiB\n'
[ "$peak" -lt 128000000 ]

kill "$client_pid" 2>/dev/null || true
wait "$client_pid" 2>/dev/null || true
client_pid=""
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
monitor_pid=""
VP_UNINSTALL_CONFIRM=DELETE vp uninstall >/dev/null
project_installed=0
printf 'pressure-uninstall=ok\n'
