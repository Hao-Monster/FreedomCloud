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
| R-108/R-110 strict Windows | State-machine, policy, rollback and broker contract tests; driver static analysis. | Signed WFP tests for TCP/UDP v4/v6, DNS, QUIC, crash, sleep, upgrade and uninstall. |
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
| `flutter test` | PASS | 37 tests, 0 failed. |
| `go test ./...` in `core` | PASS | `core` passed; `core/state` has no tests. |
| `cargo test --locked --features windows-service` | PASS | 3 tests, 0 failed. |
| Targeted `dart analyze` | PASS with info | 0 errors, 0 warnings, 18 pre-existing style infos in inspected files. |
| Windows 11 proxy/TUN acceptance | NOT RUN locally | Deliberately reserved for the isolated VM. |
| Signed WFP strict mode | NOT RUN | M3 needs signing identity, WDK and HLK release process. |
| Signed macOS Network Extension | NOT RUN | M4 needs Apple entitlement, signing and notarization. |
| 30-minute VM memory trend | NOT RUN | Requires the fixed Windows 11 VM scenario. |

Coverage is not used as a repository quality gate. The release candidate still
runs Flutter coverage where supported and records the artifact/result in the
delivery report; coverage never substitutes for the VM acceptance cases.
