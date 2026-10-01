param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$ApplicationExecutable,
  [Parameter(Mandatory=$true)][string]$RollbackInstaller,
  [Parameter(Mandatory=$true)][string]$RollbackApplicationExecutable,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')][string]$Version,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')][string]$RollbackVersion,
  [Parameter(Mandatory=$true)][ValidateSet('windows-x64','windows-arm64')][string]$Target,
  [Parameter(Mandatory=$true)][uri]$PackageUrl,
  [Parameter(Mandatory=$true)][uri]$RollbackUrl,
  [Parameter(Mandatory=$true)][string]$ManifestOutput,
  [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
  [Parameter(Mandatory=$true)][switch]$UpdaterAwareInstallers,
  [ValidateRange(1,30)][int]$ValidDays = 7
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
if (!$UpdaterAwareInstallers) { throw 'Both installers must implement FCXUPDATE: no forced application termination and data-preserving upgrade/reinstall. Rebuild the previous-version installer with the same protocol before publishing.' }
if ($Version -eq $RollbackVersion) { throw 'Update and rollback versions must differ' }
foreach ($url in @($PackageUrl,$RollbackUrl)) {
  if ($url.Scheme -ne 'https' -or $url.UserInfo) { throw 'Only direct public HTTPS artifact URLs are supported' }
}
if (Test-Path -LiteralPath $ManifestOutput) { throw 'Refusing to overwrite release manifest' }
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
if (!$certificate.HasPrivateKey -or $certificate.NotAfter -lt [DateTime]::Now.AddDays($ValidDays)) { throw 'Valid local code-signing certificate required' }
foreach ($path in @($Installer,$ApplicationExecutable,$RollbackInstaller,$RollbackApplicationExecutable)) {
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw 'Every installer and application must carry the pinned trusted publisher signature' }
}
function Artifact([string]$file,[string]$exe,[string]$version,[uri]$url) {
  return @{version=$version;url=$url.AbsoluteUri;size=(Get-Item -LiteralPath $file).Length;
    sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();
    appSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$manifest = Artifact $Installer $ApplicationExecutable $Version $PackageUrl
$manifest.installerProtocol='fcx-update-v1'
$manifest.schema=1; $manifest.target=$Target; $manifest.format='inno-exe'; $manifest.entry='FlClashX.exe'
$manifest.expiresUtc=[DateTime]::UtcNow.AddDays($ValidDays).ToString('o')
$manifest.rollback=Artifact $RollbackInstaller $RollbackApplicationExecutable $RollbackVersion $RollbackUrl
$content = New-Object Security.Cryptography.Pkcs.ContentInfo(,[Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 8 -Compress)))
$cms = New-Object Security.Cryptography.Pkcs.SignedCms($content,$false)
$signer = New-Object Security.Cryptography.Pkcs.CmsSigner($certificate)
$signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
$cms.ComputeSignature($signer)
[IO.File]::WriteAllBytes([IO.Path]::GetFullPath($ManifestOutput),$cms.Encode())
$sha = [Security.Cryptography.SHA256]::Create()
try { $pin = [BitConverter]::ToString($sha.ComputeHash($certificate.RawData)).Replace('-','') } finally { $sha.Dispose() }
Write-Output ('FCX_RELEASE_CERT_SHA256=' + $pin)
Write-Output 'Publish both original signed installers at their declared URLs and publish the CMS manifest. Client builds must use its direct HTTPS URL as FCX_RELEASE_MANIFEST_URL.'
