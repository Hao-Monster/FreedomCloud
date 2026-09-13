# M3 signed VM qualification tooling

These scripts close the reproducible package-assembly and evidence-collection
portion of M3 without weakening the production trust model. They never create a
test certificate, enable test-signing mode, install a service, load a driver or
change network state by themselves.

## Assembly order

1. Choose one 128-bit hexadecimal driver build ID and compile the driver with
   that ID.
2. Obtain trusted signatures for the driver, Agent and Core. Public Windows
   kernel qualification requires the Microsoft-signed driver returned by the
   Hardware Dashboard; a locally trusted test certificate is insufficient.
3. Run `New-M3PackageManifest.ps1` over those immutable signed files.
4. Build the production Broker with `FLCLASH_STRICT_PACKAGE_MANIFEST` set to the
   absolute generated manifest path, then sign the Broker.
5. Run `New-M3SignedVmBundle.ps1`. It rejects unsigned files and any driver,
   Agent or Core hash/publisher mismatch before producing the ZIP.
6. Transfer the ZIP to a snapshotted Windows 11 VM, extract it, run
   `Invoke-M3VmPreflight.ps1`, and follow `M3-WINDOWS-VM-CHECKLIST.md`.
7. Before restoring the VM snapshot, run
   `Collect-M3VmEvidence.ps1 -OutputDirectory <evidence-directory>`. The
   collector copies the bounded Flutter, Agent, Helper and Strict Broker logs,
   recent Service Control Manager events and the driver-capture instructions.
   It never copies profile YAML, subscriptions or credential files.

The manifest generator hashes the exact leaf publisher certificate bytes, which
matches the Broker trust contract; it does not use the certificate's SHA-1
thumbprint. The bundle retains a separate SHA-256 inventory for transport
integrity. Certificate acquisition, Hardware Dashboard submission, HLK results,
driver installation and network qualification remain external gates.

Run `tests\Test-M3PackageTools.ps1` on Windows to verify parser safety, positive
manifest generation, unsigned-driver rejection and exact embedded-manifest
rejection. A successful bundle test requires the real signed production files
and is intentionally deferred until those external inputs exist.
