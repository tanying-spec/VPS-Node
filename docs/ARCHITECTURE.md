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

## 文件布局

```text
/usr/local/bin/vp                 管理入口
/usr/local/lib/vps-node/          内核适配与 runner
/etc/vps-node/state.env           非敏感状态
/etc/vps-node/nodes.db            节点数据库（0600）
/etc/vps-node/credential-rotations.db 轮换宽限记录（0600）
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
GitHub Commit API -> 精确 SHA -> raw 文件 -> SHA-256 -> sh -n -> 原子替换
```

Release 二进制通过 GitHub Release API 的资产级 digest 校验，缺少 digest 时拒绝安装。

Mihomo 由 `mihomo-run` 启动包装器加载动态内存参数，Tunnel 由独立 runner 启动。OpenRC 和 systemd 使用相同的运行参数来源。
