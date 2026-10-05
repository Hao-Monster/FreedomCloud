#requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'StrictTest.Validation.ps1')

# Authenticode is the only package boundary replaced here. Fixture files and
# manifest bytes are real; this test never invokes the installation entrypoint.
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('flclash-strict-validation-' + [guid]::NewGuid().ToString('N'))
$testThumbprint = 'A' * 40
$certificateBytes = [Text.Encoding]::UTF8.GetBytes('fixture certificate, not a trusted signer')
$publisherHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($certificateBytes))
$signatureReader = {
    param($Path)
    [pscustomobject]@{
        Status = 'Valid'
        SignerCertificate = [pscustomobject]@{ Thumbprint = $testThumbprint; RawData = $certificateBytes }
    }
}
$script:passed = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw $Message }
}
function Assert-Rejected([scriptblock]$Action, [string]$MessagePattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught -or $caught -notlike $MessagePattern) { throw "Expected rejection '$MessagePattern'; got '$caught'" }
}
function Write-FixtureImage([string]$Path, [string]$Payload) {
    # Minimal synthetic PE headers: used only with mocked Authenticode, never run.
    $header = [byte[]]::new(512)
    $header[0] = 0x4d; $header[1] = 0x5a
    [BitConverter]::GetBytes([int]64).CopyTo($header, 60)
    $header[64] = 0x50; $header[65] = 0x45
    $header[68] = 0x64; $header[69] = 0x86
    $header[84] = 0xf0; $header[86] = 0x02
    $header[88] = 0x0b; $header[89] = 0x02
    $header[156] = if ([IO.Path]::GetExtension($Path) -ieq '.sys') { 1 } else { 3 }
    [IO.File]::WriteAllBytes($Path, [byte[]]($header + [Text.Encoding]::UTF8.GetBytes($Payload)))
}
function Write-FixtureJson($Fixture, [string]$Json) {
    [IO.File]::WriteAllText((Join-Path $Fixture.PackageDirectory 'strict-package-manifest.json'), $Json, [Text.UTF8Encoding]::new($false))
    Write-FixtureImage (Join-Path $Fixture.PackageDirectory 'FlClashStrictBroker.exe') ('fixture-broker-prefix' + $Json + 'fixture-broker-suffix')
}
function Write-FixtureManifest($Fixture) {
    $json = $Fixture.Manifest | ConvertTo-Json -Compress
    Write-FixtureJson $Fixture $json
}
function New-Fixture {
    $caseRoot = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $package = Join-Path $caseRoot 'package'
    New-Item -ItemType Directory -Path $package | Out-Null
    $manifest = [ordered]@{ protocol = 2; packageVersion = '0.2.0+fixture'; driverBuildId = '12' * 16 }
    foreach ($entry in @(@('FlClashStrictCallout.sys','driver'), @('FlClashAgent.exe','agent'), @('FlClashCore.exe','core'))) {
        $path = Join-Path $package $entry[0]
        Write-FixtureImage $path ('fixture-' + $entry[0])
        $manifest[$entry[1] + 'FileSha256'] = (Get-FileHash -LiteralPath $path).Hash
        $manifest[$entry[1] + 'PublisherCertificateSha256'] = $publisherHash
    }
    $facts = @{
        IsWindows = $true; Is64BitProcess = $true; Architecture = 'AMD64'; IsAdministrator = $true
        ProductType = 1; Version = '10.0.22631'; Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'
    }
    $parameters = @{
        HostFacts = $facts; ConfirmTestMachine = $true
        BootQueryExitCode = 0; BootConfiguration = 'testsigning Yes'
        ServiceQueryExitCodes = @{ FlClashStrictCallout = 1060; FlClashStrictBroker = 1060 }
        PackageDirectory = $package; Destination = (Join-Path $caseRoot 'protected'); Recovery = (Join-Path $caseRoot 'recovery')
        Thumbprint = $testThumbprint; ReadSignature = $signatureReader
    }
    $fixture = [pscustomobject]@{ Parameters = $parameters; Manifest = $manifest; PackageDirectory = $package; CaseRoot = $caseRoot }
    Write-FixtureManifest $fixture
    return $fixture
}
function Test-Case([string]$CaseName, [scriptblock]$Action) {
    $fixture = New-Fixture
    try {
        & $Action $fixture
        Assert-Equal (Test-Path -LiteralPath $fixture.Parameters.Destination) $false 'Validation created the protected directory'
        Assert-Equal (Test-Path -LiteralPath $fixture.Parameters.Recovery) $false 'Validation created the recovery directory'
        $script:passed++
        Write-Output "PASS $CaseName"
    } catch { throw "FAIL ${CaseName}: $($_.Exception.Message)" }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    foreach ($path in @((Join-Path (Split-Path -Parent $PSScriptRoot) 'Initialize-StrictTest.ps1'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'StrictTest.Validation.ps1'), $PSCommandPath)) {
        $tokens = $null; $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Equal $errors.Count 0 "PowerShell parser errors: $path"
    }
    Test-Case 'valid VM produces an exact read-only installation plan' {
        param($f)
        $params = $f.Parameters
        $plan = Get-StrictTestInstallationPlan @params
        Assert-Equal $plan.SourceHashes.Count 5 'Expected the four signed components and manifest'
        foreach ($name in $plan.SourceHashes.Keys) {
            Assert-Equal $plan.SourceHashes[$name] (Get-FileHash -LiteralPath (Join-Path $f.PackageDirectory $name)).Hash "Wrong planned hash: $name"
        }
        Assert-Equal $plan.Destination $params.Destination 'Wrong destination'
        Assert-Equal $plan.Recovery $params.Recovery 'Wrong recovery directory'
    }
    Test-Case 'confirmation is mandatory' {
        param($f)
        $params = $f.Parameters; $params.ConfirmTestMachine = $false
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*ConfirmTestMachine*'
    }
    foreach ($change in @(
        @('IsWindows', $false, '*Windows x64*'), @('Is64BitProcess', $false, '*Windows x64*'),
        @('Architecture', 'ARM64', '*Windows x64*'), @('IsAdministrator', $false, '*elevated*'),
        @('Version', '10.0.19045', '*Windows 11*'), @('ProductType', 3, '*Windows Server*')
    )) {
        Test-Case "reject host $($change[0])" {
            param($f)
            $params = $f.Parameters; $params.HostFacts[$change[0]] = $change[1]
            Assert-Rejected { Get-StrictTestInstallationPlan @params } $change[2]
        }
    }
    Test-Case 'physical host rejected by default' {
        param($f)
        $params = $f.Parameters; $params.HostFacts.Model = 'Physical PC'; $params.HostFacts.Manufacturer = 'Test Vendor'
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*not a VM*'
    }
    Test-Case 'explicit dedicated physical host exception retains remaining gates' {
        param($f)
        $params = $f.Parameters; $params.HostFacts.Model = 'Physical PC'; $params.HostFacts.Manufacturer = 'Test Vendor'; $params.AllowPhysicalTestHost = $true
        $plan = Get-StrictTestInstallationPlan @params
        Assert-Equal $plan.SourceHashes.Count 5 'Dedicated host should still validate all components'
        $params.ConfirmTestMachine = $false
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*ConfirmTestMachine*'
    }
    Test-Case 'test signing disabled' {
        param($f)
        $params = $f.Parameters; $params.BootConfiguration = 'testsigning No'
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*test signing*'
    }
    Test-Case 'boot query failure' {
        param($f)
        $params = $f.Parameters; $params.BootQueryExitCode = 5
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*test signing*'
    }
    foreach ($name in @('FlClashStrictCallout','FlClashStrictBroker')) {
        foreach ($exitCode in @(0, 5)) {
            Test-Case "$name existing or inaccessible ($exitCode)" {
                param($f)
                $params = $f.Parameters; $params.ServiceQueryExitCodes[$name] = $exitCode
                Assert-Rejected { Get-StrictTestInstallationPlan @params } '*exists or cannot be inspected*'
            }
        }
    }
    Test-Case 'missing service query result' {
        param($f)
        $params = $f.Parameters; $params.ServiceQueryExitCodes.Remove('FlClashStrictBroker')
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*exists or cannot be inspected*'
    }
    foreach ($field in @('Destination','Recovery')) {
        Test-Case "existing $field preserved" {
            param($f)
            $params = $f.Parameters; $existing = Join-Path $f.CaseRoot 'preexisting'
            New-Item -ItemType Directory -Path $existing | Out-Null
            $original = $params[$field]; $params[$field] = $existing
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Existing directory*'
            Assert-Equal (Test-Path -LiteralPath $existing) $true 'Existing directory was deleted'
            $params[$field] = $original
        }
    }
    Test-Case 'relative destination rejected' {
        param($f)
        $params = $f.Parameters; $original = $params.Destination; $params.Destination = 'relative'
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*absolute local paths*'
        $params.Destination = $original
    }
    foreach ($name in @('FlClashStrictCallout.sys','FlClashStrictBroker.exe','FlClashAgent.exe','FlClashCore.exe')) {
        Test-Case "invalid signature for $name" {
            param($f)
            $params = $f.Parameters
            $targetName = $name
            $validReader = $signatureReader
            $params.ReadSignature = {
                param($Path)
                $signature = & $validReader $Path
                if ([IO.Path]::GetFileName($Path) -eq $targetName) { $signature.Status = 'NotTrusted' }
                return $signature
            }.GetNewClosure()
            Assert-Rejected { Get-StrictTestInstallationPlan @params } "*Signature/trust mismatch: $targetName.*"
        }
    }
    Test-Case 'trusted but wrong certificate rejected' {
        param($f)
        $params = $f.Parameters; $params.Thumbprint = 'B' * 40
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Signature/trust mismatch*'
    }
    Test-Case 'manifest must be embedded byte for byte' {
        param($f)
        [IO.File]::AppendAllText((Join-Path $f.PackageDirectory 'strict-package-manifest.json'), ' ')
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*exact supplied package manifest*'
    }
    Test-Case 'unsupported protocol rejected' {
        param($f)
        $f.Manifest.protocol = 1; Write-FixtureManifest $f
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Unsupported strict manifest protocol*'
    }
    foreach ($component in @('driver','agent','core')) {
        Test-Case "$component file digest mismatch" {
            param($f)
            $f.Manifest[$component + 'FileSha256'] = '1' * 64; Write-FixtureManifest $f
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Manifest digest mismatch*'
        }
        Test-Case "$component publisher mismatch" {
            param($f)
            $f.Manifest[$component + 'PublisherCertificateSha256'] = '1' * 64; Write-FixtureManifest $f
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Manifest publisher mismatch*'
        }
    }
    Test-Case 'malformed digest rejected' {
        param($f)
        $f.Manifest.driverFileSha256 = 'not-a-digest'; Write-FixtureManifest $f
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Malformed manifest identity*'
    }
    Test-Case 'oversized manifest rejected' {
        param($f)
        [IO.File]::WriteAllText((Join-Path $f.PackageDirectory 'strict-package-manifest.json'), ('x' * 16385))
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*outside the supported bounds*'
    }
    foreach ($field in @('protocol','packageVersion','driverBuildId','driverFileSha256','driverPublisherCertificateSha256',
        'agentFileSha256','agentPublisherCertificateSha256','coreFileSha256','corePublisherCertificateSha256')) {
        Test-Case "missing manifest field $field" {
            param($f)
            $f.Manifest.Remove($field); Write-FixtureManifest $f
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Required manifest field is missing*'
        }
    }
    foreach ($change in @(@('unexpected', 'value', '*Unknown or duplicate*'),
        @('protocol', '2', '*numeric 2*'), @('packageVersion', 2, '*must be a string*'),
        @('packageVersion', 'with space', '*Invalid manifest packageVersion*'),
        @('packageVersion', "v1`n", '*Invalid manifest packageVersion*'),
        @('packageVersion', ('x' * 65), '*Invalid manifest packageVersion*'),
        @('driverBuildId', ('0' * 32), '*Malformed manifest identity*'),
        @('driverBuildId', 'bad', '*Malformed manifest identity*'),
        @('driverBuildId', (('1' * 32) + "`n"), '*Malformed manifest identity*'),
        @('driverFileSha256', ('0' * 64), '*Malformed manifest identity*'))) {
        Test-Case "invalid manifest $($change[0]) = $($change[1])" {
            param($f)
            $f.Manifest[$change[0]] = $change[1]; Write-FixtureManifest $f
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } $change[2]
        }
    }
    Test-Case 'duplicate field rejected like Broker serde' {
        param($f)
        $json = ($f.Manifest | ConvertTo-Json -Compress).Replace('"protocol":2', '"protocol":2,"protocol":2')
        Write-FixtureJson $f $json
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Unknown or duplicate*'
    }
    Test-Case 'JSON comments rejected like Broker serde' {
        param($f)
        $json = ($f.Manifest | ConvertTo-Json -Compress).Replace('{', '{/* comment */')
        Write-FixtureJson $f $json
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*strict JSON*'
    }
    foreach ($name in @('FlClashStrictCallout.sys','FlClashStrictBroker.exe','FlClashAgent.exe','FlClashCore.exe')) {
        Test-Case "non-AMD64 image $name rejected even with trusted signature" {
            param($f)
            $path = Join-Path $f.PackageDirectory $name
            $bytes = [IO.File]::ReadAllBytes($path); $bytes[68] = 0x4c; $bytes[69] = 0x01
            [IO.File]::WriteAllBytes($path, $bytes)
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Expected AMD64 PE image*'
        }
    }
    Test-Case 'invalid PE header bounds rejected' {
        param($f)
        $path = Join-Path $f.PackageDirectory 'FlClashStrictBroker.exe'
        $bytes = [IO.File]::ReadAllBytes($path); [BitConverter]::GetBytes([int]2147483647).CopyTo($bytes, 60)
        [IO.File]::WriteAllBytes($path, $bytes)
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Invalid PE header bounds*'
    }
    foreach ($change in @(@(0, 0, '*Invalid PE image*'), @(88, 0, '*PE32+*'),
        @(87, 0x20, '*Invalid executable PE header*'), @(156, 1, '*Invalid PE subsystem*'))) {
        Test-Case "invalid PE field at byte $($change[0])" {
            param($f)
            $path = Join-Path $f.PackageDirectory 'FlClashStrictBroker.exe'
            $bytes = [IO.File]::ReadAllBytes($path); $bytes[$change[0]] = $change[1]
            [IO.File]::WriteAllBytes($path, $bytes)
            $params = $f.Parameters
            Assert-Rejected { Get-StrictTestInstallationPlan @params } $change[2]
        }
    }
    Test-Case 'truncated PE rejected' {
        param($f)
        [IO.File]::WriteAllBytes((Join-Path $f.PackageDirectory 'FlClashStrictBroker.exe'), [byte[]](0x4d, 0x5a))
        $params = $f.Parameters
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Invalid PE image*'
    }
    Test-Case 'UNC package rejected before reading any file' {
        param($f)
        $params = $f.Parameters; $params.PackageDirectory = '\\invalid-host\fixture'
        Assert-Rejected { Get-StrictTestInstallationPlan @params } '*absolute local path*'
    }
    Test-Case 'package directory junction rejected' {
        param($f)
        $link = Join-Path $f.CaseRoot 'package-link'
        New-Item -ItemType Junction -Path $link -Target $f.PackageDirectory | Out-Null
        try {
            $params = $f.Parameters; $params.PackageDirectory = $link
            Assert-Rejected { Get-StrictTestInstallationPlan @params } '*Reparse path rejected*'
        } finally { Remove-Item -LiteralPath $link -Force }
    }
    Write-Output "Strict test validation: PASS ($script:passed cases; no installer, service, driver, boot or network commands executed)"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolved)).StartsWith('flclash-strict-validation-', [StringComparison]::Ordinal)) {
            throw 'Refusing to clean an unexpected test directory'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
