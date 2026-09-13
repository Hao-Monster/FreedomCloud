[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 does not expose IsPathFullyQualified (or the newer
# GetRelativePath API used below).  Check the drive/UNC prefix explicitly so a
# drive-relative path such as `C:logs` cannot be silently resolved elsewhere.
if (-not [IO.Path]::IsPathRooted($OutputDirectory) -or
    $OutputDirectory -notmatch '^(?:[A-Za-z]:[\\/]|\\\\)') {
    throw 'OutputDirectory must be an absolute path'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $output)) {
    New-Item -ItemType Directory -Path $output | Out-Null
}
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
    $allowed = '^(FlClashX_\d{4}-\d{2}-\d{2}(?:_\d+)?|connections_diagnostic|FlClashAgent(?:\.bootstrap)?|FlClashHelperService|helper-install|FlClashStrictBroker)\.log(?:\.\d+)?$'
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
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$inventory = New-Object Collections.Generic.List[object]
$sources = @(
    @{ root = if ($env:APPDATA) { Join-Path $env:APPDATA 'com.follow\clashx\logs' } else { $null }; label = 'appdata' },
    @{ root = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'FlClashX\logs' } else { $null }; label = 'localappdata' },
    @{ root = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX\logs' } else { $null }; label = 'programdata' },
    @{ root = if ($env:ProgramData) { Join-Path $env:ProgramData 'FlClashX.StrictBroker\logs' } else { $null }; label = 'strict-broker' },
    @{ root = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'FlClashX Service\logs' } else { $null }; label = 'helper-service' }
)
foreach ($source in $sources) {
    if ($null -ne $source.root) {
        foreach ($entry in @(Copy-ApplicationLogs -SourceRoot $source.root -Label $source.label -DestinationRoot $logRoot)) {
            $inventory.Add($entry)
        }
    }
}

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    (Join-Path $output 'log-inventory.json'),
    ($inventory | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
    $utf8
)
$eventStart = [DateTime]::Now.AddMinutes(-60)
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
For a driver-focused run, start an approved DebugView/ETW capture before the test,
save the capture as driver-debug.txt, and place it beside this evidence directory.
Do not include packet payloads, profile data, credentials, or command-line secrets.
"@,
    $utf8
)

$outputPrefix = $output.TrimEnd('\', '/') + '\'
$hashLines = Get-ChildItem -LiteralPath $output -File -Recurse |
    ForEach-Object {
        # Derive the relative path with String.Substring for PS 5.1
        # compatibility. All files come from Get-ChildItem rooted at $output,
        # so this does not evaluate or join untrusted path segments.
        $relative = $_.FullName.Substring($outputPrefix.Length) -replace '\\', '/'
        if ($relative -ne 'SHA256SUMS.txt') {
            '{0} *{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
        }
    } |
    Sort-Object
[IO.File]::WriteAllText(
    (Join-Path $output 'SHA256SUMS.txt'),
    ($hashLines -join [Environment]::NewLine) + [Environment]::NewLine,
    $utf8
)

Write-Output $output
