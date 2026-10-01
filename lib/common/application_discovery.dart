import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class ApplicationCandidate {
  const ApplicationCandidate({required this.name, required this.executable, required this.source});
  final String name;
  final String executable;
  final String source;
}

class ApplicationDiscoveryResult {
  const ApplicationDiscoveryResult(this.applications, this.warning);
  final List<ApplicationCandidate> applications;
  final String? warning;
}

/// Discovery is a hint, never signer evidence. No shortcut or desktop Exec
/// command is launched; enrollment independently verifies the selected image.
Future<ApplicationDiscoveryResult> discoverApplications(List<ApplicationCandidate> recent) async {
  final budget = Stopwatch()..start();
  final found = <String, ApplicationCandidate>{};
  Future<void> add(ApplicationCandidate candidate) async {
    if (budget.elapsed > const Duration(seconds: 25) || found.length >= 512 || candidate.executable.length > 2048 ||
        !path.isAbsolute(candidate.executable) || candidate.executable.startsWith(r'\\')) return;
    try {
      final executable = await File(candidate.executable).resolveSymbolicLinks().timeout(const Duration(seconds: 1));
      if (executable.startsWith(r'\\')) return;
      if (await FileSystemEntity.type(executable, followLinks: false) != FileSystemEntityType.file) return;
      if (Platform.isWindows && path.extension(executable).toLowerCase() != '.exe') return;
      final key = Platform.isWindows ? executable.toLowerCase() : executable;
      final existing = found[key];
      if (existing == null || (existing.source != '最近联网' && existing.name.toLowerCase().endsWith('.exe') && !candidate.name.toLowerCase().endsWith('.exe'))) {
        found[key] = ApplicationCandidate(name: candidate.name.isEmpty
          ? path.basenameWithoutExtension(executable) : candidate.name.substring(0, candidate.name.length.clamp(0, 256).toInt()),
          executable: executable, source: candidate.source);
      }
    } on FileSystemException { /* disappeared or inaccessible executable */ }
      on TimeoutException { /* unavailable filesystem candidate */ }
  }
  for (final candidate in recent.take(256)) { await add(candidate); }
  String? warning;
  try {
    if (Platform.isWindows) {
      for (final candidate in await _windowsApplications()) { await add(candidate); }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      for (final root in ['/Applications', '/System/Applications', if (home != null) path.join(home, 'Applications')]) {
        for (final bundle in await _boundedFiles(root, depth: 2, bundles: true)) {
          final binaries = Directory(path.join(bundle, 'Contents', 'MacOS'));
          if (!await binaries.exists()) continue;
          await for (final image in binaries.list(followLinks: false).take(4)) {
            if (image is File) await add(ApplicationCandidate(name: path.basenameWithoutExtension(bundle), executable: image.path, source: '已安装'));
          }
        }
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      final roots = <String>['/usr/share/applications', '/usr/local/share/applications',
        if (home != null) path.join(home, '.local/share/applications')];
      for (final root in roots) {
        for (final desktop in await _boundedFiles(root, depth: 2)) {
          if (!desktop.endsWith('.desktop') || await File(desktop).length() > 65536) continue;
          final fields = <String, String>{};
          var mainSection = false;
          for (final line in await File(desktop).readAsLines()) {
            if (line.startsWith('[')) { mainSection = line == '[Desktop Entry]'; continue; }
            final separator = line.indexOf('=');
            if (mainSection && separator > 0) fields[line.substring(0, separator)] = line.substring(separator + 1);
          }
          if (fields['Type'] != 'Application' || fields['Hidden'] == 'true' || fields['NoDisplay'] == 'true') continue;
          final command = fields['Exec'] ?? '';
          final token = RegExp(r'^\s*(?:"([^"\r\n]+)"|([^\s"\r\n]+))').firstMatch(command);
          final executable = token?.group(1) ?? token?.group(2);
          if (executable == null || executable.contains('%') || executable.contains(r'\')) continue;
          if (const {'env', 'sh', 'bash', 'zsh', 'flatpak', 'snap', 'gtk-launch'}.contains(path.basename(executable))) continue;
          final candidates = path.isAbsolute(executable) ? [executable] :
            (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(':').where(path.isAbsolute).take(32).map((directory) => path.join(directory, executable));
          for (final candidate in candidates) {
            if (await File(candidate).exists()) {
              await add(ApplicationCandidate(name: fields['Name'] ?? executable, executable: candidate, source: '已安装'));
              break;
            }
          }
        }
      }
    }
  } catch (_) {
    warning = '部分已安装应用读取失败；仍可选择最近联网应用或手动选择程序。';
  }
  return ApplicationDiscoveryResult(found.values.toList(growable: false), warning);
}

Future<List<String>> _boundedFiles(String root, {int depth = 1, bool bundles = false}) async {
  final result = <String>[];
  final queue = <(String, int)>[(root, 0)];
  var seen = 0;
  while (queue.isNotEmpty && seen < 2048 && result.length < 256) {
    final item = queue.removeAt(0);
    if (!await Directory(item.$1).exists()) continue;
    await for (final entry in Directory(item.$1).list(followLinks: false)) {
      if (++seen > 2048 || result.length >= 256) break;
      if (bundles && entry is Directory && entry.path.endsWith('.app')) {
        result.add(entry.path);
      } else if (!bundles && entry is File) {
        result.add(entry.path);
      } else if (entry is Directory && item.$2 < depth) {
        queue.add((entry.path, item.$2 + 1));
      }
    }
  }
  return result;
}

Future<List<ApplicationCandidate>> _windowsApplications() async {
  final windows = Platform.environment['SystemRoot'];
  if (windows == null) throw StateError('Windows system directory unavailable');
  final process = await Process.start(path.join(windows, r'System32\WindowsPowerShell\v1.0\powershell.exe'),
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', _windowsDiscoveryScript], runInShell: false);
  Future<String> readBounded(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024 * 1024) { process.kill(); throw StateError('Application discovery output limit'); }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
  final results = await Future.wait<Object>([process.exitCode, readBounded(process.stdout), readBounded(process.stderr)])
    .timeout(const Duration(seconds: 15), onTimeout: () { process.kill(); throw TimeoutException('Application discovery timed out'); });
  if (results[0] != 0) throw StateError('Windows application discovery failed');
  final decoded = jsonDecode(results[1] as String);
  if (decoded is! List) throw const FormatException('Invalid application discovery response');
  return decoded.take(512).whereType<Map>().where((item) => item['name'] is String && item['path'] is String)
    .map((item) => ApplicationCandidate(name: item['name'] as String, executable: item['path'] as String, source: '已安装')).toList(growable: false);
}

const _windowsDiscoveryScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$items = [System.Collections.Generic.List[object]]::new()
foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')) {
  if (Test-Path -LiteralPath $root) {
    foreach ($key in (Get-ChildItem -LiteralPath $root | Select-Object -First 256)) {
      $target = [Environment]::ExpandEnvironmentVariables([string]$key.GetValue('')).Trim('"')
      if ($target -and $items.Count -lt 512) { $items.Add(@{name=$key.PSChildName;path=$target}) }
    }
  }
}
$shell = New-Object -ComObject WScript.Shell
try {
  foreach ($folder in @([Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'))) {
    if (Test-Path -LiteralPath $folder) {
      foreach ($link in (Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -Recurse -Depth 4 | Select-Object -First 256)) {
        if ($items.Count -ge 512) { break }
        $shortcut = $shell.CreateShortcut($link.FullName)
        try {
          $target = [string]$shortcut.TargetPath
          if ($target.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)) { $items.Add(@{name=$link.BaseName;path=$target}) }
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
      }
    }
  }
} finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
ConvertTo-Json -InputObject @($items.ToArray()) -Depth 3 -Compress
''';
