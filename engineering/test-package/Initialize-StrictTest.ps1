#requires -Version 7.2
[CmdletBinding()]
param([switch]$ConfirmTestMachine, [switch]$AllowPhysicalTestHost)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StrictTest.Validation.ps1')
if (-not $ConfirmTestMachine) { throw 'Use -ConfirmTestMachine only on a snapshotted VM or dedicated test host.' }
if (-not $IsWindows) { throw 'This test installer requires Windows 11 x64.' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$hostFacts = @{
    IsWindows = $IsWindows
    Is64BitProcess = [Environment]::Is64BitProcess
    Architecture = $env:PROCESSOR_ARCHITECTURE
    IsAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    ProductType = $os.ProductType
    Version = $os.Version
    Manufacturer = $computer.Manufacturer
    Model = $computer.Model
}
Assert-StrictTestHost $hostFacts -ConfirmTestMachine:$ConfirmTestMachine -AllowPhysicalTestHost:$AllowPhysicalTestHost
$boot = & "$env:SystemRoot/System32/bcdedit.exe" /enum '{current}'
$bootExitCode = $LASTEXITCODE
$serviceQueryExitCodes = @{}
foreach ($name in @('FlClashStrictCallout','FlClashStrictBroker')) {
    & "$env:SystemRoot/System32/sc.exe" query $name *> $null
    $serviceQueryExitCodes[$name] = $LASTEXITCODE
}
$destination = Join-Path $env:ProgramFiles 'FlClashX Service'
$recovery = Join-Path $env:ProgramData 'FlClashX.StrictBroker'
$thumbprint = 'F48C72AD4E3D344DCCDC56107DE546CD957FC47D'
$plan = Get-StrictTestInstallationPlan -HostFacts $hostFacts -ConfirmTestMachine:$ConfirmTestMachine `
    -AllowPhysicalTestHost:$AllowPhysicalTestHost -BootQueryExitCode $bootExitCode -BootConfiguration ($boot -join "`n") `
    -ServiceQueryExitCodes $serviceQueryExitCodes -PackageDirectory $PSScriptRoot `
    -Destination $destination -Recovery $recovery -Thumbprint $thumbprint
$sourceHashes = $plan.SourceHashes
$files = @('FlClashStrictCallout.sys','FlClashStrictBroker.exe','FlClashAgent.exe','FlClashCore.exe')
function Invoke-ServiceCommand([string[]]$Arguments) {
    & "$env:SystemRoot/System32/sc.exe" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Service command failed ($LASTEXITCODE): $($Arguments[0]). Stop and inspect service state; restore the test-host snapshot after evidence collection." }
}
# Create both directories with protected ACLs before copying any executable.
foreach ($item in @(@($destination,'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)'),@($recovery,'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'))) {
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetSecurityDescriptorSddlForm($item[1])
    $directory = New-Object IO.DirectoryInfo($item[0])
    [IO.FileSystemAclExtensions]::Create($directory, $security)
    Assert-StrictTestNoReparse $item[0]
}
foreach ($name in ($files + @('strict-package-manifest.json'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destination $name) -ErrorAction Stop
    if ($sourceHashes[$name] -ne (Get-FileHash -LiteralPath (Join-Path $destination $name)).Hash) { throw "Copy verification failed: $name" }
}
foreach ($name in $files) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $destination $name)
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $thumbprint) { throw "Protected copy signature mismatch: $name" }
}
Invoke-ServiceCommand @('create','FlClashStrictCallout','type=','kernel','start=','demand','binPath=',('"'+(Join-Path $destination 'FlClashStrictCallout.sys')+'"'))
Invoke-ServiceCommand @('start','FlClashStrictCallout')
Invoke-ServiceCommand @('create','FlClashStrictBroker','type=','own','start=','auto','obj=','LocalSystem','binPath=',('"'+(Join-Path $destination 'FlClashStrictBroker.exe')+'"'))
Invoke-ServiceCommand @('failure','FlClashStrictBroker','reset=','86400','actions=','restart/60000/restart/120000/""')
Invoke-ServiceCommand @('failureflag','FlClashStrictBroker','1')
Invoke-ServiceCommand @('start','FlClashStrictBroker')
(Get-Service FlClashStrictBroker).WaitForStatus('Running',[TimeSpan]::FromSeconds(20))
Write-Host 'Strict test services are registered and running. This is not traffic acceptance; now launch the portable app and perform your tests.'
