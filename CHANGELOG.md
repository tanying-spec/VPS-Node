# Changelog

## 0.2.0-dev.92

- The isolated authorized-host acceptance now proves that `vp update --check` is zero-write, a checksum-verified local candidate can be installed and rolled back, and a tampered rollback point is rejected without changing the active CLI.
- CLI update and rollback acceptance also binds isolated state, node database, generated configuration and all Mihomo PIDs, while the existing final gate continues to bind formal service state, process images, command lines and sensitive file digests.
- The Windows evidence verifier requires all three update/rollback results and its synthetic evidence self-test covers the expanded schema.
- OpenRC watchdog installation no longer reports success when `crond` cannot start or cannot be registered for boot; failure restores the previous watchdog files, scheduler enablement and scheduler runtime state.
- Regression coverage now includes successful OpenRC scheduling and a failed registration after `crond` startup, proving both file rollback and scheduler-state compensation.
- `vp status` and `vp stability` now report the effective watchdog schedule instead of inferring health from a runner file alone, distinguishing a verified systemd/OpenRC schedule, isolated runner, missing/foreign definitions, disabled scheduling and an inactive scheduler.
- Watchdog layout initialization is deferred until after `ENABLE`; cancelling a first-time monitor installation now leaves configuration, data, log and library paths completely absent.
- Monitor installation refuses a missing, symlinked, non-executable, syntactically invalid or version-invalid CLI target before preview-side writes, preventing a scheduler from repeatedly invoking a broken management path.
- Stability output now evaluates watchdog runner ownership and execute permission consistently; external, symlinked, malformed and non-executable runners are reported as explicit anomalies instead of appearing installed in one line and absent in another.
- Redacted diagnostics now include machine-readable `watchdog_runner_state` and `watchdog_schedule_state` values derived from the same inspection as the dashboard; reports expose no scheduler paths or command contents and are checksum-verified in scheduled OpenRC coverage.
- Layered health checks now include a dedicated monitor layer: a verified schedule is healthy, an absent or isolated optional monitor is a warning, and broken ownership, permissions, definitions, enablement or scheduler runtime is an actionable error.
- Watchdog ownership now requires exact expected content for the runner, systemd service/timer and OpenRC periodic task, not merely a copyable marker line; altered definitions are reported, refused during reinstall and preserved during uninstall.
- Authorized-host acceptance now creates a watchdog runner entirely inside the isolated prefix, verifies exact ownership/status plus checksum-bound diagnostic mapping, and explicitly avoids registering OpenRC or touching the host scheduler.
- The locked-host runner now executes portable smoke and installer tests before real-kernel acceptance and returns a bounded trace tail only on failure; acceptance evidence sidecars use flat filenames so downloaded SHA-256 verification is portable.

## 0.2.0-dev.91

- `vp maintain --dry-run` now previews the recovery point, interrupted-transaction handling, safe repair scope, expired credential removal, oversized log trimming and fixed-prefix stale temporary cleanup without writes.
- Applying maintenance requires explicit `MAINTAIN` confirmation before layout initialization or backup creation; cancellation is zero-write and the first committed action is a verified recovery point.
- Maintenance temporary cleanup can be scoped with a validated absolute root and only touches VPS-Node fixed prefixes older than 60 minutes; logs are regular non-symlink files and retain at most 1 MiB.
- Completion output reports safe repair, expired credential, log and temporary-item counts; if later repair fails, the pre-maintenance recovery point remains available.
- Regression and isolated real-host acceptance cover preview/cancel zero writes, successful backup/cleanup, invalid database refusal with backup retention and unchanged formal services.

## 0.2.0-dev.90

- Added `vp preflight`, a single read-only installation readiness page with a clear `can install` or `do not install yet` conclusion.
- The check covers root access, OS/architecture, service manager, package manager, effective memory and CPU, disk space, system DNS, GitHub reachability, managed runner/service ownership, reserved ports and existing Xray/sing-box processes.
- The advanced numbered menu now separates pre-install readiness from the post-install `doctor` check, and README usage starts with the new command.
- Preflight never installs packages, initializes layout, downloads files, reads Tunnel credentials or changes services/network state; regression tests verify zero project writes for ready, conflict, low-memory and unsupported-service-manager cases.
- The authorized Alpine host reported OpenRC, 122 MiB effective memory, 1 effective CPU, working DNS/GitHub, no VPS-Node service conflicts and an unblocked installation conclusion.

## 0.2.0-dev.89

- Mihomo and Cloudflare Tunnel installation now checks service-manager support plus runner/service ownership immediately after `INSTALL` confirmation and before dependencies, layout initialization, downloads or Token reads.
- External same-name runner/service conflicts therefore fail with zero project writes and without replacing binaries, creating secrets or prompting for credentials.
- Regression tests bind the external files by SHA-256 and verify that configuration, data, log, binary and secret paths remain absent after a rejected install.
- Current real-host evidence now records the isolated Reality/OpenRC/lifecycle acceptance and real DNS public-to-system fallback results, while explicitly preserving the host cgroup and IPv6 limitations instead of treating them as passes.

## 0.2.0-dev.88

