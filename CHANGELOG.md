# Changelog

## 0.2.0-dev.11

- Added `vp network-optimize --dry-run` to preview global network candidates and acceptance gates without changing the host.
- Added verified network application: baseline benchmark, temporary BBR/fq application, identical retest, persistence only after passing and automatic rollback on regression.
- Candidates require full concurrent success, at least 98% of baseline throughput and no more than 125% of baseline first-byte latency.
- Added `vp network-rollback`; uninstall now restores the pre-project network values before removing project state.
- Added tests proving an improved candidate is persisted while a slower candidate is rejected and rolled back.

## 0.2.0-dev.10

- Added real concurrent node downloads with configurable 1-8 streams, success ratios, connection time, first-byte time and aggregate throughput.
- Added `vp test-all [concurrency]` to compare every Reality and Argo node and report the best measured result without changing routing automatically.
- Added `vp network` for congestion-control, queue discipline and TCP connection visibility.
- Reworked the main network menu around current state, one-click concurrent testing and existing resource/DNS adaptive verification.

## 0.2.0-dev.9

- Added read-only installer modes: `--check` for compatibility/conflicts and `--dry-run` for an exact action preview.
- Installation now reports supported architecture, OS, init system, memory, disk, dependencies, GitHub reachability, existing proxy processes and reserved-port conflicts before writing files.
- Existing Mihomo, Xray, sing-box and cloudflared processes are explicitly preserved; the installer does not stop or modify them.
- Added isolated installer tests proving check and preview modes do not create the management script or state directories.

## 0.2.0-dev.8

- Added SHA-256 verified redacted diagnostic reports that exclude credentials, UUIDs, domains and complete node links.
- Added one-shot self-healing for interrupted transactions and stopped project-owned core or Tunnel services.
- Added low-overhead scheduled monitoring through systemd timers or Alpine periodic jobs instead of a resident daemon.
- Added capped stability event history and numbered health-menu entries for reports, self-healing and monitoring.

## 0.2.0-dev.7

- Added an outcome-first home dashboard with overall readiness, node composition and a numbered next-step recommendation.
- Added transactional Reality and Argo node editing for names, ports and public endpoints, including rollback when validation or restart fails.
- Added an explicit edit entry to the numbered node-management menu; deletion once again requires typed confirmation.

## 0.2.0-dev.6

- Added `vp uninstall --dry-run` to preview every service and path affected by uninstall.
- Uninstall now creates and verifies an external recovery archive before removing anything.
- Added dangerous-path and backup-location guards so unsafe overrides cannot trigger broad deletion.

## 0.2.0-dev.5

- Added a clearly visible uninstall entry to the main interactive menu with explicit confirmation.

## 0.2.0-dev.4

- Fixed node management so the interactive menu accepts either the displayed number or the node name.

## 0.2.0-dev.3

- Added adaptive DNS upstream detection with public-DNS preference and system fallback.
- Hardened the installer so local script files require an explicit opt-in.

## 0.2.0-dev.2

- Added a one-command optimization and verification workflow.
- Added applied memory tuning parameters to the status dashboard.

## 0.2.0-dev.1

- Added Mihomo Reality primary node lifecycle.
- Added VLESS WebSocket and Cloudflare Tunnel standby lifecycle.
- Added transactional configuration with interruption recovery and rollback.
- Added cgroup-aware continuous memory profiles.
- Added layered health checks, safe repair and measured end-to-end tests.
- Added graceful credential rotation with an explicit grace period.
- Added validated backups, migration, maintenance mode and complete uninstall.
- Added exact-commit script updates, Release asset digests and rollback.
- Added OpenRC/systemd service templates and service recovery tests.
