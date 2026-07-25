# 架构约束

## 设计原则

1. 普通用户只接触 `vp`，技术参数放入高级菜单。
2. 管理状态与具体代理内核分离，节点数据不能依赖某个内核的 YAML 格式。
3. 所有写操作先生成候选状态，完成语法和运行验证后再提交。
4. 更新必须绑定不可变提交和 SHA-256，失败时保留当前版本。
5. 健康检查按进程、本地端口、协议、DNS、公网和 Tunnel 边缘分层报告。
6. 内存展示必须区分匿名工作内存、文件缓存、Swap 和 cgroup 限制。
7. 日志、分享链接和诊断输出不得暴露完整 UUID、Token、私钥或订阅凭据。
8. DNS 上游必须先实测再选择；公共 DNS 失败时回退系统解析，并在健康检查中独立报告。
9. NAT 节点必须分离内部监听端口和公网映射端口；公网端口变更不得无故重启核心。
10. Cloudflare 自动化只接受 API Token，不接受 Global API Key；远端写入必须绑定项目对象 ID 并具备精确恢复记录。

## 文件布局

```text
/usr/local/bin/vp                 管理入口
/usr/local/lib/vps-node/          内核适配与 runner
/etc/vps-node/state.env           非敏感状态
/etc/vps-node/nodes.db            节点数据库（0600）
/etc/vps-node/credential-rotations.db 轮换宽限记录（0600）
/etc/vps-node/cloudflare-cdn.db  CDN 远端对象与恢复记录（0600）
/etc/vps-node/secrets/            凭据和 Token（0700/0600）
/etc/vps-node/generated/          已提交的内核配置
/etc/vps-node/transactions/       配置事务快照
/var/lib/vps-node/                运行数据与备份索引
/var/log/vps-node/                限额日志
```

## 事务状态

```text
prepare -> validate -> activate -> verify -> commit
                          \-> rollback
```

事务目录记录 PID、阶段、旧状态清单和候选文件。启动任何写操作前，先恢复死亡 PID 留下的未完成事务。

## 更新链

```text
GitHub Commit API -> 顶层精确 SHA -> raw 文件 -> SHA-256 -> sh -n -> 版本/方向检查 -> 只读预览或三文件事务替换
```

三文件事务先暂存候选 CLI、当前 CLI 的回滚副本及其校验文件；回滚点两步交换期间发生失败会恢复原回滚点，活动 CLI 只在最后一步通过同目录 `mv` 提交。

Release 二进制通过 GitHub Release API 的资产级 digest 校验，缺少 digest 时拒绝安装。

Mihomo 由 `mihomo-run` 启动包装器加载动态内存参数，Tunnel 由独立 runner 启动。OpenRC 和 systemd 使用相同的运行参数来源。

## NAT 与 Cloudflare CDN

Reality 和 CDN 节点分别记录内部监听端口与公网映射端口。生成 Mihomo 配置时只使用内部端口，分享链接、公网测试和 Cloudflare Origin Rule 使用外部端口。

CDN 创建流程为：本地候选配置验证 → 指定子域名 DNS 写入 → 项目标记 Origin Rule 写入 → 本地状态激活 → Mihomo 重启 → 公网端到端验证 → 提交。任何正常失败都会删除项目规则、恢复原 DNS 并恢复本地事务。删除时依据保存的 Zone、DNS、Ruleset 和 Rule ID 精确操作，不通过整份 Ruleset 覆盖其他用户规则。
