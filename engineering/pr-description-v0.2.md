# PR: process-centric connections, application routing and background Agent

## Summary

Migrates the Koala-style Connections workflow into FlClashX while preserving
classic connections, Active/Log behavior and the independent Zashboard API
consumer. Adds privacy-safe diagnostics, Windows process-attribution repair,
bounded memory/polling policies and non-strict per-application PROCESS rules.
Moves desktop Core ownership into an authenticated per-user Agent so closing or
restarting Flutter no longer interrupts the proxy.

## Review order

1. Requirements, architecture and test plan under `engineering/`.
2. Connection tracker/manager/query and widget projection.
3. Per-application policy storage/compiler/UI.
4. Windows Helper service lifecycle and security boundary.
5. Performance limits, diagnostics and tests.
6. Agent protocol, confirmed-action journal, Core/Helper authentication and
   desktop attach/detach lifecycle.

## Quality gates

- [x] Full Flutter tests pass locally.
- [x] Go Core tests pass locally.
- [x] Rust Helper tests pass locally.
- [x] Rust Agent tests and Clippy gates pass locally.
- [x] Loopback lifecycle/crash/session integration tests pass locally.
- [x] Targeted runtime analyzer has no errors or warnings (style infos only).
- [x] Clean Windows portable and installer Release builds complete; artifact
      hashes are recorded in the delivery report.
- [ ] Windows 11 VM checklist accepted by tester.
- [x] Unrelated Purchase/navigation/i18n working-tree files are excluded from
      every task commit and the clean build worktree.

## Explicitly deferred

ACL-restricted named-pipe/XPC transport, signed WFP strict mode, signed macOS
Network Extension and signed Core updater/rollback are separate milestones.
The implemented Agent uses bounded loopback IPC plus random per-user
capabilities; the remaining same-user denial-of-service risk is documented. No
remote branch, PR, merge, tag or release is created without authorization.
