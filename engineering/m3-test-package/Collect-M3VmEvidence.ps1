[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [ValidateRange(1, 120)]
    [int]$DurationMinutes = 30,

    [ValidateRange(1, 60)]
    [int]$SampleIntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-FcxAbsolutePath {
    param([string]$Path)
    # IsPathFullyQualified and GetRelativePath are not available in Windows
    # PowerShell 5.1, which is still present on supported Windows 11 hosts.
    return (-not [string]::IsNullOrWhiteSpace($Path)) -and
        ($Path -match '^(?:[A-Za-z]:[\\/]|\\\\)')
}

if (-not (Test-FcxAbsolutePath $OutputDirectory)) {
    throw 'OutputDirectory must be an absolute path'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $output)) { New-Item -ItemType Directory -Path $output | Out-Null }
$outputItem = Get-Item -LiteralPath $output -Force
if (-not $outputItem.PSIsContainer -or (($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw 'OutputDirectory must be a plain directory'
}

function Copy-ApplicationLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        return @()
    }
    $destination = Join-Path $DestinationRoot $Label
    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }
    $allowed = '^(FlClashX_\d{4}-\d{2}-\d{2}(?:_\d+)?|connections_diagnostic|FlClashAgent(?:\.bootstrap)?|FlClashHelperService|FlClashStrictBroker)\.log(?:\.\d+)?$'
    $copied = New-Object Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -File -ErrorAction SilentlyContinue) {
        if ($file.Name -notmatch $allowed) {
            continue
        }
        $target = Join-Path $destination $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied.Add([pscustomobject]@{
            source = "$Label/$($file.Name)"
            copied = "logs/$Label/$($file.Name)"
            bytes = $file.Length
        })
    }
    return $copied
}

$logRoot = Join-Path $output 'logs'
if (-not (Test-Path -LiteralPath $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot | Out-Null
}
$logInventory = New-Object Collections.Generic.List[object]
$appDataRoot = if ($env:APPDATA) { Join-Path $env:APPDATA 'com.follow\clashx\logs' } else { $null }
$localAppDataRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'FlClashX\logs' } else { $null }
$programDataRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX\logs' } else { $null }
$strictBrokerLogRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX.StrictBroker\logs' } else { $null }
$serviceLogRoot = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'FlClashX Service\logs' } else { $null }
foreach ($source in @(
        @{ root = $appDataRoot; label = 'appdata' },
        @{ root = $localAppDataRoot; label = 'localappdata' },
        @{ root = $programDataRoot; label = 'programdata' },
        @{ root = $strictBrokerLogRoot; label = 'strict-broker' },
        @{ root = $serviceLogRoot; label = 'helper-service' }
    )) {
    if ($null -ne $source.root) {
        foreach ($entry in @(Copy-ApplicationLogs -SourceRoot $source.root -Label $source.label -DestinationRoot $logRoot)) {
            $logInventory.Add($entry)
        }
    }
}
$logInventory | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'log-inventory.json') -Encoding UTF8

