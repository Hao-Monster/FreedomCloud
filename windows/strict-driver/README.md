# FlClashX strict callout driver

This directory is the Windows 11 x64 M3 kernel boundary. The current source
implements a fail-closed policy snapshot and registers four WFP callouts. The
redirect callouts intentionally block: no redirect capability is advertised
until the separately revocable Broker endpoint lease and relay are complete.
Protocol v2 includes the revocable lease and binds it to the IOCTL requestor's
referenced kernel process identity, but relay and redirect mutation remain
deliberately unavailable.

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
The current repository host has neither the Visual Studio compiler nor complete
kernel headers, so the driver build gate remains `NOT RUN` rather than being
reported as successful.
