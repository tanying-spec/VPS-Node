#!/bin/sh

set -eu

SRC="${1:-/tmp/vps-node-argo-src}"
project_installed=0
old_mihomo_was_running=0
old_tunnel_was_running=0
rc-service mihomo status >/dev/null 2>&1 && old_mihomo_was_running=1
rc-service cloudflared-tunnel status >/dev/null 2>&1 && old_tunnel_was_running=1

restore_original() {
  if [ "$project_installed" = 1 ] && [ -x /usr/local/bin/vp ]; then
    VP_UNINSTALL_CONFIRM=DELETE /usr/local/bin/vp uninstall >/dev/null 2>&1 || true
  fi
  [ "$old_mihomo_was_running" = 1 ] && rc-service mihomo restart >/dev/null 2>&1 || true
  [ "$old_tunnel_was_running" = 1 ] && rc-service cloudflared-tunnel restart >/dev/null 2>&1 || true
  rm -rf "$SRC"
}
trap restore_original EXIT HUP INT TERM

record="$(awk -F'|' '$1=="vless-ws" && $7=="argo"{print;exit}' /etc/mihomo/nodes.db)"
[ -n "$record" ]
IFS='|' read -r old_proto old_name origin_port old_uuid ws_path public_host mode extra1 extra2 <<EOF
$record
EOF
[ -n "$origin_port" ] && [ -n "$ws_path" ] && [ -n "$public_host" ]
[ -s /etc/cloudflared/token ]

oom_before="$(awk '$1=="oom_kill"{print $2}' /sys/fs/cgroup/memory.events)"
cd "$SRC"
sh install.sh >/dev/null
project_installed=1
VP_CORE_SOURCE_BIN=/usr/local/bin/mihomo vp core-install >/dev/null
rc-service mihomo stop >/dev/null
vp argo-add system-argo "$origin_port" "$public_host" "$ws_path" >/tmp/vps-node-argo-add.log
VP_TUNNEL_SOURCE_BIN=/usr/local/bin/cloudflared vp tunnel-install /etc/cloudflared/token >/tmp/vps-node-argo-tunnel.log

i=0
edges=0
while [ "$i" -lt 20 ]; do
  sleep 1
  edges="$(curl -fsS --max-time 2 http://127.0.0.1:22041/metrics 2>/dev/null | awk '/^cloudflared_tunnel_ha_connections /{sum+=$2}END{print sum+0}')"
  [ "$edges" -gt 0 ] && break
  i=$((i + 1))
done
printf 'new-tunnel-edges=%s\n' "$edges"
[ "$edges" -gt 0 ]

rc-service cloudflared-tunnel stop >/dev/null
sleep 2
vp test-node system-argo >/tmp/vps-node-argo-public1.log
printf 'public-before-kill='; tail -1 /tmp/vps-node-argo-public1.log

old_pid=""
for pid in $(pidof cloudflared); do
  cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmdline" in *'22041'*) old_pid="$pid"; break ;; esac
done
[ -n "$old_pid" ]
kill -9 "$old_pid"

new_pid=""
i=0
while [ "$i" -lt 15 ]; do
  sleep 1
  for pid in $(pidof cloudflared); do
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    case "$cmdline" in *'22041'*) new_pid="$pid"; break ;; esac
  done
  [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && break
  i=$((i + 1))
done
printf 'tunnel-respawned=%s\n' "$([ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && echo yes || echo no)"
[ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ]

i=0
edges=0
while [ "$i" -lt 20 ]; do
  sleep 1
  edges="$(curl -fsS --max-time 2 http://127.0.0.1:22041/metrics 2>/dev/null | awk '/^cloudflared_tunnel_ha_connections /{sum+=$2}END{print sum+0}')"
  [ "$edges" -gt 0 ] && break
  i=$((i + 1))
done
printf 'edges-after-respawn=%s\n' "$edges"
[ "$edges" -gt 0 ]
vp test-node system-argo >/tmp/vps-node-argo-public2.log
printf 'public-after-kill='; tail -1 /tmp/vps-node-argo-public2.log

VP_UNINSTALL_CONFIRM=DELETE vp uninstall >/dev/null
project_installed=0
rc-service mihomo start >/dev/null
rc-service cloudflared-tunnel start >/dev/null
sleep 5
rc-service mihomo status >/dev/null
rc-service cloudflared-tunnel status >/dev/null
oom_after="$(awk '$1=="oom_kill"{print $2}' /sys/fs/cgroup/memory.events)"
printf 'oom-delta=%s\n' "$((oom_after - oom_before))"
printf 'original-restored=yes\n'
rm -rf "$SRC"
trap - EXIT HUP INT TERM

