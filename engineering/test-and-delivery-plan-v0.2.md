# FlClashX test and delivery plan v0.2

## Test policy

The development machine must not enable or change its system proxy, TUN/virtual
network card, WFP filters, DNS, routes or firewall. Local tests may use pure
functions, fakes, loopback-only IPC, synthetic connection JSON, static analysis,
builds and package inspection. Network-changing acceptance runs only in the
Windows 11 VM or an authorized macOS test host.

## Acceptance matrix

| Requirement/risk | Local automated evidence | VM / signed-host evidence |
|---|---|---|
| R-003/R-004 process and classic connections | Tracker/query/widget tests with full Mihomo payloads and 1,000-row virtualization. | Open Edge, browse, inspect process card/detail, switch classic mode. |
| R-005 attribution | Decode tests preserve `process` and `processPath`; diagnostics distinguish empty Core data from UI filtering. | Edge and Electron child-process cases on Windows 11. |
| R-006/R-007 diagnostics | Redaction assertions, throttling and 1 MiB rotation/limit tests where injectable I/O permits. | Export package and inspect for secrets/paths/hosts. |
| R-008 UAC/service | Unit tests for service-state decisions, protected service-copy commands, immutable Core hash, safe Core home and installer script inspection. | Fresh VM install, second start, moved portable package, repair and uninstall. |
| R-009 Zashboard | Static call-boundary test/review and existing panel build path. | Open in-app/external panel while connections refresh, pause and close rows. |
| R-001/R-002 performance | Synthetic benchmarks, non-overlap tests, hidden cadence tests, bounded-cache tests and 30-minute allocation trend. | Task Manager/Performance Recorder comparison using fixed scenarios. |
| R-109 normal application policy | Compiler unit tests and fake-Core integration tests. | Selected browser/app behavior under TUN. |
| R-108/R-110 strict Windows | State-machine, policy, rollback and broker contract tests; driver source invariants; loopback Core authentication; listener-retention, monotonic lease-handoff, TTL fallback and revoke-before-close tests; pinned-WDK compile and static analysis. | Signed WFP tests for TCP/UDP v4/v6, DNS, QUIC, crash, sleep, upgrade and uninstall; end-to-end redirect canary; Driver Verifier plus pool-tag measurements for cancelled, burst and sustained redirected TCP flows. |
| R-111 strict macOS | Shared policy contract tests and XPC/extension integration tests. | Signed/notarized Network Extension tests on supported macOS versions. |
| R-120–R-124 Agent | IPC/state-machine/reconnect tests and process lifecycle integration. | Close/reopen UI without interrupting traffic; verify UI memory is released. |
| R-201–R-208 | Per-feature unit/component/integration tests in separate PRs. | Feature-specific smoke and rollback tests. |

## TDD sequence for M0

1. Run the existing connections suite to establish green.
2. Add failing tests for bounded LRU behavior and hidden/visible polling cadence.
3. Implement the minimum cache and cadence changes; rerun target tests.
4. Add failing Rust tests for arbitrary helper update/start paths.
5. Implement canonical path restrictions and typed error outcomes; rerun Rust.
6. Add service decision tests where the Dart boundary can be isolated without
   invoking `sc.exe` or UAC.
7. Run connection tests, full Flutter tests, targeted analyzer, Rust tests, Go
   tests and Windows release build.
8. Review the final diff for unrelated files, secrets, debug output and cache or
   history structures without limits.

## TDD sequence for M2

1. Add failing Agent tests for singleton ownership, endpoint authentication,
   bounded frames, active-session replacement and lifecycle controls.
2. Implement the minimum per-user Agent protocol and make those tests green.
3. Add failing journal tests for confirmation-only recording, coalescing,
   ordering, capacity and replay failure; implement bounded replay.
4. Add failing crash/backoff/interrupt tests; implement generation-specific
   Core authentication and interruptible bounded recovery.
5. Add Helper tests proving unauthenticated start and stop are rejected, then
   require the per-user Helper credential and immutable Core hash.