- README now stays focused on the project, current capabilities, installation and usage; detailed release history remains in this changelog.
- Mihomo and Cloudflare Tunnel runner/service installation now refuses external same-name files and uses same-directory atomic replacement for owned definitions.
- Failed enablement, restart, state activation, state commit or interruption restores the previous runner, service definition and enablement state.
- Uninstall only stops, restores, disables, removes and audits core/tunnel service definitions proven to belong to VPS-Node; external definitions are preserved with a warning.
- Regression coverage verifies external runner/service preservation and external same-name definitions surviving uninstall.

## 0.2.0-dev.87

- Monitor installation now previews scheduler, cadence, behavior and target definitions and requires explicit `ENABLE` confirmation.
- Runner, systemd service/timer and OpenRC periodic definitions carry a VPS-Node ownership marker; any external same-name file or symlink is refused before writes.
- Installation binds all targets across confirmation, stages replacements in their destination directories and restores prior files plus timer activity when systemd enablement fails or the process is interrupted.
- Reinstallation safely updates owned definitions while preserving the previous verified set on failure.
- Uninstall only stops, moves, removes and audits watchdog definitions whose ownership marker is present; external same-name systemd/OpenRC tasks are preserved.
- Regression tests cover cancellation, external runner/timer preservation, modes and markers, successful systemd installation and full rollback after enable failure.

## 0.2.0-dev.86

- Periodic self-heal now observes network runtime drift, invalid persistence, orphan rollback snapshots and configurations lacking rollback snapshots.
- Network monitoring is intentionally read-only: it never calls the repair path, writes sysctl values, edits persistence or deletes anomaly evidence.
- A transition back to active or unapplied consistency emits a recovered event, while unresolved anomaly states remain visible in the stability log.
- Identical `network-monitor` and healthy-check states are deduplicated by their latest action-specific event, preventing five/fifteen-minute log spam.
- Interactive self-heal summaries distinguish repairs, notices and actual failures.
- Regression tests prove each anomaly and recovery event, one-event deduplication and byte-identical sysctl state and persistence across every background check.

## 0.2.0-dev.85

- Redacted diagnostics now include the shared six-state network optimization verdict, live congestion control/qdisc, verified targets only when strict persistence is valid, and a machine-readable recommended action.
- Invalid and orphan persistence never exposes file contents, file paths or rollback-before values and is reported with `not-managed` targets.
- Network evidence remains free of public addresses, node endpoints, UUIDs, Tunnel tokens and complete links.
- Regression tests generate and SHA-256-verify reports for none, active, runtime drift, invalid persistence, orphan snapshot and orphan configuration states.
- Every state-specific report is checked for mode `600` and for absence of known sensitive fixtures and managed file paths.

## 0.2.0-dev.84

- The dashboard's overall verdict now consumes the same network consistency inspection used by `vp network` and the applied-optimization summary.
- Invalid persistence, an orphan configuration, an orphan rollback snapshot and live runtime drift each receive a distinct top-level status instead of being hidden by a generic ready verdict.
- Every anomaly provides an exact numbered menu path to inspect, repair, roll back or export a redacted diagnostic report.
- Core installation, corrupt node data and unavailable primary/backup services retain higher priority, while healthy or unapplied networking does not create false dashboard warnings.
- Regression tests prove all network anomaly-to-dashboard mappings and the healthy-state non-warning case.

## 0.2.0-dev.83

- Persistent network configuration now requires the exact VPS-Node ownership marker, exactly one congestion-control field, exactly one qdisc field and no unknown content.
- Verified optimization refuses external, malformed and orphan persistence before benchmarking or changing live sysctl values; rollback likewise refuses to delete configuration it cannot prove it owns.
- Snapshot/config file states and both live parameters are bound across the baseline benchmark, and persistence states remain bound across the candidate retest.
- A concurrent file change aborts with the original live parameters intact and without creating a rollback snapshot or overwriting the competing file.
- Hosts already running BBR/fq outside VPS-Node are reported as externally managed; no fake rollback point or duplicate persistence is created.
- Regression tests cover external-file preservation, mid-benchmark mutation, missing/duplicate fields, absent ownership markers, rollback refusal and externally enabled BBR/fq.

## 0.2.0-dev.82

- Added `vp network-repair` for the only automatically provable anomaly: valid persistence whose live congestion control or qdisc has drifted.
- Repair previews live and verified target values, explains its host-global impact and requires explicit `REPAIR` confirmation.
- Approval is bound to both persistence files and both live sysctl values; changes during confirmation abort before any write.
- Applying the two live parameters is compensated on partial failure, followed by live-value verification and proof that persistence files stayed byte-identical.
- Invalid persistence and orphan snapshot/configuration states are explicitly refused instead of being guessed or overwritten; regression tests cover cancellation, partial failure, success and refusal.

## 0.2.0-dev.81

- Network optimization status now validates the rollback snapshot and persistent sysctl configuration as strict regular files with exactly one valid value for each managed field.
- `vp network` distinguishes active-and-consistent state, live runtime drift, invalid persistence, an orphan rollback snapshot, an orphan configuration and a clean unapplied state.
- The dashboard reuses the same inspection result, so it cannot disagree with `vp network` or claim an optimization merely because two files exist.
- Regression tests cover all six states, expected/live parameter reporting and recovery to a valid state before the existing transactional rollback cases continue.

