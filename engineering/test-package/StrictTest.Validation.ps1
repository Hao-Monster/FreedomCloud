#requires -Version 7.2
# Read-only validation shared by the installer and its isolated fixture tests.
Set-StrictMode -Version Latest

function Assert-StrictTestHost {
    param([hashtable]$Facts, [switch]$ConfirmTestMachine, [switch]$AllowPhysicalTestHost)
    if (-not $ConfirmTestMachine) { throw 'Use -ConfirmTestMachine only on a snapshotted VM or dedicated test host.' }
    if (-not $Facts.IsWindows -or -not $Facts.Is64BitProcess -or $Facts.Architecture -ne 'AMD64') {
        throw 'This test installer requires Windows x64.'
    }
    if (-not $Facts.IsAdministrator) { throw 'Run in an elevated PowerShell window.' }
    if ($Facts.ProductType -ne 1 -or [version]$Facts.Version -lt [version]'10.0.22000') {
        throw 'This test installer requires Windows 11; Windows Server is not supported.'
    }
    $identity = ($Facts.Manufacturer + ' ' + $Facts.Model).ToLowerInvariant()
    $isVm = $false
    foreach ($marker in @('virtual', 'vmware', 'virtualbox', 'kvm', 'qemu', 'xen', 'parallels', 'hyper-v')) {
        if ($identity.Contains($marker)) { $isVm = $true; break }
    }
    if (-not $isVm -and -not $AllowPhysicalTestHost) {
        throw 'Host is not a VM. Only a dedicated test machine may use -AllowPhysicalTestHost; never use a development workstation.'
    }
}

function Assert-StrictTestNoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse path rejected: $Path" }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
}

function Test-StrictTestByteSequence([byte[]]$Haystack, [byte[]]$Needle) {
    if ($Needle.Length -eq 0 -or $Needle.Length -gt $Haystack.Length) { return $false }
    $limit = $Haystack.Length - $Needle.Length
    for ($offset = 0; $offset -le $limit; ++$offset) {
        if ($Haystack[$offset] -ne $Needle[0]) { continue }
        $match = $true
        for ($index = 1; $index -lt $Needle.Length; ++$index) {
            if ($Haystack[$offset + $index] -ne $Needle[$index]) { $match = $false; break }
        }
        if ($match) { return $true }
    }
    return $false
}

function Assert-StrictTestSignature {
    param($Signature, [string]$Thumbprint, [string]$Name)
    if ($null -eq $Signature -or $Signature.Status -ne 'Valid' -or
        $null -eq $Signature.SignerCertificate -or
        $Signature.SignerCertificate.Thumbprint -ne $Thumbprint) {
        throw "Signature/trust mismatch: $Name. Only the supplied test certificate is accepted."
    }
}

function Assert-StrictTestAmd64Image([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw "Invalid PE image: $Path" }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt $stream.Length - 26) { throw "Invalid PE header bounds: $Path" }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw "Expected AMD64 PE image: $Path" }
        $stream.Position = $peOffset + 20
        $optionalSize = $reader.ReadUInt16()
        $characteristics = $reader.ReadUInt16()
        if ($optionalSize -lt 70 -or $peOffset + 24 + $optionalSize -gt $stream.Length -or
            ($characteristics -band 0x2000) -ne 0 -or ($characteristics -band 0x0002) -eq 0) {
            throw "Invalid executable PE header: $Path"
        }
        $stream.Position = $peOffset + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw "Expected PE32+ optional header: $Path" }
        $stream.Position = $peOffset + 24 + 68
        $subsystem = $reader.ReadUInt16()
        if (([IO.Path]::GetExtension($Path) -ieq '.sys' -and $subsystem -ne 1) -or
            ([IO.Path]::GetExtension($Path) -ieq '.exe' -and $subsystem -notin @(2, 3))) {
            throw "Invalid PE subsystem for package component: $Path"
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function Read-StrictTestManifest([byte[]]$Bytes) {
    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt 16384) { throw 'Strict manifest is outside the supported bounds (1..16384 bytes).' }
    # Match StrictPackageManifest's serde contract, including strict JSON,
    # exact field names, duplicate rejection and JSON value types.
    $json = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    try { $document = [System.Text.Json.JsonDocument]::Parse($json) }
    catch { throw 'Manifest must use strict JSON.' }
    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'Manifest must be a JSON object.' }
        $fields = @('protocol','packageVersion','driverBuildId','driverFileSha256','driverPublisherCertificateSha256',
            'agentFileSha256','agentPublisherCertificateSha256','coreFileSha256','corePublisherCertificateSha256')
        $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($field in $fields) { [void]$allowed.Add($field) }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $values = [ordered]@{}
        foreach ($property in $document.RootElement.EnumerateObject()) {
            if (-not $allowed.Contains($property.Name) -or -not $seen.Add($property.Name)) {
                throw "Unknown or duplicate manifest field: $($property.Name)"
            }
            if ($property.Name -ceq 'protocol') {
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or $property.Value.GetRawText() -cne '2') {
                    throw 'Unsupported strict manifest protocol; numeric 2 is required.'
                }
                $values.protocol = 2
            } else {
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw "Manifest field must be a string: $($property.Name)" }
                $values[$property.Name] = $property.Value.GetString()
            }
        }
        if ($seen.Count -ne $fields.Count) { throw 'Required manifest field is missing.' }
        if ($values.packageVersion -cnotmatch '\A[A-Za-z0-9.+-]{1,64}\z') { throw 'Invalid manifest packageVersion.' }
        foreach ($field in ($fields | Where-Object { $_ -notin @('protocol','packageVersion') })) {
            $length = if ($field -ceq 'driverBuildId') { 32 } else { 64 }
            if ($values[$field] -cnotmatch "\A[0-9A-Fa-f]{$length}\z" -or $values[$field] -match '^0+$') {
                throw "Malformed manifest identity: $field"
            }
        }
        return [pscustomobject]$values
    } finally { $document.Dispose() }
}

