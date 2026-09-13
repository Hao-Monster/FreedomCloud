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

The versioned 168-byte snapshot exports spin-lock-consistent attempted,
succeeded, failed, in-flight and partial-batch counters plus the last completion
status. Broker baselines and monitors them only while injection work is pending,
at most once per 100 ms, and stops the reusable bridge on any new failure or
accounting drift. The production runtime pre-arms exactly one receive for the
lease owner while UDP admission remains closed; receive setup is serialized with
lease mutation and restarts the manual queue after a prior purge. Reply batches
still require the open gate. A 25 ms Engine Actor check translates bridge failure
into prepared cancellation, verified lease/gate revocation, forwarding teardown
and forced blocking. Proven cleanup keeps the Actor available but suspends health
polling; at most four pre-failure queued requests are rejected, and only a fresh
authenticated commit attempt re-arms supervision. Cleanup uncertainty still
terminates the Actor. This remains an inactive vertical slice: a multi-record
batch can have an accepted prefix if a later initiation fails, and real
WDK/driver fault execution is not proven. No UDP/DNS/QUIC capability is
advertised until end-to-end canaries, signing, performance measurement and VM
qualification are complete. Capture also rejects flows requiring ALE
reclassification; enterprise IPsec
compatibility remains a separate VM gate because locally generated inbound
injection bypasses IPsec processing.

## Build contract

The build is pinned to WDK/SDK `10.0.28000.2526` through `packages.config` and
`Directory.Build.props`. Restore those packages with an official NuGet client
before building:

```powershell
nuget.exe restore .\packages.config -PackagesDirectory .\packages `
  -Source https://api.nuget.org/v3/index.json -NonInteractive
```

Use the 64-bit Visual Studio 2026 MSBuild executable with the x64 KMDF toolset.
The x64 WDK package contains the x64 ApiValidator, so invoking 32-bit MSBuild
would incorrectly search for an unavailable x86 validator. A 128-bit build ID
from the signed package manifest is mandatory:

```powershell
& '<VisualStudio>\MSBuild\Current\Bin\amd64\MSBuild.exe' `
  .\FlClashStrictCallout.vcxproj /t:Rebuild /m /p:Configuration=Release `
  /p:Platform=x64 /p:FlClashDriverBuildId=0123456789abcdef0123456789abcdef
```

The Release configuration treats compiler and WDK code-analysis warnings as
errors and runs DriverMinimumRules plus ApiValidator. A successful local build
therefore proves the pinned compiler/static-analysis gate, but not driver load,
runtime behavior, signing or Windows Hardware Lab Kit qualification.

The project deliberately disables automatic signing. Release packaging must
inject the authorized signing identity, emit a SHA-256 signed artifact and use
the same build ID in the Broker package manifest. Do not substitute a generated
test certificate for a release artifact.

## FlClashX setup packaging

The Flutter setup script keeps strict artifacts opt-in so ordinary builds cannot
ship this driver accidentally. To assemble an explicitly signed strict package,
set `FLCLASH_STRICT_PACKAGE=1` and provide absolute paths for
`FLCLASH_STRICT_DRIVER_PATH` and `FLCLASH_STRICT_PACKAGE_MANIFEST`. A prebuilt,
signed Broker can be selected with `FLCLASH_STRICT_BROKER_PATH`; otherwise
`setup.dart` builds `services/strict-broker` with the supplied manifest embedded.
The generated portable root contains `FlClashStrictCallout.sys`,
`FlClashStrictBroker.exe` and `strict-package-manifest.json`; the Inno installer
also installs the strict set (including the matching `FlClashAgent.exe`) under
the protected `FlClashX Service` directory and manages the
`FlClashStrictBroker` SCM service. The legacy `windows/strict_capture` artifact
is never selected by this path.

## Local safety boundary

Compilation and static analysis are allowed on a development host. Driver
loading, service creation, WFP object installation, test-signing mode and
network classification tests run only in the isolated Windows 11 VM matrix.
The current repository host completed the pinned Release compile,
DriverMinimumRules and ApiValidator gates without loading the resulting unsigned
driver. Release signing, Driver Verifier, real IOCTL/WFP execution and network
qualification remain VM/release-pipeline gates.