## 0.2.0-dev.80

- Network rollback now stages exact copies of the rollback snapshot and persistent sysctl configuration before touching live kernel values.
- Live congestion/qdisc restoration and removal of both persistence files form one compensated transaction protected by `EXIT`, `HUP`, `INT` and `TERM` cleanup.
- A partial file-removal failure restores the pre-rollback live values and both files with their modes instead of leaving split runtime/persistence state.
- Fault-injection tests prove parameter and file hashes are unchanged after a removal failure and no rollback-stage files remain.

## 0.2.0-dev.79

- Manual `vp network-rollback` now previews current/restored congestion control and qdisc values plus the host-global and persistence-file impact before requiring `ROLLBACK`.
- Approval is bound to exact rollback-snapshot and sysctl-config file states as well as both live kernel values.
- Any change during confirmation aborts before sysctl writes; cancellation leaves live parameters and persistence files byte-identical.
- Internal uninstall rollback retains the explicit non-interactive `--quiet` path, and regression tests cover cancellation plus existing compensation failures.

## 0.2.0-dev.78

- Node deletion now previews name, protocol, listener port, associated credential-rotation count and the service-restart impact before `DELETE` confirmation.
- The preview explicitly states that both current and grace-period credentials for the node are permanently removed.
- Cancellation has a consistent non-applied result and leaves node, rotation, generated configuration and state files byte-identical.
- Regression tests cover cancellation with an active rotation and retain the existing exact-state race rejection.

## 0.2.0-dev.77

- Reality and Argo node creation now preview non-secret listener and endpoint settings plus service impact before requiring `CREATE`.
- UUID, Reality keypair, Short ID and automatic WebSocket path generation all occur only after approval.
- Duplicate names are rejected before preview, while the existing transaction still rechecks the authoritative candidate for concurrent additions.
- Cancellation tests for both protocols prove node, rotation, generated configuration and state files remain byte-identical without transaction residue.

## 0.2.0-dev.76

- `vp edit` now previews protocol, old/new name and port plus Reality SNI/address family or Tunnel hostname/WebSocket path before requiring `EDIT`.
- The preview is deliberately credential-free and states that UUID and Reality keys remain unchanged.
- Command-level confirmation protects both direct CLI and numbered-menu use; cancellation occurs before race hooks or transaction creation.
- Regression tests prove cancellation leaves node, rotation, generated configuration and state files byte-identical with no transaction residue.

## 0.2.0-dev.75

- Starting credential rotation now previews the node, protocol, grace period, dual-credential impact and exact finalization command before requiring `ROTATE`.
- The confirmation belongs to `vp rotate` itself, so direct CLI and numbered-menu use share one safety boundary.
- Cancellation occurs before UUID generation or transaction creation and leaves node, rotation, generated configuration and state files untouched.
- Portable and isolated-host tests explicitly authorize rotation; regression coverage proves cancellation is byte-identical and transaction-free.

## 0.2.0-dev.74

- Core and Tunnel installation now arm dedicated `EXIT`, `HUP`, `INT` and `TERM` recovery immediately after binary promotion.
- An interrupted command restores the prior active/rollback binaries plus core runtime environment or Tunnel token/runner and aborts any active state transaction.
- Final state-transaction commit failure is now handled as an installation failure instead of being ignored.
- Interruption-injection tests prove binaries, rollback points, state, token and transaction directories are restored byte-for-byte with no prior-backup snapshot residue.

## 0.2.0-dev.73

- Mihomo and cloudflared installation now snapshot any pre-existing rollback binary before promoting the active version to the new rollback point.
- A failure after candidate commit restores both the prior active binary and the exact rollback point that existed before installation.
- The prior rollback snapshot is discarded only after state, service and restart commits all succeed, so successful updates still expose the immediately previous active version.
- Regression tests force core and Tunnel restart failures and prove active binaries, runtime state, tokens and older rollback binaries remain byte-identical.

## 0.2.0-dev.72

- Mihomo and cloudflared installation approval is now bound to SHA-256-backed states of both the active and rollback binaries captured before dependency work or downloads.
- Candidate verification is followed by exact state rechecks; concurrent active or rollback-binary changes are preserved and rejected instead of overwritten.
- A Tunnel candidate failure before binary commit no longer invokes rollback with an older backup, preventing stale recovery from overwriting concurrent binary or token changes.
- Race-injection tests prove external binaries, prior rollback points and Tunnel tokens remain intact while no runtime state is committed.

## 0.2.0-dev.71

- Mihomo and cloudflared binary rollback now validate the backup, preview current/target versions and service impact, then require the exact `ROLLBACK` confirmation.
- Approval is bound to SHA-256-backed states of both the active and backup binaries; a source changed after validation is preserved and rejected.
- The confirmed backup is copied to a private stage, validated again and only then exchanged with the active binary.
- Regression tests prove cancellation is byte-identical, post-validation source races do not alter the active binary, and successful rollback exchanges both versions.

## 0.2.0-dev.70

- `vp core-install` and `vp tunnel-install` now preview the installed version, trusted source, verification boundary and affected service before requiring the exact `INSTALL` confirmation.
- Command-level confirmation protects both direct CLI and numbered-menu use instead of relying on callers to provide a separate warning.
- Cancellation occurs before dependency installation, layout initialization, downloads, token input or project-state writes.
- Portable and authorized-host test harnesses explicitly opt into installation; regression tests prove cancellation creates no project paths.

