$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('m3-evidence-' + [guid]::NewGuid().ToString('N'))
$evidence = Join-Path $temp 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
try {
    @{
        'strict-state.txt' = "service=FlClashStrictCallout`nservice=FlClashStrictBroker"
        'process-samples.csv' = 'sample'
        'driver-verifier.txt' = 'verifier'
        'service-control-events.txt' = ''
        'driver-debug-instructions.txt' = 'instructions'
    }.GetEnumerator() | ForEach-Object {
        [IO.File]::WriteAllText((Join-Path $evidence $_.Key), $_.Value)
    }
    $summary = @{
        schema = 1
        sampleRows = 1
        services = @(
            @{ name = 'FlClashStrictCallout'; state = 'Running'; startMode = 'Auto' }
            @{ name = 'FlClashStrictBroker'; state = 'Running'; startMode = 'Auto' }
        )
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'system-summary.json')
    $hashLines = Get-ChildItem -LiteralPath $evidence -File | ForEach-Object {
        '{0} *{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.Name
    } | Sort-Object
    [IO.File]::WriteAllText((Join-Path $evidence 'SHA256SUMS.txt'), ($hashLines -join [Environment]::NewLine) + [Environment]::NewLine)
    $preflight = @{
        schema = 1
        elevated = $true
        virtualMachine = $true
        signatures = @{
            'FlClashStrictCallout.sys' = 'Valid'
            'FlClashStrictBroker.exe' = 'Valid'
            'FlClashAgent.exe' = 'Valid'
            'FlClashCore.exe' = 'Valid'
        }
        hashes = @{
            'FlClashStrictCallout.sys' = ('a' * 64)
            'FlClashStrictBroker.exe' = ('b' * 64)
            'FlClashAgent.exe' = ('c' * 64)
            'FlClashCore.exe' = ('d' * 64)
        }
    }
    $preflightPath = Join-Path $temp 'M3-PREFLIGHT.json'
    $preflight | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $preflightPath
    $validator = Join-Path $scriptRoot 'Validate-M3VmEvidence.ps1'
    & $validator -EvidenceDirectory $evidence -PreflightJson $preflightPath | Out-Null
    Add-Content -LiteralPath (Join-Path $evidence 'strict-state.txt') 'tampered'
    $tamperCaught = $false
    $tamperMessage = ''
    try {
        & $validator -EvidenceDirectory $evidence -PreflightJson $preflightPath | Out-Null
    }
    catch {
        $tamperCaught = $true
        $tamperMessage = $_.Exception.Message
    }
    if (-not $tamperCaught -or $tamperMessage -notmatch 'hash mismatch') {
        throw 'tampered evidence was not rejected'
    }
    Write-Output 'M3 evidence integrity tests: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
