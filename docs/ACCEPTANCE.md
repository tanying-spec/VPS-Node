# 唯一测试机隔离验收

允许的实机只有 `134.209.180.134`。不得在其他主机运行本验收。

脚本中的目标 IP 为常量，不能通过环境变量改成其他主机。旧的非隔离系统测试已经删除。

验收脚本使用：

- `/tmp/vps-node-acceptance-<pid>` 独立配置、数据、日志和二进制目录；
- `vps-node-acceptance-core-<pid>` 独立 OpenRC 服务名；
- 自动选择的独立 Reality 端口；
- 本机回环 Reality 协议认证与两路并发下载；
- 独立备份、诊断、轮换、订阅、卸载和外部恢复包。

运行前记录正式 `mihomo`、`cloudflared-tunnel` 状态，以及正式 init 脚本和 Mihomo 配置摘要。验收结束后必须完全一致，否则视为失败。

```sh
VP_TEST_MIHOMO_BIN=/正式内核路径 sh tests/isolated_acceptance.sh
```

如需同时验收 Cloudflare 公网备用线路，必须预先创建一条与正式业务完全独立的 Tunnel，并将其 Public Hostname 服务指向指定的固定源站端口：

```sh
VP_TEST_MIHOMO_BIN=/正式内核路径 \
VP_TEST_CLOUDFLARED_BIN=/正式cloudflared二进制路径 \
VP_TEST_TUNNEL_TOKEN_FILE=/root/独立测试.token \
VP_TEST_ARGO_HOST=独立测试域名 \
VP_TEST_ARGO_PATH=/独立测试路径 \
VP_TEST_ARGO_ORIGIN_PORT=独立固定端口 \
sh tests/isolated_acceptance.sh
```

五项 Tunnel 参数必须同时提供。脚本会在安装测试组件前拒绝已知正式 Token，以及出现在正式 `/etc/mihomo/nodes.db` 中的域名。Token、域名和链接不会写入验收证据。

网络候选参数只执行 `--dry-run`；实机验收不会修改主机全局 sysctl。

尚需在获得 SSH 授权后记录：

- Alpine/OpenRC 实际输出；
- 正式服务验收前后状态；
- Reality 回环认证与两路并发结果；
- 卸载后隔离文件和服务清理结果；
- 外部恢复包 SHA-256。

成功后会在 `${VP_ACCEPTANCE_EVIDENCE_DIR:-/root}` 创建脱敏验收证据及 `.sha256`。证据包含当前版本、测试时间、主机、Reality/轮换/恢复/自愈/卸载结论，以及正式服务状态、PID 和配置摘要是否保持不变；不包含节点链接、UUID、域名、Token 或密钥。
