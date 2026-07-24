# VPS-Node

面向个人自用 VPS 的轻量节点管理项目。项目以“默认可用、故障可解释、修改可回滚”为核心，不追求协议数量。

当前处于早期开发阶段。计划提供：

- Reality 主线路
- VLESS WebSocket + Cloudflare Tunnel 备用线路
- 事务化配置修改与中断恢复
- 分层健康检查和安全自动修复
- 真实公网端到端测试
- 基于 cgroup 的内存自适应
- 凭据轮换、备份迁移、更新回滚和安全维护

开发阶段可在仓库目录执行：

```sh
sh vp.sh status
sh vp.sh doctor
```

正式版本将支持：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh
vp
```

目前不要用于生产环境。

