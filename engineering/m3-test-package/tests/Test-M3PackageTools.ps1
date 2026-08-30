[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path -Parent $PSScriptRoot
$manifestTool = Join-Path $toolRoot 'New-M3PackageManifest.ps1'
$bundleTool = Join-Path $toolRoot 'New-M3SignedVmBundle.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('flclash-m3-package-test-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $scripts = Get-ChildItem -LiteralPath $toolRoot -Filter '*.ps1'
    foreach ($script in $scripts) {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -ne 0) { throw "PowerShell parse failure: $($script.Name)" }
    }

    $manifest = Join-Path $testRoot 'strict-package-manifest.json'
    & $manifestTool `
        -DriverBuildId '0123456789abcdef0123456789abcdef' `
        -PackageVersion '0.2.0+m3-tool-test' `
        -DriverPath "$env:SystemRoot\System32\drivers\null.sys" `
        -AgentPath "$env:SystemRoot\System32\notepad.exe" `
        -CorePath "$env:SystemRoot\System32\cmd.exe" `
        -OutputPath $manifest | Out-Null
    $parsed = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($parsed.protocol -ne 2 -or (Get-Item -LiteralPath $manifest).Length -gt 16384) {
        throw 'valid signed package inputs did not produce a bounded protocol-v2 manifest'
    }

    $unsigned = Join-Path $testRoot 'unsigned.sys'
    [IO.File]::WriteAllBytes($unsigned, [byte[]](1, 2, 3, 4))
    $unsignedRejected = $false
    try {
        & $manifestTool `
            -DriverBuildId '0123456789abcdef0123456789abcdef' `
            -PackageVersion 'negative' `
            -DriverPath $unsigned `
            -AgentPath "$env:SystemRoot\System32\notepad.exe" `
            -CorePath "$env:SystemRoot\System32\cmd.exe" `
            -OutputPath (Join-Path $testRoot 'unsigned.json') | Out-Null
    }
    catch {
        $unsignedRejected = $_.Exception.Message -like '*valid trusted*'
    }
    if (-not $unsignedRejected) { throw 'unsigned driver input did not fail closed' }

    $manifestMismatchRejected = $false
    try {
        & $bundleTool `
            -DriverPath "$env:SystemRoot\System32\drivers\null.sys" `
            -BrokerPath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -AgentPath "$env:SystemRoot\System32\notepad.exe" `
            -CorePath "$env:SystemRoot\System32\cmd.exe" `
            -ManifestPath $manifest `
            -SourceCommit ('ab' * 20) `
            -OutputZip (Join-Path $testRoot 'must-not-exist.zip') | Out-Null
    }
    catch {
        $manifestMismatchRejected = $_.Exception.Message -like '*exact supplied package manifest*'
    }
    if (-not $manifestMismatchRejected) {
        throw 'a signed Broker without the exact embedded manifest did not fail closed'
    }

    Write-Output 'M3 package tool tests: PASS'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolved)).StartsWith('flclash-m3-package-test-', [StringComparison]::Ordinal)) {
            throw 'refusing to clean an unexpected test directory'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
