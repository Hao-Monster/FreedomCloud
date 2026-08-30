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

if (-not [IO.Path]::IsPathFullyQualified($OutputDirectory)) {
    throw 'OutputDirectory must be an absolute path'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $output)) { New-Item -ItemType Directory -Path $output | Out-Null }
$outputItem = Get-Item -LiteralPath $output -Force
if (-not $outputItem.PSIsContainer -or (($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw 'OutputDirectory must be a plain directory'
}

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
$hashLines = Get-ChildItem -LiteralPath $output -File |
    Where-Object Name -ne 'SHA256SUMS.txt' |
    Sort-Object Name |
    ForEach-Object { '{0} *{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.Name }
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), ($hashLines -join [Environment]::NewLine) + [Environment]::NewLine, $utf8)

Write-Output $output
