# M2 background Agent detailed design

Status: implemented locally on `codex/koala-connections`; Windows 11 VM
acceptance remains pending.

## 1. Scope and invariants

M2 implements R-120 through R-124. It does not implement Windows WFP strict
capture, macOS Network Extension capture, target-process injection or signed
production release infrastructure.

The design has four non-negotiable invariants:

1. The Flutter process is a disposable presentation client and never becomes
   the long-lived owner of Core, TUN or system-proxy state.
2. Closing or restarting the UI must not restart Core or rebuild listeners.
3. Only an authenticated per-user UI session may control Agent, and only an
   authenticated Agent may initialize its Core generation.
4. Every queue, frame and replay structure is bounded; connection/log streams
   may shed load, but control results and lifecycle acknowledgements may not.

Active/Log presentation and Zashboard are deliberately outside this ownership
change. Agent forwards the existing Core protocol. Zashboard remains an
independent External Controller consumer.

## 2. Runtime model

```text
FlClashX Flutter UI (disposable)
  ├─ reads endpoint document from per-user data directory
  ├─ authenticates one loopback IPC session
  ├─ sends existing Core actions and namespaced Agent controls
  └─ detaches without stopping Core
                 │  protocol v1, random 256-bit capability
                 ▼
FlClashAgent (persistent, low privilege, one instance per user)
  ├─ owns Core generation and restart policy
  ├─ keeps the bounded confirmed-action journal
  ├─ revokes an older UI when a newer UI authenticates
  └─ delegates only fixed privileged Core operations when required
                 │  one-time generation token handshake
                 ▼
FlClashCore                    FlClashHelperService (Windows)
  ├─ existing action protocol  ├─ fixed executable and service Core paths
  ├─ TUN/system proxy          ├─ immutable embedded Core digest
  └─ External Controller      └─ authenticated bounded start/stop requests
```

The per-user singleton lock and endpoint document are stored under the same
application data root. The endpoint document contains protocol version, PID,
loopback port and a freshly generated 256-bit hexadecimal capability. It is
removed during graceful shutdown. Stale documents are harmless because the
client validates the schema and must also complete a live authenticated
connection.

## 3. IPC protocol and trust boundaries

### UI to Agent

- Transport: IPv4 loopback TCP, protocol version 1.
- Authentication frame limit: 4 KiB.
- Subsequent frame limit: 1 MiB.
- Parsing uses fixed-size incremental reads; a peer cannot force an unbounded
  `read_line` allocation before the size check.
- Authentication token comparison is constant time.
- Exactly one authenticated UI is active. A newly authenticated UI atomically
  cancels the old session, preventing split-brain control after restart.
- Agent controls are isolated under `_agent`; existing Core actions retain
  their wire shape and therefore do not collide with lifecycle controls.
- Control result and Core action response delivery uses backpressure.
  Unsolicited stream messages whose method is `message` may be dropped when the
  bounded output queue is saturated.

### Agent to Core

Each Core generation receives a different random token. Core accepts the
optional authenticated startup form and requires the first frame to be the
matching `_agentCore` handshake before accepting actions. The old one-argument
startup form remains for existing direct/debug integrations; release desktop
packages use Agent.

### Agent to Windows Helper

The Helper accepts only fixed start/stop operations. Both require a 256-bit
per-user credential stored under the application data directory. Start also
receives the generation-specific Core authentication token. Request bodies are
bounded, executable/config roots are canonicalized and restricted, and Core
integrity is compared with the digest embedded at Helper build time.

This capability model blocks unauthenticated and cross-user callers under the
expected per-user directory ACL. A malicious process already running as the
same user can read that user's credential and interrupt the proxy. This is a
known Medium local denial-of-service residual risk. Replacing loopback Helper
control with an ACL-restricted named pipe is defense in depth for a later
milestone; arbitrary privileged execution and file replacement are not exposed
now.

## 4. Lifecycle state machine

Agent Core state is `starting`, `ready`, `stopped` or `failed`. Every successful
start increments `generation`.

```text
stopped/failed ── start or attach ──> starting ── handshake ──> ready
      ▲                                  │                       │
      │                                  └─ failure/backoff ─────┘
      └──────── stopCore / shutdownAgent / bounded retry exhaustion
```

Unexpected Core exit is retried at most five times with 1, 2, 4, 8 and 16
second delays. Start, attach, replay and backoff all remain interruptible by
stop, restart and shutdown. Retry exhaustion produces an explicit failed state
instead of an infinite crash loop.

