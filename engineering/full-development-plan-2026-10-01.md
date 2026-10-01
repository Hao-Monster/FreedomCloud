# Full requirement implementation plan

Baseline: requirements-baseline-v0.2.md; source c6247fbaab64da07f34c75b2b31029c7e572fab9.
User instruction: implement all approved functionality; user owns all execution,
testing and acceptance. No tests, builds, lint, device configuration or release
qualification are run by implementation workers. Source review and integration
remain the coordinator's responsibility. Code implementation is not acceptance.

## Coverage and work packages

| Work item | Requirements | Implementation and integration scope | Dependencies | State |
|---|---|---|---|---|
| DEV-00 | R-001..R-012 | Preserve bounded connection pipeline, diagnostics, UAC and existing UI; retain packaging identity | Existing M0 | Existing implementation; user acceptance pending |
| DEV-01 | R-101..R-106, R-109 | Preserve existing normal app policy and bounded process-family selection | Existing M1 | Existing policy plus installed/recent application picker implemented |
| DEV-02 | R-107,R-108,R-110,R-112,R-114,R-116 | Complete Windows installation, protected recovery state, forwarding integration, fail-closed recovery and signing/build ordering | DEV-03 | Windows code integrated; user execution remains pending |
| DEV-03 | R-011,R-110 | Self-signed development artifact chain; signed Core digest before Helper/UI, manifest before Broker, all components same source | Signing identity local; no formal release signing | Build/sign ordering and helper scripts implemented; artifacts not produced |
| DEV-04 | R-113,R-115 | Operator recovery diagnostics and publisher-verified atomic identity migration | DEV-02 | Identity migration and recovery diagnostics implemented |
| DEV-05 | R-120..R-124 | Preserve existing Agent ownership and attach/detach; integrate strict recovery into background runtime | Existing M2, DEV-02 | Durable intent and bounded background recovery implemented |
| DEV-06 | R-111,R-106,R-108,R-114,R-116 | macOS Network Extension, signed app identity, authenticated control, forwarding and lifecycle recovery, host integration | User accepted managed per-app VPN; Apple entitlement and MDM required | System extension, host UI, authenticated ingress and durable recovery source integrated; execution pending |
| DEV-07 | R-201,R-208 | Enhanced tray, actual active group/node navigation | Existing providers | Implemented and integrated |
| DEV-08 | R-202,R-207 | Actual config comparison and rule editing with bounded undo/restore and YAML synchronization | Existing configuration pipeline | Implemented and integrated |
| DEV-09 | R-203 | Bounded health checks, progress/errors, allowlisted diagnostic export | Existing diagnostic interfaces | Implemented by coordinator after Antigravity connection failure |
| DEV-10 | R-204 | PAC settings, native platform operations, persistence and stop/restore lifecycle | Existing system proxy pipeline | Implemented and integrated |
| DEV-11 | R-205 | Opt-in network-triggered profile selection, precedence/debounce, offline preservation | Existing connectivity/profile pipeline | Transport-based implementation integrated |
| DEV-12 | R-206 | Signed update manifest, bounded download/progress, platform trust, transactional install/rollback and UI | Release public trust identity; no private key in source | Desktop update code integrated; execution and acceptance remain user-owned |

## Execution order and ownership

1. Isolate worktrees from the exact baseline. Preserve all pre-existing worktrees.
2. Parallel first wave: tray/navigation, config/rules, Windows integration,
   Antigravity health-check implementation; coordinator owns PAC and shared wiring.
3. Review each returned diff, integrate only assigned files, resolve actual API
   mismatches by reading callers. Empty or out-of-scope worker output is not done.
4. Subsequent independent waves: network automation, updater, upgrade identity,
   macOS backend and signing-chain completion. Do not advertise absent backend
   capabilities or replace security checks with permissive stubs.
5. Record each item's real code status and remaining integration. Keep atomic
   commits and a reviewable integration branch; do not describe unexecuted checks
   as passed or merge unverified work under a false green claim.

## Handoff boundaries

