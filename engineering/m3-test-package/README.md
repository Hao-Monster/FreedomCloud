# M3 signed VM qualification tooling

These scripts close the reproducible package-assembly and evidence-collection
portion of M3 without weakening the production trust model. They never create a
test certificate, enable test-signing mode, install a service, load a driver or
change network state by themselves.

Portable and signed VM ZIPs use `New-DeterministicZip.ps1`. It includes hidden
files in ordinal path order, rejects links and output paths inside the source,
uses a fixed `-SourceDateEpoch`, and writes uncompressed entries through a
temporary file before replacement. `setup.dart` derives this epoch from
`SOURCE_DATE_EPOCH` when supplied, otherwise from the recorded source commit.
The source tree state remains part of `BUILD-INFO.txt`; dirty checkouts are
explicitly marked non-reproducible. The portable ZIP, strict VM bundle and Inno
installer, when available, each get their own adjacent `.sha256` file.

## Assembly order

The embedded manifest must not contain the final Broker file hash: embedding
that hash changes the binary, and signing changes it again. Broker Authenticode
verification protects the embedded manifest; the final Broker hash belongs in
the external bundle inventory after signing. A plain SHA-256 inventory provides
transport integrity, not an independent publisher signature for the ZIP.
`tests/Test-M3ManifestAssemblyOrder.ps1` verifies that manifest generation needs
no Broker binary and retains the Driver/Agent/Core identity pins.

1. Choose one 128-bit hexadecimal driver build ID and compile the driver with
   that ID.
2. Obtain trusted signatures for the driver, Agent and Core. Public Windows
   kernel qualification requires the Microsoft-signed driver returned by the
   Hardware Dashboard; a locally trusted test certificate is insufficient.
3. Run `New-M3PackageManifest.ps1` over those immutable signed files.
4. Build the production Broker with `FLCLASH_STRICT_PACKAGE_MANIFEST` set to the
   absolute generated manifest path, then sign the Broker.
5. Run `New-M3SignedVmBundle.ps1 -SourceDateEpoch <unix-seconds>`. It rejects unsigned files and any driver,
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
