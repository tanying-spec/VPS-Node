# 唯一测试机实机证据

所有记录仅来自授权主机 `134.209.180.134`，证据内容经过脱敏且由 SHA-256 sidecar 校验。原始证据保存在测试机 `/root`，本文件只记录可公开复核的结论和摘要哈希。

## 0.2.0-dev.88

执行时间：2026-07-24 22:48–22:51 UTC。

隔离功能验收：

- Reality IPv4 回环认证与两路并发：`2/2`。
- 凭据轮换、备份恢复、自愈、诊断脱敏、可恢复卸载：全部通过。
- 正式 Mihomo 与 Cloudflare Tunnel 的服务状态、PID、二进制、命令行、配置、init 定义和敏感状态摘要：前后不变。
- 公网 IPv6：测试机不具备，记录为 `not-available`，不计为通过。
- 独立 Cloudflare Tunnel：本批次未提供独立 Token/域名，因此未执行，不能复用正式 Tunnel 冒充证据。
- 原始脱敏证据 SHA-256：`e8a2e88388d86877d6aad133294c0c7a9bb24718d92724d7955bbea39f377ce6`。

真实 DNS 档位：

- `1.1.1.1/8.8.8.8` 实际可达时保持公共 DNS 模式。
- 使用不可达保留地址时自动回退系统 DNS。
- 两个场景分别启动真实 Mihomo 并完成域名代理检查，共两次真实内核启动、两次代理 DNS 检查。
- 正式服务及敏感状态摘要前后不变。
- 摘要 SHA-256：`3cf84ae5fcaabee4795a9ddc701289e81475d6383a41e45eaa0630e1ee39ca64`。
- CSV SHA-256：`8267af447b2514ebee7b0c6bef6a76a6bca17de93c6dbc315014fb1b8a0b68b2`。

资源档位环境结论：

- cgroup v2 暴露了 `memory` 与 `cpu` 控制器，但未向 SSH 测试进程委派；根 cgroup 同时包含 PID 1，不能在不改变容器运行模型的情况下安全启用子树控制器。
- `memory_profiles.sh` 明确失败为 `memory controller is not delegated`。
- `cpu_profiles.sh` 明确失败为 `cpu controller is unavailable`。
- 以上结果是环境门槛未满足，不得写成算法通过或用模拟结果替代。

## 0.2.0-dev.89

执行时间：2026-07-24 22:57 UTC。

- 当前脚本 SHA-256：`d8c353c6b314d302b4bc619c5050c48285459dae7efa5a097409e9e136313e43`。
- Reality IPv4 回环认证与两路并发：`2/2`。
- 凭据轮换、备份恢复、自愈、诊断脱敏、可恢复卸载：全部通过。
- 正式 Mihomo 与 Cloudflare Tunnel 的服务状态、PID、二进制、命令行、配置、init 定义和敏感状态摘要：前后不变。
- 公网 IPv6：`not-available`；独立 Cloudflare Tunnel：`not-requested`，两项均未冒充通过。
- 隔离验收原始脱敏证据 SHA-256：`c653711f9df1dc7ee60dacf98f61901a0d0b86c9c55f2a9e482714adab3367b7`。
- 真实 DNS：公共模式保留、强制失败回退系统模式均通过，共两次真实内核启动和两次域名代理检查。
- DNS 摘要 SHA-256：`d282b5b1d781358eef861fdcc8b7a1a6858bd95427345325d1db39944c7c9c00`；CSV SHA-256：`8267af447b2514ebee7b0c6bef6a76a6bca17de93c6dbc315014fb1b8a0b68b2`。

## 0.2.0-dev.90

安装前统一只读预检在唯一测试机上的实际结论：

- root、Alpine Linux 3.21、x86_64、OpenRC 与 apk：满足安装条件。
- 实际可用资源：约 122 MiB 内存、1 核 CPU；项目会选择对应自适应档位。
- 根文件系统可用空间约 411 MiB。
- 系统 DNS 可解析 GitHub，GitHub 项目仓库可访问。
- VPS-Node 的 Mihomo/Tunnel 运行器及服务名均无冲突。
- 最终结论：可以安装，未发现阻止项。
- 检查期间未创建项目目录、安装依赖、读取 Token 或修改服务与网络参数。
- 当前版本隔离闭环同时再次通过：Reality IPv4 `2/2`、轮换、备份恢复、自愈、脱敏报告与可恢复卸载均成功，正式服务全部受检状态不变。
- `dev.90` 当前脚本 SHA-256：`4e2f5cd583f8519c32040cca0ef2b6361d14873fc78c98b60459769ddf9f180f`。
- 隔离验收原始脱敏证据 SHA-256：`697c98ebd569e7d430e7090fcf3973f19c620ed15963b69e30aef0d05ac0752a`。