## 0.2.0-dev.69

- `vp rollback` now displays the current version, verified rollback target and integrity result, then requires the exact `ROLLBACK` confirmation.
- The confirmation is owned by the command itself, so direct CLI and numbered-menu use share the same safety boundary.
- Cancellation occurs before directory creation, staging or exchange and leaves the active CLI, rollback script and checksum sidecar byte-identical.
- Regression tests prove cancellation leaves no CLI-exchange staging files before enabling confirmation for race and failure-injection cases.

## 0.2.0-dev.68

- `vp update` now owns the `UPDATE` confirmation after displaying the verified candidate preview; direct CLI use can no longer bypass the second confirmation provided by the menu.
- Cancellation removes candidate stages and leaves the active CLI, rollback script and rollback sidecar untouched.
- The numbered update menu delegates to the same command-level confirmation instead of maintaining a separate safety path.
- Regression tests prove explicit cancellation is byte-for-byte zero-write before enabling confirmation for apply and failure-injection cases.

## 0.2.0-dev.67

- Backup archives and SHA-256 sidecars now commit with same-directory atomic no-clobber links instead of overwrite-capable moves.
- An archive created by another task in the final commit window is preserved and makes backup creation fail safely.
- A sidecar collision removes only the archive committed by this transaction while preserving the external sidecar.
- Cleanup tracks ownership of each committed path, and race-injection tests prove concurrent archive and sidecar files are never deleted or overwritten.

## 0.2.0-dev.66

- Starting a credential rotation now binds the old UUID and in-progress-rotation check to exact node and rotation database states.
- Finalizing a named or expired rotation similarly binds its preview and confirmation to both databases before transaction creation.
- Concurrent node, credential or grace-record changes are preserved; stale UUID replacement and stale `FINALIZE` approval are rejected.
- Regression tests cover both rotation stages and prove original credentials, grace records, state and concurrent nodes remain intact without transaction residue.

## 0.2.0-dev.65

- Node editing now binds the source record calculation to the exact node and credential-rotation database states read at command start.
- Both databases are rechecked after port, endpoint, path and address-family preparation and before a state transaction is created.
- Concurrent node or rotation changes are preserved instead of being overwritten by a replacement record derived from stale fields.
- Regression tests inject a valid concurrent node and prove the original target, concurrent content, state and rotations remain intact with no transaction residue.

## 0.2.0-dev.64

- Node deletion now binds `DELETE` approval to the exact node and credential-rotation database states shown before confirmation.
- Any concurrent add, edit, rotation or deletion detected after confirmation aborts before a state transaction is created.
- The concurrent database content is preserved and the originally selected node is not removed under stale approval.
- Regression tests inject a valid concurrent node and prove no transaction, state change, rotation change or target deletion occurs.

## 0.2.0-dev.63

- Backup pruning now records the exact archive and sidecar file states for every validated recovery point in the displayed deletion plan.
- Each pair must still match its approved content immediately before deletion; merely remaining a different valid backup is no longer sufficient.
- A same-name recovery point replaced after `PRUNE` confirmation stops the operation before that file or any later candidate is deleted.
- Regression tests replace the oldest candidate with another valid recovery point and prove all planned files remain present.

## 0.2.0-dev.62

- Backup restore now binds the archive and SHA-256 sidecar file type, symlink identity and content hash to the validated preview.
- Both files are rechecked after extraction and again after `RESTORE` confirmation, before layout initialization or state-transaction creation.
- An archive changed while tar is reading it or while the user reviews the preview is rejected even if the extracted snapshot happens to parse successfully.
- Race-injection tests prove after-extract and after-confirm mutations leave the current VPS-Node state byte-identical and do not alter the sidecar.

## 0.2.0-dev.61

- CLI rollback now binds the validated active CLI, rollback script and checksum sidecar states to the subsequent three-file exchange.
- All three paths are rechecked after staging; a rollback source changed after SHA-256, syntax and version validation is preserved and rejected.
- Restoring into a missing active-CLI path uses an atomic no-clobber commit, preserving a file created in the final rollback window.
- Regression tests prove source-race and commit-race failures leave the unaffected active or rollback assets byte-identical.

## 0.2.0-dev.60

- CLI update approval is now bound to SHA-256-backed states of the active CLI, rollback script and rollback sidecar captured before candidate download.
- Changes detected after candidate verification, while copying the active CLI, or immediately before final replacement abort without overwriting the concurrent content.
- First-time CLI creation through `vp update` uses an atomic no-clobber commit, preserving a target created in the final commit window.
- Race-injection tests cover post-check mutation, mutation during backup and commit-time creation while proving prior rollback assets remain byte-identical.

## 0.2.0-dev.59

- Installer approval is now bound to SHA-256-backed snapshots of the CLI, rollback script and rollback checksum paths taken before download or package installation.
- A target or rollback asset created, replaced or modified after preflight aborts installation before VPS-Node state initialization.
- Fresh installation commits with an atomic no-clobber hard link, closing the final check-to-replace window when another task creates the target at commit time.
- Existing CLI content is rechecked after backup and immediately before replacement; race-injection tests prove external content and prior rollback assets are preserved.

