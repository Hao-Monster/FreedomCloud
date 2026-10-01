[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Path,
    [Parameter(Mandatory = $true)] [string]$SignTool,
    [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9a-fA-F]{40}$')] [string]$Thumbprint
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$binary = Get-Item -LiteralPath $Path -Force
$tool = Get-Item -LiteralPath $SignTool -Force
if ($binary.PSIsContainer -or $tool.PSIsContainer -or
    ($binary.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    ($tool.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Signing inputs must be plain files'
}
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint"
if (-not $certificate.HasPrivateKey -or $certificate.NotAfter -le (Get-Date)) {
    throw 'Signing certificate must have a private key and be current'
}
& $tool.FullName sign /fd SHA256 /sha1 $Thumbprint /s My $binary.FullName
if ($LASTEXITCODE -ne 0) { throw 'SignTool signing failed' }
# This does not change any machine trust store or boot security configuration.
& $tool.FullName verify /pa $binary.FullName
if ($LASTEXITCODE -ne 0) { throw 'Signed binary is not trusted in the build account' }
