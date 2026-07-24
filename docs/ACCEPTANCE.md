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

网络候选参数只执行 `--dry-run`；实机验收不会修改主机全局 sysctl。

尚需在获得 SSH 授权后记录：

- Alpine/OpenRC 实际输出；
- 正式服务验收前后状态；
- Reality 回环认证与两路并发结果；
- 卸载后隔离文件和服务清理结果；
- 外部恢复包 SHA-256。
