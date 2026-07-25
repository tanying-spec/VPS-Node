# VPS-Node

一个面向个人自用 VPS 的节点管理工具。安装后输入 `vp`，按中文菜单即可创建节点、查看链接、测速、修复、更新或卸载。

> 项目仍在开发中。建议先在自己的测试 VPS 上使用，再逐步迁移正式节点。

## 适合谁

- 想用 VPS 搭建自用节点，但不想手写复杂配置。
- 希望低内存 VPS 也能自动选择合适参数。
- 需要 Reality 主线路，并可选 Cloudflare Tunnel 或 CDN 直连备用线路。
- 希望修改前有备份，失败时能回滚。

目前支持使用 `apk` 或 `apt-get` 的 Linux 系统，例如 Alpine、Debian 和 Ubuntu。安装时需要使用 `root` 用户。

## 最快开始：只需 3 步

### 1. 登录 VPS

使用服务器商提供的 IP、SSH 端口和 root 密码登录 VPS。

### 2. 安装 VPS-Node

复制下面整行命令，在 VPS 中粘贴并回车：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh
```

看到安装完成后，输入：

```sh
vp
```

如果你已经是 `root`，不需要在命令里加 `sudo`。

### 3. 创建并复制节点链接

进入首页后：

1. 输入 `1`，创建 Reality 主节点。
2. 不确定如何填写时，直接回车使用默认值。
3. 创建完成后，可按提示立即显示链接。
4. 如果当时没有显示，回到首页输入 `3`。
5. 选择节点编号，再输入 `1` 显示链接。
6. 复制完整链接，导入 v2rayN、Shadowrocket 等客户端。

到这里，第一次使用就完成了。

## 日常怎么用

以后登录 VPS，只需输入：

```sh
vp
```

首页常用入口：

| 想做什么 | 首页选择 |
| --- | ---: |
| 创建 Reality 主节点 | `1` |
| 配置 Cloudflare Tunnel/CDN 备用节点 | `2` |
| 查看节点、链接、测速或删除 | `3` |
| 查看网络状态、一键测速和优化 | `4` |
| 健康检查与安全修复 | `5` |
| 一键安全维护 | `6` |
| 备份、恢复或迁移旧项目 | `7` |
| 检查更新、应用更新或回滚 | `8` |
| 卸载 VPS-Node | `11` |

首页顶部会显示核心服务、Cloudflare Tunnel、节点数量、网络优化和后台监测状态。看到异常时，优先进入 `5` 做健康检查。

## Cloudflare 备用线路（可选）

Reality 主节点不需要 Cloudflare Token。

菜单提供两种方式：

- Tunnel：兼容性最好，需要 Tunnel Token 和公网主机名。
- CDN 直连：不运行 `cloudflared`，适合低内存或 NAT VPS，但需要一个专用的 Flexible SSL Zone。

配置 Tunnel 时需要提前准备：

- Cloudflare Tunnel Token。
- 已接入 Cloudflare 的域名。
- Tunnel 中已经配置好的公网主机名。

没有这些内容可以先跳过，不影响 Reality 主节点使用。

配置 CDN 直连时，请创建最小权限 Cloudflare API Token，仅授予目标 Zone：

- Zone Read。
- DNS Edit。
- Rulesets Edit。
- Zone Settings Read。

程序只修改指定子域名 DNS，并创建带 `VPS-Node CDN` 标记的路径级 Origin Rule。不会修改整个 Zone 的 SSL、安全等级、Bot 设置或其他规则。为避免程序偷偷降低安全级别，当前 Zone 不是 `Flexible` 时会拒绝创建；建议使用不承载网站的独立 Zone。

如果 VPS 使用端口映射，程序会自动提示 NAT 模式，分别保存内部监听端口和公网映射端口。检测错误时可在创建页面手动输入 `direct` 或 `nat`；以后可在节点管理中只更新公网端口，Mihomo 不会重启，验证失败会恢复旧端口。

## 更新与卸载

推荐直接从 `vp` 首页操作：

- 输入 `8`：先检查更新，再决定是否应用；更新失败可回滚上一版本。
- 输入 `11`：卸载项目前会先创建并校验恢复包，再停止和删除项目自己的服务与文件。

也可以使用命令：

```sh
vp update --check
vp uninstall
```

正式更新需要按提示确认。正式卸载需要输入 `DELETE`，避免误操作。

## 常见问题

### 提示 `sudo: not found`

如果登录的是 `root`，直接运行安装命令，不要加 `sudo`：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh
```

### 提示必须使用 root

先切换到 root 用户，再重新执行安装。不同服务商的切换方式可能不同；最简单的方式是登录时直接使用用户名 `root`。

### 无法下载，或 GitHub 连接超时

这通常是 VPS 到 GitHub 的网络问题，不是安装命令格式错误。可以稍后重试，或先确认 VPS 能否访问：

```sh
curl -I https://raw.githubusercontent.com
```

### 节点链接在哪里

输入 `vp` → 首页选择 `3` → 选择节点 → 输入 `1` 显示链接。

### 创建了节点但客户端连不上

先在首页选择 `3`，对该节点执行端到端测试；再进入首页 `5` 做健康检查。Reality 端口还必须在服务商防火墙和系统防火墙中允许访问。

### 低内存 VPS 能用吗

项目会读取 VPS 或容器实际可用的内存与 CPU 限额，为 Mihomo 选择相应参数，而不是给所有机器写入同一套限制。极低内存环境仍可能受系统中其他程序影响，首页状态和健康检查会显示实际结果。

### 公网 VPS 被识别成 NAT 怎么办

自动检测只提供建议，创建 Reality 或 CDN 节点时可以直接把模式改成 `direct`。已创建节点可输入 `vp` → `3` → 选择节点 → `7` 纠正模式或更新公网映射端口。

### 会不会修改其他服务

项目只管理自己确认拥有的文件和服务。网络优化会先测试、显示候选参数，并在应用后复测；卸载时会恢复项目保存的网络参数。正式使用前仍建议创建 VPS 快照。

## 安装前先检查（可选）

只检查环境，不安装或修改系统：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --check
```

预览安装将执行的操作：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --dry-run
```

## 给高级用户

普通用户无需记忆命令。需要自动化、备份恢复、迁移或凭据轮换时，可查看 [完整命令说明](docs/CLI.md)。

项目的测试与开发资料：

- [版本更新记录](CHANGELOG.md)
- [测试矩阵](docs/TEST_MATRIX.md)
- [唯一实机验收方法](docs/ACCEPTANCE.md)
- [当前完成度与证据等级](docs/COMPLETION_AUDIT.md)
- [与旧项目的功能差距](docs/FEATURE_GAP.md)

安全提醒：不要把服务器密码、Cloudflare Token、UUID 或完整节点链接提交到 GitHub Issue、日志或截图中。