- User owns build/test/lint/type checking, real-device validation and acceptance.
- Certificate purchase, Apple entitlement, secure boot changes, driver loading,
  machine certificate trust and releases are not performed by coding workers.
- Formal commercial signing remains on hold; self-signing is for test artifacts.
- Non-goals in the baseline remain excluded. No injection, dummy successes,
  placeholder features, broad identity wildcards or silent direct fallback.
- Rollback for code is an ordinary revert of the focused feature commit. Runtime
  rollback must be implemented by each feature where applicable.

## Implementation decisions

### Windows strict capture and signing

The driver reports implemented transport capabilities only when all eight
callouts, injection/redirect handles, receive queue, pool and process lifecycle
registration are available. Capability support is distinct from traffic health
and from user acceptance. The Broker retains policy guards during preparation,
checks the actual forwarding path before admission, and revokes leases on
failure. No fabricated healthy flag is an acceptable substitute for that path.

Each strict TCP dial and UDP association resolves its selected group to a fixed
protocol proxy object at the actual dial boundary. DIRECT, PASS and unsupported
exits fail closed; the original mutable group is never dialed after this check.
This gate is restricted to authenticated strict ingress. Ordinary traffic and
explicit non-strict DIRECT policies retain their prior behavior.

The canary runs in a bounded PID-scoped admission while production guards stay
installed. Actual kernel TCP redirect records, scoped UDP injection evidence
and authenticated Core DNS-restoration receipts are required. Both redir-host
and Fake-IP mapping are supported by the code. See
`services/strict-broker/STRICT_CANARY.md` for endpoints, budgets and runtime
dependencies; none of those probes was executed during development.

Installer order is protected directory/ACL, kernel service, Broker service.
Upgrade waits for services to stop before replacing binaries. Managed updates
must not force-kill arbitrary processes. Signing order is signed Core bytes,
Core digest, Helper and UI compilation, signed Agent, manifest, compiled Broker,
signed Broker/UI and final package checksums. A Broker from a different manifest
cannot be reused in the source-built chain.

Application migration is initiated from the policy row. The Agent retains
logical policy ownership; the Broker independently verifies the replacement
publisher and every bounded retained identity. Old identities remain guarded
while an old executable might still run. A newer revision is required even for
rollback; certificate rotation is not implicitly trusted.

Recovery uses a single bounded supervisor, authenticated status, five scheduled
attempts and visible exhaustion. Desired enable/disable intent must survive an
Agent restart in protected, atomically replaced per-user storage. Credentials
must never be persisted with that intent.

### Desktop UI and configuration

Enhanced tray menus reuse the same profile/group/node operations as the normal
UI on Windows, Linux and macOS. Traffic rates reuse existing events with a
two-second display limit. Connection navigation distinguishes the observed
historic chain from a policy's currently selected chain.

The actual configuration view obtains a deep-copied Core snapshot through the
existing authenticated IPC after ApplyConfig. Last-submitted UI configuration
is a separate, profile-bound source. Dynamic provider-expanded node state is
not falsely represented as RawConfig. Sensitive fields are hidden in the view.

Rules are edited against the real profile YAML, parsed by the existing Core
parser, with bounded document undo/redo and a disk-conflict check. Saving a
subscription edit explicitly confirms disabling automatic refresh. No source
rule edit silently replaces app-policy or runtime override behavior.

### PAC, automation and diagnostics

PAC uses an explicitly configured HTTP(S) URL and each OS's native PAC engine;
no script is executed by Flutter. PAC settings persist separately and integrate
with the existing system-proxy switch. OS setting changes are serialized.

Network automation is opt-in. Transport-to-profile rules are evaluated after
two seconds of stable network events in Ethernet/Wi-Fi/mobile/Bluetooth/other
priority order; missing profiles report failure, and offline does not stop the
Core. The initial feature is transport matching, not SSID/geolocation tracking.

One-click health checks have bounded timeouts and a single active operation.
Shareable JSON is an allowlist of check identifiers, statuses and elapsed times,
not raw logs or profiles. Local control-plane health is not a strict traffic
acceptance claim.

### Signed updates

