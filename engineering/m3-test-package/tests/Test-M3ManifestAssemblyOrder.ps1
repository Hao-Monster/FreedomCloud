[CmdletBinding()]
param([string]$ToolRoot)

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
    $ToolRoot = Join-Path (Get-Location).Path 'engineering/m3-test-package'
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$generator = Join-Path $ToolRoot 'New-M3PackageManifest.ps1'
$parameters = (Get-Command $generator).Parameters
if ($parameters.ContainsKey('BrokerPath')) {
    throw 'Manifest generation must precede Broker compilation and must not require a Broker binary'
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('m3-assembly-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
    & $generator -DriverBuildId ('12' * 16) -PackageVersion 'assembly-order' `
        -DriverPath "$env:SystemRoot\System32\drivers\null.sys" `
        -AgentPath "$env:SystemRoot\System32\notepad.exe" `
        -CorePath "$env:SystemRoot\System32\cmd.exe" -OutputPath $temporary | Out-Null
    $manifest = Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json
    if ($manifest.PSObject.Properties.Name -contains 'brokerFileSha256') {
        throw 'Embedded manifest cannot contain the hash of its containing Broker'
    }
    foreach ($role in @('driver', 'agent', 'core')) {
        if ($manifest."${role}FileSha256" -notmatch '^[a-f0-9]{64}$' -or
            $manifest."${role}PublisherCertificateSha256" -notmatch '^[a-f0-9]{64}$') {
            throw "Missing pinned identity: $role"
        }
    }
    Write-Output 'Manifest assembly order: PASS (no Broker input or self hash; dependency identities retained)'
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
