# PR: process-centric connections and non-strict application routing

## Summary

Migrates the Koala-style Connections workflow into FlClashX while preserving
classic connections, Active/Log behavior and the independent Zashboard API
consumer. Adds privacy-safe diagnostics, Windows process-attribution repair,
bounded memory/polling policies and non-strict per-application PROCESS rules.

## Review order

1. Requirements, architecture and test plan under `engineering/`.
2. Connection tracker/manager/query and widget projection.
3. Per-application policy storage/compiler/UI.
4. Windows Helper service lifecycle and security boundary.
5. Performance limits, diagnostics and tests.

## Quality gates

- [x] Full Flutter tests pass locally.
- [x] Go Core tests pass locally.
- [x] Rust Helper tests pass locally.
- [x] Targeted analyzer has no errors or warnings.
- [ ] Clean Windows release build and artifact hashes recorded.
- [ ] Windows 11 VM checklist accepted by tester.
- [ ] No unrelated Purchase/navigation/i18n working-tree files in the PR.

## Explicitly deferred

Background Agent, OS-authenticated IPC, signed WFP strict mode, signed macOS
Network Extension and signed Core updater/rollback are separate milestones.
No remote branch, PR, merge, tag or release is created without authorization.
