[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$PreflightJson
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

function Resolve-PlainDirectory {
    param([string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Label must be an absolute path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$Label must be a plain directory"
    }
    return $item.FullName
}

$evidence = Resolve-PlainDirectory $EvidenceDirectory 'evidence directory'
$preflightPath = Resolve-PlainFile $PreflightJson 'preflight report'
$preflight = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
if ($preflight.schema -ne 1 -or $preflight.elevated -ne $true -or $preflight.virtualMachine -ne $true) {
    throw 'preflight is not an elevated isolated VM report'
}
foreach ($name in @('FlClashStrictCallout.sys', 'FlClashStrictBroker.exe', 'FlClashAgent.exe', 'FlClashCore.exe')) {
    if ($preflight.signatures.$name -ne 'Valid') { throw "preflight signature is not valid: $name" }
    if ($preflight.hashes.$name -notmatch '^[a-f0-9]{64}$') { throw "preflight hash is missing: $name" }
}
foreach ($name in @(
    'strict-state.txt',
    'system-summary.json',
    'process-samples.csv',
    'driver-verifier.txt',
    'service-control-events.txt',
    'driver-debug-instructions.txt',
    'SHA256SUMS.txt'
)) {
    Resolve-PlainFile (Join-Path $evidence $name) "evidence/$name" | Out-Null
}
$summary = Get-Content -LiteralPath (Join-Path $evidence 'system-summary.json') -Raw | ConvertFrom-Json
if ($summary.schema -ne 1 -or $summary.sampleRows -lt 1) { throw 'system summary has no process samples' }
$strictState = Get-Content -LiteralPath (Join-Path $evidence 'strict-state.txt') -Raw
foreach ($serviceName in @('FlClashStrictCallout', 'FlClashStrictBroker')) {
    if (-not $strictState.Contains("service=$serviceName")) { throw "strict service state is missing: $serviceName" }
}

Write-Output 'M3 VM evidence validation: PASS (read-only completeness and trust gates)'
