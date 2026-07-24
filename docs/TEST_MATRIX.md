# 测试矩阵

所有实机测试只在 `134.209.180.134` 进行；测试期间使用隔离目录和独立服务名，完成后恢复原服务。

| 类别 | 证据 |
| --- | --- |
| Shell 语法、安装与初始化 | `tests/smoke.sh`，指定测试机通过 |
| 事务提交、失败回滚、SIGKILL 恢复 | `tests/smoke.sh`，通过 |
| Reality / VLESS-WS 端到端 | 独立 Mihomo 客户端 HTTPS 204，通过 |
| Cloudflare Tunnel 公网入口 | `tests/system_argo_test.sh`，公网测速约 16 MiB/s，通过 |
| Tunnel 进程恢复 | `tests/system_argo_test.sh`，边缘连接恢复为 2，通过 |
| 并发压力 | `tests/system_pressure_test.sh`，4×10 MiB，峰值约 103 MiB，通过 |
| 内存适配 | `tests/memory_profiles.sh`，64–2048 MiB，通过 |
| DNS 自适应 | 公共 DNS 实测可用时选择 `1.1.1.1/8.8.8.8`；模拟不可达时回退系统 DNS，通过 |
| 凭据轮换 | 新旧同时有效，正式切换后旧凭据 HTTP 000，通过 |
| 备份迁移 | SHA-256、恢复和配置验证，通过 |
| 更新与回滚 | 精确提交、坏 SHA 拒绝、版本回滚，通过 |
| 完整卸载 | 文件、服务、进程和 runlevel 残留为 0，通过 |

ShellCheck 在 128 MiB cgroup 中作为额外工具运行时曾被自身 OOM 杀死；这不是项目服务测试，且工具已移除。核心脚本通过 `sh -n` 和上述运行矩阵验证。
