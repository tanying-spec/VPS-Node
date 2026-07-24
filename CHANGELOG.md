# Changelog

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
