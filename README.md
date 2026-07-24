# VPS-Node

详细版本记录请查看 [CHANGELOG.md](CHANGELOG.md)。

面向个人自用 VPS 的轻量节点管理项目，核心目标是默认可用、故障可解释、修改可回滚。

当前已经具备：

- Reality 主线路
- VLESS WebSocket + Cloudflare Tunnel 备用线路
- 可恢复状态事务
- Mihomo 适配器与按 cgroup 内存自适应
- 启动前自适应 DNS：公共 DNS 可用时优先使用，否则回退到系统有效 DNS
- 分层健康检查和安全修复
- 真实端到端测试
- 凭据轮换、备份迁移、安全维护
- 精确提交更新、SHA-256 校验和版本回滚

## 安装

安装前只检查，不修改系统：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --check
```

预览正式安装会做什么：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --dry-run
```

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh
vp
```

安装后常用命令：

```sh
vp preflight
vp core-install
vp reality-add home 443 www.amd.com ipv4
vp reality-add home-v6 8443 www.amd.com ipv6
vp argo-add backup 25443 tunnel.example.com /private-path
vp nodes
vp link home
vp subscription plain
vp subscription base64
vp test-node home
vp test-node home 4
vp test-all 4
vp network
vp network-optimize --dry-run
vp network-optimize home 4
vp network-repair
vp network-rollback
vp report
vp self-heal
vp monitor-install
vp stability
vp optimize
vp rotate home 24
# 验证新链接后执行；需要输入 FINALIZE：
vp rotate-finalize home
vp backup
vp backups
vp backup-prune --keep 5 --dry-run
vp backup-prune --keep 5 --apply
vp restore /path/to/backup.tar.gz --dry-run
vp restore /path/to/backup.tar.gz --apply
# 仅兼容确认可信但没有 SHA-256 的旧备份：
vp restore /path/to/legacy-backup.tar.gz --dry-run --allow-unverified
vp migrate-mh /etc/mihomo/nodes.db --dry-run
vp migrate-mh /etc/mihomo/nodes.db --apply
vp maintain
vp version-status
vp update --check
# 正式更新会先显示候选信息，并要求输入 UPDATE：
vp update
vp update --allow-downgrade
vp rollback
vp uninstall
```

`vp preflight` 是安装前的一键只读检查：集中显示 root 权限、系统与架构、服务管理方式、内存/CPU 自适应、磁盘、DNS、GitHub 连通性、默认端口和外部同名服务冲突，并给出“可以安装”或“暂不建议安装”的明确结论。它不会安装依赖、创建项目目录、读取 Tunnel Token 或修改服务和网络参数。

普通用户可以直接运行 `vp`，首页菜单会引导创建主节点、备用节点、测试、修复、维护和迁移；命令参数适合高级用户和自动化。

`vp optimize` 会根据当前 cgroup/主机内存重新计算已验证的 Mihomo 运行参数，必要时重启服务，并立即执行健康检查；不会修改节点地址、UUID 或 Tunnel Token。

DNS 选择会在核心安装或优化时重新检测：优先验证 `1.1.1.1`、`8.8.8.8` 的解析和可用的 TCP 53；公共 DNS 不可达时才使用 `/etc/resolv.conf` 中当前有效的系统 DNS。健康检查会把 DNS 上游故障与节点协议故障分开报告。

## 验证范围

以下能力已有自动测试或早期隔离实机记录；早期实机结果不等同于当前版本验收。当前版本仍缺少的唯一测试机证据以 [完成度审计](docs/COMPLETION_AUDIT.md) 和 [测试矩阵](docs/TEST_MATRIX.md) 为准：

- 事务正常提交、验证失败回滚、SIGKILL 中断恢复
- Reality 和 VLESS-WS 独立客户端真实 HTTPS 代理
- Cloudflare Tunnel 公网 hostname、边缘连接和 Tunnel 进程自动恢复
- OpenRC 服务安装、启用、崩溃自动拉起和完整卸载
- 64–2048 MiB 模拟 cgroup 内存档位
- cgroup CPU quota、cpuset 与宿主可见核心数的联合限制
- 凭据轮换宽限期、旧凭据移除和重启持久化
- 备份 SHA-256、恢复验证和恢复失败回滚
- 管理脚本精确提交下载、SHA-256、更新失败保留和版本回滚

Reality 从 VPS 内部使用公网 IP 测试时，如果宿主网络不支持 NAT hairpin，程序会明确提示需要外部网络复核，不会误判为协议故障。

项目仍处于开发阶段，建议先在自己的测试 VPS 上验证域名、Tunnel ingress 和防火墙策略。

新旧项目的逐项能力取舍见 [docs/FEATURE_GAP.md](docs/FEATURE_GAP.md)。
唯一测试机的隔离验收步骤见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。
当前版本逐项完成度、证据等级和剩余发布门槛见 [docs/COMPLETION_AUDIT.md](docs/COMPLETION_AUDIT.md)。

只有设置 `VP_LOCAL_SOURCE=1` 时安装器才会读取当前目录的 `vp.sh`；普通远程一键安装始终从 GitHub 精确提交下载，避免误用当前目录中的旧文件。

卸载可从首页选择“卸载 VPS-Node”，也可以执行 `vp uninstall`。输入 `DELETE` 后会先创建并校验外部恢复包，再停止项目服务、回滚项目应用的网络参数并删除自身数据。只有服务进程和全部管理路径均确认消失后才会提示成功；如有残留，会列出准确路径并保留恢复包。