| User action | UI | Agent | Core/proxy | Observable result |
|---|---|---|---|---|
| Close UI | Saves preferences, marks UI inactive, detaches and exits. | Continues. | Continues unchanged. | Reopen attaches to the same PID/generation. |
| Restart UI | Detaches, launches replacement UI. | Continues. | Continues unchanged. | No listener rebuild or connection interruption. |
| Stop proxy | Remains open. | Remains available. | Existing proxy stop path runs; desired state becomes stopped. | UI can start it again without recreating Agent. |
| Full exit | Performs existing proxy/DNS cleanup, requests Agent shutdown, exits. | ACKs, stops Core, removes endpoint and exits. | Stops. | No background FlClashX runtime remains. |
| Core crash | Shows recovery only if needed. | Starts a new generation and replays confirmed desired state. | Restarts with bounded backoff. | UI stays attached or reconnects. |

`proxyRunning` is tri-state. `null` means no explicit start/stop action has been
confirmed, so first launch still honors the user's existing `autoRun` setting.
Explicit `true` or `false` survives UI detach/reattach.

## 5. Confirmed-action journal

Agent records only actions that Core has confirmed as successful. Failed,
timed-out or unconfirmed mutations are not replayed. The journal:

- contains at most 128 entries;
- coalesces state-setting keys so the newest desired value wins;
- preserves dependency order for initialization, configuration and listeners;
- excludes connection snapshots, request logs and other high-volume streams;
- replays once per new Core generation and reports replay failure explicitly.

This is crash recovery, not a second configuration database. Flutter's existing
persistent configuration remains the durable source used if a completely new
Agent PID is launched and the in-memory journal no longer exists.

## 6. Flutter attach and recovery behavior

`ClashService` chooses Agent whenever the packaged binary is present. It first
tries the published endpoint, otherwise launches Agent detached and waits for a
bounded readiness interval. Packages without Agent retain the legacy direct
host only for source/debug compatibility.

On reattach to the same Agent PID, Flutter refreshes groups/providers and UI
projections without calling `applyProfile`; rebuilding the listener would break
R-121. If the Agent PID changes, the existing recovery callback rehydrates
state from Flutter's persistent configuration. A same-PID transport loss does
not restart Core.

## 7. Resource and performance design

- Tokio runtime uses two worker threads.
- IPC queues are bounded to 256 entries; journal is bounded to 128 entries.
- No connection/log payload is retained by Agent for a detached UI.
- Closed Flutter UI means no Flutter engine, connection polling, icon decoding
  or widget work remains resident.
- Release profile strips symbols, enables LTO and abort-on-panic where defined
  by the Agent crate.
- Measured on the development host with loopback Core IPC only: Agent working
  set 6.74 MiB, private memory 1.25 MiB, six threads after one idle second.
  This is a local diagnostic measurement, not a VM production guarantee.

Backpressure intentionally favors correctness over telemetry completeness:
lifecycle/control results cannot be discarded; only unsolicited high-rate
stream events may be dropped for a slow/disconnected UI.

## 8. Packaging and upgrade behavior

`setup.dart` builds Agent for Windows, Linux and macOS. Windows and Linux CMake
install it beside Core; the macOS target copies and signs it with the app. The
Windows installer stops UI, Agent, Core and Helper during upgrade/uninstall so
files are not left locked.

The local installer is intentionally unsigned and may display Windows trust
warnings. Production publication still requires the project's release signing
process. The installer is not executed on the development host because it
would alter services and network-related state.

## 9. Test mapping and rollback

| Requirement | Automated evidence | Remaining acceptance |
|---|---|---|
| R-120 | Detach/reattach loopback lifecycle test preserves Agent PID. | Close UI during real VM traffic and verify continuity. |
| R-121 | Same-PID reconnect and Core generation tests; Flutter avoids listener rebuild. | Reopen UI and observe active flows/TUN in VM. |
| R-122 | Stop/restart/shutdown command tests, shutdown ACK and endpoint cleanup. | Exercise all three user actions in VM. |
| R-123 | Singleton, auth, session revocation, Core handshake and Helper auth tests. | Confirm one-time UAC/service lifecycle in VM. |
| R-124 | Flutter exits on detach; Agent retains no connection/icon projection. | Measure UI/Agent/Core memory separately in VM. |

Rollback is commit-level for source and installer-level for the VM. Before VM
installation, take a snapshot. If lifecycle or networking fails, collect the
diagnostic bundle, uninstall the test build, verify Helper/Agent/Core are gone,
and restore the snapshot. Do not downgrade over a running Agent.
