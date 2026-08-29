# M3 Windows strict application proxy detailed design

Status: approved requirements R-101 through R-116; implementation in progress
on `codex/windows-strict-mode`. This document does not claim a signed or
VM-qualified driver.

## 1. Product contract

Strict mode strengthens, rather than replaces, existing domain/IP routing. For
every explicitly selected Windows application family:

- `forceProxy`: redirect the flow into the FlClashX/Mihomo data path or block it;
- `block`: block the flow at WFP;
- never silently permit a physical-network fallback;
- keep enforcement active while Flutter is closed;
- preserve the normal Mihomo domain/IP rules after capture.

`DIRECT` remains an explicit normal-routing action and is not called strict.
Kernel/system, protected-process, WSL/VM/container and delegated-service traffic
is outside the application identity guarantee until its actual network process
is explicitly selected.

## 2. Evidence-based architecture decision

Windows Filtering Platform ALE connect redirection is the selected mechanism.
The callout changes an application's remote endpoint to a local Broker. The
Broker owns two sockets: the redirected inbound socket and a new outbound proxy
socket. It retrieves WFP redirect records/context from the first and applies the
redirect record to the second, preserving proxy-chain tracking and preventing
loops.

Primary references:

- Microsoft, *Using Bind or Connect Redirection*:
  https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection
- Microsoft, *Using Proxied Connections Tracking*:
  https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-proxied-connections-tracking
- Microsoft, `SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS` and context:
  https://learn.microsoft.com/en-us/windows-hardware/drivers/network/sio-query-wfp-connection-redirect-records
- Microsoft, WFP filtering conditions and `FWPM_CONDITION_ALE_APP_ID`:
  https://learn.microsoft.com/en-us/windows-hardware/drivers/network/filtering-condition-identifiers
- Microsoft, WFP object management and transactions:
  https://learn.microsoft.com/en-us/windows/win32/fwp/object-management

Target components:

```text
Flutter UI (low privilege, disposable)
       │ existing authenticated Agent IPC
       ▼
FlClashAgent (per user)
  ├─ desired strict policy and state projection
  ├─ requires complete Broker capability proof
  └─ never reports armed optimistically
       │ ACL named pipe + per-session capability
       ▼
FlClashStrictBroker (LocalService/SYSTEM, narrow surface)
  ├─ signer/App-ID verification
  ├─ recovery marker and WFP transaction owner
  ├─ local TCP/UDP redirect relay
  └─ health/capability/filter-generation attestation
       │ IOCTL + WFP provider/sublayer/callouts
       ▼
Signed FlClashStrictCallout.sys
  ├─ ALE_CONNECT_REDIRECT V4/V6
  ├─ ALE_AUTH_CONNECT V4/V6 fail-closed guard
  └─ immutable bounded policy snapshot
       │
       └─ Broker → Mihomo SOCKS/TUN/DNS path → selected policy group
```

The existing Helper remains responsible only for its fixed Core service
operations. Expanding it into a generic driver/Broker executor is forbidden.

Before opening the fixed callout device, the Broker replacement-locks and
verifies the packaged `.sys`, queries SCM with read-only rights, and accepts
only an exact `SERVICE_KERNEL_DRIVER` whose non-expandable canonical image path
matches that locked file. It then opens the device and immediately requires a
read-only IOCTL snapshot carrying the same package-injected 128-bit build ID.
Any type, path or build mismatch prevents the channel from being constructed;
no capability is inferred from the device name alone.

The production Broker build embeds a bounded, closed-schema package manifest.
The manifest pins the signed driver's SHA-256, publisher-certificate SHA-256
and build ID; the driver hash is computed through the same replacement-locked
handle used for signature verification. Enabling the production-host feature
without an explicit absolute manifest build input is a build error. Runtime
arguments cannot substitute a driver path, digest or publisher identity.

## 3. Application identity

Policy input is not a raw path wildcard. Broker canonicalizes the file, obtains
the WFP byte-blob application identifier with `FwpmGetAppIdFromFileName0`, and
verifies the Authenticode publisher/signing chain. A strict family contains one
primary identity and an explicit bounded set of verified child identities.

