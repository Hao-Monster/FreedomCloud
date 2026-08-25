# FlClashX architecture v0.2

## Scope review

The approved roadmap is delivered as independently reviewable milestones:

1. **M0 — Connections quality gate (implemented on current branch).** Finish P0, remove
   unbounded caches, make refresh visibility-aware, harden diagnostics/helper,
   prove Zashboard independence, and ship a portable Windows VM test package.
2. **M1 — Non-strict application policy (implemented on current branch).** Add application identity, policy
   storage, rule compiler, UI and diagnostics using Mihomo PROCESS rules.
3. **M2 — Background Agent.** Move Core ownership and policy enforcement out of
   Flutter; implement attach/detach and the three exit actions.
4. **M3 — Windows strict mode.** Add the signed WFP package, broker, fail-closed
   state machine, DNS handling, upgrade/uninstall recovery and VM matrix.
5. **M4 — macOS strict mode.** Add the signed Network Extension and equivalent
   identity/recovery tests.
6. **M5 — P2 roadmap.** Deliver R-201 through R-208 as separate pull requests in
   the approved order.

M3 requires a Windows driver-signing identity and WDK/HLK release process. M4
requires an Apple Developer team, Network Extension entitlement, signing and
notarization. R-206 requires release-signing public keys and an offline private
key process. Code can prepare these interfaces, but release acceptance cannot
be fabricated without those external prerequisites.

## Target component model

```text
Flutter UI (low privilege)
  ├─ Connections projection (visible only)
  ├─ Application policy editor
  ├─ Tray / diagnostics / configuration diff
  └─ authenticated local IPC
                 │
Per-user FlClash Agent (low privilege, persistent)
  ├─ owns desired state and Core lifecycle
  ├─ compiles domain + application policies
  ├─ exposes bounded connection snapshots
  ├─ owns update verification and rollback state
  └─ coordinates one capture owner per flow
          │                         │
Mihomo Core                     Privileged broker
  ├─ TUN / system proxy         ├─ narrow authenticated IPC
  ├─ DNS / Fake-IP              ├─ Windows WFP operations
  ├─ PROCESS rules              └─ recovery/uninstall cleanup
  └─ External Controller
          │
      Zashboard (independent API consumer)
```

The UI never runs elevated. The privileged component must not accept arbitrary
commands, executable paths, environment paths, file-copy targets or unsigned
policy blobs. Its public surface is a small versioned command enum with strict
path and caller validation.

## Connections data path

1. Core produces one connection snapshot.
2. A persistent worker decodes JSON off the raster/UI isolate.
3. `ConnectionTracker` performs one O(n) ID diff and one process aggregation.
4. Immutable active, bounded closed and process projections are published.
5. Visible list/table widgets use builder virtualization and lazy icons.
6. Filtering and sorting operate on projections without mutating manager state.

Refresh policy:

- Visible Connections page: configured 100–10,000 ms, default 500 ms.
- Hidden page/window in M0: zero connection polling and zero icon extraction;
  becoming visible triggers one immediate refresh.
- Closed Flutter UI after M2: zero UI polling. Agent may keep a bounded journal.
- Requests/diagnostics/history/icon caches always have explicit limits.

Performance budgets for acceptance measurement:

| Scenario | Budget |
|---|---|
| Hidden UI | No high-frequency connection polling and no icon extraction. |
| Icon cache | At most 64 decoded application entries per platform cache. |
| Closed history | At most 300 entries, session scoped unless a later privacy design approves persistence. |
| Diagnostic file | At most 1 MiB, metadata-free. |
| 1,000 active + 300 closed | No overlapping polls; list/table builds only visible rows; no monotonic cache growth over a 30-minute synthetic run. |
| UI responsiveness | JSON/model decode stays off the UI isolate; refresh does not synchronously extract multiple Windows icons in one frame. |

Memory acceptance compares deltas against the same build's idle Flutter baseline.
An absolute Task Manager number includes Flutter engine, Core, shared pages and
OS accounting and is not by itself an actionable regression metric.

## Application policy model

```text
ApplicationIdentity
  id: stable UUID
  canonicalPath
  executableName
  publisher/signing identity
  bundle identifier (macOS)
  verified child identities[]

ApplicationPolicy
  identityId
  action: inherit | forceProxy | forceDirect | block
  targetPolicyGroup?  // forceProxy only
  enforcement: normal | strict
  enabled
```

Normal rules are inserted before the ordinary domain/IP rules:

- `PROCESS-PATH,<canonical path>,<target>`
- verified `PROCESS-NAME` fallback only when unambiguous
- `<target>` is a policy group, `DIRECT`, or `REJECT`

Strict rules are not represented as a promise in YAML alone. The platform
backend must report `armed` before the Agent marks a policy active. If capture or
the proxy route fails, the backend enters `blocking`, not `direct`.

## Strict capture state machine

```text
disabled → preparing → armed → degraded/blocking → recovering → disabled
                    ↘ failure ↗
```

- `preparing`: install/validate filters and exclusions before enabling policy.
- `armed`: selected flows have exactly one capture owner.
- `degraded/blocking`: Core/broker unavailable; selected flows are blocked.
- `recovering`: bounded retry with exponential backoff and an operator-visible
  reason; never removes the block before forwarding is healthy.
- `disabled`: filters and persistent recovery markers are removed atomically.

Core, Agent, broker, loopback proxy ports, TUN interface and already-redirected
flows are explicit exclusions to prevent loops and double capture.

## Security decisions

- No target-process injection, DLL proxying or remote CSS.
- Canonicalize and compare filesystem paths before privileged operations.
- Keep the SYSTEM Helper and its Core copy in the protected
  `Program Files\FlClashX Service` directory, including portable deployments.
- Use only the Core hash compiled into the Helper. A sibling hash file and the
  privileged unsigned Core-replacement endpoint are forbidden.
- Reject Core initialization or configuration reads outside the startup
  `SAFE_PATHS` data root.
- Disable standalone desktop Core updates until R-206 verifies signatures
  before stopping or replacing Core and provides rollback.
- Prefer OS-authenticated IPC (Windows named pipe ACL / macOS XPC) over an
  unauthenticated loopback HTTP control plane.
- Redact process paths, domains, IPs and configuration values from shareable
  diagnostics by default.
- Treat application paths as identity hints, not trust anchors; strict identity
  uses publisher/signature data.
- Persist a recovery marker before installing strict filters and clear it only
  after verified removal.

## Zashboard boundary

Zashboard depends on the External Controller endpoint and secret. It does not
depend on `ConnectionManager`, process grouping, Active/Closed UI state, request
log presentation or icon caches. Changes to those projections therefore must
not start, stop, reset or reconfigure the External Controller.