## 0.2.0-dev.58

- Uninstall now audits every managed project path and the selected systemd/OpenRC service definitions after deletion.
- A retained directory, CLI, rollback asset, service unit, init script or watchdog job makes uninstall return failure instead of falsely reporting success.
- Failure output lists each exact residual path, preserves the verified recovery archive and gives a direct cleanup/reinstall/restore route.
- Regression tests inject a partial deletion and prove the residual is reported, the success message is suppressed and the recovery archive remains valid.

## 0.2.0-dev.57

- Uninstall now creates and verifies its external recovery archive before stopping services, rolling back host networking or deleting project files.
- Mihomo, cloudflared and the watchdog are stopped before destructive work; a failed stop restores the previous running state and leaves project and network state untouched.
- Process-level checks reject uninstall when either the core or an orphaned cloudflared process remains alive, including hosts without a detectable service manager.
- OpenRC watchdog jobs are held transactionally and restored on failure; regression tests prove stop-failure preservation, valid recovery evidence and orphan-Tunnel rejection.

## 0.2.0-dev.56

- Mihomo-lite-argo migration now accepts only a readable regular source database and rejects symlinks or special files.
- The source SHA-256 is captured before parsing and rechecked after `MIGRATE` confirmation; any change aborts before backup or transaction creation.
- Imported listener ports are rechecked after confirmation to close the preview/approval timing window.
- Regression tests prove symlink rejection and that a source mutation during confirmation produces no node change and no migration backup side effect.

## 0.2.0-dev.55

- Dashboard next actions now show the complete main-menu and submenu route instead of implying that entering a top-level menu performs the action directly.
- Repair, diagnostic, restore, link, test and credential-finalization guidance now maps to the exact numbered choices the user must press.
- A leftover Tunnel token without any Argo node no longer makes the dashboard report a broken backup route or a fully ready primary/backup setup.
- Scenario tests verify uninstalled, active/expired rotation, invalid-state and token-without-node conclusions plus their actionable routes.

## 0.2.0-dev.54

- Self-heal locks now bind the PID to the Linux process start time instead of trusting a reusable PID alone.
- A live unrelated process that reused a stale PID no longer blocks periodic self-heal indefinitely; status reports the mismatched lock as stale and the next check reclaims it.
- Lock release verifies both owner fields so an older process cannot remove a successor's lock.
- Fresh incomplete locks are not immediately stolen during the small directory/identity creation window, while legacy PID-only locks remain conservatively compatible.

## 0.2.0-dev.53

- Redacted diagnostics and their SHA-256 sidecars are now staged in the destination directory and committed only after report generation and hashing succeed.
- Existing reports, existing sidecars and symlink destinations are rejected instead of overwritten by a root process.
- A failure after the report commit but before the sidecar commit removes the unverified report and all stage files.
- Regression tests prove interrupted cleanup, symlink-target protection, existing-evidence preservation and the existing UUID/domain/Token redaction guarantees.

## 0.2.0-dev.52

- Finalizing a named credential rotation now previews the permanent removal of the old credential and requires `FINALIZE` confirmation.
- Active grace periods show the remaining time and warn that early finalization can disconnect clients that still use the old link.
- Cancellation leaves both the rotation database and generated dual-credential configuration unchanged.
- Regression tests prove cancellation, service-restart rollback and successful old-credential removal; automated `--expired` maintenance remains non-interactive and only removes expired records.

## 0.2.0-dev.51

- Non-root installation now gives an actionable `su -` path and explicitly states that sudo is not required.
- A fresh install preserves an existing orphaned `vp.previous` and its checksum instead of deleting the user's last rollback asset.
- Reinstallation stages the new rollback script and checksum separately, then restores the original pair if either commit phase fails.
- Installer smoke tests inject failure after each rollback-point commit and prove the current CLI and prior rollback assets remain unchanged.

## 0.2.0-dev.50

- Portable backups no longer include host-bound runtime data such as network rollback snapshots, OOM baselines, self-heal locks or nested managed backups.
- Restore no longer deletes or replaces the destination host's data directory while restoring node configuration, runtime parameters and secrets.
- Legacy archives that contain a `data/` payload remain readable, but that host-specific payload is intentionally ignored.
- Regression tests prove new archives exclude runtime data and both new and legacy restores preserve the destination host's network rollback and local-state markers.

## 0.2.0-dev.49

- Restore now rejects archives and SHA-256 sidecars that are not readable regular files, including symlinks.
- Backups without a SHA-256 sidecar are rejected by default instead of being accepted after a warning.
- Trusted legacy backups can still be inspected or restored only through the explicit `--allow-unverified` compatibility flag.
- Regression tests prove the secure default, explicit legacy path and sidecar-symlink rejection while still exercising unsafe-archive and database-integrity checks.

## 0.2.0-dev.48

- Network rollback now treats congestion-control and qdisc restoration as a compensated transaction.
- If qdisc restoration fails after congestion control changed, both values are restored to their pre-call state instead of leaving a mixed kernel configuration.
- Failed rollback keeps the persistent configuration and snapshot intact so the user can safely retry after the underlying write failure is resolved.
- Added a one-shot qdisc failure-injection regression test that proves compensation and the subsequent successful retry.

