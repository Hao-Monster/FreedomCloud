# FlClashX branch and technical-debt register v0.2

Status date: 2026-08-29

## Branch dependency ledger

| Branch | Base | Purpose | State | Merge rule |
|---|---|---|---|---|
| `codex/koala-connections` | project baseline | M0/M1/M2 | Code complete; Windows 11 VM acceptance open. | Do not close or merge until VM evidence is reviewed. |
| `codex/windows-strict-mode` | `45ec3b3` from M2 | M3 Windows strict capture | Active development in `E:\CodeWorkstation\FlClashX-m3`. | Stacked on M2; no M3 commit is added to the M2 branch. |

Current M3 head at this review point: `0a71d42`. M2 remains at `45ec3b3` in
its original worktree; no cross-branch fix has been required.

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
| TD-001 | High | M1 application identity is path-only. | A replaced executable can inherit a strict policy. | Canonical WFP App ID plus verified signer/publisher identity; child identities explicit and bounded. | Partial through `11235f1`: Broker reopens and replacement-locks every executable, verifies exact WFP App-ID plus trusted embedded/catalog signer, rejects unpinned children, and binds the verified raw App-ID bytes to filter installation; real WFP/VM proof remains |
| TD-002 | High | No WFP callout/Broker data plane exists. | “Strict” cannot guarantee proxy-or-block. | Signed callout, authenticated Broker, TCP/UDP v4/v6, DNS/QUIC VM evidence. | Partial through `f08fda5`: bounded plans and transactional control-plane adapter exist; real WFP objects, callout and relay do not |
| TD-003 | High | No persistent fail-closed recovery marker/filter set. | Broker/Core crash could allow physical-network fallback. | Persistent guard filters survive process death; restart/uninstall recovery proven. | Partial through `f08fda5`: atomic marker, guard-first plan and enumerate-after-mutate contract exist; real persistent WFP guards do not |
| TD-004 | Medium | Helper uses bounded loopback capability IPC. | A malicious same-user process can interrupt proxy state. | New strict Broker uses an ACL-restricted named pipe plus capability; Helper migration assessed separately. | Partial at `353ffd6`: authenticated local named-pipe primitive exists; production service host remains TD-011 |
| TD-005 | Medium | Normal proxy policy compiles to hard-coded `GLOBAL`. | It cannot select an arbitrary policy group. | Persist and validate an explicit target group with backward-compatible schema migration. | Open |
| TD-006 | Medium | M2 full analyzer baseline has 699 findings. | New findings are harder to distinguish from existing debt. | Changed-file warning gate plus a separately scoped baseline reduction plan. | Accepted baseline; no expansion |
| TD-007 | Low | Helper rustfmt baseline includes an unstaged import-order change and trailing blank lines. | Whole-crate format gate is red. | Resolve only after the owner’s dirty file is reconciled; never overwrite it from M3. | Deferred, isolated by worktree |
| TD-008 | External blocker | Driver signing identity, Visual Studio/WDK build integration and HLK release pipeline are unavailable in the current toolchain. | Driver cannot be release-signed or VM-qualified here. | Authorized certificate, WDK/VS build host, HLK results and signed package provenance. | Open |
| TD-009 | External blocker | Windows 11 M2 VM acceptance is still running. | M3 inherits any undiscovered Agent lifecycle defect. | Completed M2 checklist and reviewed logs. | Open; M3 stays stacked |
| TD-010 | High | Broker recovery directory ACL provisioning is not implemented and runtime verification is not VM-qualified. | A writable recovery directory would permit denial of service or policy-state tampering. | Installer creates a non-inheriting LocalSystem/Administrators ACL, Broker verifies it, and VM tamper tests pass. | Partial through `0a71d42`: the only public recovery-store constructor rejects reparse points, inherited/null/defaulted/extra ACEs, and any ACL other than exact LocalSystem/Administrators full control; installer provisioning and VM tamper proof remain activation blockers |
| TD-011 | High | Broker has no production service host, bounded concurrent named-pipe accept loop or per-request deadline. | The authenticated IPC primitive cannot yet provide resilient privileged service operation. | SCM-hosted Broker has bounded workers, frame/read/write deadlines, cancellation, overload rejection and shutdown tests. | Open, Broker activation blocker |
| TD-012 | Medium | Publisher-preserving executable upgrade/re-enrollment is not implemented. | An application update is safely rejected but requires manual disable/re-enrollment. | Atomic identity migration verifies the same publisher, records the new App-ID/path and keeps guards installed throughout; rollback and VM update tests pass. | Open; safe failure behavior exists |
| TD-013 | High | Worst-case indexed WFP filter cardinality is not benchmarked. | Up to 4,224 executable identities can produce 8,448 persistent guards plus up to 8,448 redirects; BFE update latency or classify overhead could violate the performance-first requirement. | On representative Windows 11 VMs, record transactional install/remove time, p95/p99 connect latency, CPU and working set at 1/128/512/4,224 identities; set an evidence-based supported limit without using a global fail-closed filter. | Open, performance activation blocker |

## M3 implementation evidence

| Commit | Scope | Verification | Debt impact |
|---|---|---|---|
| `f383da9` | Agent fail-closed strict state projection | Agent 23 tests; Flutter protocol 3 tests | Establishes state reporting; closes no WFP debt |
| `87eb0e0` | Bounded canonical policy and Broker request contract | Contract 4 tests; Agent 23 tests; Clippy | Partial TD-001/TD-004 only |
| `d163b5c` | Broker transaction and interrupted-cleanup engine | Broker fail-closed 10 tests; Clippy | Partial TD-002/TD-003 only |
| `f985288` | Atomic recovery marker and persistent revision high watermark | Recovery-file 3 tests plus Broker regression; Clippy | Partial TD-003; TD-010 remains |
| `353ffd6` | ACL-restricted local named pipe plus OS-token and capability authentication | IPC-auth 6 tests and Windows named-pipe loopback test; Clippy | Partial TD-004; TD-011 remains |
| `c56acf4` | Windows executable App-ID, Authenticode/catalog signer verification and replacement-lock lease | Broker 23 tests, including real Windows catalog signature and unsigned rejection; Clippy | Partial TD-001; TD-012 records upgrade workflow |
| `1cb9548` | Bounded, correlated and fail-closed Broker response contract | Contract 5 tests plus Broker regression; Clippy | Enables authenticated bidirectional IPC; closes no service-host debt |
| `5f23da2` | Authenticated command dispatch, Broker-owned health probe, force-blocking and bidirectional named-pipe exchange | Broker 26 tests, including Windows request/response loopback; Clippy | Partial TD-004; TD-011 remains |
| `11235f1` | Verified raw WFP App-ID set passed under executable replacement lease into every filter installation | Broker 28 tests, including memory/coverage bounds; Clippy | Further partial TD-001; real WFP proof remains |
| `7f8f0fb` | Deterministic per-App-ID indexed WFP plan with persistent guard/dynamic redirect ordering | WFP-plan 3 tests plus Broker regression; Clippy | Partial TD-002/TD-003; TD-013 records scale proof |
| `f08fda5` | Immutable snapshot and exact-enumeration WFP control-plane transaction adapter | WFP-backend 4 tests; Broker 33 tests total; Clippy | Partial TD-002/TD-003; concrete Windows backend/callout remain |
| `0a71d42` | Runtime verification of the protected recovery-directory owner and exact LocalSystem/Administrators DACL | Broker 37 tests total, including descriptor and public-constructor rejection; Clippy | Partial TD-010; installer provisioning and VM tamper proof remain |

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
