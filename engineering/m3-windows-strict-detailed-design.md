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

The Core half of reserved-listener injection and bound-address reporting now
exists behind the authenticated Windows Agent/Core channel. It accepts at most
128 distinct real proxy groups, binds authenticated TCP-only SOCKS listeners to
ephemeral `127.0.0.1` ports, rejects stale generations and removes the listeners
on stop, configuration replacement or explicit revocation. UI-originated use of
the reserved action is rejected by the Agent. The Agent now also owns a private
Broker activation/session client and a tested orchestration model that orders
Broker prepare before Core ingress, Core ingress before Broker commit, Broker
force-blocking before an explicit newer-generation Core revoke, and Broker
disable before Core cleanup. An ambiguous Core response cannot collapse into a
local `Unchanged` result, and cleanup is not reported disabled until the Core
revoke is correlated. These are currently library/runtime primitives rather than
a product trigger: no UI or background policy source invokes them yet. Core
socket-owner/authentication proof and the bounded Broker TCP relay exist in
source, but redirect capability bits remain off until production wiring and the
driver/VM gates complete.

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
System-only driver device. The production runtime shares the driver's one
exclusive authenticated device handle with the control plane and serializes all
policy and lease IOCTLs. Redirect filters are installed only after the driver
attests the same revision/digest and live lease generation. Missing, expired or
revoked lease state always classifies selected proxy traffic as block. Runtime
teardown revokes admission (or conservatively waits for the six-second TTL to
expire) before closing relay endpoints; the policy transition then removes
dynamic redirects while persistent guards continue blocking. A process-exit
callback revokes the held Broker process identity immediately; a numeric PID
alone is forbidden.

The protocol-v2 implementation constrains lease TTL to 1–30 seconds and accepts
only exact `127.0.0.1`/`::1` addresses with nonzero ports. The driver obtains the
requestor PID from the KMDF request itself, immediately resolves and references
the corresponding `PEPROCESS`, and never accepts a user-supplied PID. The image
uses the force-integrity linker flag required for process callbacks. Policy
replacement/unload revokes the lease first; expiry, explicit revocation and the
referenced process exit use the same rundown-protected destruction path.

The TCP source path now registers `classifyFn1` callouts, caches one
provider-bound redirect handle, and mutates v4/v6 connect requests inline only
after an exact App-ID policy hit, proxy action, TCP protocol, safe non-loopback
original destination and current revision/digest/TTL lease all agree. The
112-byte context binds the original destination and target group to the lease
generation, nonce and policy digest. Self-redirection state is queried only at
the redirect layer; the authorization guard follows the layer contract by
requiring the redirected flag, original-destination metadata and current
leased Broker PID. Missing metadata, another redirect provider, stale policy,
unsupported transport or any allocation/API error remains block. Lease renewal
changes generation without terminating an already-authorized flow, so
redirect reauthorization binds the existing context to the stable policy while
the guard still binds the current Broker PID. Broker accepted-socket validation
accepts only the current or immediately previous attested generation with the
same nonce; this bounded window closes the driver-to-Broker renewal handoff and
older queued contexts fail closed.

The production TCP runtime now binds exact dual-stack listeners plus reserved
UDP loopback sockets. Core additionally binds one shared UDP ingress socket per
strict generation, independent of target-group count. Broker health frames are
fixed at 80 bytes and carry protocol/kind, generation, a 128-bit key identifier,
a random 128-bit nonce and HMAC-SHA256. Invalid, oversized, stale or
unauthenticated frames are silently discarded. Broker proves every TCP SOCKS
ingress and the shared UDP socket belong to one pinned live Core process, then authenticates every
per-group key through at most eight 256 KiB-stack probe workers without issuing
an external CONNECT. It then
starts a 2–16 worker TCP pool, activates a CNG-random six-second lease and renews
it every two seconds while rechecking Core listener ownership. A duplicate pair
of TCP socket handles keeps endpoints bound if the accept loop exits before the
renewal worker can revoke admission. Successful revocation is immediate; a
failed or ambiguous IOCTL waits through the conservatively tracked TTL before
endpoint handles are released.

These are source-level invariants only. TCP redirect and loop-protection
capability bits remain disabled until the driver compiles under the pinned WDK,
passes static analysis and Driver Verifier, and completes the Windows 11 VM
matrix with the production Broker runtime.

### UDP, DNS and QUIC

UDP is not declared complete by reusing the TCP relay. A separate association
table with idle expiry, datagram size bounds, IPv4/IPv6 parity and SOCKS5 UDP or
equivalent Mihomo ingress is required. UDP/443 is QUIC and must pass the same
strict policy. DNS from selected applications must be redirected to Mihomo DNS;
direct physical-interface port 53/853 is guarded.