```text
StrictApplicationIdentity
  identityId: UUID
  canonicalPath
  wfpAppIdDigest
  publisherCertificateSha256
  productName? / originalFilename?       // diagnostics only
  verifiedChildren[]                     // max 32 per family
```

An upgrade may migrate a path only when the new binary's publisher identity
matches the stored publisher and the migration is recorded atomically. File
names, directory similarity and process ancestry alone never authorize a new
identity.

## 4. Policy and capability contract

Each policy bundle is canonical JSON with protocol version, monotonically
increasing revision, creation time, application identities, action and target
group. It is limited to 128 families and 1 MiB before Broker parsing. Broker
computes a SHA-256 digest over the canonical representation and returns it with
the installed filter generation.

Required capability bits are:

```text
driverSigned, identityVerified,
tcp4Redirect, tcp6Redirect,
udp4Redirect, udp6Redirect,
dnsCaptured, quicCaptured,
redirectLoopProtected, persistentFailClosed, recoveryVerified
```

Agent enters `armed` only when all bits required by the selected policy are
true, revision/digest match, Broker heartbeat is current, Core/TUN/DNS and relay
health are good, and the persistent guard generation is enumerably installed.
Missing UDP or QUIC proof therefore cannot produce a partially strict success.

## 5. Fail-closed state machine

```text
disabled → preparing → blocking → armed
    ▲           │           │       │
    │           └ failure ──┘       ├ heartbeat/Core/Broker loss
    │                               ▼
    └──── verified removal ← recovering/blocking
```

- `disabled`: no M3 provider filters and no recovery marker.
- `preparing`: identities, signatures, Core/TUN/DNS, ports and driver are
  validated; no user-visible success is reported.
- `blocking`: persistent per-app v4/v6 TCP/UDP guard filters and recovery marker
  exist, but forwarding is not completely healthy. Selected traffic is blocked.
- `armed`: matching redirect filters, relay and Mihomo path are healthy; the
  persistent guard remains as the fallback.
- `recovering`: bounded retry rebuilds dynamic redirect state while the
  persistent guard continues to block.

Filter lifetime is deliberately asymmetric:

1. Provider/sublayer and fallback guard filters are persistent.
2. Redirect filters and Broker session objects are dynamic.
3. If Broker dies, dynamic redirects disappear automatically while persistent
   guards continue blocking.
4. Restart reads the recovery marker, verifies actual WFP objects by GUID and
   digest, and starts in `blocking`, never `disabled`.
5. Disable/uninstall removes redirects first, keeps guards during teardown,
   removes guards transactionally, verifies enumeration, then clears the marker.

This uses WFP transactions for atomic groups. It never deletes another
provider's objects and never treats “not found” as proof of successful cleanup
without enumerating the FlClashX provider/sublayer.

The management graph is also sealed: one persistent provider is bound to the
`FlClashStrictCallout` kernel service, one maximum-weight persistent sublayer is
bound to that provider, and four persistent management callouts are bound to
their exact ALE layers. Startup creates only missing objects in one transaction.
An existing key is accepted only when its provider, service, layer, flags,
provider data and display identity are canonical. Filter cleanup performs the
same complete structural validation before deleting anything; an unexpected
same-provider object aborts and rolls back the whole transaction.

## 6. Data plane

### TCP IPv4/IPv6

The callout at ALE connect redirect checks redirect state, original app ID and
the immutable policy snapshot. Matching `forceProxy` flows are redirected to a
Broker loopback listener; matching `block` flows are blocked. The Broker queries
the original destination/context and redirect record, opens the outbound proxy
socket, applies the redirect record, and relays with bounded buffers and
half-close propagation.

The Mihomo-facing adapter must carry the original destination through SOCKS5 or
an equivalent existing supported ingress. Broker and Core executables, Broker
listeners, loopback, the TUN adapter and already redirected flows are explicit
exclusions.

