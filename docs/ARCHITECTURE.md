# 架构约束

## 设计原则

1. 普通用户只接触 `vp`，技术参数放入高级菜单。
2. 管理状态与具体代理内核分离，节点数据不能依赖某个内核的 YAML 格式。
3. 所有写操作先生成候选状态，完成语法和运行验证后再提交。
4. 更新必须绑定不可变提交和 SHA-256，失败时保留当前版本。
5. 健康检查按进程、本地端口、协议、DNS、公网和 Tunnel 边缘分层报告。
6. 内存展示必须区分匿名工作内存、文件缓存、Swap 和 cgroup 限制。
7. 日志、分享链接和诊断输出不得暴露完整 UUID、Token、私钥或订阅凭据。

## 文件布局

```text
/usr/local/bin/vp                 管理入口
/usr/local/lib/vps-node/          内核适配与辅助组件
/etc/vps-node/state.env           非敏感状态
/etc/vps-node/nodes.db            节点数据库（0600）
/etc/vps-node/secrets/            凭据和私钥（0700/0600）
/etc/vps-node/generated/          已提交的内核配置
/etc/vps-node/transactions/       配置事务快照
/var/lib/vps-node/                运行数据与备份索引
/var/log/vps-node/                限额日志
```

## 节点状态模型

节点数据库保存协议无关字段。内核适配器负责将其渲染为 Mihomo、sing-box 或 Xray 配置。首个稳定版本默认使用一个经过实机验证的内核，不同时运行多个内核。

## 事务状态

```text
prepare -> validate -> activate -> verify -> commit
                          \-> rollback
```

事务目录必须记录 PID、阶段、旧状态清单和候选文件校验值。启动任何写操作前，先恢复死亡 PID 留下的未完成事务。

