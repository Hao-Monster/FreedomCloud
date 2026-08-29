# FlClashX branch and technical-debt register v0.2

Status date: 2026-08-29

## Branch dependency ledger

| Branch | Base | Purpose | State | Merge rule |
|---|---|---|---|---|
| `codex/koala-connections` | project baseline | M0/M1/M2 | Code complete; Windows 11 VM acceptance open. | Do not close or merge until VM evidence is reviewed. |
| `codex/windows-strict-mode` | `45ec3b3` from M2 | M3 Windows strict capture | Active development in `E:\CodeWorkstation\FlClashX-m3`. | Stacked on M2; no M3 commit is added to the M2 branch. |

Latest M3 implementation evidence at this review point: `bd68b0a`. M2 remains at `45ec3b3` in
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
| TD-001 | High | M1 application identity is path-only. | A replaced executable can inherit a strict policy. | Canonical WFP App ID plus verified signer/publisher identity; child identities explicit and bounded. | Partial through `11235f1` and `e6e07b5`: Broker replacement-locks each selected executable and the pinned `.sys`, verifies exact WFP App-ID plus trusted embedded/catalog publisher, rejects unpinned children, and binds raw App-ID bytes to filter installation; loaded-driver binding and VM proof remain |
| TD-002 | High | No WFP callout/Broker data plane exists. | “Strict” cannot guarantee proxy-or-block. | Signed callout, authenticated Broker, TCP/UDP v4/v6, DNS/QUIC VM evidence. | Partial through `aa45bc5`, `358f933` and `bd68b0a`: driver attestation, canonical WFP enumeration, atomic real-BFE filter transactions and a bounded IOCTL policy channel exist; provider/callout registration, kernel classify path, listener lease, relay and VM proof remain |
| TD-003 | High | No persistent fail-closed recovery marker/filter set. | Broker/Core crash could allow physical-network fallback. | Persistent guard filters survive process death; restart/uninstall recovery proven. | Partial through `358f933`: the concrete backend uses a non-dynamic BFE session for transactional persistent guards and independently enumerates their canonical structure; no driver callout, installed object or crash/VM proof exists yet |
| TD-004 | Medium | Helper uses bounded loopback capability IPC. | A malicious same-user process can interrupt proxy state. | New strict Broker uses an ACL-restricted named pipe plus capability; Helper migration assessed separately. | Partial through `88a7d18`: authenticated, deadline-bound named-pipe and SCM host primitives exist; production executable wiring and VM proof remain under TD-011 |
| TD-005 | Medium | Normal proxy policy compiles to hard-coded `GLOBAL`. | It cannot select an arbitrary policy group. | Persist and validate an explicit target group with backward-compatible schema migration. | Open |
| TD-006 | Medium | M2 full analyzer baseline has 699 findings. | New findings are harder to distinguish from existing debt. | Changed-file warning gate plus a separately scoped baseline reduction plan. | Accepted baseline; no expansion |
| TD-007 | Low | Helper rustfmt baseline includes an unstaged import-order change and trailing blank lines. | Whole-crate format gate is red. | Resolve only after the owner’s dirty file is reconciled; never overwrite it from M3. | Deferred, isolated by worktree |
| TD-008 | External blocker | Driver signing identity, Visual Studio/WDK build integration and HLK release pipeline are unavailable in the current toolchain. | Driver cannot be release-signed or VM-qualified here. | Authorized certificate, WDK/VS build host, HLK results and signed package provenance. | Open |
| TD-009 | External blocker | Windows 11 M2 VM acceptance is still running. | M3 inherits any undiscovered Agent lifecycle defect. | Completed M2 checklist and reviewed logs. | Open; M3 stays stacked |
| TD-010 | High | Broker recovery directory ACL provisioning is not implemented and runtime verification is not VM-qualified. | A writable recovery directory or pre-existing state file would permit denial of service or policy-state tampering. | Installer creates a non-inheriting LocalSystem/Administrators ACL, Broker verifies it, and VM tamper tests pass. | Partial through `d915b65`: the public store verifies the directory, every opened state-file handle and every temporary-file handle against exact effective LocalSystem/Administrators full control, rejecting reparse points and extra/defaulted/null ACLs; installer provisioning, path-parent assurance and VM tamper proof remain activation blockers |
| TD-011 | High | Broker service primitives are not yet assembled into the production executable or VM-qualified under LocalSystem. | The authenticated IPC components cannot yet provide a release-ready privileged service. | SCM-hosted Broker has bounded workers, frame/read/write deadlines, cancellation, overload rejection and shutdown tests. | Partial through `3efd705`, `93077ba` and `88a7d18`: overlapped I/O has total deadlines and cancellation, the fixed worker pool rejects overload and abandons timed-out execution lanes without spawning replacements, and SCM state/control handling exists; real component wiring, LocalSystem multi-instance, recovery configuration and VM stop/restart proof remain activation blockers |
| TD-012 | Medium | Publisher-preserving executable upgrade/re-enrollment is not implemented. | An application update is safely rejected but requires manual disable/re-enrollment. | Atomic identity migration verifies the same publisher, records the new App-ID/path and keeps guards installed throughout; rollback and VM update tests pass. | Open; safe failure behavior exists |
| TD-013 | High | Worst-case indexed WFP/filter-policy cardinality is not benchmarked. | Up to 4,224 executable identities can produce 8,448 persistent guards plus up to 8,448 redirects; BFE update latency, classify overhead or the bounded `METHOD_BUFFERED` upload allocation could violate the performance-first requirement. | On representative Windows 11 VMs, record transactional install/remove/upload time, p95/p99 connect latency, CPU, nonpaged-pool and working set at 1/128/512/4,224 identities; choose direct/chunked upload and an evidence-based supported limit without using a global fail-closed filter. | Open, performance activation blocker |
| TD-014 | High | The signed `.sys` trust lease is not yet bound to the exact loaded service/device instance. | A stale or incorrectly configured kernel service could answer the fixed device path while a different file was inspected. | Verify SCM kernel-driver service type and canonical image path, pin a build identity in the signed package and require the IOCTL handshake to return the same build identity before granting `driverSigned`. | Open; current channel is fail-safe but not activation-ready |
| TD-015 | High | The immutable policy/IOCTL contract has no separately revocable Broker listener lease (PID, TCP/UDP endpoints and nonce). | A redirect callout cannot safely choose a live loopback target, and embedding a stale PID/port in persistent policy would create denial or misdelivery risk. | Add a short-lived endpoint lease only after listeners are bound; bind it to policy digest and Broker process identity, clear it before relay teardown, and keep guards blocking whenever the lease is absent/expired. | Open; kernel redirect capability must remain unadvertised |

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
| `3efd705` | Overlapped named-pipe connect/read/write with total deadlines and cancellation drain | Broker 40 tests total, including silent-client and idle-connect deadline tests; Clippy | Partial TD-011; removes indefinite pipe I/O |
| `93077ba` | Fixed-size named-pipe/handler worker pool with OS overload rejection, bounded shutdown and poisoned-lane retirement | Broker 43 tests total, including stuck-handler and saturation tests; Clippy | Partial TD-011; LocalSystem multi-instance proof remains VM-only because owner SID is deliberately denied pipe-instance creation |
| `88a7d18` | SCM dispatcher, service-status lifecycle and stop/shutdown/preshutdown cancellation adapter | Broker 45 tests total; SCM pure-state tests and Clippy | Partial TD-011; production executable wiring and SCM VM lifecycle proof remain |
| `d915b65` | Handle-bound ACL verification for existing and newly-created recovery state files | Broker 46 tests total, including explicit/inherited file-DACL allowlists; Clippy | Further partial TD-010; closes the pre-existing-file ACL gap but not installer/VM gates |
| `aa45bc5` | Windows control bridge combines monotonic driver attestation with enumerated filter inventory | Broker 49 tests total; Clippy | Partial TD-002/TD-003; rejects generation rollback and inconsistent unloaded capability state |
| `358f933` | Concrete BFE engine with atomic replace/remove transactions, persistent guards, dynamic redirects and canonical structural enumeration | Broker 52 tests total; Clippy | Further partial TD-002/TD-003; local tests compile/pure-validate only and never mutate development-host WFP |
| `e6e07b5` | Replacement-locked `.sys` Authenticode/catalog trust and pinned publisher verification | Broker 53 tests total, including a real signed Windows system driver and mismatch rejection; Clippy | Further partial TD-001/TD-008; release signer/build/loaded-image binding remain |
| `bd68b0a` | Versioned bounded driver wire format, payload digest, strict snapshot parser and cancellable total-deadline IOCTL channel | Broker 57 tests total; Clippy | Further partial TD-002; no target device was opened locally and kernel counterpart/VM proof remain |

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
