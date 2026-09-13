[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$DriverPath,
    [Parameter(Mandatory = $true)] [string]$BrokerPath,
    [Parameter(Mandatory = $true)] [string]$AgentPath,
    [Parameter(Mandatory = $true)] [string]$CorePath,
    [Parameter(Mandatory = $true)] [string]$ManifestPath,
    [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9A-Fa-f]{40,64}$')] [string]$SourceCommit,
    [Parameter(Mandatory = $true)] [string]$OutputZip,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PlainFile {
    param([string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Label must be an absolute path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$Label must be a plain file"
    }
    return $item.FullName
}

function Get-SignedIdentity {
    param([string]$Path, [string]$Label)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.RawData.Length -eq 0) {
        throw "$Label is not signed by a currently trusted Authenticode/catalog publisher"
    }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $certificateHash = $sha256.ComputeHash($signature.SignerCertificate.RawData) }
    finally { $sha256.Dispose() }
    return [pscustomobject]@{
        FileSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        PublisherCertificateSha256 = ([BitConverter]::ToString($certificateHash) -replace '-', '').ToLowerInvariant()
    }
}

function Assert-EqualHex {
    param([string]$Actual, [string]$Expected, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Expected) -or
        -not $Actual.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label does not match the signed package manifest"
    }
}

function Test-ContainsByteSequence {
    param([byte[]]$Haystack, [byte[]]$Needle)
    if ($Needle.Length -eq 0 -or $Needle.Length -gt $Haystack.Length) { return $false }
    $limit = $Haystack.Length - $Needle.Length
    for ($offset = 0; $offset -le $limit; ++$offset) {
        if ($Haystack[$offset] -ne $Needle[0]) { continue }
        $isMatch = $true
        for ($index = 1; $index -lt $Needle.Length; ++$index) {
            if ($Haystack[$offset + $index] -ne $Needle[$index]) {
                $isMatch = $false
                break
            }
        }
        if ($isMatch) { return $true }
    }
    return $false
}

$driver = Resolve-PlainFile $DriverPath 'driver'
$broker = Resolve-PlainFile $BrokerPath 'Broker'
$agent = Resolve-PlainFile $AgentPath 'Agent'
$core = Resolve-PlainFile $CorePath 'Core'
$manifestFile = Resolve-PlainFile $ManifestPath 'package manifest'
if ((Get-Item -LiteralPath $manifestFile).Length -gt 16384) { throw 'package manifest is too large' }
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
if ($manifest.protocol -ne 2 -or
    $manifest.driverBuildId -notmatch '^[0-9A-Fa-f]{32}$' -or
    $manifest.packageVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$') {
    throw 'package manifest header is invalid'
}

$driverIdentity = Get-SignedIdentity $driver 'driver'
$brokerIdentity = Get-SignedIdentity $broker 'Broker'
$agentIdentity = Get-SignedIdentity $agent 'Agent'
$coreIdentity = Get-SignedIdentity $core 'Core'
Assert-EqualHex $driverIdentity.FileSha256 $manifest.driverFileSha256 'driver digest'
Assert-EqualHex $driverIdentity.PublisherCertificateSha256 $manifest.driverPublisherCertificateSha256 'driver publisher'
Assert-EqualHex $agentIdentity.FileSha256 $manifest.agentFileSha256 'Agent digest'
Assert-EqualHex $agentIdentity.PublisherCertificateSha256 $manifest.agentPublisherCertificateSha256 'Agent publisher'
Assert-EqualHex $coreIdentity.FileSha256 $manifest.coreFileSha256 'Core digest'
Assert-EqualHex $coreIdentity.PublisherCertificateSha256 $manifest.corePublisherCertificateSha256 'Core publisher'
$manifestBytes = [IO.File]::ReadAllBytes($manifestFile)
$brokerBytes = [IO.File]::ReadAllBytes($broker)
if (-not (Test-ContainsByteSequence -Haystack $brokerBytes -Needle $manifestBytes)) {
    throw 'Broker does not embed the exact supplied package manifest'
}

if (-not [IO.Path]::IsPathFullyQualified($OutputZip) -or
    -not $OutputZip.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputZip must be an absolute .zip path'
}
$output = [IO.Path]::GetFullPath($OutputZip)
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    throw 'OutputZip parent directory does not exist'
}
$outputParentItem = Get-Item -LiteralPath $outputParent -Force
if (($outputParentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'OutputZip parent directory must not be a reparse point'
}
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw 'OutputZip already exists; use -Force to replace it'
}

