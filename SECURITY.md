# Security Policy

## Reporting a vulnerability

请不要在公开 Issue 中提交 Token、UUID、私钥、完整分享链接或主机凭据。请先通过项目维护者的私下联系方式报告，并提供复现步骤、受影响版本和最小化日志。

## 本项目的安全边界

- 配置、节点数据库、Token 和备份默认使用 600 权限。
- 分享链接只在用户主动请求时输出。
- 更新脚本和 Release 二进制都必须通过 SHA-256 校验。
- 备份恢复拒绝绝对路径和 `..` 路径。
- `vp repair` 不会自动修改防火墙或远程 Cloudflare 路由。

