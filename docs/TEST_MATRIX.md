# 测试矩阵与证据等级

所有需要真实 Mihomo、OpenRC、网络出口或资源压力的实机测试只能在 `134.209.180.134` 运行。当前版本的实机验收尚未执行；SSH 公钥授权仍缺失。

## 当前版本已有证据

| 类别 | 当前证据 | 结论 |
| --- | --- | --- |
| Shell 语法、安装与初始化 | GitHub Actions：`tests/smoke.sh`、`tests/install_smoke.sh` | 已通过 |
| 配置事务、失败回滚、SIGKILL 恢复 | `tests/smoke.sh` 故障注入 | 已通过 |
| 数据库约束、配置漂移、自愈互斥 | `tests/smoke.sh` | 已通过 |
| DNS、内存/CPU 档位、端口冲突 | 模拟 cgroup、DNS 和监听端口 | 已通过模拟验证 |
| 备份、恢复、恶意归档拒绝 | 真实 tar 往返与攻击样本 | 已通过 |
| 安装、更新、回滚、来源与降级保护 | 本地候选源、顶层 SHA 样本、同版本异内容/隐式降级拒绝、显式降级、初始化失败恢复、CLI/回滚文件交换中途恢复及 SHA-256 篡改故障注入 | 已通过 |
| 可恢复卸载及文件残留 | 隔离目录自动测试 | 已通过 |
| Reality 真实认证与并发 | `tests/isolated_acceptance.sh` | 待唯一测试机执行 |
| Alpine/OpenRC 服务生命周期 | `tests/isolated_acceptance.sh` | 待唯一测试机执行 |
| 正式 Mihomo/cloudflared 前后不变 | 状态及配置/init 哈希对比 | 待唯一测试机执行 |
| 64–2048 MiB 真实 Mihomo 档位 | `tests/memory_profiles.sh`（不可绕过主机锁） | 待唯一测试机执行 |
| Cloudflare Tunnel 独立公网入口 | 需要独立测试 Tunnel 凭据和域名 | 尚缺当前版本证据 |
| IPv6 Reality 外部可达性 | 需要测试机公网 IPv6 与外部复核 | 尚缺当前版本证据 |

## 历史结果的处理

早期开发阶段曾记录 Reality/VLESS-WS、Cloudflare Tunnel、4×10 MiB 压力和约 16 MiB/s Tunnel 吞吐结果。这些结果可以作为设计参考，但不是 `0.2.0-dev.34` 当前代码的验收证据，因此不用于宣称当前版本已通过。

旧的 `system_argo_test.sh` 和 `system_pressure_test.sh` 会正式安装管理脚本并停止已有服务，不符合“隔离且正式服务前后不变”的硬约束，已删除。后续实机证据只能由锁定主机的隔离验收入口产生。

ShellCheck 在极低内存 cgroup 中作为额外工具运行时曾被工具自身 OOM 杀死；当前 CI 使用 `sh -n`、校验和及可移植烟雾测试，不把该历史事件计为项目服务故障。