6. Add Flutter protocol/packaging tests, then implement Agent-first attach,
   detach, UI restart and full-exit ownership.
7. Run loopback-only lifecycle tests for same-PID reattach, crash generation,
   old-session revocation, shutdown ACK and stop-during-start latency.
8. Measure idle Agent resources without enabling listeners, TUN, DNS, routes or
   system proxy; run static, unit, integration and release-build gates.
9. Rebuild the installer, inspect its contents/hashes and reserve all real
   networking/UAC/uninstall behavior for the Windows 11 VM.

## Windows VM checklist

1. Snapshot a clean Windows 11 VM.
2. Extract the portable package to a fixed directory.
3. First start: allow the one-time helper registration if required.
4. Exit and start again: no service delete/recreate UAC prompt.
5. Enable the existing virtual network card in the VM only.
6. Open Edge and browse `google.com`; verify Edge or its actual network child
   appears with icon, totals and rates.
7. Verify search by process, host, IP, proxy and rule; switch sort directions,
   process/classic and list/table modes.
8. Pause/resume, close one connection, close a filtered set, inspect closed
   history, clear history and open details.
9. Open Zashboard and exercise its connections/proxies pages.
10. Hide the UI for five minutes and record CPU/memory; verify connection polling
    stops, then reopen and verify an immediate refresh.
11. Confirm SCM points to
    `C:\Program Files\FlClashX Service\FlClashHelperService.exe`, not the
    extracted portable directory.
12. Export `connections_diagnostic.log` and application logs before restoring the
    VM snapshot.

## Git and pull-request plan

Current branch: `codex/koala-connections`.

Implemented commits:

- `6890522 feat(connections): add process-centric connection manager`
- `c50d548 chore(connections): add privacy-safe diagnostics`
- `260ea06 docs(connections): freeze v0.2 architecture and test plan`
- `d78e118 perf(connections): bound icon caches and reduce hidden polling`
- `8af6225 security(helper): constrain privileged core operations`
- `3598148 fix(windows): make helper service setup idempotent`
- `5bd9e2a fix(connections): require process metadata for process view`
- `03fd6d7 feat(connections): export privacy-safe diagnostics`
- `c727eda feat(routing): add bounded per-application policies`
- `bdada36 perf(connections): stop polling while view is hidden`
- `76d4195 perf(runtime): bound decoded images and restore proportional GC`
- `5e6ab91 security(helper): isolate privileged service binaries`
- `342b665 docs(delivery): record v0.2 release candidate gates`
- `43ac51d perf(build): stream release artifact hashing`
- `53b85dd fix(build): launch Inno compiler without shell splitting`
- `cb41855 fix(build): keep portable build independent of Inno`
- `4eafd12 feat(runtime): add authenticated background agent`
- `306c947 feat(desktop): detach UI from background agent`
- `1b3a2ef fix(build): embed VM acceptance metadata`

Only task files are staged. The pre-existing Purchase/QR/navigation/i18n working
tree changes are explicitly excluded. No remote push, PR creation, merge, tag or
release occurs without explicit authorization.

PR quality gates:

- Every accepted M0 behavior maps to a test or a named VM acceptance step.
- No new analyzer errors in changed files.
- Full Flutter tests, Rust tests, Go tests and Windows release build complete.
- No known Critical/High security issue in the changed attack surface.
- Portable artifact includes commit/build identity and SHA-256.
- Remaining signed-driver, entitlement and real-network items are marked NOT RUN
  rather than reported as passed.

## Local execution record

Environment: Windows development host, Flutter 3.41.7. No system proxy, TUN,
route, DNS, firewall, WFP or service installation was changed.

