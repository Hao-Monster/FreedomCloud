# FlClashX strict callout driver

This directory is the Windows 11 x64 M3 kernel boundary. The current source
implements a fail-closed policy snapshot, a revocable Broker endpoint lease,
inline lease-bound TCP redirect mutation and eight WFP callouts. It also exposes
a capacity-one manual Direct-I/O receive queue and allocation-free reply-batch
validation for the unfinished UDP path. UDP flow provenance is capped at 1,024
reference-counted contexts and datagram classification is conditional on that
context. A separate lease-owner gate lets the authorization layer pass UDP to
conditional capture only after Broker has attested the exact dynamic WFP graph,
and closes before filter removal or lease teardown. The outbound v4/v6 packet
classifier now validates one bounded UDP packet without allocation, emits one
lease- and flow-bound captured record into the pending Broker Direct-I/O request,
and absorbs the original only after successful delivery. Missing requests,
malformed packets, stale leases and saturation remain blocked.

The first valid packet also binds the exact address, port, flag, compartment,
interface and sub-interface tuple used for receive injection. Separate v4/v6
transport-injection handles are created before callout registration, and
self-injected packets bypass recapture only when their opaque injection context
is the exact live flow context.
Reply validation uses a fixed 256-bucket driver-token index and verifies the
complete flow tuple plus lease identity before taking a reference; it never
scans the full 1,024-flow lifecycle list.
Each flow also owns a 64-packet reply replay window. Prevalidation is
non-mutating; an injection transaction commits the sequence only after it owns
the exact flow reference, one of 256 global in-flight slots, packet storage, MDL
and NBL. WFP constructs the v4/v6 IP header and UDP checksum before transport-
receive injection. Immediate failure and asynchronous completion both release
every resource; lease/gate teardown drains in-flight injections before flow
contexts and injection infrastructure.

This is still an inactive vertical slice. Asynchronous completion status is not
yet exported to the Broker, a multi-record batch can have an accepted prefix if
a later initiation fails, and production bridge ownership is unfinished. No
UDP/DNS/QUIC capability is advertised until completion health, fail-closed
runtime integration, signing, performance measurement and VM qualification are
complete. Capture also rejects flows requiring ALE reclassification; enterprise
IPsec compatibility remains a separate VM gate because locally generated inbound
injection bypasses IPsec processing.

## Build contract

Use a Visual Studio + WDK host with the x64 KMDF toolset. A 128-bit build ID
from the signed package manifest is mandatory:

```powershell
msbuild .\FlClashStrictCallout.vcxproj /m /p:Configuration=Release `
  /p:Platform=x64 /p:FlClashDriverBuildId=0123456789abcdef0123456789abcdef
```

The project deliberately disables automatic signing. Release packaging must
inject the authorized signing identity, emit a SHA-256 signed artifact and use
the same build ID in the Broker package manifest. Do not substitute a generated
test certificate for a release artifact.

## Local safety boundary

Compilation and static analysis are allowed on a development host. Driver
loading, service creation, WFP object installation, test-signing mode and
network classification tests run only in the isolated Windows 11 VM matrix.
The current repository host has a Visual Studio compiler installation but no
complete WDK kernel headers or driver tools, so the driver build gate remains
`NOT RUN` rather than being reported as successful.