$staging = Join-Path $outputParent ('.m3-vm-bundle-' + [Guid]::NewGuid().ToString('N'))
$temporaryZip = Join-Path $outputParent ('.m3-vm-bundle-' + [Guid]::NewGuid().ToString('N') + '.zip')
$utf8 = New-Object Text.UTF8Encoding($false)
try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    Copy-Item -LiteralPath $driver -Destination (Join-Path $staging 'FlClashStrictCallout.sys')
    Copy-Item -LiteralPath $broker -Destination (Join-Path $staging 'FlClashStrictBroker.exe')
    Copy-Item -LiteralPath $agent -Destination (Join-Path $staging 'FlClashAgent.exe')
    Copy-Item -LiteralPath $core -Destination (Join-Path $staging 'FlClashCore.exe')
    Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $staging 'strict-package-manifest.json')
    foreach ($support in @(
        'Invoke-M3VmPreflight.ps1'
        'Collect-M3VmEvidence.ps1'
        'M3-WINDOWS-VM-CHECKLIST.md'
        'REAL-WINDOWS11-TEST-GUIDE.md'
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $support) -Destination (Join-Path $staging $support)
    }

    $stagedDriver = Get-SignedIdentity (Join-Path $staging 'FlClashStrictCallout.sys') 'staged driver'
    $stagedBroker = Get-SignedIdentity (Join-Path $staging 'FlClashStrictBroker.exe') 'staged Broker'
    $stagedAgent = Get-SignedIdentity (Join-Path $staging 'FlClashAgent.exe') 'staged Agent'
    $stagedCore = Get-SignedIdentity (Join-Path $staging 'FlClashCore.exe') 'staged Core'
    Assert-EqualHex $stagedDriver.FileSha256 $driverIdentity.FileSha256 'staged driver digest'
    Assert-EqualHex $stagedBroker.FileSha256 $brokerIdentity.FileSha256 'staged Broker digest'
    Assert-EqualHex $stagedAgent.FileSha256 $agentIdentity.FileSha256 'staged Agent digest'
    Assert-EqualHex $stagedCore.FileSha256 $coreIdentity.FileSha256 'staged Core digest'
    Assert-EqualHex (Get-FileHash -LiteralPath (Join-Path $staging 'strict-package-manifest.json') -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash 'staged manifest digest'

    $buildInfo = @(
        'FlClashX M3 signed Windows VM qualification bundle'
        "Source commit: $($SourceCommit.ToLowerInvariant())"
        "Package version: $($manifest.packageVersion)"
        "Driver build ID: $($manifest.driverBuildId.ToLowerInvariant())"
        "Created UTC: $([DateTime]::UtcNow.ToString('o'))"
        "Broker SHA-256: $($brokerIdentity.FileSha256)"
        'Purpose: isolated Windows 11 VM qualification only; not a public release.'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $staging 'BUILD-INFO.txt'), $buildInfo + [Environment]::NewLine, $utf8)

    $sumLines = Get-ChildItem -LiteralPath $staging -File |
        Where-Object Name -ne 'SHA256SUMS.txt' |
        Sort-Object Name |
        ForEach-Object { '{0} *{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.Name }
    [IO.File]::WriteAllText((Join-Path $staging 'SHA256SUMS.txt'), ($sumLines -join [Environment]::NewLine) + [Environment]::NewLine, $utf8)
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $temporaryZip -CompressionLevel Optimal
    Move-Item -LiteralPath $temporaryZip -Destination $output -Force:$Force
}
finally {
    if (Test-Path -LiteralPath $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force }
    if (Test-Path -LiteralPath $staging) {
        $resolvedStaging = (Resolve-Path -LiteralPath $staging).Path
        $resolvedParent = (Resolve-Path -LiteralPath $outputParent).Path.TrimEnd('\') + '\'
        if (-not $resolvedStaging.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolvedStaging)).StartsWith('.m3-vm-bundle-', [StringComparison]::Ordinal)) {
            throw 'refusing to clean an unexpected staging path'
        }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}

Write-Output $output
