[CmdletBinding()]
param(
  [string]$VisualStudioRoot,
  [string]$WdkVersion = '10.0.28000.0'
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'FlClashStrictCallout.vcxproj'
$roots = @()
if ($VisualStudioRoot) { $roots += $VisualStudioRoot }
$roots += @(
  (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\18\Insiders'),
  (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\BuildTools'),
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools')
)
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$msbuild = $null
foreach ($root in $roots) {
  $candidate = Join-Path $root 'MSBuild\Current\Bin\amd64\MSBuild.exe'
  if (Test-Path $candidate) { $msbuild = $candidate; break }
}
if (-not $msbuild) { throw 'No 64-bit MSBuild.exe was found in the supported Visual Studio roots.' }

$vsRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $msbuild -Parent) -Parent) -Parent) -Parent) -Parent
$vcRoot = Join-Path $vsRoot 'VC'
$vcTool = Get-ChildItem (Join-Path $vcRoot 'Tools\MSVC') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if (-not $vcTool) { throw "MSVC toolset was not found below $vcRoot." }
$cl = Join-Path $vcTool.FullName 'bin\Hostx64\x64\cl.exe'
if (-not (Test-Path $cl)) { throw "x64 compiler was not found: $cl" }
$spectre = Join-Path $vcTool.FullName 'lib\spectre'
if (-not (Test-Path $spectre)) { throw "Spectre libraries were not found: $spectre" }

$kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$include = Join-Path $kitsRoot "Include\$WdkVersion"
$lib = Join-Path $kitsRoot "Lib\$WdkVersion\km\x64"
if (-not (Test-Path (Join-Path $include 'km\ntifs.h'))) { throw "WDK headers were not found: $include" }
if (-not (Test-Path (Join-Path $lib 'ntoskrnl.lib'))) { throw "WDK kernel libraries were not found: $lib" }

$vcTargetCandidates = @('v180', 'v170') | ForEach-Object { Join-Path $vsRoot "MSBuild\Microsoft\VC\$_\Platforms\x64\PlatformToolsets\WindowsKernelModeDriver10.0\Toolset.props" }
$toolset = $vcTargetCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $toolset) { throw 'WindowsKernelModeDriver10.0 x64 toolset props were not found.' }

[pscustomobject]@{
  VisualStudioRoot = $vsRoot
  MSBuild = $msbuild
  MSBuildVersion = (& $msbuild -version -nologo | Select-Object -Last 1).Trim()
  MSVC = $vcTool.Name
  Compiler = $cl
  SpectreLibraries = $spectre
  WDKSDK = $WdkVersion
  WDKHeaders = $include
  WDKLibraries = $lib
  KernelModeDriverToolset = $toolset
  Project = $project
  Ready = $true
} | ConvertTo-Json -Depth 3
