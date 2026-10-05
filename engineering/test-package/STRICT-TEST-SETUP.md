# Isolated Windows strict test setup

`Initialize-StrictTest.ps1` is an optional, one-time setup tool for the fixed
test-certificate package. It is not a production installer, an upgrade tool, or
evidence of Microsoft-signed M3 qualification. It does not enable test signing,
import certificates, change Secure Boot/HVCI, or configure traffic routing.

Run it only in a snapshotted Windows 11 x64 VM. An explicitly authorized,
dedicated physical test machine may use `-AllowPhysicalTestHost`; this option is
never permission to use the development workstation. VM detection checks the
reported manufacturer/model, not a security isolation proof. The operator must
ensure that the host is actually isolated and recoverable.

This test tool requires elevated **PowerShell 7.2 or newer**. The separate M3
qualification tools retain their existing Windows PowerShell 5.1 compatibility.
Windows 10, Windows Server, ARM64 and 32-bit PowerShell are rejected.

## Prepare and run on the isolated test host

1. Take a restorable VM snapshot or dedicated-host backup. Do not transfer real
   credentials, subscriptions or private profiles into the test fixture.
2. Prepare test signing and trust for the supplied test certificate separately,
   under the test-host authorization, and reboot as necessary. This script only
   verifies that test signing is already enabled. It accepts the fixed test
   certificate thumbprint embedded in the script, not arbitrary trusted signers.
3. Place these two scripts in the same plain local directory as the matching
   `FlClashStrictCallout.sys`, `FlClashStrictBroker.exe`, `FlClashAgent.exe`,
   `FlClashCore.exe` and `strict-package-manifest.json`:
   `Initialize-StrictTest.ps1` and `StrictTest.Validation.ps1`.
   Do not use a network share, junction, symbolic link or synchronized directory.
   Existing ordinary/signed package assembly does not automatically include this
   optional setup tool; copy both scripts only into the dedicated test bundle.
4. From that directory in elevated PowerShell 7.2+, run:

   ```powershell
   .\Initialize-StrictTest.ps1 -ConfirmTestMachine
   ```

   Only on an authorized dedicated physical test host, add
   `-AllowPhysicalTestHost`. Both switches are required for that exception.

The script refuses an existing Broker/driver service or either installation
directory. It does not overwrite an existing Helper installation. All host,
path, signature and manifest checks finish before installation begins. The
Broker must embed the exact supplied manifest bytes; the manifest must pin the
Driver/Agent/Core file hashes and publisher certificate hashes. Copied files are
hashed and signature-checked again before any service is registered.
All four binaries must have AMD64 PE32+ headers. The manifest also follows the
Broker's exact nine-field contract and 16 KiB limit, including version/build ID,
nonzero identities, strict JSON types, and rejection of unknown/duplicate fields.

Installation creates protected directories under Program Files and ProgramData,
registers and starts the driver and LocalSystem Broker, and sets Broker restart
recovery. This is a privileged system change: never invoke the entrypoint as a
unit test. Success means only that service setup completed, not that strict
traffic, lifecycle, fault containment or public-release requirements passed.

If setup fails after creating files/services, stop and collect redacted evidence;
it intentionally does not perform an automatic destructive rollback. Restore the
VM snapshot or dedicated-host backup before retrying. The script will refuse to
upgrade or repair that partial installation. Do not manually delete unknown
services or shared installation directories to make a second run succeed.

For actual traffic and lifecycle acceptance, use the relevant isolated-host
checklists. A test-certificate result never satisfies
`../m3-test-package/M3-WINDOWS-VM-CHECKLIST.md`'s Microsoft-signed release gate.

## Developer validation without installation

```powershell
pwsh -NoProfile -File engineering/test-package/tests/Test-StrictTestValidation.ps1
```

The test exercises the read-only plan with temporary files and an explicit
Authenticode fixture reader. It covers VM/platform gates, explicit host consent,
test-signing evidence, absent-service requirements, existing/reparse paths,
signatures and exact manifest/hash/publisher binding. It does not execute the
installer, `sc.exe`, `bcdedit.exe`, certificate trust changes or network commands.
The mocked certificate response is not evidence that an actual package is signed.

The related desktop launch change uses protected Agent/Core paths only when both
files exactly match the portable bundle. A mismatched or missing protected file
fails launch and reports failure without falling back to the portable path.
Existing authenticated Agent attachment keeps its previous behavior. Real signed
process startup, service recovery and traffic tests remain isolated-host gates.
