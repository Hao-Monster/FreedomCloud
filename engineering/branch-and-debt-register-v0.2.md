# FlClashX branch and technical-debt register v0.2

Status date: 2026-08-29

## Branch dependency ledger

| Branch | Base | Purpose | State | Merge rule |
|---|---|---|---|---|
| `codex/koala-connections` | project baseline | M0/M1/M2 | Code complete; Windows 11 VM acceptance open. | Do not close or merge until VM evidence is reviewed. |
| `codex/windows-strict-mode` | `45ec3b3` from M2 | M3 Windows strict capture | Active development in `E:\CodeWorkstation\FlClashX-m3`. | Stacked on M2; no M3 commit is added to the M2 branch. |

M2 fixes discovered during VM acceptance are committed first on
`codex/koala-connections`, then cherry-picked once onto M3 with both commit IDs
recorded below. Do not duplicate the fix by hand. Do not rebase, merge or rewrite
either branch without explicit authorization. Before a future PR, use
`git range-diff` to prove the M3-only range after M2 is finalized.

### Cross-branch fix ledger

| Issue | M2 commit | M3 commit | Verification | State |
|---|---|---|---|---|
| None yet | — | — | — | Open ledger |

## Technical-debt ledger

Debt is closed only by a commit plus named verification evidence. A comment,
UI switch, mock backend or deferred exception is not closure.

| ID | Severity | Debt | Consequence | Exit criterion | State |
|---|---|---|---|---|---|
| TD-001 | High | M1 application identity is path-only. | A replaced executable can inherit a strict policy. | Canonical WFP App ID plus verified signer/publisher identity; child identities explicit and bounded. | Open, M3 blocker |
| TD-002 | High | No WFP callout/Broker data plane exists. | “Strict” cannot guarantee proxy-or-block. | Signed callout, authenticated Broker, TCP/UDP v4/v6, DNS/QUIC VM evidence. | Open, M3 blocker |
| TD-003 | High | No persistent fail-closed recovery marker/filter set. | Broker/Core crash could allow physical-network fallback. | Persistent guard filters survive process death; restart/uninstall recovery proven. | Open, M3 blocker |
| TD-004 | Medium | Helper uses bounded loopback capability IPC. | A malicious same-user process can interrupt proxy state. | New strict Broker uses an ACL-restricted named pipe plus capability; Helper migration assessed separately. | Open |
| TD-005 | Medium | Normal proxy policy compiles to hard-coded `GLOBAL`. | It cannot select an arbitrary policy group. | Persist and validate an explicit target group with backward-compatible schema migration. | Open |
| TD-006 | Medium | M2 full analyzer baseline has 699 findings. | New findings are harder to distinguish from existing debt. | Changed-file warning gate plus a separately scoped baseline reduction plan. | Accepted baseline; no expansion |
| TD-007 | Low | Helper rustfmt baseline includes an unstaged import-order change and trailing blank lines. | Whole-crate format gate is red. | Resolve only after the owner’s dirty file is reconciled; never overwrite it from M3. | Deferred, isolated by worktree |
| TD-008 | External blocker | Driver signing identity, Visual Studio/WDK build integration and HLK release pipeline are unavailable in the current toolchain. | Driver cannot be release-signed or VM-qualified here. | Authorized certificate, WDK/VS build host, HLK results and signed package provenance. | Open |
| TD-009 | External blocker | Windows 11 M2 VM acceptance is still running. | M3 inherits any undiscovered Agent lifecycle defect. | Completed M2 checklist and reviewed logs. | Open; M3 stays stacked |

## Debt controls

- Strict UI controls remain hidden until the backend reports all required
  capabilities and a verified filter generation. There is no optimistic fallback.
- Every privileged command is a versioned enum; arbitrary executable, path,
  registry, service or shell operations are forbidden.
- Policy/app/session collections have explicit limits before entering privileged
  code. Driver classification paths do not allocate, block, log payloads or call
  user mode synchronously.
- M3 commits are split into design/contract, state machine, Broker, driver,
  packaging and verification units. A commit never mixes generated UI churn or
  unrelated M2 fixes.
- Real WFP, route, DNS, TUN, firewall, service and driver installation tests are
  prohibited on the development host and remain VM-only.
