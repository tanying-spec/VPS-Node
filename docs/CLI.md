# VPS-Node 完整命令说明

普通用户建议直接运行 `vp` 使用中文菜单。这里的命令主要用于自动化、排错和高级维护。

## 状态与诊断

```sh
vp
vp status
vp preflight
vp doctor
vp health
vp report
vp stability
vp version-status
```

- `vp`：打开首页菜单。
- `vp status`：查看当前状态。
- `vp preflight`：只读检查安装环境。
- `vp doctor`：检查已安装环境的基础条件。
- `vp health`：执行分层健康检查。
- `vp report`：生成脱敏诊断报告。
- `vp stability`：查看后台稳定性监测记录。
- `vp version-status`：查看当前脚本和可用回滚版本。

## 创建和管理节点

```sh
vp core-install
vp reality-add home 443 www.amd.com ipv4
vp reality-add nat-home 24443 www.amd.com ipv4 nat 34443
vp argo-add backup 25443 tunnel.example.com /private-path
vp cf-token-set /root/cloudflare-api.token
vp cdn-add cdn-backup 26443 cdn.example.com /private-cdn nat 36443
vp nodes
vp link home
vp test-node home
vp test-node home 4
vp test-all 4
vp edit home new-name 8443 www.amd.com ipv4
vp delete home
```

Reality 新增的第五、六个参数为网络模式和公网映射端口。旧写法仍按直连处理。`edit` 后面的参数依次为：原节点名、新节点名、新端口、新 SNI/域名、地址族或 WebSocket 路径。不想修改的参数可以传入空字符串 `''`。Reality IPv6 节点目前只支持直连。

CDN 直连要求最小权限 Cloudflare API Token，以及专用的 Flexible SSL Zone。程序不会自动更改 Zone SSL 或安全设置。

```sh
vp nat-detect
vp network-mode-set home nat 34443
vp nat-port-update home 35443
vp cdn-port-update cdn-backup 37443
```

公网端口更新不会重启 Mihomo。程序会临时应用新端口并执行节点测试，失败时恢复本地记录和 Cloudflare Origin Rule。

## 导出订阅

```sh
vp subscription plain
vp subscription base64
```

## 网络状态与优化

```sh
vp network
vp network-optimize --dry-run
vp network-optimize home 4
vp network-repair
vp network-rollback
vp optimize
```

- `network-optimize --dry-run`：只显示候选优化，不应用。
- `network-optimize home 4`：以指定节点和并发数建立基线，应用候选参数后复测；验证不通过会回滚。
- `network-repair`：修复已验证参数发生的运行时漂移。
- `network-rollback`：恢复应用优化前保存的网络参数。
- `optimize`：重新计算资源与 DNS 自适应参数并执行健康检查。

## 修复与后台监测

```sh
vp repair
vp self-heal
vp monitor-install
vp maintain --dry-run
vp maintain
```

正式执行 `vp maintain` 前会创建恢复点，并要求输入 `MAINTAIN`。

## 凭据轮换

```sh
vp rotate home 24
vp rotations
vp rotate-finalize home
```

`rotate` 会让新旧凭据并存指定小时数。确认客户端已改用新链接后，再执行 `rotate-finalize` 并按提示确认。

## 备份、恢复和迁移

```sh
vp backup
vp backups
vp backup-prune --keep 5 --dry-run
vp backup-prune --keep 5 --apply
vp restore /path/to/backup.tar.gz --dry-run
vp restore /path/to/backup.tar.gz --apply
vp migrate-mh /etc/mihomo/nodes.db --dry-run
vp migrate-mh /etc/mihomo/nodes.db --apply
```

旧备份没有 SHA-256 校验文件时，只有确认来源可信才可额外使用 `--allow-unverified`。

## 更新、回滚和卸载

```sh
vp update --check
vp update
vp update --allow-downgrade
vp rollback
vp uninstall --dry-run
vp uninstall
```

- `update --check`：只读检查，不覆盖当前脚本。
- `update`：校验下载内容并要求输入 `UPDATE` 后更新。
- `rollback`：回滚到上一个已校验的管理脚本。
- `uninstall --dry-run`：预览卸载范围。
- `uninstall`：创建并校验恢复包后卸载，需输入 `DELETE`。

## 安装器高级选项

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --check
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh -s -- --dry-run
curl -fsSL https://raw.githubusercontent.com/tanying-spec/VPS-Node/main/install.sh | sh
```

已经使用 `root` 登录时不要添加 `sudo`。
