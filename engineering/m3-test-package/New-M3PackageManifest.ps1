[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{32}$')]
    [string]$DriverBuildId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$')]
    [string]$PackageVersion,

    [Parameter(Mandatory = $true)]
    [string]$DriverPath,

    [Parameter(Mandatory = $true)]
    [string]$BrokerPath,

    [Parameter(Mandatory = $true)]
    [string]$AgentPath,

    [Parameter(Mandatory = $true)]
    [string]$CorePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-FcxAbsolutePath {
    param([string]$Path)
    # IsPathFullyQualified was added after the Windows PowerShell 5.1
    # runtime. Keep the package tooling usable on the supported inbox shell.
    return (-not [string]::IsNullOrWhiteSpace($Path)) -and
        ($Path -match '^(?:[A-Za-z]:[\\/]|\\\\)')
}

function Resolve-PlainFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-FcxAbsolutePath $Path)) {
        throw "$Label must be an absolute path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "$Label must be a plain file"
    }
    return $item.FullName
}

function Get-FileIdentity {
    param([string]$Path, [string]$Label)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.RawData.Length -eq 0) {
        throw "$Label does not have a valid trusted Authenticode/catalog signature"
    }

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $publisherDigest = $sha256.ComputeHash($signature.SignerCertificate.RawData)
    }
    finally {
        $sha256.Dispose()
    }

    return [pscustomobject]@{
        FileSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        PublisherCertificateSha256 = ([BitConverter]::ToString($publisherDigest) -replace '-', '').ToLowerInvariant()
    }
}

$driver = Resolve-PlainFile -Path $DriverPath -Label 'driver'
$broker = Resolve-PlainFile -Path $BrokerPath -Label 'Broker'
$agent = Resolve-PlainFile -Path $AgentPath -Label 'Agent'
$core = Resolve-PlainFile -Path $CorePath -Label 'Core'
if (-not (Test-FcxAbsolutePath $OutputPath)) {
    throw 'OutputPath must be an absolute path'
}
$output = [IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw 'OutputPath parent directory does not exist'
}
$parentItem = Get-Item -LiteralPath $parent -Force
if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'OutputPath parent directory must not be a reparse point'
}
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw 'OutputPath already exists; use -Force to replace it'
}

$driverIdentity = Get-FileIdentity -Path $driver -Label 'driver'
$brokerIdentity = Get-FileIdentity -Path $broker -Label 'Broker'
$agentIdentity = Get-FileIdentity -Path $agent -Label 'Agent'
$coreIdentity = Get-FileIdentity -Path $core -Label 'Core'
$manifest = [ordered]@{
    protocol = 2
    packageVersion = $PackageVersion
    driverBuildId = $DriverBuildId.ToLowerInvariant()
    driverFileSha256 = $driverIdentity.FileSha256
    driverPublisherCertificateSha256 = $driverIdentity.PublisherCertificateSha256
    brokerFileSha256 = $brokerIdentity.FileSha256
    brokerPublisherCertificateSha256 = $brokerIdentity.PublisherCertificateSha256
    agentFileSha256 = $agentIdentity.FileSha256
    agentPublisherCertificateSha256 = $agentIdentity.PublisherCertificateSha256
    coreFileSha256 = $coreIdentity.FileSha256
    corePublisherCertificateSha256 = $coreIdentity.PublisherCertificateSha256
}
$json = ($manifest | ConvertTo-Json -Depth 2) + [Environment]::NewLine
$utf8 = New-Object Text.UTF8Encoding($false)
$temporary = Join-Path $parent ('.m3-manifest-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllText($temporary, $json, $utf8)
    if ((Get-Item -LiteralPath $temporary).Length -gt 16384) {
        throw 'generated package manifest exceeds the Broker size limit'
    }
    Move-Item -LiteralPath $temporary -Destination $output -Force:$Force
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

Write-Output $output
