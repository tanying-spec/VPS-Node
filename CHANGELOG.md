# Changelog

## 0.2.0-dev.16

- Share links are now validated before output; malformed UUIDs, ports, Reality fields, Tunnel hosts, WebSocket paths and unavailable public addresses produce specific errors instead of incomplete links.
- WebSocket paths and node labels use byte-safe percent encoding, so reserved characters cannot corrupt URI query or fragment boundaries.
- Subscription export inherits the same validation and aborts rather than silently including a broken node.

## 0.2.0-dev.15

- Added preview-first migration from Mihomo-lite-argo `nodes.db`.
- Only lossless VLESS-Reality and standard Argo VLESS-WS records are imported; unsupported protocols and lossy CDN/direct WS mappings are explicitly counted and skipped.
- Apply mode requires `MIGRATE`, creates a VPS-Node backup, validates the complete Mihomo candidate, restarts and rolls back transactionally on failure.
- Migration preserves the source database and never imports Tunnel tokens, users, traffic/firewall rules, cron jobs or sysctl settings.

## 0.2.0-dev.14

- Added a host-locked isolated acceptance harness for the only authorized test machine (`134.209.180.134`).
- Acceptance uses unique temporary paths, OpenRC service names and ports, then verifies formal Mihomo/cloudflared service states and configuration digests are unchanged.
- The harness covers real Reality loopback authentication, two-stream download, rotation-aware subscriptions, backup, redacted diagnostics, network dry-run and recoverable uninstall.

## 0.2.0-dev.13

- Added explicit IPv4/IPv6 Reality lifecycle with public-IPv6 preflight, family-aware listeners, bracketed IPv6 links, editing and health diagnostics.
- Existing Reality records without a family field remain IPv4-compatible.
- Added `vp subscription plain|base64` for all current nodes.
- Active credential rotations now export both current and temporary old links so subscription updates do not prematurely break clients.
- Added IPv4/IPv6 availability to network status and redacted diagnostics without exposing the actual addresses.

## 0.2.0-dev.12

- Added cgroup v1/v2 CPU quota and cpuset-aware effective CPU detection.
- Runtime profiles now cap `GOMAXPROCS` to actual CPU entitlement and reduce GC CPU overhead on sub-core containers without loosening ultra-low-memory profiles.
- Added outcome-focused CPU details and OOM-kill delta reporting to the dashboard; health checks distinguish new OOM events from historical totals.
- Added an evidence-based feature-gap audit against Mihomo-lite-argo and documented intentionally excluded multi-user overhead.

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
