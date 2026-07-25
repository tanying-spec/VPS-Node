# 唯一测试机实机证据

所有记录仅来自授权主机 `134.209.180.134`，证据内容经过脱敏且由 SHA-256 sidecar 校验。原始证据保存在测试机 `/root`，本文件只记录可公开复核的结论和摘要哈希。

## 0.2.0-dev.96

- 2026-07-25 06:56 UTC 在唯一授权主机完成完整 smoke、安装器和隔离真实 Mihomo 验收。
- Cloudflare 普通用户菜单状态摘要、Token 入口、权限提示和 CDN 专用编辑引导回归通过；CDN 节点不会再误入通用编辑表单。
- Reality IPv4 回环认证与两路并发为 `2/2`；正式 Mihomo 与 Cloudflare Tunnel 保持 `active`，全部受检 PID、进程、配置和敏感摘要前后不变。
- 测试脚本 SHA-256：`bdfd4c1b1a92e8237b17b85a2fe4caaf1e94964e5ae9f21d222c2c10f8c46340`。
- 原始脱敏证据 SHA-256：`7f34abbcac369bc0486620370efb71b05941588893ee61e17ed8031156491fce`。
- 真实 CDN 公网闭环仍未请求，继续明确记录为缺独立测试材料。

## 0.2.0-dev.95

- 2026-07-25 06:48 UTC 在唯一授权主机完成完整 smoke、安装器、真实 CDN 验收器默认路径和隔离真实 Mihomo 验收。
- 新验收器的七项 CDN 参数、安全拒绝、脱敏证据字段和默认不请求路径已验证；本次未提供独立 Token/Zone/端口映射，因此公网结果明确记录为 `not-requested`。
- Reality IPv4 回环认证与两路并发为 `2/2`；正式 Mihomo 与 Cloudflare Tunnel 保持 `active`，PID、进程镜像、命令行、配置/init 和敏感状态摘要前后不变。
- 测试脚本 SHA-256：`e8ae9a72ddffdbee0334298b1c31747725a1a85ffd7edecece26702b8f59be6c`。
- 原始脱敏证据 SHA-256：`e0c56b14fffc5fa43cafdd56e5c01fb62fabe243b386442489d46b6b1c0d55dc`。
- 真实 CDN 公网闭环仍需独立测试材料，不能把默认路径或伪 API 结果记为公网通过。

## 0.2.0-dev.94

- 2026-07-25 06:29 UTC 在唯一授权主机完成完整 smoke、安装器和隔离真实 Mihomo 验收。
- Cloudflare 伪 API 覆盖单节点删除及整体卸载，确认只删除记录中的 DNS 对象和项目 Origin Rule；远端恢复失败会阻止本地状态删除。
- Reality IPv4 回环认证与两路并发为 `2/2`；轮换、备份恢复、自愈、诊断脱敏、维护、CLI 更新/回滚、篡改拒绝和可恢复卸载全部通过。
- 正式 Mihomo 与 Cloudflare Tunnel 均保持 `active`，PID、进程镜像、命令行、配置/init 摘要及敏感状态摘要前后不变。
- 测试脚本 SHA-256：`0b4807301f5bb208febae3f2d3d34f214da747488981f585ad1ec634a1479bd4`。
- 原始脱敏证据 SHA-256：`3acf7bc5b5c3fd62978c1b69d814ff6d3d3389ae284bb0833cafe82a978033c5`。
- 真实 Cloudflare CDN 公网边缘仍未请求，不能用伪 API 结果代替公网证据。

## 0.2.0-dev.93

执行时间：2026-07-25 06:13 UTC。

- 完整 `tests/smoke.sh` 与 `tests/install_smoke.sh` 通过，包括 NAT 自动检测/手动模型、内外端口配置、无重启端口成功提交、验证失败哈希恢复，以及伪 Cloudflare API 的 Token、DNS、Origin Rule、创建失败清理、端口更新和精确删除。
- 隔离真实 Mihomo Reality IPv4 回环认证与两路并发：`2/2`；轮换、备份恢复、配置漂移自愈、诊断脱敏、维护、CLI 更新/回滚、篡改拒绝和可恢复卸载全部通过。
- 正式 Mihomo 与 Cloudflare Tunnel 均保持 `active`，PID、进程镜像、命令行、配置/init 摘要及敏感状态摘要前后不变。
- 公网 IPv6 不可用；独立 Tunnel 与真实 Cloudflare CDN API/边缘均未请求，不能把伪 API 测试记为公网通过。
- 测试脚本 SHA-256：`dfbba3b57a12e0f9f8588563957dabfa39aa3574bfecfd172dcabdb1068d40b0`。
- 原始脱敏证据 SHA-256：`15062655d2f8904820fa5809189536c3b0bc2d90294722ad31f6c36cb0d39bd3`。

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

## 0.2.0-dev.91

- 当前脚本 SHA-256：`8309acaacdfb50960915b2bbd5314064e26b1d1684fda6177e529a28358dfacf`。
- 一键维护 dry-run 保持日志、节点数据库和项目状态不变。
- 正式维护先创建恢复点，随后将隔离过大日志截断到 1 MiB，并只删除固定测试根目录中超过 60 分钟的 VPS-Node 前缀临时项。
- Reality IPv4 `2/2`、轮换、备份恢复、自愈、脱敏报告、维护和可恢复卸载完整闭环均通过。
- 正式 Mihomo/Tunnel 的状态、PID、二进制、命令行、配置、init 定义及敏感摘要前后不变；代理与 Tunnel 指标 HTTP 检查均为 200。
- 原始脱敏证据 SHA-256：`f4929f21a21016b7c5bda073305daedff4bb054135a8837a63baac92658f84e3`。

## 0.2.0-dev.92

- 执行时间：2026-07-25 03:39–03:42 UTC。
- 当前脚本 SHA-256：`4650759d9d4c8bc498b69dccba890358f009ea212d114e759331431ce8c337d9`。
- 完整 `tests/smoke.sh`、`tests/install_smoke.sh`、真实 DNS 档位和隔离实机验收均通过。
- Reality IPv4 回环真实认证与两路并发：`2/2`。
- CLI 更新只读检查保持零写入；校验候选更新、回滚和回滚点篡改拒绝均通过，节点状态、生成配置和全部 Mihomo PID 未变化。
- 隔离后台监控运行器的精确内容、执行权限、状态页和脱敏诊断映射通过；没有注册 OpenRC 周期任务，也没有修改正式 `crond` 状态。
- 一键维护、凭据轮换、备份恢复、配置漂移自愈、脱敏诊断和可恢复卸载闭环均通过。
- 正式 Mihomo PID 保持 `321849`，正式 cloudflared PID 保持 `321562`；服务、二进制镜像、命令行、配置/init 和敏感状态摘要前后不变。
- 验收后正式代理 HTTP 为 `204`，Tunnel 指标 HTTP 为 `200`，相关 `/tmp` 测试残留为 `0`。
- 原始脱敏证据 SHA-256：`23079985bf2b713892bdff6ddf05b89b020f0988333c20feead5794bf4c86a3d`。
- 公网 IPv6 仍为 `not-available`；独立 Cloudflare Tunnel 因未提供独立测试 Token/域名仍为 `not-requested`，两项均未冒充通过。