The shared Core UDP endpoint introduced by `ec6437c`/`939c98a` and extended by
`231f10f` supports both health proof and a private data protocol. The Rust wire
codec in `d833af0` shares a fixed Go/Rust HMAC vector, and `95e1096` adds the
matching persistent Broker transport. Data frames
use an 80-byte canonical header followed by a 1–16 KiB payload and a 32-byte
HMAC-SHA256 tag. The header binds direction, generation, 128-bit credential ID,
128-bit association ID, monotonic sequence, canonical IPv4/IPv6 endpoint and
payload length. Outbound and reply directions use distinct kinds. Reserved
bytes, zero IDs/sequences/ports, non-canonical mapped addresses, loopback,
link-local, multicast, broadcast, unsafe reply sources, wrong generation,
wrong source socket, replayed sequence and invalid tags are rejected before the
payload enters Mihomo.

Core owns one receive goroutine, at most 1,024 associations and at most 256
in-flight payload buffers (4 MiB at the 16 KiB maximum). Associations expire
after 90 idle seconds and use a 64-packet sliding replay window. Their Mihomo
NAT keys are precomputed once and include generation, credential and association
identity; valid payloads are routed with the exact prepared `SpecialProxy`
group. HMAC states and payload buffers are pooled. Oversized Windows datagrams
that return `WSAEMSGSIZE` are consumed and discarded without terminating the
generation-scoped service. Broker must allocate cryptographically random,
generation-unique association IDs; a live collision across credentials fails
closed.

Broker owns one connected exact-loopback UDP socket per transport, fixed send
and receive frame buffers, stable integer credential indexes and a hard limit
of 1,024 live associations. Target-group/credential changes on an association,
unknown keys, invalid HMACs, stale/replayed replies and oversized datagrams fail
closed; a rejected datagram does not poison the following valid sequence. This
per-datagram path has no heap allocation or atomic reference-count operation.

The production Broker runtime owns this reusable bridge and feeds captured
driver datagrams into this transport. It pre-arms one lease-owner Direct-I/O
receive before opening UDP admission, owns the bridge for the forwarding-runtime
lifetime and propagates worker failure into verified lease/gate revocation before
teardown. Driver execution and end-to-end VM behavior are not proven. Therefore
the implemented path cannot yet satisfy
`udp4Redirect`, `udp6Redirect`, `dnsCaptured` or `quicCaptured`.

`8134220` defines the driver/Broker datagram transfer boundary without enabling
it. One direct-I/O batch is capped at 256 KiB and 64 records; every payload is
1–16 KiB. The fixed 96-byte batch header binds direction, lease generation,
policy revision, policy digest and lease nonce. Each 80-byte record header binds
a nonzero flow token and sequence, target-group index, flags and canonical
same-family local/remote endpoints. Records are eight-byte aligned with required
zero padding. The Rust decoder validates the complete batch once and then yields
borrowed payload slices, avoiding one heap allocation per datagram. Unknown
flags, unsafe endpoints, trailing bytes and nonzero reserved/padding bytes fail
closed.

The production lease-renewal path increments its generation while retaining the
same activation nonce. A receive completion can race one renewal, so Broker
admits captured batches only for the current or immediately previous attested
generation while requiring the same policy revision, policy digest and nonce.
Older batches fail closed. Returned reply batches use the current identity; the
driver must bind their flow tokens to state created within that same live Broker
activation. Revocation, expiry, policy change, Broker exit or nonce change
invalidates all flow and generation state. Capability bits remain off until the
complete capture/reinjection implementation exists and is VM-proven.

The production runtime stores that two-generation window behind one read/write
lock. Renewal retains the write guard across the driver lease mutation and the
window update, so bridge decode cannot observe a newly accepted driver generation
with stale userspace admission state. This lock is a renewal/control-plane
boundary, not a classifier or per-packet kernel lock.

`f9a8470` adds cancellable Direct-I/O calls on the already opened, attested
overlapped device handle. A pending receive does not hold the control-plane
mutex, so lease renewal and fail-closed policy commands cannot wait behind the
data path. No second open is attempted against the exclusive control device.
`METHOD_OUT_DIRECT` is used for driver-to-Broker captured batches and
`METHOD_IN_DIRECT` for Broker-to-driver reply batches; both retain the 256 KiB
hard boundary.

