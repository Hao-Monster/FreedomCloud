[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$PackageDirectory,
  [Parameter(Mandatory)] [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PackageDirectory -PathType Container)) {
  throw "Driver package directory does not exist: $PackageDirectory"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Write-Host 'HLK is an external, interactive workflow and is not executed automatically.'
Write-Host '1. On the HLK controller, create a project for the target Windows 11 build.'
Write-Host '2. Add the clean client and import the package from:' $PackageDirectory
Write-Host '3. Run the official playlist, review every failure, and export the .hlkx file.'
Write-Host '4. Copy the .hlkx and controller logs to:' $OutputDirectory
Write-Host '5. Submit the package through Partner Center using the publisher certificate.'

Copy-Item -LiteralPath (Join-Path $PackageDirectory 'strict_capture.inf') -Destination $OutputDirectory -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $PackageDirectory 'strict_capture.sys') -Destination $OutputDirectory -Force -ErrorAction SilentlyContinue
