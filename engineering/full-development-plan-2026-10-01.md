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
| DEV-01 | R-101..R-106, R-109 | Preserve existing normal app policy and bounded process-family selection | Existing M1 | Existing implementation; user acceptance pending |
| DEV-02 | R-107,R-108,R-110,R-112,R-114,R-116 | Complete Windows installation, protected recovery state, forwarding integration, fail-closed recovery and signing/build ordering | DEV-03 | In development |
| DEV-03 | R-011,R-110 | Self-signed development artifact chain; signed Core digest before Helper/UI, manifest before Broker, all components same source | Signing identity local; no formal release signing | Planned |
| DEV-04 | R-113,R-115 | Operator recovery diagnostics and publisher-verified atomic identity migration | DEV-02 | Planned |
| DEV-05 | R-120..R-124 | Preserve existing Agent ownership and attach/detach; integrate strict recovery into background runtime | Existing M2, DEV-02 | In development |
| DEV-06 | R-111,R-106,R-108,R-114,R-116 | macOS Network Extension, signed app identity, authenticated control, forwarding and lifecycle recovery, host integration | Apple entitlement/signing supplied by user for execution | Planned |
| DEV-07 | R-201,R-208 | Enhanced tray, actual active group/node navigation | Existing providers | Delegated: p2_tray_route |
| DEV-08 | R-202,R-207 | Actual config comparison and rule editing with bounded undo/restore and YAML synchronization | Existing configuration pipeline | Delegated: p2_config_rules |
| DEV-09 | R-203 | Bounded health checks, progress/errors, allowlisted diagnostic export | Existing diagnostic interfaces | Delegated: Antigravity fcx-r203-health-bundle-20261001-01 |
| DEV-10 | R-204 | PAC settings, native platform operations, persistence and stop/restore lifecycle | Existing system proxy pipeline | In development |
| DEV-11 | R-205 | Opt-in network-triggered profile selection, precedence/debounce, offline preservation | Existing connectivity/profile pipeline | Planned |
| DEV-12 | R-206 | Signed update manifest, bounded download/progress, platform trust, transactional install/rollback and UI | Release public trust identity; no private key in source | Planned |

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
