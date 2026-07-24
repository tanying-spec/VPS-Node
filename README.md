# VPS-Node

> `0.2.0-dev.10` 新增 `vp test-node 节点名 4` 单节点并发测速、`vp test-all 4` 全部节点对比和 `vp network` 当前网络状态。测速会报告并发成功率、连接/首包时间和聚合吞吐，但不会根据一次结果擅自切换线路。

> `0.2.0-dev.8` 新增 `vp report` 脱敏诊断报告、`vp self-heal` 单次自愈、`vp monitor-install` 低开销定时自愈和 `vp stability` 稳定性记录。后台检查使用定时任务，不增加常驻管理进程。

> `0.2.0-dev.7` 首页会直接显示总体可用状态、主备节点数量和下一步编号建议；节点管理支持修改名称、端口、Reality SNI、Tunnel 域名与 WebSocket 路径，变更失败会自动回滚。

> 从 `0.2.0-dev.6` 起，可先运行 `vp uninstall --dry-run` 预览卸载范围。正式卸载会先在 `/root` 创建带 SHA-256 校验的独立恢复包；备份或校验失败时不会删除项目。

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
vp core-install
vp reality-add home 443 www.amd.com
vp argo-add backup 25443 tunnel.example.com /private-path
vp nodes
vp link home
vp test-node home
vp test-node home 4
vp test-all 4
vp network
vp report
vp self-heal
vp monitor-install
vp stability
vp optimize
vp rotate home 24
vp rotate-finalize home
vp backup
vp restore /path/to/backup.tar.gz
vp maintain
vp update
vp rollback
vp uninstall
```

普通用户可以直接运行 `vp`，首页菜单会引导创建主节点、备用节点、测试、修复、维护和迁移；命令参数适合高级用户和自动化。

`vp optimize` 会根据当前 cgroup/主机内存重新计算已验证的 Mihomo 运行参数，必要时重启服务，并立即执行健康检查；不会修改节点地址、UUID 或 Tunnel Token。

DNS 选择会在核心安装或优化时重新检测：优先验证 `1.1.1.1`、`8.8.8.8` 的解析和可用的 TCP 53；公共 DNS 不可达时才使用 `/etc/resolv.conf` 中当前有效的系统 DNS。健康检查会把 DNS 上游故障与节点协议故障分开报告。

## 验证范围

指定测试机上已验证：

- 事务正常提交、验证失败回滚、SIGKILL 中断恢复
- Reality 和 VLESS-WS 独立客户端真实 HTTPS 代理
- Cloudflare Tunnel 公网 hostname、边缘连接和 Tunnel 进程自动恢复
- OpenRC 服务安装、启用、崩溃自动拉起和完整卸载
- 64–2048 MiB 模拟 cgroup 内存档位
- 凭据轮换宽限期、旧凭据移除和重启持久化
- 备份 SHA-256、恢复验证和恢复失败回滚
- 管理脚本精确提交下载、SHA-256、更新失败保留和版本回滚

Reality 从 VPS 内部使用公网 IP 测试时，如果宿主网络不支持 NAT hairpin，程序会明确提示需要外部网络复核，不会误判为协议故障。

项目仍处于开发阶段，建议先在自己的测试 VPS 上验证域名、Tunnel ingress 和防火墙策略。

只有设置 `VP_LOCAL_SOURCE=1` 时安装器才会读取当前目录的 `vp.sh`；普通远程一键安装始终从 GitHub 精确提交下载，避免误用当前目录中的旧文件。

卸载可从首页选择“卸载 VPS-Node”，也可以执行 `vp uninstall`。输入 `DELETE` 后会删除 VPS-Node 自己的服务、状态、凭据、备份和管理脚本。
