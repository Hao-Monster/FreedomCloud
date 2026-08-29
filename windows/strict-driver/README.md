# FlClashX strict callout driver

This directory is the Windows 11 x64 M3 kernel boundary. The current source
implements a fail-closed policy snapshot, a revocable Broker endpoint lease,
inline lease-bound TCP redirect mutation and eight WFP callouts. It also exposes
a capacity-one manual Direct-I/O receive queue and allocation-free reply-batch
validation for the unfinished UDP path. UDP flow provenance is capped at 1,024
reference-counted contexts and datagram classification is conditional on that
context. A separate lease-owner gate lets the authorization layer pass UDP to
conditional capture only after Broker has attested the exact dynamic WFP graph,
and closes before filter removal or lease teardown.
The packet classifier still blocks selected UDP because capture and reinjection
are unfinished. No UDP reply is accepted for injection and no UDP/DNS/QUIC
capability is advertised until production bridge ownership, capture,
reinjection, signing and VM qualification are complete.

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