## 0.2.0-dev.47

- Network optimization now stages rollback snapshots and persistent sysctl configuration in their target directories, applies mode checks and commits each file atomically.
- Failure after a new snapshot commit or before configuration commit restores the original congestion control/qdisc, removes only the newly created snapshot and cleans all stage files.
- Existing unreadable/malformed snapshots and non-regular configuration targets are preserved and rejected rather than silently overwritten.
- Added fault-injection regression tests for both persistence phases alongside the existing performance-regression rollback test.

## 0.2.0-dev.46

- Added real DNS adaptation acceptance with one scenario following the host's measured public-DNS result and one scenario forcing public failure through a reserved unreachable address.
- Public resolvers are retained only after real query plus TCP 53 success; forced failure must select the existing system resolver without changing `/etc/resolv.conf`.
- Each selected DNS profile is placed into an isolated real Mihomo configuration and must resolve a hostname during a successful proxy request.
- Source-bound DNS evidence records only mode, result flags and resolver count, not resolver addresses; offline tests reject a re-signed result that omits system fallback.

## 0.2.0-dev.45

- Every real CPU quota profile now runs a bounded multi-worker saturation load concurrently with the four-client Mihomo transfer.
- Quotas below the host's actual online CPU capacity must produce at least one real `cpu.stat` throttling event; merely reading back `cpu.max` no longer counts as proof of enforcement.
- CPU evidence records whether throttling is required and the observed event count, while summary totals prove every profile received a saturation check.
- Offline evidence tests reject a re-signed quota row that claims throttling is required but records zero events.

## 0.2.0-dev.44

- Added real cgroup v2 CPU quota acceptance with both configuration generation and the real Mihomo process executed inside the same isolated quota.
- Every host tests 0.5, 0.999 and 1 CPU; hosts with at least two or four online CPUs extend the matrix through 1.001/1.5/2 and 2.001/4 CPUs without pretending unavailable hardware exists.
- Evidence proves exact quota detection, effective CPU count, GOMAXPROCS, sub-one-CPU profile/GOGC behavior, four-client complete transfers, cgroup throttling counters and unchanged formal services.
- Added source-bound CPU summary/CSV verification and an offline negative test rejecting a forged quota transition.

## 0.2.0-dev.43

- Expanded real-core memory acceptance from eight representative limits to fifteen limits covering both sides of every 96/160/320/640 MiB profile boundary.
- The matrix now proves 15 isolated core startups, 60 concurrent clients and exactly 60 MiB transferred while retaining hard cgroup limits, peak tracking and zero-OOM requirements.
- Local evidence verification checks every exact budget, profile, GOMEMLIMIT, GOGC and GOMAXPROCS transition, including equal budgets across adjacent threshold boundaries without regression.
- Authorized-host preflight inputs are now assigned and explicitly exported before the remote script, avoiding shell-specific temporary-assignment behavior.

## 0.2.0-dev.42

- Added a mandatory read-only authorized-host preflight before any source upload or test execution, plus a standalone `-PreflightOnly` mode.
- Preflight verifies the fixed public IP, Alpine/root environment, required commands, runnable/readable Mihomo, readable formal state, `/tmp` capacity and the exact Cloudflare transfer endpoint used by memory acceptance.
- When requested, it also verifies cgroup v2 memory capability or independent Tunnel token separation, free origin port, cloudflared availability and public-edge reachability without printing sensitive values.
- Full acceptance stores the redacted preflight result with SHA-256 and revalidates its semantics locally; offline tests reject a preflight that claims a required endpoint is unavailable.

## 0.2.0-dev.41

- Each enforced memory profile now runs four simultaneous 1 MiB downloads through the isolated real Mihomo process rather than a single transfer.
- Acceptance requires all four clients to succeed, verifies exactly 4 MiB per profile and 32 MiB across the eight-profile matrix, then confirms the core remains alive with zero OOM.
- Structured memory evidence records per-row concurrency and byte counts; local semantic verification rejects missing clients, truncated transfers and re-signed OOM results.

## 0.2.0-dev.40

- Replaced configuration-only memory profile checks with eight real Mihomo runs under isolated cgroup v2 hard limits from 64 through 2048 MiB.
- Every profile validates the generated budget and Go runtime settings, starts the real core, proves proxy egress, transfers 1 MiB, records `memory.peak`, requires zero `oom_kill`, then destroys its cgroup.
- Memory acceptance snapshots formal Mihomo/cloudflared state, PIDs, executable/cmdline digests, config, init scripts, databases and Tunnel token before and after the complete profile matrix.
- Added source-bound summary/CSV evidence and local semantic verification for exact limits, budgets, profiles, runtime tuning, observed peaks and formal-service invariants; offline tests reject a re-signed row reporting OOM.

## 0.2.0-dev.39

- Isolated acceptance now verifies the uploaded `vp.sh` against its 64-character SHA-256 before execution and binds both exact version and script digest into evidence.
- Formal-service invariants now cover sensitive state files, Tunnel token, the formal Mihomo binary, running executable images and hashed command lines in addition to service state, PIDs, config and init scripts.
- The Windows runner refuses non-empty evidence destinations and requires exactly one acceptance record proving the current source hash, fixed host and every mandatory result, including the requested Tunnel mode.
- Added an offline evidence verifier self-test that accepts a valid fixture, rejects content tampering and rejects forged source metadata even after its checksum sidecar is recomputed.