The pinned Mihomo v1.19.28 source and its
[official listener contract](https://wiki.metacubex.one/en/config/inbound/listeners/)
support
multiple SOCKS listeners with an independent `proxy` field. M3 therefore uses
one reserved loopback-only, authenticated SOCKS ingress per distinct target
policy group rather than reusing the public `mixed-port`. The Agent injects
those reserved listeners into the Core configuration through a private
Agent/Core control path, and Core reports the addresses it actually bound. The
Broker accepts a target-group mapping only after an authenticated SOCKS probe
and OS verification of the packaged Core process owning the endpoint. Neither
an arbitrary Agent-supplied port nor a successful TCP connect is forwarding
health. Listener names, credentials and ports are session-scoped, bounded and
removed before the Broker endpoint lease is revoked.

The reserved-listener injection, bound-address report, Core socket-owner proof
and SOCKS health probe described above are design commitments, not current
capability claims. Redirect capability bits remain off until all four exist.

This mapping is compatible with the normal per-application policy schema:
version-1 persisted proxy entries migrate to `GLOBAL`, while version-2 entries
carry the explicit group. If that group is absent from the active profile, the
normal rule compiler emits `REJECT` and a redacted aggregate diagnostic instead
of silently falling back to `GLOBAL`, ordinary rules or a direct route. Strict
mode remains `blocking` until the corresponding reserved ingress is proven.

The persistent policy snapshot deliberately does not contain a listener PID or
port. Those values are process-lifetime state and would become unsafe after a
Broker crash or PID/port reuse. A separate endpoint lease is required:

```text
StrictEndpointLease
  protocol, revision, policyDigest
  Broker process identity held by the driver (not an unverified numeric PID)
  TCP v4/v6 and UDP v4/v6 loopback endpoints
  random 128-bit lease nonce
  monotonically increasing lease generation and bounded expiry
```

The LocalSystem Broker binds every listener first, then sends the lease over a
System-only driver device. Redirect filters are installed only after the driver
attests the same revision/digest and live lease generation. Missing, expired or
revoked lease state always classifies selected proxy traffic as block. Teardown
removes dynamic redirects first, revokes the lease, closes relay sockets and
only then considers persistent guard removal. A process-exit callback revokes
the held Broker process identity immediately; a numeric PID alone is forbidden.

The protocol-v2 implementation constrains lease TTL to 1–30 seconds and accepts
only exact `127.0.0.1`/`::1` addresses with nonzero ports. The driver obtains the
requestor PID from the KMDF request itself, immediately resolves and references
the corresponding `PEPROCESS`, and never accepts a user-supplied PID. The image
uses the force-integrity linker flag required for process callbacks. Policy
replacement/unload revokes the lease first; expiry, explicit revocation and the
referenced process exit use the same rundown-protected destruction path. This
milestone does not enable redirect capability bits or mutate connect requests.

### UDP, DNS and QUIC

UDP is not declared complete by reusing the TCP relay. A separate association
table with idle expiry, datagram size bounds, IPv4/IPv6 parity and SOCKS5 UDP or
equivalent Mihomo ingress is required. UDP/443 is QUIC and must pass the same
strict policy. DNS from selected applications must be redirected to Mihomo DNS;
direct physical-interface port 53/853 is guarded.

Initial strict acceptance requires Mihomo Fake-IP/virtual-network-card mode so
domain mappings remain available to existing domain rules. Real-IP domain
restoration is a separate proof item and cannot be inferred from an IP-only WFP
context.

ALE connect redirection can cover connected UDP. Unconnected datagram send,
DNS and QUIC coverage must be proven through the required bind/resource or
datagram-layer path and VM bypass matrix before any UDP/DNS/QUIC capability bit
is advertised. Until that proof exists, the driver returns no such capability
and the Agent remains `blocking`.

## 7. Broker IPC and privileges

- Transport: versioned Windows named pipe, not a public TCP port.
- ACL: LocalSystem, the owning interactive user SID and Administrators for
  recovery only; remote clients rejected.
- Authentication: OS token/impersonation check plus a random Agent session
  capability. Both must succeed.
- Bootstrap: a separate local-only activation pipe accepts a closed 4 KiB frame
  containing only request ID and fresh 256-bit capability. SID and PID come
  exclusively from the impersonated token and `GetNamedPipeClientProcessId`;
  the interactive Session ID comes from `GetNamedPipeClientSessionId`.
  LocalSystem and Session 0 activation are rejected. The Broker opens that PID,
  requires the exact protected packaged Agent path, replacement-locks the image,
  verifies embedded file/publisher digests, and retains the process handle for
  exit detection.
- Package verification is startup-cached: the Agent image is hashed and
  signature-checked once, then held replacement-locked by a shared trust lease.
  Rejected activation attempts compare only the kernel-derived process image
  path/liveness against that lease and never repeat file hashing or signing
  work. Each accepted session retains the shared file lock independently.
- Session: after verification, the Broker creates a CNG-random owner-only data
  pipe with a fixed worker bound. A live Agent cannot be replaced. An exited
  Agent can be reaped or replaced only after fail-closed backend cleanup
  succeeds; cleanup failure preserves the prior recovery/session state.
- Runtime ownership: the SCM host derives only fixed package paths and a direct
  Windows ProgramData Known-Folder recovery path. Recovery ACL verification
  precedes persistent WFP provisioning. WFP, driver and recovery handles are
  created and used by one Engine Actor; four active/four queued data requests
  are bounded, while lease-revoke/block/shutdown commands use a separate
  priority channel between transactions. Raw WFP handles are never marked
  `Send` or shared across pipe threads.
- Until real loopback listeners, relay probes and lease renewal exist, the
  production health probe always reports unavailable. Proxy commit therefore
  fails closed; block-only policy remains usable and no placeholder health is
  advertised.
- Commands: `preparePolicy`, `commitPolicy`, `forceBlocking`, `disablePolicy`,
  `status`, `diagnostics`; no arbitrary command/path/registry/service API.
- The Broker reopens and validates executable handles to prevent path-swap
  races. UI-supplied signer claims are never trusted.
- Diagnostics contain identity IDs, state/reason codes, revision/digest and
  counters; no destination host/IP, payload, token or full user path by default.

## 8. Performance and resource limits

- Driver classify path performs no heap allocation, blocking I/O, payload log,
  registry access or user-mode round trip.
- Policy snapshots are immutable and swapped atomically; maximum 128 families
  and 32 child identities per family.
- App-ID lookup is hash-indexed; expected classify complexity is O(1).
- Broker has bounded concurrent TCP sessions, UDP associations, per-flow buffers
  and diagnostic ring. Overload transitions the affected selected flow to block,
  never direct.
- Heartbeats are low frequency and independent of the Flutter window.
- Benchmarks record classify latency, relay throughput, CPU, working set,
  allocation trend and overload rejection without enabling WFP on the
  development host.

## 9. Test and release gates

Local non-network tests:

- policy schema, canonical serialization, digest and size/count bounds;
- every legal/illegal state transition and stale revision/heartbeat;
- incomplete capability matrices always remain `blocking`;
- path/signer mismatch, child-family bounds and replay/rollback;
- named-pipe authorization and malformed frame fuzzing with a fake Broker;
- WFP policy-plan generation and GUID ownership using fake engine interfaces;
- driver compile/static analysis when the WDK build host is available.

Windows 11 VM tests:

- signed driver install/upgrade/uninstall and BFE/service restart;
- TCP/UDP IPv4/IPv6, DNS, QUIC/HTTP3 and Electron child processes;
- Core, Agent, Broker and UI crash in every state;
- sleep/resume, network change, route loss and proxy-node failure;
- physical-interface bind/bypass attempts result in proxy or block;
- filter enumeration and ordinary networking after disable/uninstall;
- Zashboard and normal unselected application rules remain unchanged.

Release is blocked without a trusted signing identity, WDK/HLK evidence,
complete protocol capability proof and the VM matrix. Test signing is permitted
only inside an explicitly isolated VM and is never labeled a production build.
