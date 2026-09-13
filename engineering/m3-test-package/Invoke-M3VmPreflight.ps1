[CmdletBinding()]
param(
    [string]$PackageDirectory = $PSScriptRoot,
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot 'evidence'),
    [switch]$AllowPhysicalTestHost
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-VirtualMachine {
    param([string]$Manufacturer, [string]$Model)
    $identity = ($Manufacturer + ' ' + $Model).ToLowerInvariant()
    foreach ($marker in @('virtual', 'vmware', 'virtualbox', 'kvm', 'qemu', 'xen', 'parallels', 'hyper-v')) {
        if ($identity.Contains($marker)) { return $true }
    }
    return $false
}

function Assert-PlainDirectory {
    param([string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Label must be an absolute path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$Label must be a plain directory"
    }
    return $item.FullName
}

$package = Assert-PlainDirectory ([IO.Path]::GetFullPath($PackageDirectory)) 'package directory'
if (-not (Test-IsAdministrator)) { throw 'M3 VM qualification must run from an elevated PowerShell session' }
$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$isVm = Test-VirtualMachine $computer.Manufacturer $computer.Model
if (-not $isVm -and -not $AllowPhysicalTestHost) {
    throw 'host does not identify as a VM; use an isolated VM or explicitly allow a dedicated physical test host'
}

$expectedFiles = @(
    'FlClashStrictCallout.sys',
    'FlClashStrictBroker.exe',
    'FlClashAgent.exe',
    'FlClashCore.exe',
    'strict-package-manifest.json',
    'SHA256SUMS.txt'
)
foreach ($name in $expectedFiles) {
    $path = Join-Path $package $name
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$name must be a plain package file"
    }
}

$sumPath = Join-Path $package 'SHA256SUMS.txt'
$sumLines = Get-Content -LiteralPath $sumPath
$verified = [ordered]@{}
foreach ($line in $sumLines) {
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*([0-9A-Za-z][0-9A-Za-z._-]{0,127})$') {
        throw 'SHA256SUMS.txt contains an invalid or unsafe entry'
    }
    $name = $Matches[2]
    if ($verified.Contains($name)) { throw "duplicate package hash entry: $name" }
    $path = Join-Path $package $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "package file is missing: $name" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if (-not $actual.Equals($Matches[1], [StringComparison]::OrdinalIgnoreCase)) {
        throw "package hash mismatch: $name"
    }
    $verified[$name] = $actual.ToLowerInvariant()
}
foreach ($name in $expectedFiles | Where-Object { $_ -ne 'SHA256SUMS.txt' }) {
    if (-not $verified.Contains($name)) { throw "package hash is not declared: $name" }
}

$signatureResults = [ordered]@{}
foreach ($name in @('FlClashStrictCallout.sys', 'FlClashStrictBroker.exe', 'FlClashAgent.exe', 'FlClashCore.exe')) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $package $name)
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "package signature is not trusted: $name"
    }
    $signatureResults[$name] = $signature.Status.ToString()
}

$secureBoot = 'unsupported'
try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { $secureBoot = 'unavailable' }
$hvci = 0
$hvciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
if (Test-Path -LiteralPath $hvciPath) {
    $hvci = [int](Get-ItemPropertyValue -LiteralPath $hvciPath -Name Enabled -ErrorAction SilentlyContinue)
}
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$manifest = Get-Content -LiteralPath (Join-Path $package 'strict-package-manifest.json') -Raw | ConvertFrom-Json
$report = [ordered]@{
    schema = 1
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    osCaption = $os.Caption
    osVersion = $os.Version
    osBuild = $os.BuildNumber
    virtualMachine = $isVm
    manufacturer = $computer.Manufacturer
    model = $computer.Model
    elevated = $true
    secureBoot = $secureBoot
    hvciEnabled = ($hvci -eq 1)
    packageVersion = $manifest.packageVersion
    driverBuildId = $manifest.driverBuildId
    hashes = $verified
    signatures = $signatureResults
}

$evidenceFull = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not (Test-Path -LiteralPath $evidenceFull)) { New-Item -ItemType Directory -Path $evidenceFull | Out-Null }
$evidence = Assert-PlainDirectory $evidenceFull 'evidence directory'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $evidence 'M3-PREFLIGHT.json'), ($report | ConvertTo-Json -Depth 5) + [Environment]::NewLine, $utf8)
Write-Output (Join-Path $evidence 'M3-PREFLIGHT.json')