`0f51dca` adds the Broker association state needed for asynchronous UDP rather
than assuming one reply for each request. It preallocates two hash indexes and
caps them at 1,024 flows. A flow token is bound once to one Core association,
target-group index, flags and local/remote endpoint pair. Captured and reply
directions each use a 64-packet replay window, and state expires after 90 idle
seconds. Unknown associations, endpoint/group/flag drift, ID collisions and
capacity overflow fail closed. Payloads are not retained in this table.

`b99a668` composes those pieces into a reusable Broker bridge without enabling
the production capability. One dedicated receive worker waits on the pending
Direct-I/O request and a manual-reset cancellation event, so shutdown can use
one exact `CancelIoEx` instead of cancelling and reissuing an IOCTL on a short
polling cadence. The bridge owns exactly two reusable 256 KiB capture buffers;
the receiver and Core owner each use a 512 KiB stack. The Core owner validates
the complete borrowed batch, updates the bounded association table, sends over
one persistent authenticated UDP transport, and combines up to 64 asynchronous
Core replies into one returned batch. A single captured datagram may produce
zero, one or multiple replies. Saturation, malformed identity, route drift,
unknown reply association and submission failure stop the bridge fail closed.
The bridge baselines the driver's monotonic injection-health snapshot at startup
and, only while an injection is unresolved, samples it at most once per 100 ms.
Any new completion failure, partial batch, counter rollback or accounting drift
stops the bridge; an idle bridge issues no health IOCTL. Production forwarding-
runtime ownership now pre-arms and owns this bridge. The Engine Actor checks
worker liveness every 25 ms without network I/O or allocation; on failure it
marks pending receive cancellation as expected, revokes and verifies the
endpoint lease/gate, stops renewal and bridge workers, stops TCP listeners and
forces blocking. This source/loopback proof is not a substitute for WDK and VM
fault testing, so this component cannot advertise UDP support.

`4b2031e` adds the matching KMDF request boundary without pretending the data
plane is complete. The default sequential queue performs only bounded validation
and forwards one exact 256 KiB receive request to a manual queue, allowing lease
renewal and fail-closed controls to continue while that request is pending. Both
queued and driver-owned request counts must be zero before another receive is
accepted, bounding locked receive memory to 256 KiB. Receive admission requires
the live lease-owning Broker PID. Production pre-arm is admitted for that exact
lease owner while the gate remains closed, serialized with lease mutation and
followed by a manual-queue restart after a prior purge; reply submission still
requires active UDP admission. Submitted reply batches are parsed without
allocation and must match the current lease generation, revision, digest and
nonce plus every ABI size, alignment, padding, UDP, endpoint and flag invariant.
Valid replies now continue through exact flow lookup, resource admission and WFP
injection initiation. UDP/DNS/QUIC capability bits nevertheless remain off until
end-to-end driver execution, completion fault handling, DNS/QUIC behavior and VM
qualification are proven.

`c71e5d2`/`07d8933`/`94b9eb3` add the bounded flow-provenance foundation.
Per-App-ID `ALE_FLOW_ESTABLISHED_V4/V6` filters use the inspection action and
return only `CONTINUE`; they never permit or block at a
layer whose contract forbids those actions. One persistent global filter per
datagram family invokes a `CONDITIONAL_ON_FLOW` callout, so traffic without an
associated context does not enter the packet hot path. The driver caps state at
1,024 nonpaged contexts, binds each to the exact policy digest, lease nonce and
target group, and uses reference counting so a concurrent flow-delete callback
cannot free creator-owned bookkeeping. Lease replacement, revocation and unload
stop new associations, remove existing contexts and drain them before callout
unregistration.

`56b6a05` adds a separate two-phase UDP admission gate; an endpoint lease alone
still cannot open UDP. Broker first installs and exactly enumerates the complete
dynamic flow-filter graph while the gate is closed, then asks the lease-owning
driver handle to open the gate and re-attests that state. Teardown closes and
re-attests the gate before removing dynamic filters. Activation or post-open
attestation failure revokes before rollback; if revocation is uncertain, the
filters remain installed fail closed. Lease loss closes admission before flow
contexts drain, while a renewal by the same process with unchanged revision,
policy digest and nonce preserves the gate and existing contexts.