## 0.2.0-dev.38

- Extended the fixed authorized-host runner with optional independent Cloudflare Tunnel public-edge acceptance using only a remote token file path, host, path and fixed origin port supplied together.
- Added offline `-ValidateOnly` parameter checks, including rejection of partial inputs, relative/formal token paths, malformed hosts and paths, and unsafe origin ports without reading token content or connecting to a host.
- Cloudflared is discovered read-only only when public-edge acceptance is requested; executable discovery now handles empty output safely.
- CI checks all four public-edge parameters, forbids plaintext-token parameters and exercises valid and invalid parameter combinations.

## 0.2.0-dev.37

- Added a Windows PowerShell authorized-host runner fixed to `134.209.180.134:18750`; host and port are constants rather than user-overridable parameters.
- The runner enforces public-key-only SSH, uploads only four allowlisted acceptance files into a random `/tmp` directory, discovers the running Mihomo executable read-only and never performs a formal installation.
- It runs isolated acceptance plus memory profiles, downloads only redacted evidence, verifies every SHA-256 locally and removes the remote temporary source in `finally` handling.
- CI statically forbids password helpers/authentication and host overrides, checks the PowerShell AST, and retains the existing shell-side fixed-host guards.

## 0.2.0-dev.36

- Backup creation now refuses overwrite, requires SHA-256 and commits archive/checksum from same-directory temporary files; checksum commit failure removes the incomplete restore point.
- Added `vp backups` with per-restore-point size, embedded version and integrity/restorability status.
- Added `vp backup-prune --keep N --dry-run|--apply`: only the oldest fully verified project restore points are eligible, at least one is retained, and apply requires `PRUNE` confirmation.
- Corrupt backups, unrelated files and symlinked/escaped backup directories are never auto-deleted; regression tests cover seven valid points, invalid and unrelated files, zero-write preview, overwrite refusal and retention results.

## 0.2.0-dev.35

- Added `vp update --check` / `--dry-run`: it downloads and verifies the exact candidate, then reports current/candidate versions, change direction and immutable source without changing CLI or rollback files.
- Online update now stages and transactionally exchanges the previous CLI and checksum before atomically replacing the active CLI; any intermediate failure restores the exact prior rollback point while leaving the active CLI unchanged.
- Fault-injection tests cover failures after previous-CLI exchange and after checksum exchange, proving all pre-existing file hashes survive.
- The numbered update menu separates read-only checking from applying an update and requires typing `UPDATE` before replacement.

## 0.2.0-dev.34

- CLI rollback validates and stages the target version before replacing the active script, then exchanges active CLI, previous CLI and checksum through same-directory atomic moves.
- A failed exchange after either the active-CLI or previous-CLI step restores all three original files; fault-injection tests prove their hashes remain unchanged.
- The home dashboard and update menu now show the installed CLI version plus rollback availability, target version and checksum/syntax/version validity.
- Added `vp version-status` for a concise non-interactive current/rollback version summary; corrupted rollback artifacts are visibly marked and remain blocked.

## 0.2.0-dev.33

- Installer and self-update reject local test sources unless test hooks are explicitly enabled; non-official repository/ref sources now require a visible `VP_ALLOW_CUSTOM_SOURCE=1` opt-in.
- Commit resolution reads only the top-level GitHub commit SHA, avoiding accidental selection of nested tree or parent SHAs from compact or reordered JSON.
- Online update accepts only stable or `dev.N` project versions, rejects same-version/different-content replacements and blocks implicit downgrades; deliberate downgrade requires `vp update --allow-downgrade`.
- The candidate management script is staged inside the destination directory before atomic replacement, avoiding cross-filesystem `/tmp` moves.
- Installer replacement is transactional: initialization failure restores the previous CLI plus the exact pre-existing rollback script and checksum; failure-injection tests prove all three hashes remain unchanged.

## 0.2.0-dev.32

- Release asset parsing is independent of JSON line breaks and field order, including compact GitHub API responses and nested uploader objects.
- Mihomo now selects exactly one compatible or baseline architecture asset; cloudflared selects exactly one extensionless architecture asset and rejects ambiguous duplicates.
- Binary installation requires a 64-character hexadecimal SHA-256 digest and an official repository release-download URL whose final filename exactly matches the selected asset before any download starts.
- Supply-chain regression tests cover reordered compact JSON, escaped URLs, untrusted download hosts, short digests and duplicate matching assets.

## 0.2.0-dev.31

- Authorized-host acceptance can optionally validate an independent Cloudflare Tunnel using a separate binary/token/hostname/path/fixed origin port bundle.
- The harness rejects partial inputs, the known formal Tunnel token and hostnames present in the formal Mihomo database before changing test state.
- Optional Argo acceptance proves edge connections, two-stream public transfer, supervised cloudflared respawn and successful transfer after respawn without exposing credentials in evidence.

## 0.2.0-dev.30

