param(
  [Parameter(Mandatory=$true)][string]$BundleDirectory,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')][string]$Version,
  [Parameter(Mandatory=$true)][ValidateSet('windows-x64','windows-arm64')][string]$Target,
  [Parameter(Mandatory=$true)][uri]$PackageUrl,
  [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
  [ValidateRange(1,30)][int]$ValidDays = 7
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PackageUrl.Scheme -ne 'https' -or $PackageUrl.UserInfo) { throw 'A direct HTTPS artifact URL is required' }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path.TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.Equals($bundle,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($bundle+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the application bundle' }
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
if (!$certificate.HasPrivateKey -or $certificate.NotAfter -lt [DateTime]::Now.AddDays($ValidDays)) { throw 'A valid local signing certificate and private key are required' }
[IO.Directory]::CreateDirectory($output) | Out-Null
$archivePath = Join-Path $output ('FreedomCloud-' + $Version + '-' + $Target + '.zip')
$manifestPath = Join-Path $output ('FreedomCloud-' + $Version + '-' + $Target + '.p7m')
if ((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $manifestPath)) { throw 'Refusing to overwrite an existing release' }
$inventory = @()
$files = @(Get-ChildItem -LiteralPath $bundle -Recurse -Force -File | Sort-Object FullName)
foreach ($file in $files) {
  if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links cannot be published' }
  $relative = $file.FullName.Substring($bundle.Length+1).Replace('\','/')
  if ($relative -ieq 'release.p7m') { throw 'Remove old release envelope before publishing' }
  $inventory += @{path=$relative;size=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
foreach ($required in @('FlClashX.exe','FlClashCore.exe','FlClashAgent.exe','FlClashHelperService.exe')) {
  if ($required -notin $inventory.path) { throw 'The input must be the complete portable bundle' }
}
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $bundle 'FlClashX.exe')
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw 'Sign the complete application entrypoint with this certificate before creating the immutable release inventory' }
$stream = [IO.File]::Open($archivePath,'CreateNew','ReadWrite','None')
$zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
try {
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($bundle.Length+1).Replace('\','/')
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally { $zip.Dispose(); $stream.Dispose() }
$manifest = @{schema=1;version=$Version;target=$Target;format='portable-zip';entry='FlClashX.exe';url=$PackageUrl.AbsoluteUri;
  expiresUtc=[DateTime]::UtcNow.AddDays($ValidDays).ToString('o');size=(Get-Item -LiteralPath $archivePath).Length;
  sha256=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant();files=$inventory}
$content = New-Object Security.Cryptography.Pkcs.ContentInfo(,[Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 8 -Compress)))
$cms = New-Object Security.Cryptography.Pkcs.SignedCms($content,$false)
$signer = New-Object Security.Cryptography.Pkcs.CmsSigner($certificate)
$signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
$cms.ComputeSignature($signer)
[IO.File]::WriteAllBytes($manifestPath,$cms.Encode())
$sha = [Security.Cryptography.SHA256]::Create()
try { $pin = [BitConverter]::ToString($sha.ComputeHash($certificate.RawData)).Replace('-','') } finally { $sha.Dispose() }
Write-Output ('FCX_RELEASE_CERT_SHA256=' + $pin)
Write-Output ('Publish ZIP to: ' + $PackageUrl.AbsoluteUri)
Write-Output ('Publish CMS manifest and build client with FCX_RELEASE_MANIFEST_URL pointing to its direct HTTPS URL: ' + $manifestPath)