`0ae10d9` adds the first bounded outbound v4/v6 capture implementation. The
conditional `DATAGRAM_DATA` classifier accepts exactly one NBL and one NET_BUFFER,
validates the WFP endpoints against the UDP header and the live policy/nonce-bound
flow context, copies at most 16 KiB into the already pinned 256 KiB Direct-I/O
buffer, and completes one canonical captured record. It performs no packet-path
allocation or wait-lock acquisition. Only after the Broker request completes is
the original packet blocked with `ABSORB`; every missing request, malformed
packet, expired/mismatched lease, sequence overflow or resource failure is
blocked without absorption. Broker exit, incompatible lease replacement and
gate deactivation first close admission, fence in-flight lease readers, purge
the manual queue and drain flow contexts. The classifier deliberately does not
call APC-only process-status APIs because WFP can invoke it at `DISPATCH_LEVEL`.

`7e337bd` binds the receive-injection provenance before a capture can leave the
driver. The first valid packet fixes the exact local/remote address and port,
flags, compartment, interface and sub-interface under the flow lock; later
packets on that context must match every field. Driver initialization creates
separate v4/v6 transport injection handles before registering callouts and
destroys them only after callout unregistration. The datagram classifier queries
injection state before endpoint parsing and permits a self-injected packet only
when its opaque injection context is the exact live flow-context pointer. This
prevents a foreign or stale injected packet from claiming the loop bypass.

`0027f9c` adds a fixed 256-bucket token index beside the lifecycle list. Driver-
generated monotonic nonzero tokens distribute the maximum 1,024 contexts across
the buckets, while link/unlink of both lists remains atomic under the existing
flow spin lock. A reply record is structurally validated first, then looks only
inside its token bucket and must exactly match the target group, family, flags,
ports, addresses, revision, policy digest and lease nonce before acquiring a
flow reference. A collision miss returns no pointer; review caught and fixed a
candidate/result aliasing error before commit. Token exhaustion fails closed.
This removes a full-list scan from the future reply hot path without adding a
second lock or an unbounded table.

`ceee929` adds an independent 64-packet reply replay window to each flow. Under
the same flow lock it accepts monotonic progress and one copy of an out-of-order
sequence inside the previous 63 positions, rejects zero/duplicate/stale values,
and guards both shift operations before evaluating them. Prevalidation evaluates
the window without mutation; the injection transaction commits the sequence
only after it owns the exact flow reference, in-flight slot and packet
resources. This prevents a structurally valid request that later fails resource
admission from consuming a reply sequence.

`dd2e9b2` completes the inactive kernel reply-initiation slice. A valid record
first reacquires the exact indexed flow and one of 256 global in-flight slots,
then allocates one bounded nonpaged context containing IP-header backfill, the
UDP header and at most 16 KiB of payload. A driver-owned NBL pool supplies the
NBL/NET_BUFFER; one MDL describes the context packet storage. The driver reverses
the recorded endpoints, asks WFP to construct the v4/v6 IP header and complete
the UDP/IP checksums, commits the per-flow replay sequence, and initiates
transport-receive injection using the exact compartment, interface,
sub-interface and flow pointer as opaque self-injection provenance. Immediate
failure frees the NBL, MDL, packet context, flow reference and admission slot;
successful initiation transfers that ownership to the completion callback.
Lease loss, incompatible renewal, gate deactivation and unload wait for every
in-flight completion before draining flow contexts or destroying injection
handles and the NBL pool. Flows that require ALE reclassification are rejected
before capture because this injection API is not valid for that case.

The batch has an exact validation-only first pass, followed by revalidation and
per-record initiation. This prevents malformed trailing records from creating a
partial side effect, but a runtime/resource failure during the second pass can
still leave an accepted prefix in flight. Likewise WFP reports final asynchronous
delivery status only through `NET_BUFFER_LIST_STATUS`, after the IOCTL has
returned. `4ba9e71` extends the versioned driver snapshot from 128 to 168 bytes
with spin-lock-consistent attempted, succeeded, failed, in-flight and partial-
batch counters plus the last failure status. Broker validates
`attempted = succeeded + failed + in-flight`, the 256-operation ceiling and
status/counter consistency. `62d0c44` baselines those counters for each bridge
and terminates on any new failure, partial batch, rollback or accounting drift.
`959adb6` connects that termination to the production Engine Actor. The actor
prepares cancellation, directly revokes and attests the endpoint lease/gate,
deactivates forwarding and forces blocking before returning the runtime error.
Retrying an ambiguous batch is forbidden because accepted sequences may already
be committed.

This remains an inactive vertical slice. Production ownership and health of the
asynchronous Broker bridge are wired to the admission supervisor, but current
capture completes one Direct-I/O request per datagram rather than coalescing up
to the ABI limit. No UDP/DNS/QUIC capability is advertised until end-to-end WFP
canaries, DNS/QUIC semantics, representative performance evidence and the
WDK/Windows 11 VM gates pass.

