# 唯一测试机隔离验收

允许的实机只有 `134.209.180.134`。不得在其他主机运行本验收。

在 Windows 项目目录中推荐使用固定入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1
```

如果只想检查测试机是否具备条件，不上传文件、不启动测试，可运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1 -PreflightOnly
```

预检会验证固定公网 IP、root/Alpine、工具、Mihomo、正式状态可读取、临时空间和测试下载端点；默认还检查 cgroup v2 memory 条件。附带四项独立 Tunnel 参数时会额外检查 Token 与正式 Token 不同、域名未被正式节点使用、源站端口空闲、cloudflared 可用和边缘域名可达。输出不会包含实际 Token、域名、路径、节点凭据或二进制路径。

该入口固定连接 `root@134.209.180.134:18750`，强制 `BatchMode=yes`、关闭密码和键盘交互认证，仅使用专用公钥。它只上传 `vp.sh`、校验文件和四个验收脚本到随机 `/tmp`，不会把整个工作区、Token 或其他本地文件上传。成功后证据保存在本地 `evidence/<run-id>`（已从 Git 忽略），远端临时源码无论成功失败都会尝试清理。

如测试机尚未授权专用公钥，请在测试机控制台执行一次（不会更改 SSH 端口或认证策略）：

```sh
install -d -m 700 /root/.ssh
key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJS6tPqkMs4Q/FbG2ZM8wWyPlXl/ppT2C/DiKLeJjIz9 codex-u683775765-62.72.48.31'
grep -qxF "$key" /root/.ssh/authorized_keys 2>/dev/null || printf '%s\n' "$key" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

只运行隔离功能验收、跳过内存档位时：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1 -SkipMemoryProfiles
```

若要同时跳过内存和 CPU 资源档位，只运行功能验收：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1 -SkipMemoryProfiles -SkipCpuProfiles -SkipDnsProfiles
```

如需由同一个固定入口同时执行完全独立的 Cloudflare Tunnel 公网验收，可使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1 `
  -TunnelTokenFile /root/independent-test.token `
  -TunnelHost test.example.com `
  -TunnelPath /private-test-path `
  -TunnelOriginPort 25443
```

四项必须同时提供。`TunnelTokenFile` 是测试机上的绝对文件路径，不是 Token 内容，并且不能使用正式 `/etc/cloudflared/token`。Public Hostname 必须预先指向该固定源站端口。可先追加 `-ValidateOnly` 离线检查参数；该模式不会连接测试机、不会读取 Token 文件。

验收入口会拒绝非空的本地证据目录，避免不同批次混在一起。远端执行前必须通过当前 `vp.sh.sha256`；下载后不仅复核每个 sidecar，还会确认唯一验收记录绑定当前版本、当前脚本 SHA-256、固定主机、要求的 Tunnel 模式及全部正式服务不变结论。可运行以下命令离线自测证据验证器（不会联网）：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_authorized_host.ps1 -SelfTestEvidence
```

默认入口随后会执行十五档真实内存验收，而不是只计算参数。测试机必须提供可委派的 cgroup v2 memory controller；档位为 64、96、97、128、160、161、192、256、320、321、512、640、641、1024、2048 MiB，覆盖全部策略切换边界前后。每档都会施加独立硬上限，启动真实 Mihomo，验证代理出口并完成四路并发、每路 1 MiB 的精确字节传输，记录峰值及 OOM 后清理。若环境无法提供真正的 cgroup 内存约束，验收会明确失败，不会降级成模拟结果。

默认入口也会执行真实 CPU quota 验收。0.5、0.999、1 核在任何测试机必测；只有测试机确实具备至少 2 或 4 个在线 CPU 时，才继续测试更高配额。配置生成过程本身和真实 Mihomo 都位于对应 CPU cgroup 中，避免从父环境读取到错误配额。每档在四路代理传输期间还会执行短时饱和负载；当配额低于宿主实际容量时必须观察到真实 throttling 事件。可用 `-SkipCpuProfiles` 单独跳过。

默认入口还会执行真实 DNS 自适应验收。若 1.1.1.1/8.8.8.8 的实际查询和 TCP 53 正常，就必须继续使用公共 DNS；随后以不可达保留地址强制触发系统 DNS 回退。两个结果都会分别启动真实 Mihomo 完成域名代理访问，全程不修改 `/etc/resolv.conf`，证据不记录系统解析器地址。可用 `-SkipDnsProfiles` 单独跳过。

脚本中的目标 IP 为常量，不能通过环境变量改成其他主机。旧的非隔离系统测试已经删除。

验收脚本使用：

- `/tmp/vps-node-acceptance-<pid>` 独立配置、数据、日志和二进制目录；
- `vps-node-acceptance-core-<pid>` 独立 OpenRC 服务名；
- 自动选择的独立 Reality 端口；
- 本机回环 Reality 协议认证与两路并发下载；
- 独立备份、诊断、轮换、订阅、卸载和外部恢复包。

运行前记录正式 `mihomo`、`cloudflared-tunnel` 状态，以及正式 init 脚本和 Mihomo 配置摘要。验收结束后必须完全一致，否则视为失败。

```sh
VP_TEST_MIHOMO_BIN=/正式内核路径 sh tests/isolated_acceptance.sh
```

如需同时验收 Cloudflare 公网备用线路，必须预先创建一条与正式业务完全独立的 Tunnel，并将其 Public Hostname 服务指向指定的固定源站端口：

```sh
VP_TEST_MIHOMO_BIN=/正式内核路径 \
VP_TEST_CLOUDFLARED_BIN=/正式cloudflared二进制路径 \
VP_TEST_TUNNEL_TOKEN_FILE=/root/独立测试.token \
VP_TEST_ARGO_HOST=独立测试域名 \
VP_TEST_ARGO_PATH=/独立测试路径 \
VP_TEST_ARGO_ORIGIN_PORT=独立固定端口 \
sh tests/isolated_acceptance.sh
```

五项 Tunnel 参数必须同时提供。脚本会在安装测试组件前拒绝已知正式 Token，以及出现在正式 `/etc/mihomo/nodes.db` 中的域名。Token、域名和链接不会写入验收证据。

网络候选参数只执行 `--dry-run`；实机验收不会修改主机全局 sysctl。

尚需在获得 SSH 授权后记录：

- Alpine/OpenRC 实际输出；
- 正式服务验收前后状态；
- Reality 回环认证与两路并发结果；
- 卸载后隔离文件和服务清理结果；
- 外部恢复包 SHA-256。

成功后会在 `${VP_ACCEPTANCE_EVIDENCE_DIR:-/root}` 创建脱敏验收证据及 `.sha256`。证据包含当前版本、测试时间、主机、Reality/轮换/恢复/自愈/卸载结论，以及正式服务状态、PID 和配置摘要是否保持不变；不包含节点链接、UUID、域名、Token 或密钥。
