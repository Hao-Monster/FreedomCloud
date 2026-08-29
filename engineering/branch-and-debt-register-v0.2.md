# FlClashX branch and technical-debt register v0.2

Status date: 2026-08-29

## Branch dependency ledger

| Branch | Base | Purpose | State | Merge rule |
|---|---|---|---|---|
| `codex/koala-connections` | project baseline | M0/M1/M2 | Code complete; Windows 11 VM acceptance open. | Do not close or merge until VM evidence is reviewed. |
| `codex/windows-strict-mode` | `45ec3b3` from M2 | M3 Windows strict capture | Active development in `E:\CodeWorkstation\FlClashX-m3`. | Stacked on M2; no M3 commit is added to the M2 branch. |

Latest M3 implementation evidence at this review point: `5f3185d`. M2 remains at `45ec3b3` in
its original worktree; no cross-branch fix has been required. The M2 worktree currently contains
uncommitted acceptance-time changes, so M3 treats that entire worktree as read-only and does not
stage, normalize or otherwise modify it.

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
| TD-001 | High | M1 application identity is path-only. | A replaced executable can inherit a strict policy. | Canonical WFP App ID plus verified signer/publisher identity; child identities explicit and bounded. | Partial through `11235f1`, `e6e07b5` and `5d0152c`: Broker replacement-locks each selected executable and the pinned `.sys`, verifies exact WFP App-ID plus trusted embedded/catalog publisher, rejects unpinned children, binds raw App-ID bytes to filter installation, and rejects an SCM driver image path that differs from the pinned file; release-signed package and VM proof remain |
| TD-002 | High | No WFP callout/Broker data plane exists. | “Strict” cannot guarantee proxy-or-block. | Signed callout, authenticated Broker, TCP/UDP v4/v6, DNS/QUIC VM evidence. | Partial through `aa45bc5`, `358f933`, `bd68b0a`, `4eb5721`, `144e2b6` and `eed5767`: driver attestation, canonical WFP enumeration, atomic real-BFE filter/management-object transactions, bounded policy/lease IOCTLs and a fail-closed four-callout kernel source path exist; relay, actual redirect mutation, driver build and VM proof remain |
| TD-003 | High | No persistent fail-closed recovery marker/filter set. | Broker/Core crash could allow physical-network fallback. | Persistent guard filters survive process death; restart/uninstall recovery proven. | Partial through `358f933`, `4eb5721` and `144e2b6`: persistent provider/sublayer/callout/guard objects are provisioned and structurally attested, cleanup refuses noncanonical same-provider objects, and the kernel source advertises only persistent fail-closed; the driver has not been built/loaded and crash/VM proof remains |
| TD-004 | Medium | Helper uses bounded loopback capability IPC. | A malicious same-user process can interrupt proxy state. | New strict Broker uses an ACL-restricted named pipe plus capability; Helper migration assessed separately. | Partial through `88a7d18`, `7f3b87d` and `bff7b0c`: authenticated deadline-bound data pipes, a separately bounded activation pipe, OS-token/PID identity and one supervised Agent session exist; production executable wiring and VM proof remain under TD-011/TD-016 |
| TD-005 | Medium | Normal proxy policy compiles to hard-coded `GLOBAL`. | It cannot select an arbitrary policy group. | Persist and validate an explicit target group with backward-compatible schema migration. | Open |
| TD-006 | Medium | M2 full analyzer baseline has 699 findings. | New findings are harder to distinguish from existing debt. | Changed-file warning gate plus a separately scoped baseline reduction plan. | Accepted baseline; no expansion |
| TD-007 | Low | Helper rustfmt baseline includes an unstaged import-order change and trailing blank lines. | Whole-crate format gate is red. | Resolve only after the owner’s dirty file is reconciled; never overwrite it from M3. | Deferred, isolated by worktree |
| TD-008 | External blocker | Driver signing identity, Visual Studio/WDK build integration and HLK release pipeline are unavailable in the current toolchain. | Driver cannot be release-signed or VM-qualified here. | Authorized certificate, WDK/VS build host, HLK results and signed package provenance. | Open; `4eb5721` adds the x64 KMDF project and mandatory package build-ID generator, while `f196a2a` adds a mandatory embedded package-identity input; compilation, SDV/CodeQL, signing and driver load are explicitly `NOT RUN` on this host |
| TD-009 | External blocker | Windows 11 M2 VM acceptance is still running. | M3 inherits any undiscovered Agent lifecycle defect. | Completed M2 checklist and reviewed logs. | Open; M3 stays stacked |
| TD-010 | High | Broker recovery directory ACL provisioning is not implemented and runtime verification is not VM-qualified. | A writable recovery directory or pre-existing state file would permit denial of service or policy-state tampering. | Installer creates a non-inheriting LocalSystem/Administrators ACL, Broker verifies it, and VM tamper tests pass. | Partial through `d915b65`: the public store verifies the directory, every opened state-file handle and every temporary-file handle against exact effective LocalSystem/Administrators full control, rejecting reparse points and extra/defaulted/null ACLs; installer provisioning, path-parent assurance and VM tamper proof remain activation blockers |
| TD-011 | High | Broker service primitives are not yet assembled into the production executable or VM-qualified under LocalSystem. | The authenticated IPC components cannot yet provide a release-ready privileged service. | SCM-hosted Broker has bounded workers, frame/read/write deadlines, cancellation, overload rejection and shutdown tests. | Partial through `3efd705`, `93077ba`, `88a7d18`, `f196a2a`, `7f3b87d` and `bff7b0c`: bounded IPC/worker/SCM primitives, mandatory embedded package identity, authenticated activation and a supervised one-Agent data session exist; real executable/component wiring, protected recovery configuration and VM stop/restart/multi-instance proof remain activation blockers |
| TD-012 | Medium | Publisher-preserving executable upgrade/re-enrollment is not implemented. | An application update is safely rejected but requires manual disable/re-enrollment. | Atomic identity migration verifies the same publisher, records the new App-ID/path and keeps guards installed throughout; rollback and VM update tests pass. | Open; safe failure behavior exists |
| TD-013 | High | Worst-case indexed WFP/filter-policy cardinality is not benchmarked. | Up to 4,224 executable identities can produce 8,448 persistent guards plus up to 8,448 redirects; BFE update latency, classify overhead or the bounded `METHOD_BUFFERED` upload allocation could violate the performance-first requirement. | On representative Windows 11 VMs, record transactional install/remove/upload time, p95/p99 connect latency, CPU, nonpaged-pool and working set at 1/128/512/4,224 identities; choose direct/chunked upload and an evidence-based supported limit without using a global fail-closed filter. | Open, performance activation blocker; `4eb5721` uses one bounded nonpaged snapshot allocation and hash-indexed classify lookup, but no representative measurements exist |
| TD-014 | High | The signed `.sys` trust lease is not yet release/VM-proven against the loaded service/device instance. | A stale or incorrectly configured kernel service could answer the fixed device path while a different file was inspected. | Verify SCM kernel-driver service type and canonical image path, pin signed-file digest and build identity in the package, and require the IOCTL handshake to return the same build identity before granting `driverSigned`. | Partial through `855fe86`, `5d0152c` and `f196a2a`: the Broker replacement-locks the signed file, hashes it through the locked handle, requires exact embedded file/publisher identities and an exclusive `SERVICE_KERNEL_DRIVER` image-path binding, then immediately requires the embedded 128-bit build identity from a read-only IOCTL handshake; real signed-package assembly and Windows 11 VM proof remain |
| TD-015 | High | The immutable policy/IOCTL contract has no separately revocable Broker listener lease (PID, TCP/UDP endpoints and nonce). | A redirect callout cannot safely choose a live loopback target, and embedding a stale PID/port in persistent policy would create denial or misdelivery risk. | Add a short-lived endpoint lease only after listeners are bound; bind it to policy digest and Broker process identity, clear it before relay teardown, and keep guards blocking whenever the lease is absent/expired. | Partial through `eed5767`: protocol v2 carries four exact loopback endpoints, policy binding, nonce and 1–30 second TTL; the driver references the IOCTL requestor's `PEPROCESS` and revokes on exit, expiry, policy replacement/unload or explicit IOCTL. Broker listener assembly, secure nonce generation/renewal, classify-path lease use and VM proof remain; redirect capabilities stay unadvertised |
| TD-016 | High | Per-user activation/bootstrap is not yet production-host/VM proven under LocalSystem. | A static secret, command-line secret or SYSTEM-owned data pipe would either expose control or prevent the interactive Agent from connecting; incomplete wiring could bypass cleanup on Agent exit. | A separate local activation protocol obtains the OS SID/session and process handle from the pipe, replacement-locks and verifies the exact packaged Agent image, creates a fresh bounded owner-only data pipe, rejects live-session takeover, and forces blocking/revocation on Agent exit; multi-session and restart behavior are VM-proven. | Partial through `f008dac`, `c645b1c`, `7f3b87d`, `bff7b0c` and `5f3185d`: the closed 4 KiB protocol carries only a fresh capability; the Broker derives SID/PID/session ID from the local pipe, rejects LocalSystem and session-zero activation, pins exact protected Agent path/file/publisher while retaining the process handle, generates a CNG-random data-pipe name, rejects a live takeover, and requires fail-closed cleanup before replacing/reaping an exited session. Production SCM wiring, successful end-to-end verification of the release-signed Agent and LocalSystem multi-instance/VM proof remain |

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
| `855fe86` | Shared packed C/Rust ABI and exact 128-bit signed-package build-identity handshake | Driver-channel 6 tests and WFP-control 3 tests; Clippy | Partial TD-014; rejects a stale or mismatched device response but SCM image-path binding remains |
| `4eb5721` | System-only non-PnP KMDF control device, immutable bounded policy snapshot, cache-aware rundown and four fail-closed WFP callout registrations | Broker 60 tests total; Clippy; build-header valid/invalid input checks; C driver build `NOT RUN` because VS/complete WDK are absent | Further partial TD-002/TD-003/TD-008/TD-013; advertises no redirect capability and cannot activate strict proxy mode |
| `144e2b6` | Transactional persistent WFP provider/sublayer/four-callout provisioning, service binding and exact management-object attestation | Broker 61 tests total; Clippy; pure structure tests only, with no development-host BFE mutation | Further partial TD-002/TD-003; malformed key collisions and same-provider noncanonical deletion candidates fail the whole transaction |
| `eed5767` | Protocol-v2 revocable endpoint lease bound to policy digest, exact loopback endpoints and a referenced Broker kernel process object | Broker 63 tests total; Clippy; source/ABI invariants; C driver build and process-exit VM exercise `NOT RUN` | Partial TD-015; redirect claims without a live lease are rejected, while the kernel still advertises no redirect capability |
| `5d0152c` | Read-only SCM kernel-service type/canonical image binding plus immediate device build-identity handshake | Broker 66 tests total; Clippy and rustfmt; pure SCM-path tests only, with no development-host service or driver mutation | Further partial TD-001/TD-014; release-signed package assembly and Windows 11 VM loaded-image proof remain |
| `f196a2a` | Mandatory embedded package-identity contract and replacement-locked signed-driver file SHA-256 pin | Broker 68 tests total; normal/`production-host` Clippy and rustfmt; missing-manifest build fails, fixture-backed feature build passes; no service/driver mutation | Further partial TD-008/TD-011/TD-014; actual release manifest, signing and VM proof remain |
| `f008dac` | Exact packaged Agent file/publisher/process-path verification with a retained kernel process handle | Broker 69 tests total; real catalog-signed process identity and exit-handle test; Clippy | Partial TD-016; protected release Agent and activation-pipe end-to-end proof remain |
| `c645b1c` | Closed 4 KiB Agent-to-Broker activation request/response contract | Contract 6 tests; Clippy and rustfmt | Partial TD-016; no SID, PID, path or service value is accepted from the frame |
| `7f3b87d` | Local-only activation pipe, OS token/PID extraction, exact packaged-Agent verification hook and CNG-random owner data-pipe name | Broker 72 tests total, including real named-pipe correlation/identity; normal and `production-host` Clippy | Further partial TD-004/TD-016; release-signed Agent success and LocalSystem VM proof remain |
| `bff7b0c` | Single active Agent session registry and bounded data-pipe session that requires fail-closed cleanup before exited-owner replacement/reaping | Broker 78 tests total, including real signed-process exit and data-pipe teardown; Clippy | Further partial TD-011/TD-016; production engine callback wiring and LocalSystem multi-instance/VM proof remain |
| `5f3185d` | Kernel-derived client Session ID binding for activation and data-session startup | Broker 78 tests total, including real named-pipe Session ID and Agent-exit cleanup; normal and `production-host` Clippy | Further partial TD-016; rejects LocalSystem/session-zero activation, while SCM/LocalSystem VM proof remains |

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