After this fail-closed cleanup the Engine Actor deliberately exits instead of
silently reconstructing mutable kernel/userspace ownership in place. This is the
safe current behavior, not a completed availability design: TD-027 requires a
stable recovery marker and bounded in-process or SCM recovery proof, including
no admission reopen before full guard, lease and runtime attestation.

The current exact first-endpoint binding deliberately fails closed if a WFP flow
context later presents a different destination. Windows 11 VM acceptance must
prove whether one unconnected UDP socket alternating destinations receives one
context per endpoint or reuses a context. Reuse requires a bounded child table
keyed by flow token plus endpoint tuple; simply allowing endpoint drift is not
acceptable because it could route a reply to the wrong socket destination.

Initial strict acceptance requires Mihomo Fake-IP/virtual-network-card mode so
domain mappings remain available to existing domain rules. Real-IP domain
restoration is a separate proof item and cannot be inferred from an IP-only WFP
context.

ALE connect redirection cannot be the sole strict UDP mechanism. Microsoft
documents that connected UDP using `connect`/`send` can be dropped when locally
redirected, while non-TCP redirect records are delivered through `WSARecvMsg`
and only the flow-creating packet carries the record. The production design
therefore requires a bounded datagram-layer v4/v6 path with flow identity,
first-packet provenance, authenticated Core associations, idle expiry and reply
reinjection. It must prove both connected `connect`/`send` and unconnected
`sendto`, DNS and QUIC in the VM bypass matrix before any UDP/DNS/QUIC
capability bit is advertised. Until that proof exists, the driver returns no
such capability and the Agent remains `blocking`.

At `FWPM_LAYER_ALE_FLOW_ESTABLISHED_V4/V6`, where App-ID is available, the
driver must associate a compact referenced flow context using
`FwpsFlowAssociateContext0`. `DATAGRAM_DATA_V4/V6` has no App-ID field, so it
must consume that context rather than re-identify the process. The classify path
must never synchronously wait for Broker: selected outbound packets are cloned
into a bounded nonpaged queue, the originals are blocked/absorbed, and Broker
later returns authenticated reply batches for injection. Packets identified as
self-injected are permitted to prevent loops. Queue overflow, absent/stale lease,
missing flow context and Broker failure remain fail-closed.

Primary constraints: [Microsoft connected-UDP local-proxy limitation](https://learn.microsoft.com/en-us/troubleshoot/windows-hardware/drivers/redirection-connected-udp-traffic-local-proxy-fail)
and [Microsoft non-TCP redirect-record contract](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-records).

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
- Real loopback TCP listeners, authenticated Core ingress probes, fixed session
  workers, lease renewal and a pre-armed production UDP bridge now exist in the
  production host. The probe still reports relay and DNS health as false until
  end-to-end WFP redirect/capture/injection and DNS/QUIC canaries pass. Proxy
  commit therefore remains fail-closed; block-only policy remains usable and no
  placeholder capability is advertised.
- Commands: `preparePolicy`, `commitPolicy`, `forceBlocking`, `disablePolicy`,
  `status`, `diagnostics`; no arbitrary command/path/registry/service API.
- The Broker reopens and validates executable handles to prevent path-swap
  races. UI-supplied signer claims are never trusted.
- Diagnostics contain identity IDs, state/reason codes, revision/digest and
  counters; no destination host/IP, payload, token or full user path by default.

## 8. Performance and resource limits

- Driver misses, block decisions and expired-lease paths perform no heap
  allocation, blocking I/O, payload log, registry access or user-mode round
  trip. A successful local TCP redirect necessarily allocates one fixed
  112-byte nonpaged context and transfers its lifetime to WFP so user mode can
  recover the original destination.
- Policy snapshots are immutable and swapped atomically; maximum 128 families
  and 32 child identities per family.
- App-ID lookup is hash-indexed; expected classify complexity is O(1).
- Broker has bounded concurrent TCP sessions, UDP associations, per-flow buffers
  and diagnostic ring. Overload transitions the affected selected flow to block,
  never direct.
- Production TCP worker count follows available CPUs but is clamped to 2–16,
  with one queued connection per worker and 512 KiB worker stacks. Core ingress
  authentication uses at most eight transient 256 KiB-stack workers.
- Heartbeats are low frequency and independent of the Flutter window.
- Benchmarks record classify latency, relay throughput, CPU, working set,
  allocation trend, redirect-context pool-tag growth and overload rejection.
  Driver Verifier exercises cancelled-connect, burst and sustained-flow cases
  in the isolated VM; WFP is never enabled on the development host.

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
