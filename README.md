# VPS-Node

> `0.2.0-dev.27` 手工与定时自愈使用 PID 感知互斥锁，重叠任务会零影响跳过，崩溃遗留的过期锁会自动回收；连续相同的健康事件不再反复写日志，但故障和恢复事件仍完整保留。

> `0.2.0-dev.26` Cloudflare Tunnel 指标端口也会自动检测冲突、避让 Mihomo 内部端口并持久化；二进制、Token、运行器、指标端口和更新前服务状态共同参与原子回滚，首页状态会显示实际指标端口。

> `0.2.0-dev.25` 安装 Mihomo 时会自动检测内部混合代理端口和控制端口冲突，选择空闲端口并持久化，后续修复、更新和重启不会回到默认值；明确指定的端口冲突会直接报错。安装失败会同时恢复旧二进制、状态、配置和 `core.env`。

> `0.2.0-dev.24` 完整卸载同步清理管理脚本、上一版脚本及其 SHA-256 校验文件，卸载预览和危险路径保护也包含新增校验文件；自动测试确认三者均无残留。

> `0.2.0-dev.23` 健康检查能够识别“语法有效但已被手工修改”的 Mihomo 配置漂移；安全修复从节点与轮换数据库重建配置并强制重载核心，启动失败会恢复修复前配置和运行参数。损坏的状态数据库不会被猜测修复，首页会引导从可信备份恢复。

> `0.2.0-dev.22` 首页状态不再写死 Tunnel 服务名，并会优先识别节点数据库异常、进行中的凭据轮换和已经到期但尚未移除的旧凭据；状态页同时显示进行中与已到期数量，并给出下一步编号指引。

> `0.2.0-dev.21` 恢复备份支持 `vp restore 备份文件 --dry-run`：先检查归档、数据库关联和当前 Mihomo 内核兼容性，只显示脱敏范围摘要；正式恢复必须输入 `RESTORE`，取消或预览不会改变当前状态。

> `0.2.0-dev.20` 所有创建、编辑、迁移和恢复事务统一验证节点数据库：协议、字段数、UUID、端口、Reality 密钥、WS 路径、域名及名称/监听端口唯一性；凭据轮换还必须与现有节点协议和当前 UUID 一致。异常备份不会改变在线状态。

> `0.2.0-dev.19` 安装和在线更新会为上一版管理脚本生成独立 SHA-256；回滚前必须先通过校验，即使损坏内容仍符合 shell 语法也会拒绝执行。自动测试覆盖坏更新、正常更新、正常回滚和备份篡改拒绝。

> `0.2.0-dev.18` 备份恢复增加 root 级归档安全检查：只接受规定的 `manifest/config/data` 结构，在解压前拒绝符号链接、硬链接、设备文件、越界路径和额外顶层内容；自动测试覆盖真实备份恢复闭环与恶意归档拒绝。

> `0.2.0-dev.17` Cloudflare Tunnel 安装与 Token 更新改为原子操作：新二进制、新 Token 或服务重启任一步失败，都会恢复旧二进制、旧 Token 权限及更新前服务状态；首次安装失败则清除不完整文件。

> `0.2.0-dev.16` 分享链接会先执行完整性检查，再安全编码路径和节点名称；UUID、端口、Reality 参数、Tunnel 域名、WebSocket 路径或公网地址异常时会明确报错，不再输出看似完整但无法使用的残缺链接。订阅导出执行同样的检查。

> `0.2.0-dev.15` 新增 `vp migrate-mh /etc/mihomo/nodes.db --dry-run` 和 `--apply`。只迁移能够无损映射的 Reality 与标准 Argo WS；不猜测转换其他协议，也不读取旧 Tunnel Token、用户、iptables、cron 或 sysctl。

> `0.2.0-dev.13` Reality 节点可明确选择 `ipv4` 或 `ipv6`；IPv6 会先验证公网可用性，分享链接自动使用方括号。`vp subscription base64` 可导出全部节点，并在凭据轮换宽限期内同时包含新旧链接。

> `0.2.0-dev.12` 内存自适应进一步加入 cgroup CPU quota 与 cpuset：`GOMAXPROCS` 不再只看宿主可见核心数。首页会区分 OOM 历史累计和自上次确认后的新增次数。

> `0.2.0-dev.11` 新增 `vp network-optimize --dry-run`、`vp network-optimize 节点名 4` 和 `vp network-rollback`。候选参数只有在同节点、同并发复测不回退时才会保存；吞吐或首包表现不达标会立即恢复原值。

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
vp network-rollback
vp report
vp self-heal
vp monitor-install
vp stability
vp optimize
vp rotate home 24
vp rotate-finalize home
vp backup
vp restore /path/to/backup.tar.gz --dry-run
vp restore /path/to/backup.tar.gz --apply
vp migrate-mh /etc/mihomo/nodes.db --dry-run
vp migrate-mh /etc/mihomo/nodes.db --apply
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
- cgroup CPU quota、cpuset 与宿主可见核心数的联合限制
- 凭据轮换宽限期、旧凭据移除和重启持久化
- 备份 SHA-256、恢复验证和恢复失败回滚
- 管理脚本精确提交下载、SHA-256、更新失败保留和版本回滚

Reality 从 VPS 内部使用公网 IP 测试时，如果宿主网络不支持 NAT hairpin，程序会明确提示需要外部网络复核，不会误判为协议故障。

项目仍处于开发阶段，建议先在自己的测试 VPS 上验证域名、Tunnel ingress 和防火墙策略。

新旧项目的逐项能力取舍见 [docs/FEATURE_GAP.md](docs/FEATURE_GAP.md)。
唯一测试机的隔离验收步骤见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

只有设置 `VP_LOCAL_SOURCE=1` 时安装器才会读取当前目录的 `vp.sh`；普通远程一键安装始终从 GitHub 精确提交下载，避免误用当前目录中的旧文件。

卸载可从首页选择“卸载 VPS-Node”，也可以执行 `vp uninstall`。输入 `DELETE` 后会删除 VPS-Node 自己的服务、状态、凭据、备份和管理脚本。
