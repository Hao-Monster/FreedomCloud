/// The worker runs without elevation. Portable bundles are switched locally;
/// installed distributions delegate changes to a verified elevated installer.
const windowsSignedUpdater = r'''
param([Parameter(Mandatory=$true)][string]$JobPath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression.FileSystem
$job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json
$root = [IO.Path]::GetFullPath($job.root)
function Hash([string]$file) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
function AtomicJson([string]$path, $value) {
  $temp = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  [IO.File]::WriteAllText($temp, ($value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
  if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, $null) }
  else { [IO.File]::Move($temp, $path) }
}
function Manifest([string]$file) {
  $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
  $cms.Decode([IO.File]::ReadAllBytes($file))
  if ($cms.SignerInfos.Count -ne 1) { throw 'Expected exactly one release signer' }
  $signer = $cms.SignerInfos[0]
  if ($signer.DigestAlgorithm.Value -notin @('2.16.840.1.101.3.4.2.1','2.16.840.1.101.3.4.2.2','2.16.840.1.101.3.4.2.3')) { throw 'Weak release digest rejected' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $pin = [BitConverter]::ToString($sha.ComputeHash($signer.Certificate.RawData)).Replace('-','') } finally { $sha.Dispose() }
  if ($pin -cne $job.pin) { throw 'Release signer does not match compiled publisher identity' }
  $cms.CheckSignature($true)
  $m = [Text.Encoding]::UTF8.GetString($cms.ContentInfo.Content) | ConvertFrom-Json
  if ($m.schema -ne 1 -or $m.format -notin @('portable-zip','inno-exe') -or $m.entry -cne 'FlClashX.exe') { throw 'Unsupported release manifest' }
  if ($m.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid package identity' }
  return $m
}
function RelativePath([string]$name) {
  if (!$name -or $name.Contains('\') -or $name.Contains(':') -or $name.StartsWith('/') -or $name.EndsWith('/')) { throw 'Invalid release path' }
  foreach ($part in $name.Split('/')) {
    if (!$part -or $part -in @('.','..') -or $part.TrimEnd(' ','.') -cne $part -or $part -match '[<>"|?*\x00-\x1f]' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Unsafe release path' }
  }
  if ($name -ieq 'release.p7m') { throw 'Reserved release path' }
  return $name
}
function NoLinks([string]$path) {
  $item = Get-Item -LiteralPath $path
  while ($null -ne $item) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point update paths are not supported' }
    if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
  }
}
function Preflight {
  NoLinks $root
}
function PortablePreflight {
  Preflight
  foreach ($name in @('FlClashHelperService','FlClashStrictBroker','FlClashStrictCallout')) {
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) { throw 'Installed privileged services detected. Use a signed complete installer; portable update cannot replace the service trust chain.' }
  }
}
function VerifyRelease([string]$directory) {
  NoLinks $directory
  $m = Manifest (Join-Path $directory 'release.p7m')
  foreach ($record in $m.files) {
    $relative = RelativePath $record.path
    $file = Join-Path $directory $relative
    NoLinks $file
    if (!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -ne $record.size -or (Hash $file) -ine $record.sha256) { throw 'Staged file no longer matches signed manifest' }
  }
  $actual = @(Get-ChildItem -LiteralPath $directory -Recurse -File -Force)
  if ($actual.Count -ne @($m.files).Count + 1) { throw 'Unexpected file in staged release' }
  $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $directory $m.entry)
  if ($signature.Status -ne 'Valid') { throw 'Application Authenticode signature is not trusted on this computer' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $pin = [BitConverter]::ToString($sha.ComputeHash($signature.SignerCertificate.RawData)).Replace('-','') } finally { $sha.Dispose() }
  if ($pin -cne $job.pin) { throw 'Application signer differs from release publisher' }
  return (Join-Path $directory $m.entry)
}
function VerifyPointer($pointer) {
  if ($pointer.kind -eq 'release') {
    $path = [IO.Path]::GetFullPath($pointer.directory)
    if (!$path.StartsWith((Join-Path $root 'versions') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Release pointer outside versions directory' }
    return VerifyRelease $path
  }
  if ($pointer.kind -ne 'baseline') { throw 'Unknown version pointer' }
  if (@(Get-ChildItem -LiteralPath $pointer.directory -Recurse -File -Force).Count -ne @($pointer.files).Count) { throw 'Previous installation file inventory changed' }
  foreach ($record in $pointer.files) {
    $path = Join-Path $pointer.directory (RelativePath $record.path)
    NoLinks $path
    if ((Hash $path) -ine $record.sha256) { throw 'Previous installation changed; automatic rollback refused' }
  }
  return Join-Path $pointer.directory 'FlClashX.exe'
}
function VerifyInstaller([string]$path, $record) {
  NoLinks $path
  if ($record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $record.size -le 0 -or $record.size -gt 2147483648 -or
      (Get-Item -LiteralPath $path).Length -ne $record.size -or (Hash $path) -ine $record.sha256) { throw 'Installer integrity mismatch' }
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  if ($signature.Status -ne 'Valid') { throw 'Installer Authenticode signature is not trusted' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $pin = [BitConverter]::ToString($sha.ComputeHash($signature.SignerCertificate.RawData)).Replace('-','') } finally { $sha.Dispose() }
  if ($pin -cne $job.pin) { throw 'Installer publisher differs from the compiled release identity' }
}
function InstallerPointer($pointer) {
  $directory = [IO.Path]::GetFullPath($pointer.directory)
  if (!$directory.StartsWith((Join-Path $root 'installers')+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Installer pointer outside cache' }
  NoLinks $directory
  $m = Manifest (Join-Path $directory 'release.p7m')
  if ($m.format -ne 'inno-exe' -or $m.installerProtocol -ne 'fcx-update-v1' -or $pointer.role -notin @('new','rollback')) { throw 'Invalid installer pointer' }
  if ($pointer.role -eq 'new') { $path = Join-Path $directory 'setup.exe'; $record = $m }
  else { $path = Join-Path $directory 'rollback.exe'; $record = $m.rollback }
  VerifyInstaller $path $record
  return @{path=$path;record=$record}
}
function VerifyInstalledApplication($pointer, [string]$path) {
  $resolved = InstallerPointer $pointer
  if ($resolved.record.appSha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Hash $path) -ine $resolved.record.appSha256) { throw 'Installed application does not match signed release identity' }
}
function RunInstaller($pointer, [string]$installDirectory) {
  $resolved = InstallerPointer $pointer
  # Hold a non-writable, non-deletable handle throughout signature verification
  # and elevated execution. Only the signed installer receives elevation.
  $hold = [IO.File]::Open($resolved.path,'Open','Read','Read')
  try {
    VerifyInstaller $resolved.path $resolved.record
    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /FCXUPDATE /DIR="' + $installDirectory + '"'
    $process = Start-Process -FilePath $resolved.path -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
    # Do not kill an installer while it changes services or files. A slow or
    # interactive installer remains visible to the user via UAC/Windows UI.
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw ('Inno installer failed with exit code ' + $process.ExitCode) }
  } finally { $hold.Dispose() }
}
function RunInstallerUpdate {
  Preflight
  $lock = [IO.File]::Open((Join-Path $root 'transaction.lock'),'OpenOrCreate','ReadWrite','None')
  try {
    $currentPath = Join-Path $root 'installed-current.json'
    $previousPath = Join-Path $root 'installed-previous.json'
    if ($job.action -eq 'rollbackInstaller') {
      $next = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
      $old = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
    } else {
      $m = Manifest $job.manifest
      $directory = Join-Path (Join-Path $root 'installers') (Hash $job.manifest).ToLowerInvariant()
      $next = @{directory=$directory;role='new'}
      $old = @{directory=$directory;role='rollback'}
    }
    InstallerPointer $next | Out-Null
    InstallerPointer $old | Out-Null
    VerifyInstalledApplication $old $job.currentExe
    $installDirectory = [IO.Path]::GetDirectoryName($job.currentExe)
    NoLinks $installDirectory
    $parent = Get-Process -Id $job.parentPid -ErrorAction SilentlyContinue
    if ($parent -and !$parent.WaitForExit(60000)) { throw 'Application did not stop; installer not launched' }
    AtomicJson (Join-Path $root 'last-result.json') @{state='installing';time=[DateTime]::UtcNow.ToString('o')}
    try {
      RunInstaller $next $installDirectory
      VerifyInstalledApplication $next $job.currentExe
    } catch {
      $installError = $_.Exception.Message
      try {
        RunInstaller $old $installDirectory
        VerifyInstalledApplication $old $job.currentExe
        AtomicJson $currentPath $old
        Start-Process -FilePath $job.currentExe -WorkingDirectory $installDirectory | Out-Null
      } catch {
        throw ('Update failed: ' + $installError + '; previous-version reinstall also failed: ' + $_.Exception.Message + '. Signed installers remain in the update cache for manual recovery. No success is claimed.')
      }
      throw ('Update failed: ' + $installError + '; previous-version installer completed and previous application was relaunched. User data was not restored or overwritten by the updater.')
    }
    AtomicJson $previousPath $old
    AtomicJson $currentPath $next
    Start-Process -FilePath $job.currentExe -WorkingDirectory $installDirectory | Out-Null
    AtomicJson (Join-Path $root 'last-result.json') @{state='installer-completed-awaiting-user-acceptance';time=[DateTime]::UtcNow.ToString('o')}
  } finally { $lock.Dispose() }
}

try {
  if ($job.action -eq 'preflight') { Preflight; exit 0 }
  if ($job.action -eq 'manifest') { Manifest $job.manifest | ConvertTo-Json -Depth 12 -Compress; exit 0 }
  if ($job.action -eq 'checkRollback') { PortablePreflight; VerifyPointer (Get-Content -LiteralPath (Join-Path $root 'previous.json') -Raw | ConvertFrom-Json) | Out-Null; exit 0 }
  if ($job.action -eq 'checkInstallerRollback') {
    Preflight
    InstallerPointer (Get-Content -LiteralPath (Join-Path $root 'installed-previous.json') -Raw | ConvertFrom-Json) | Out-Null
    InstallerPointer (Get-Content -LiteralPath (Join-Path $root 'installed-current.json') -Raw | ConvertFrom-Json) | Out-Null
    exit 0
  }
  if ($job.action -eq 'stageInstaller') {
    Preflight
    $m = Manifest $job.manifest
    if ($m.format -ne 'inno-exe' -or $m.installerProtocol -ne 'fcx-update-v1' -or !$m.rollback -or $m.rollback.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') { throw 'Signed matching rollback installer is required' }
    if ($m.appSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $m.rollback.appSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Exact application identities required for update and recovery' }
    VerifyInstaller $job.archive $m
    VerifyInstaller $job.rollbackInstaller $m.rollback
    if ((Hash $job.currentExe) -ine $m.rollback.appSha256) { throw 'Rollback installer does not correspond to the currently running application binary' }
    $cache = Join-Path $root 'installers'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    NoLinks $cache
    $directory = Join-Path $cache (Hash $job.manifest).ToLowerInvariant()
    if (!(Test-Path -LiteralPath $directory)) {
      $stage = Join-Path $cache ('.staging-' + [guid]::NewGuid().ToString('N'))
      [IO.Directory]::CreateDirectory($stage) | Out-Null
      Copy-Item -LiteralPath $job.archive -Destination (Join-Path $stage 'setup.exe')
      Copy-Item -LiteralPath $job.rollbackInstaller -Destination (Join-Path $stage 'rollback.exe')
      Copy-Item -LiteralPath $job.manifest -Destination (Join-Path $stage 'release.p7m')
      VerifyInstaller (Join-Path $stage 'setup.exe') $m
      VerifyInstaller (Join-Path $stage 'rollback.exe') $m.rollback
      [IO.Directory]::Move($stage,$directory)
    }
    InstallerPointer @{directory=$directory;role='new'} | Out-Null
    InstallerPointer @{directory=$directory;role='rollback'} | Out-Null
    exit 0
  }
  if ($job.action -in @('applyInstaller','rollbackInstaller')) { RunInstallerUpdate; exit 0 }
  if ($job.action -eq 'stage') {
    PortablePreflight
    $m = Manifest $job.manifest
    if ((Hash $job.archive) -ine $m.sha256 -or (Get-Item -LiteralPath $job.archive).Length -ne $m.size) { throw 'Archive integrity mismatch' }
    if (@($m.files).Count -lt 4 -or @($m.files).Count -gt 20000) { throw 'Invalid file inventory' }
    $expected = @{}; [long]$total = 0
    foreach ($record in $m.files) {
      $name = RelativePath $record.path
      if ($expected.ContainsKey($name) -or $record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $record.size -lt 0 -or $record.size -gt 1073741824) { throw 'Invalid file inventory entry' }
      $expected[$name] = $record; $total += $record.size
      if ($total -gt 8589934592) { throw 'Expanded package exceeds limit' }
    }
    foreach ($required in @('FlClashX.exe','FlClashCore.exe','FlClashAgent.exe','FlClashHelperService.exe')) {
      if (!$expected.ContainsKey($required)) { throw 'Not a complete application package' }
    }
    $versions = Join-Path $root 'versions'
    [IO.Directory]::CreateDirectory($versions) | Out-Null
    NoLinks $versions
    $destination = Join-Path $versions $m.sha256.ToLowerInvariant()
    if (Test-Path -LiteralPath $destination) { VerifyRelease $destination | Out-Null; exit 0 }
    $stage = Join-Path $versions ('.staging-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($job.archive)
    try {
      $seen = @{}
      foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/') -and $entry.Length -eq 0) { continue }
        $name = RelativePath $entry.FullName
        if (!$expected.ContainsKey($name) -or $seen.ContainsKey($name) -or $entry.Length -ne $expected[$name].size -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'ZIP differs from signed file inventory' }
        $seen[$name] = $true
        $target = Join-Path $stage $name
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        $source = $entry.Open(); $output = [IO.File]::Open($target, 'CreateNew', 'Write', 'None')
        try {
          $buffer = New-Object byte[] 65536; [long]$written = 0
          while (($read = $source.Read($buffer,0,$buffer.Length)) -gt 0) {
            $written += $read
            if ($written -gt $expected[$name].size) { throw 'Expanded file exceeds signed size' }
            $output.Write($buffer,0,$read)
          }
          if ($written -ne $expected[$name].size) { throw 'Truncated archive entry' }
        } finally { $source.Dispose(); $output.Dispose() }
        if ((Hash $target) -ine $expected[$name].sha256) { throw 'Extracted file integrity mismatch' }
      }
      if ($seen.Count -ne $expected.Count) { throw 'Incomplete package' }
    } finally { $zip.Dispose() }
    Copy-Item -LiteralPath $job.manifest -Destination (Join-Path $stage 'release.p7m')
    VerifyRelease $stage | Out-Null
    [IO.Directory]::Move($stage, $destination)
    exit 0
  }
  PortablePreflight
  $lock = [IO.File]::Open((Join-Path $root 'transaction.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
  try {
    $currentPath = Join-Path $root 'current.json'; $previousPath = Join-Path $root 'previous.json'
    if ($job.action -eq 'launch') {
      $pointer = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
      $exe = VerifyPointer $pointer
      Start-Process -FilePath $exe -WorkingDirectory ([IO.Path]::GetDirectoryName($exe)) | Out-Null
      exit 0
    }
    if ($job.action -notin @('apply','rollback')) { throw 'Unsupported updater action' }
    $old = $null
    if (Test-Path -LiteralPath $currentPath) { $old = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json }
    if (!$old) {
      $directory = [IO.Path]::GetDirectoryName($job.currentExe)
      NoLinks $directory
      $files = @(Get-ChildItem -LiteralPath $directory -File -Recurse -Force)
      if ($files.Count -gt 20000) { throw 'Previous installation too large for rollback inventory' }
      $records = @($files | ForEach-Object {
        NoLinks $_.FullName
        @{path=$_.FullName.Substring($directory.Length+1).Replace('\','/');sha256=(Hash $_.FullName)}
      })
      $old = @{kind='baseline';directory=$directory;files=$records}
    }
    if ($job.action -eq 'rollback') { $next = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json }
    else {
      $m = Manifest $job.manifest
      $next = @{kind='release';directory=(Join-Path (Join-Path $root 'versions') $m.sha256.ToLowerInvariant())}
    }
    $exe = VerifyPointer $next
    VerifyPointer $old | Out-Null
    $parent = Get-Process -Id $job.parentPid -ErrorAction SilentlyContinue
    if ($parent -and !$parent.WaitForExit(60000)) { throw 'Application did not shut down; update was not applied' }
    AtomicJson $previousPath $old
    AtomicJson $currentPath $next
    try {
      $child = Start-Process -FilePath $exe -WorkingDirectory ([IO.Path]::GetDirectoryName($exe)) -PassThru
      if ($child.WaitForExit(8000)) { throw 'New application exited during startup' }
      AtomicJson (Join-Path $root 'last-result.json') @{state='launched-awaiting-user-acceptance';time=[DateTime]::UtcNow.ToString('o')}
    } catch {
      AtomicJson $currentPath $old
      $fallback = VerifyPointer $old
      Start-Process -FilePath $fallback -WorkingDirectory ([IO.Path]::GetDirectoryName($fallback)) | Out-Null
      throw
    }
    # Stable shortcut follows the verified current pointer. User data remains
    # in Application Support and is neither migrated nor restored by updater.
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $root 'launch.ps1') -Force
    AtomicJson (Join-Path $root 'launch.json') @{action='launch';root=$root;pin=$job.pin}
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'FreedomCloud Updated.lnk'))
    $shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
    $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $root 'launch.ps1') + '" "' + (Join-Path $root 'launch.json') + '"'
    $shortcut.WorkingDirectory = $root
    $shortcut.Save()
  } finally { $lock.Dispose() }
} catch {
  AtomicJson (Join-Path $root 'last-result.json') @{state='failed';reason=$_.Exception.Message;time=[DateTime]::UtcNow.ToString('o')}
  Write-Error $_
  exit 1
}
''';