function Read-StrictTestPackage {
    param(
        [string]$PackageDirectory,
        [string]$Thumbprint,
        [scriptblock]$ReadSignature = { param($Path) Get-AuthenticodeSignature -LiteralPath $Path }
    )
    if (-not [IO.Path]::IsPathFullyQualified($PackageDirectory) -or $PackageDirectory.StartsWith('\\')) {
        throw 'Package directory must be an absolute local path.'
    }
    Assert-StrictTestNoReparse $PackageDirectory
    $files = @('FlClashStrictCallout.sys','FlClashStrictBroker.exe','FlClashAgent.exe','FlClashCore.exe')
    $sourceHashes = @{}
    foreach ($name in ($files + @('strict-package-manifest.json'))) {
        $path = Join-Path $PackageDirectory $name
        Assert-StrictTestNoReparse $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package entry must be a file: $name" }
        $sourceHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($name -ne 'strict-package-manifest.json') {
            Assert-StrictTestAmd64Image $path
            Assert-StrictTestSignature (& $ReadSignature $path) $Thumbprint $name
        }
    }
    $manifestPath = Join-Path $PackageDirectory 'strict-package-manifest.json'
    $brokerPath = Join-Path $PackageDirectory 'FlClashStrictBroker.exe'
    $manifestLength = (Get-Item -LiteralPath $manifestPath).Length
    $brokerLength = (Get-Item -LiteralPath $brokerPath).Length
    if ($manifestLength -lt 1 -or $manifestLength -gt 16384 -or $brokerLength -lt 1 -or $brokerLength -gt 268435456) {
        throw 'Package manifest or Broker size is outside the supported bounds.'
    }
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $brokerBytes = [IO.File]::ReadAllBytes($brokerPath)
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($manifestBytes)) -ne $sourceHashes['strict-package-manifest.json'] -or
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($brokerBytes)) -ne $sourceHashes['FlClashStrictBroker.exe']) {
        throw 'Package changed during manifest verification.'
    }
    if (-not (Test-StrictTestByteSequence $brokerBytes $manifestBytes)) {
        throw 'Broker does not embed the exact supplied package manifest.'
    }
    $manifest = Read-StrictTestManifest $manifestBytes
    foreach ($entry in @(
        @('FlClashStrictCallout.sys','driverFileSha256','driverPublisherCertificateSha256'),
        @('FlClashAgent.exe','agentFileSha256','agentPublisherCertificateSha256'),
        @('FlClashCore.exe','coreFileSha256','corePublisherCertificateSha256')
    )) {
        $expectedFileHash = $manifest.($entry[1])
        $expectedPublisherHash = $manifest.($entry[2])
        if ($expectedFileHash -notmatch '\A[0-9a-fA-F]{64}\z' -or $expectedPublisherHash -notmatch '\A[0-9a-fA-F]{64}\z') {
            throw "Malformed manifest identity: $($entry[0])"
        }
        if ($sourceHashes[$entry[0]] -ne $expectedFileHash) { throw "Manifest digest mismatch: $($entry[0])" }
        $signature = & $ReadSignature (Join-Path $PackageDirectory $entry[0])
        Assert-StrictTestSignature $signature $Thumbprint $entry[0]
        $publisherHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($signature.SignerCertificate.RawData))
        if ($publisherHash -ne $expectedPublisherHash) { throw "Manifest publisher mismatch: $($entry[0])" }
    }
    return $sourceHashes
}

function Get-StrictTestInstallationPlan {
    param(
        [hashtable]$HostFacts,
        [switch]$ConfirmTestMachine,
        [switch]$AllowPhysicalTestHost,
        [int]$BootQueryExitCode,
        [string]$BootConfiguration,
        [hashtable]$ServiceQueryExitCodes,
        [string]$PackageDirectory,
        [string]$Destination,
        [string]$Recovery,
        [string]$Thumbprint,
        [scriptblock]$ReadSignature = { param($Path) Get-AuthenticodeSignature -LiteralPath $Path }
    )
    Assert-StrictTestHost $HostFacts -ConfirmTestMachine:$ConfirmTestMachine -AllowPhysicalTestHost:$AllowPhysicalTestHost
    if ($BootQueryExitCode -ne 0 -or $BootConfiguration -notmatch '(?im)^testsigning\s+(Yes|是)\s*$') {
        throw 'Enable test signing on the dedicated test host and reboot first. This script never changes boot or certificate trust settings.'
    }
    foreach ($name in @('FlClashStrictCallout','FlClashStrictBroker')) {
        if (-not $ServiceQueryExitCodes.ContainsKey($name) -or $ServiceQueryExitCodes[$name] -ne 1060) {
            throw "Service $name exists or cannot be inspected. This fresh-test setup refuses upgrades."
        }
    }
    foreach ($path in @($Destination, $Recovery)) {
        if (-not [IO.Path]::IsPathFullyQualified($path) -or $path.StartsWith('\\')) { throw 'Installation directories must be absolute local paths.' }
        if (Test-Path -LiteralPath $path) { throw "Existing directory is not replaced: $path" }
        Assert-StrictTestNoReparse (Split-Path -Parent $path)
    }
    $hashes = Read-StrictTestPackage $PackageDirectory $Thumbprint $ReadSignature
    # This function performs no installation. All mutations remain in the
    # explicit entry script after every gate has succeeded.
    return [pscustomobject]@{ SourceHashes = $hashes; Destination = $Destination; Recovery = $Recovery }
}
