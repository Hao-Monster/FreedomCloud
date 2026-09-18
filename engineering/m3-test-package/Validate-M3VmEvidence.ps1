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
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be an absolute path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$Label must be a plain file"
    }
    return $item.FullName
}

function Resolve-PlainDirectory {
    param([string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be an absolute path" }
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
    if ($preflight.hashes.$name -notmatch '^[0-9A-Fa-f]{64}$') { throw "preflight hash is missing: $name" }
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
$summaryServices = @($summary.services)
foreach ($serviceName in @('FlClashStrictCallout', 'FlClashStrictBroker')) {
    $service = $summaryServices | Where-Object { $_.name -eq $serviceName } | Select-Object -First 1
    if ($null -eq $service -or [string]::IsNullOrWhiteSpace([string]$service.state) -or [string]::IsNullOrWhiteSpace([string]$service.startMode)) {
        throw "system summary service record is missing: $serviceName"
    }
}
$strictState = Get-Content -LiteralPath (Join-Path $evidence 'strict-state.txt') -Raw
foreach ($serviceName in @('FlClashStrictCallout', 'FlClashStrictBroker')) {
    if (-not $strictState.Contains("service=$serviceName")) { throw "strict service state is missing: $serviceName" }
}

$sumPath = Join-Path $evidence 'SHA256SUMS.txt'
$sumPattern = '^([0-9A-Fa-f]{64}) \*([0-9A-Za-z][0-9A-Za-z._/-]{0,255})$'
$declared = @{}
foreach ($line in (Get-Content -LiteralPath $sumPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch $sumPattern) { throw 'SHA256SUMS.txt contains an invalid or unsafe entry' }
    $relative = $Matches[2] -replace '/', '\\'
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) { throw 'SHA256SUMS.txt contains an unsafe path' }
    $key = $relative.ToLowerInvariant()
    if ($declared.ContainsKey($key)) { throw "SHA256SUMS.txt contains a duplicate entry: $relative" }
    $declared[$key] = $Matches[1].ToUpperInvariant()
}
$actualFiles = Get-ChildItem -LiteralPath $evidence -File -Recurse |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' }
foreach ($file in $actualFiles) {
    $relative = $file.FullName.Substring($evidence.Length).TrimStart('\\')
    $key = $relative.ToLowerInvariant()
    if (-not $declared.ContainsKey($key)) { throw "evidence file is not covered by SHA256SUMS.txt: $relative" }
    $actualHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($declared[$key] -ne $actualHash) { throw "evidence hash mismatch: $relative" }
}
foreach ($key in $declared.Keys) {
    $candidate = Join-Path $evidence $key
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "SHA256SUMS.txt references a missing file: $key" }
}
if ($declared.Count -lt 1) { throw 'SHA256SUMS.txt contains no evidence files' }

Write-Output 'M3 VM evidence validation: PASS (read-only completeness and trust gates)'
