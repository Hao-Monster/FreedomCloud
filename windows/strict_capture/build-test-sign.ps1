[CmdletBinding()]
param(
  [switch]$CreateTestCertificate,
  [string]$CertificatePath = (Join-Path $env:TEMP 'FlClashXStrictCapture-Test.cer')
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'strict_capture.vcxproj'
$msbuild = @(
  (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\MSBuild.exe'),
  (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild with WDK support was not found.' }

& $msbuild $project '/p:Configuration=Release' '/p:Platform=x64' '/m'
$msbuildExit = $LASTEXITCODE
$sys = Join-Path $PSScriptRoot 'x64\Release\strict_capture.sys'
if ($msbuildExit -ne 0 -or -not (Test-Path $sys)) {
  # VS 18 currently does not ship the WindowsKernelModeDriver10.0 platform
  # toolset. The WDK headers/libs are still sufficient for a deterministic
  # compile/link fallback, so keep the dev build usable without installing a
  # second Visual Studio instance.
  $vsRoot = Split-Path (Split-Path (Split-Path (Split-Path $msbuild -Parent) -Parent) -Parent) -Parent
  $vcvars = Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'
  $wdk = 'C:\Program Files (x86)\Windows Kits\10'
  $include = Join-Path $wdk 'Include\10.0.26100.0'
  $lib = Join-Path $wdk 'Lib\10.0.26100.0\km\x64'
  $objDir = Join-Path $PSScriptRoot 'obj'
  New-Item -ItemType Directory -Force -Path $objDir, (Split-Path $sys -Parent) | Out-Null
  $cmd = "call `"$vcvars`" -arch=x64 -host_arch=x64 && cl /nologo /c /kernel /W3 /D_AMD64_ /DAMD64 /I`"$include\km`" /I`"$include\shared`" `"$PSScriptRoot\strict_capture.c`" /Fo:`"$objDir\strict_capture.obj`" && link /nologo /driver /subsystem:native /entry:DriverEntry /nodefaultlib /libpath:`"$lib`" /out:`"$sys`" `"$objDir\strict_capture.obj`" ntoskrnl.lib fwpkclnt.lib bufferoverflowfastfailk.lib"
  cmd.exe /d /s /c $cmd
  if ($LASTEXITCODE -ne 0) { throw "MSBuild and direct WDK compile both failed (MSBuild exit $msbuildExit; direct exit $LASTEXITCODE)." }
}
if (-not (Test-Path $sys)) { throw "Driver output was not produced: $sys" }
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter signtool.exe |
  Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } | Select-Object -First 1
if (-not $signtool) { throw 'signtool.exe was not found.' }

if ($CreateTestCertificate) {
  Write-Warning 'Creating a local test certificate only; this is not a production publisher identity.'
  $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=FlClashX Strict Capture Test' -CertStoreLocation Cert:\CurrentUser\My
  Export-Certificate -Cert $cert -FilePath $CertificatePath | Out-Null
  & $signtool.FullName sign /fd SHA256 /a $sys
} else {
  Write-Host "Built unsigned driver: $sys"
  Write-Host 'Pass -CreateTestCertificate only on an isolated test machine to sign a development artifact.'
}