Updates pin publisher trust in build configuration, authenticate the manifest,
bound downloads and validate platform, version and exact package bytes before
shutdown. Full-package updates preserve the Helper/Core relationship. Installed
Windows packages require a signed new Inno installer and a signed rollback
installer matching the currently running version; portable distributions retain
complete side-by-side versions. Recovery failure is reported, not hidden.

### macOS managed deployment decision

The user accepted managed per-app VPN on 2026-10-01. R-111 now uses a provisioned
Network Extension system extension for Developer ID distribution, loaded by
NEAppProxyProviderManager from MDM-owned profiles. Host activation, exact signed
identity export, profile generation, policy control and Xcode embedding are wired.
Unmanaged desktop capture and self-signed macOS Network Extension deployment are
not claimed. Apple entitlement, provisioning and MDM deployment remain external.

Provider configuration and replay generation live in System.keychain. The host
keeps its control key in its own Keychain and bootstraps through the OS VPN API.
Core control uses mutual HMAC with an inherited-stdin launch key, authenticated
SOCKS TCP and FCXD UDP. Explicit DIRECT/INHERIT apps must be removed from the MDM
mapping; no provider path creates a direct destination socket. Before an app rule
is edited, the host durably revokes the old provider policy to prevent stale
forwarding. Reapplication checks the exact MDM mapping and signature requirement.

Agent recovery persists both the successful Core configuration replay and strict
fixed-port credentials in Keychain, outside the ordinary journal. Explicit login
Agent registration is integrated with ownership and publisher checks; registration
is not a runtime health claim. The provider
never relaxes capture to compensate for a missing or failed Core. See
`macos-managed-strict.md` and `macos/StrictProxy/README.md` for deployment contracts.

## Execution record

- Antigravity task returned a language-server-not-running error and no diff.
  DEV-09 was implemented by the coordinator instead; it is not an Antigravity
  completion.
- First-wave tray, configuration, PAC/transport automation, diagnostics and
  Windows installer/signing changes are integrated in focused local commits.
- macOS managed provider, host, Xcode and Core/Agent source packages were developed
  concurrently in isolated worktrees after the managed deployment decision.
- Application discovery, durable identity/recovery and all eight P2 work
  packages are integrated. Windows strict source integration is saved through
  commit `3ab7416`; that is a code baseline, not a validated release.
- No tests, build, lint, typecheck, runtime probes, machine provisioning or
  acceptance have been executed by any worker for these changes.

## Remaining delivery boundary

R-111's former missing provider target, host activation, durable configuration and
macOS policy ingress now have integrated implementations. This is source delivery,
not a verified build or managed-device acceptance. Unsupported NE protocol/endpoint
shapes fail closed; authenticated UDP accepts IPv4/IPv6 and macOS-only FCXD v2
domain endpoints through the existing Core proxy resolver. Exact helper identities must be enrolled
separately; unknown helpers are blocked. Those limits are explicit and must not be
reported as unrestricted protocol or process-family coverage.

Signing artifacts, a real release feed, operating-system trust provisioning and
device acceptance are external execution inputs. Formal commercial signing
remains on hold; the Windows development signing path remains supported.

The integration checkout is `E:\CodeWorkstation\FlClashX-full-development` on
`codex/full-requirements-development`. The original checkout and pre-existing
branches/worktrees are preserved. Changes are saved in focused local commits;
the source branch is handed off through a Draft PR targeting main. Main
merge and distribution remain pending user-owned validation and required checks.
None of the commits is described as having passed CI.

The source handoff targets main under the user-authorized main integration scope.
Development is an ancestor behind main; targeting it would re-list already merged
main history. This exception does not bypass either branch protection or tests.

## Automated merge checks authorized

The user subsequently authorized Codex to execute the required automated checks
for PR #53: Flutter tests, Core Go tests and M3 package integrity checks. Earlier
NOT RUN entries describe the source-only handoff, not a permanent prohibition.
Real-device and business acceptance remain user-owned. Required checks must pass
on the final PR head before merging; no branch-protection bypass is permitted.
