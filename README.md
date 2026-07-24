# VPS-Node

面向个人自用 VPS 的轻量节点管理项目，核心目标是默认可用、故障可解释、修改可回滚。

当前已经具备：

- Reality 主线路
- VLESS WebSocket + Cloudflare Tunnel 备用线路
- 可恢复状态事务
- Mihomo 适配器与按 cgroup 内存自适应
- 分层健康检查和安全修复
- 真实端到端测试
- 凭据轮换、备份迁移、安全维护
- 精确提交更新、SHA-256 校验和版本回滚

## 安装

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
vp optimize
vp rotate home 24
vp rotate-finalize home
vp backup
vp restore /path/to/backup.tar.gz
vp maintain
vp update
vp rollback
```

普通用户可以直接运行 `vp`，首页菜单会引导创建主节点、备用节点、测试、修复、维护和迁移；命令参数适合高级用户和自动化。

`vp optimize` 会根据当前 cgroup/主机内存重新计算已验证的 Mihomo 运行参数，必要时重启服务，并立即执行健康检查；不会修改节点地址、UUID 或 Tunnel Token。

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