- Isolated acceptance now proves formal Mihomo/cloudflared process IDs remain unchanged in addition to service states and config/init digests.
- Added backup dry-run/apply round-trip, configuration-drift self-heal and conditional IPv6 Reality loopback to the authorized-host acceptance flow.
- Successful acceptance writes a permission-restricted redacted evidence file plus SHA-256 outside the temporary test tree so results survive cleanup.

## 0.2.0-dev.29

- Reclassified test evidence so historical host results are not presented as proof for the current version; added a requirement-by-requirement completion audit and explicit remaining release gates.
- Removed two legacy system tests that performed formal `/usr/local/bin/vp` installation and stopped existing services, violating the mandatory isolation boundary.
- Real-core memory and acceptance tests now enforce the fixed authorized public IP `134.209.180.134` without an environment-variable bypass.

## 0.2.0-dev.28

- Self-heal now rebuilds missing, invalid or drifted Mihomo configuration from validated authoritative node/rotation state and uses the existing verified restart/rollback path.
- Invalid node or rotation databases are never guessed or overwritten; self-heal records a distinct state failure and returns non-zero for manual trusted-backup recovery.
- Tests prove drift is repaired automatically while a malformed live database and the existing generated configuration remain byte-for-byte unchanged.

## 0.2.0-dev.27

- Periodic/manual self-heal runs now use a PID-aware lock so overlapping timers cannot race into duplicate service restarts.
- Live locks cause a zero-impact skip; stale locks left by crashes are reclaimed automatically and the lock is removed on normal/signal exit.
- Consecutive identical healthy events are deduplicated while failures/recoveries remain fully recorded; tests cover live-lock skip, stale-lock recovery and log deduplication.

## 0.2.0-dev.26

- Cloudflare Tunnel metrics port now detects conflicts, automatically avoids Mihomo internal ports and persists the selected value for health/status and future updates.
- Tunnel installation includes the metrics-port state and runner in its atomic rollback boundary alongside binary, token and prior service state.
- Tests cover conflict-driven selection, successful persistence and both update/fresh-install failure paths leaving no new metrics-port state.

## 0.2.0-dev.25

- Mihomo mixed-proxy and controller ports now detect conflicts at core installation, automatically select free internal ports and persist them in authoritative state for later repair/update runs.
- Explicit user port overrides fail clearly instead of being silently changed; status shows the applied internal ports.
- Core-install rollback now restores the previous binary, state/config and `core.env`; failure-injection tests verify all three hashes remain unchanged after a forced restart failure.

## 0.2.0-dev.24

- Complete uninstall now previews, path-validates and removes the management-script rollback SHA-256 sidecar introduced in dev.19.
- Added residual-file coverage proving the CLI, previous CLI and previous-CLI checksum are all absent after recoverable uninstall.

## 0.2.0-dev.23

- Health checks now detect syntactically valid Mihomo configuration drift by rendering the expected configuration from authoritative node/rotation state and comparing it without exposing secrets.
- Safe repair restarts the core whenever generated configuration changes, not only when the process is absent or runtime limits change.
- Failed repaired-config startup restores both the pre-repair configuration and runtime environment; tests cover drift detection, repair and forced-restart rollback.

## 0.2.0-dev.22

- Dashboard service status now consistently honors custom/isolated core and Tunnel service names instead of using a hard-coded Tunnel name.
- The home conclusion detects invalid live node/rotation databases before reporting readiness.
- Active and expired credential rotations receive explicit outcome-first conclusions and next-step guidance; both counts are visible in status.

## 0.2.0-dev.21

- Added `vp restore BACKUP --dry-run` with archive, state-database and current-Mihomo validation before any project state is initialized or changed.
- Restore displays only a redacted scope summary (version/time, protocol counts, rotation count and token presence), then requires an explicit `RESTORE` confirmation to apply.
- Added evidence that dry-run leaves current state unchanged before the tested apply/rollback-capable restore path.

## 0.2.0-dev.20

- Centralized candidate-state validation now enforces supported protocols, exact field counts, UUID/port/key/path/host constraints and unique node names/listen ports.
- Credential rotations must reference an existing node of the same protocol, contain valid old/current UUIDs, match the node current UUID and use a valid time window.
- Restore and migration inherit these checks; tests prove duplicate listeners and inconsistent rotation records are rejected without changing live state.

## 0.2.0-dev.19

- Installer and self-update now create a permission-restricted SHA-256 sidecar for the previous management script.
- Rollback verifies the stored script before executing it and refuses syntax-preserving corruption; successful swaps regenerate the checksum for the new rollback target.
- Added complete bad-update rejection, update, rollback, checksum-tamper rejection and reinstall-backup tests.

## 0.2.0-dev.18

- Backup restore now accepts only the documented manifest/config/data layout and rejects unexpected top-level paths.
- Archives containing symlinks, hard links, devices or other special entries are rejected before extraction under root.
- Added portable round-trip backup/restore coverage and a malicious-symlink archive rejection test.

## 0.2.0-dev.17

- Cloudflare Tunnel installation and token rotation are now atomic across the binary, token file and service restart.
- A failed first install removes partial binary/token artifacts; a failed update restores the previous executable, token permissions and prior running/stopped state.
- Added failure-injection coverage for both update rollback and clean first-install rollback.

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