| Command | Result | Evidence |
|---|---|---|
| `flutter test` | PASS | 43 tests, 0 failed, 0 skipped; 19.2 seconds in the final run. |
| Metadata packaging TDD | RED → GREEN | Before implementation, `flutter test test/setup_test.dart` failed because `Build.writeWindowsTestPackageMetadata` did not exist; after implementation, 3 tests passed. |
| `go test ./...` in `core` | PASS | `core` passed; `core/state` has no tests. |
| M2 `cargo test --locked` in `services/agent` | PASS | 15 tests, 0 failed. |
| `cargo test --locked --features windows-service` in `services/helper` | PASS | 5 tests, 0 failed. |
| Agent/Helper `cargo clippy --all-targets ... -- -D warnings` | PASS | 0 Clippy warnings. |
| Targeted `dart analyze` (M2 runtime changes) | PASS with info | Exit 0; 0 errors, 0 warnings and 82 style infos. Build tooling separately retains one pre-existing warning. |
| Full `flutter analyze` | FAIL (baseline) | Exit 1; 699 repository issues. Four warnings are the removed-lint entry reported three times and the pre-existing `setup.dart` non-null assertion; the rest are infos. |
| Agent `cargo fmt --all -- --check` | PASS | Agent sources are rustfmt-clean. |
| Helper `cargo fmt --all -- --check` | FAIL (baseline) | Existing/user-unstaged `src/main.rs` import order and trailing blank lines in two untouched files; changed Helper hub passes Clippy/tests and was not reformatted over user work. |
| Loopback Agent lifecycle/crash/session integration | PASS | Same-PID detach/reattach, generation 1→2 replay, old-session revocation, shutdown ACK/endpoint cleanup and 28 ms stop-during-start response. |
| Idle Agent resource sample | PASS (diagnostic) | 6.74 MiB working set, 1.25 MiB private memory, six threads; loopback Core IPC only. |
| `dart run setup.dart windows --arch amd64 --out app` | PASS | Core, Agent, Helper, Flutter Windows x64 Release, portable ZIP and local installer built. |
| Installer execution on development host | NOT RUN | Deliberately reserved for the isolated VM because it changes service/network-related state. |
| Windows 11 proxy/TUN acceptance | NOT RUN locally | Deliberately reserved for the isolated VM. |
| Signed WFP strict mode | NOT RUN | M3 needs signing identity, WDK and HLK release process. |
| M3 Broker TCP runtime | PASS (local source/loopback) | 113 normal and 121 `production-host` Broker tests; normal/production Clippy and rustfmt; optimized production Broker build. No device, WFP, service, proxy, TUN, DNS, route or firewall state was changed. |
| M3 Agent strict orchestration | PASS (local pure/IPC-contract tests) | 42 tests, 0 failed/skipped; `cargo clippy --all-targets -- -D warnings`, rustfmt and optimized `flclash-agent.exe` build pass. Covers private-session request binding, prepare/Core/commit ordering, early-arm rejection, complete persistent-guard proof, explicit revoke after ambiguity, Broker-before-Core force-block/disable order and revoke retry. Production trigger, LocalSystem activation and real WFP/Core traffic are `NOT RUN`. |
| M3 shared Core UDP health ingress | RED → GREEN / PASS (local loopback only) | Initial Core target test failed because the UDP protocol did not exist. Final Core strict tests plus full `go test ./...`, `go vet ./...` and `go build ./...` pass. Contract has 7 tests; Agent has 42 tests. Broker has 117 normal and 125 `production-host` tests; normal/production Clippy, rustfmt and optimized `FlClashStrictBroker.exe` build pass. Covers exact loopback/owner PID, same pinned Core process, cross-language HMAC vector, exact frame size, stale/corrupt/correlation rejection and revoke. No application UDP payload, WFP, DNS, QUIC or external network traffic was exercised. |
| Signed macOS Network Extension | NOT RUN | M4 needs Apple entitlement, signing and notarization. |
| 30-minute VM memory trend | NOT RUN | Requires the fixed Windows 11 VM scenario. |

The most recent M2 run did not collect a new LCOV report. The prior M0/M1 LCOV
baseline was 1,435/22,693 lines (6.32%) for the complete Flutter application;
branch coverage is not emitted by this runner. Rust coverage tooling is not
configured. Coverage remains an explicit gap and never substitutes for the VM
lifecycle, UAC and real-network cases.