# Keep the recovery marker out of shared evidence because it may contain full
# executable paths. Record only presence, bounded target count and a digest so
# crash/upgrade/uninstall recovery can still be correlated safely.
$strictState = New-Object Text.StringBuilder
[void]$strictState.AppendLine("capturedUtc=$([DateTime]::UtcNow.ToString('o'))")
foreach ($serviceName in @('FlClashHelperService', 'FlClashStrictCallout', 'FlClashStrictBroker')) {
    [void]$strictState.AppendLine("service=$serviceName")
    [void]$strictState.AppendLine((& sc.exe query $serviceName 2>&1 | Out-String).Trim())
    [void]$strictState.AppendLine((& sc.exe qc $serviceName 2>&1 | Out-String).Trim())
}
foreach ($marker in @(
        @{ path = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX\strict-recovery.json' } else { $null }; label = 'helper' },
        @{ path = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX.StrictBroker\strict-recovery-v1.json' } else { $null }; label = 'broker' }
    )) {
    if ($null -ne $marker.path -and (Test-Path -LiteralPath $marker.path -PathType Leaf)) {
        $markerHash = (Get-FileHash -LiteralPath $marker.path -Algorithm SHA256).Hash
        try {
            $markerJson = Get-Content -LiteralPath $marker.path -Raw | ConvertFrom-Json
            $markerTargets = if ($null -ne $markerJson.targets) { @($markerJson.targets).Count } elseif ($null -ne $markerJson.marker) { 1 } else { 0 }
        } catch {
            $markerTargets = 'invalid-json'
        }
        [void]$strictState.AppendLine("recoveryMarker.$($marker.label).present=true")
        [void]$strictState.AppendLine("recoveryMarker.$($marker.label).targets=$markerTargets")
        [void]$strictState.AppendLine("recoveryMarker.$($marker.label).sha256=$markerHash")
    } else {
        [void]$strictState.AppendLine("recoveryMarker.$($marker.label).present=false")
    }
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $output 'strict-state.txt'), $strictState.ToString(), $utf8)

$processNames = @('FlClashX', 'FlClashAgent', 'FlClashCore', 'FlClashStrictBroker', 'FlClashHelperService')
$sampleLimit = [Math]::Ceiling(($DurationMinutes * 60) / $SampleIntervalSeconds) + 1
$samples = New-Object Collections.Generic.List[object]
for ($sample = 0; $sample -lt $sampleLimit; ++$sample) {
    $now = [DateTime]::UtcNow.ToString('o')
    foreach ($name in $processNames) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $samples.Add([pscustomobject]@{
                collectedUtc = $now
                process = $name
                pid = $process.Id
                workingSetBytes = $process.WorkingSet64
                privateBytes = $process.PrivateMemorySize64
                handleCount = $process.HandleCount
                threadCount = $process.Threads.Count
                totalProcessorSeconds = $process.TotalProcessorTime.TotalSeconds
            })
        }
    }
    if ($sample + 1 -lt $sampleLimit) { Start-Sleep -Seconds $SampleIntervalSeconds }
}
$samples | Export-Csv -LiteralPath (Join-Path $output 'process-samples.csv') -NoTypeInformation -Encoding UTF8

$services = foreach ($name in @('FlClashStrictCallout', 'FlClashStrictBroker', 'FlClashHelperService')) {
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        [pscustomobject]@{
            name = $name
            state = $service.State
            startMode = $service.StartMode
            serviceType = $service.ServiceType
            processId = $service.ProcessId
        }
    }
}
$system = Get-CimInstance -ClassName Win32_OperatingSystem
$summary = [ordered]@{
    schema = 1
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    osVersion = $system.Version
    osBuild = $system.BuildNumber
    durationMinutes = $DurationMinutes
    intervalSeconds = $SampleIntervalSeconds
    sampleRows = $samples.Count
    services = @($services)
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $output 'system-summary.json'), ($summary | ConvertTo-Json -Depth 4) + [Environment]::NewLine, $utf8)

$verifier = & verifier.exe /querysettings 2>&1 | Out-String
[IO.File]::WriteAllText((Join-Path $output 'driver-verifier.txt'), $verifier, $utf8)
$eventStart = [DateTime]::Now.AddMinutes(-[Math]::Max(60, $DurationMinutes + 10))
$serviceEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Service Control Manager'
    StartTime = $eventStart
} -MaxEvents 200 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Format-List | Out-String
[IO.File]::WriteAllText((Join-Path $output 'service-control-events.txt'), $serviceEvents, $utf8)
[IO.File]::WriteAllText(
    (Join-Path $output 'driver-debug-instructions.txt'),
    @"
Kernel driver diagnostics use DbgPrintEx and are not written from the driver to disk.
For a driver-focused run, start an approved DebugView or WFP ETW capture before the
test, save it as driver-debug.txt, and place it beside this evidence directory.
Record capture start/stop time and Windows build number.
The driver must never write arbitrary files from kernel mode.
Do not include packet payloads, profile data, credentials, or command-line secrets.
"@,
    $utf8
)
$outputPrefix = $output.TrimEnd('\\') + '\\'
$hashLines = Get-ChildItem -LiteralPath $output -File -Recurse |
    ForEach-Object {
        if (-not $_.FullName.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'evidence file escaped the output directory'
        }
        $relative = $_.FullName.Substring($outputPrefix.Length) -replace '\\', '/'
        if ($relative -ne 'SHA256SUMS.txt') {
            '{0} *{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
        }
    } |
    Sort-Object
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), ($hashLines -join [Environment]::NewLine) + [Environment]::NewLine, $utf8)

Write-Output $output
