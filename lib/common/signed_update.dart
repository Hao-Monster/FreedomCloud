import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/ed25519_verify.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/common/signed_update_unix.dart';
import 'package:flclashx/common/signed_update_windows.dart';
import 'package:flclashx/services/xboard_bootstrap.dart';
import 'package:path/path.dart' as p;

/// Summary returned when a newer signed update manifest is verified.
class SignedUpdateCheckResult {
  const SignedUpdateCheckResult({
    required this.version,
    this.releaseNotes = '',
    this.publishedAt,
  });

  final String version;
  final String releaseNotes;
  final String? publishedAt;
}

/// Supports both Ed25519-signed `latest.json` manifests (using the embedded
/// `fn-2026-v1` public key) and attached CMS `.p7m` manifests. All downloads
/// enforce strict TLS verification, no HTTP redirects, and `DIRECT`-first
/// routing immune to permissive global `HttpOverrides`.
class SignedUpdate {
  SignedUpdate({
    List<Uri>? manifestFeeds,
    Map<String, Uint8List>? trustedKeys,
    DateTime Function()? now,
  })  : _manifestFeeds = manifestFeeds,
        _trustedKeys = trustedKeys,
        _now = now ?? (() => DateTime.now().toUtc());

  static const feed = String.fromEnvironment('FCX_RELEASE_MANIFEST_URL');
  static const macTeam = String.fromEnvironment('FCX_MACOS_TEAM_ID');
  static const publisher = String.fromEnvironment('FCX_RELEASE_CERT_SHA256');

  static const List<String> defaultManifestFeedUrls = <String>[
    'https://api.westernmoviefans.com/api/v1/client/releases/stable/latest.json',
    'https://fast.hjy.ca:8443/api/v1/client/releases/stable/latest.json',
  ];

  final List<Uri>? _manifestFeeds;
  final Map<String, Uint8List>? _trustedKeys;
  final DateTime Function() _now;

  HttpClient? _client;
  bool _cancelled = false;
  Directory? _session;
  Map<String, dynamic>? _manifest;
  String? _script;
  String? _root;
  bool _ed25519Mode = false;

  Future<void>? _initializing;

  List<Uri> get _effectiveFeeds {
    final injected = _manifestFeeds;
    if (injected != null) {
      return injected;
    }
    if (feed.isNotEmpty) {
      final parsed = Uri.tryParse(feed);
      return parsed == null ? const [] : <Uri>[parsed];
    }
    final dynamicOrigins =
        TransportMirrorPool.shared.orderedOrigins(capability: 'update');
    if (dynamicOrigins.isNotEmpty) {
      return dynamicOrigins
          .map(
            (origin) => origin.replace(
              path: '/api/v1/client/releases/stable/latest.json',
            ),
          )
          .toList(growable: false);
    }
    return defaultManifestFeedUrls.map(Uri.parse).toList(growable: false);
  }

  bool get _usesCmsFeed {
    final injected = _manifestFeeds;
    if (injected != null) {
      return injected.any((u) => u.path.toLowerCase().endsWith('.p7m'));
    }
    return feed.isNotEmpty && !feed.toLowerCase().endsWith('.json');
  }

  String? get unavailable {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return '自动更新仅支持桌面平台';
    }
    final feeds = _effectiveFeeds;
    if (feeds.isEmpty) {
      return '此构建未配置 HTTPS 签名发布清单地址。';
    }
    for (final uri in feeds) {
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        return '此构建未配置有效的 HTTPS 签名发布清单地址。';
      }
    }
    if (_usesCmsFeed) {
      if (Platform.isMacOS && !RegExp(r'^[A-Z0-9]{10}$').hasMatch(macTeam)) {
        return '此构建未配置 FCX_MACOS_TEAM_ID（Developer ID 发布团队）';
      }
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(publisher)) {
        return '此构建未配置发布证书 SHA-256（FCX_RELEASE_CERT_SHA256）。';
      }
    }
    return null;
  }

  Future<void> _initialize() => _initializing ??=
      _initializeStorage().catchError((Object error, StackTrace stack) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _initializeStorage() async {
    if (unavailable != null) throw StateError(unavailable!);
    _root ??= p.join(await appPath.homeDirPath, 'signed-updates');
    await Directory(_root!).create(recursive: true);
    _session ??= await Directory(_root!).createTemp('download-');
    _script ??=
        p.join(_session!.path, Platform.isWindows ? 'update.ps1' : 'update.py');
    await File(_script!).writeAsString(
      Platform.isWindows ? windowsSignedUpdater : unixSignedUpdater,
      flush: true,
    );
  }

  Future<String> _run(
    String action, {
    Map<String, dynamic> extra = const {},
  }) async {
    final job = await _job(action, extra);
    final process = await Process.start(
      Platform.isWindows ? 'powershell.exe' : 'python3',
      Platform.isWindows
          ? [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              _script!,
              job,
            ]
          : [_script!, job],
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        process.kill();
        throw TimeoutException('更新操作超时');
      },
    );
    final text = await output;
    final error = await errors;
    if (code != 0) {
      throw StateError(error.trim().isEmpty ? '更新操作失败 ($code)' : error.trim());
    }
    return text;
  }

  Future<String> _job(String action, Map<String, dynamic> extra) async {
    final path = p.join(_session!.path, '$action.json');
    final format = _manifest?['format']?.toString();
    await File(path).writeAsString(
      jsonEncode({
        'action': action,
        'mode': _ed25519Mode ? 'ed25519' : 'cms',
        'root': _root,
        'pin': publisher.toUpperCase(),
        'macTeam': macTeam,
        'manifest': p.join(_session!.path, 'release.p7m'),
        'archive': p.join(
          _session!.path,
          format == 'inno-exe' ? 'package.exe' : 'package.zip',
        ),
        'rollbackInstaller': p.join(_session!.path, 'rollback.exe'),
        'currentExe': Platform.resolvedExecutable,
        'parentPid': pid,
        if (_ed25519Mode && _manifest != null) ...{
          'targetSha256': _manifest!['sha256'],
          'targetSize': _manifest!['size'],
          'targetEntry': _manifest!['entry'] ??
              (Platform.isWindows ? 'FreedomNet.exe' : 'FreedomNet'),
        },
        ...extra,
      }),
      flush: true,
    );
    return path;
  }

  HttpClient _createStrictDirectClient() {
    // Explicitly defeat permissive FlClashHttpOverrides certificate/proxy
    // injection so update manifests and binaries verify TLS strictly over DIRECT.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..badCertificateCallback = ((_, __, ___) => false)
      ..findProxy = (_) => 'DIRECT';
    return client;
  }

  Future<void> _download(
    Uri url,
    File file,
    int limit,
    void Function(int, int) progress,
  ) async {
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw StateError('发布下载必须使用 HTTPS');
    }
    final client = _createStrictDirectClient();
    _client = client;
    final deadline =
        Timer(const Duration(minutes: 5), () => client.close(force: true));
    final sink = file.openWrite();
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          '下载返回 HTTP ${response.statusCode}（发布端必须提供直接 HTTPS 地址）',
        );
      }
      if (response.contentLength > limit) throw StateError('下载超过允许大小');
      var count = 0;
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw StateError('已取消更新');
        count += bytes.length;
        if (count > limit) throw StateError('下载超过允许大小');
        sink.add(bytes);
        await sink.flush();
        progress(
          count,
          response.contentLength > 0 ? response.contentLength : limit,
        );
      }
      await sink.flush();
    } finally {
      deadline.cancel();
      await sink.close();
      client.close(force: true);
      _client = null;
    }
  }

  Future<Uint8List> _downloadMemory(Uri url, int limit) async {
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw StateError('发布清单必须使用 HTTPS');
    }
    final client = _createStrictDirectClient();
    _client = client;
    final deadline =
        Timer(const Duration(seconds: 30), () => client.close(force: true));
    final builder = BytesBuilder(copy: false);
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          '清单返回 HTTP ${response.statusCode}（发布端必须提供直接 HTTPS 地址）',
        );
      }
      if (response.contentLength > limit) {
        throw StateError('发布清单超过允许大小');
      }
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (_cancelled) throw StateError('已取消更新');
        if (builder.length + chunk.length > limit) {
          throw StateError('发布清单超过允许大小');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      deadline.cancel();
      client.close(force: true);
      _client = null;
    }
  }

  List<String> _platformTargetKeys() {
    final abi = Abi.current();
    final isX64 = [Abi.windowsX64, Abi.macosX64, Abi.linuxX64].contains(abi);
    final isArm64 =
        [Abi.windowsArm64, Abi.macosArm64, Abi.linuxArm64].contains(abi);
    final platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : 'linux';
    if (isX64) return <String>['$platform-x64', '$platform-amd64'];
    if (isArm64) return <String>['$platform-arm64'];
    return const <String>[];
  }

  Map<String, dynamic> _parseAndVerifyEd25519Manifest(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw StateError('Ed25519 更新清单 JSON 无效');
    }
    if (decoded is! Map) {
      throw StateError('Ed25519 更新清单格式无效');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    if (!verifySignedJsonEnvelope(
      envelope,
      trustedKeys: _trustedKeys,
      now: _now(),
    )) {
      throw StateError('更新清单 Ed25519 签名或有效期校验失败');
    }
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    if (payload['schema_version'] != 1) {
      throw StateError('更新清单 schema_version 不兼容');
    }
    final version = payload['version'];
    if (version is! String || version.trim().isEmpty) {
      throw StateError('更新清单缺少版本号');
    }
    final targetsRaw = payload['targets'];
    if (targetsRaw is! Map) {
      throw StateError('更新清单缺少目标平台配置');
    }
    Map<String, dynamic>? selectedTarget;
    String? matchedTargetKey;
    for (final key in _platformTargetKeys()) {
      final candidate = targetsRaw[key];
      if (candidate is Map) {
        selectedTarget = Map<String, dynamic>.from(candidate);
        matchedTargetKey = key;
        break;
      }
    }
    if (selectedTarget == null || matchedTargetKey == null) {
      throw StateError('当前平台暂无兼容的签名更新包');
    }
    final format = selectedTarget['format']?.toString() ?? '';
    final allowedFormats = Platform.isWindows
        ? const ['inno-exe']
        : Platform.isMacOS
            ? const ['macos-app-zip', 'portable-zip']
            : const ['portable-zip'];
    if (!allowedFormats.contains(format)) {
      throw StateError('发布清单格式不兼容: $format');
    }
    final rawUrl = selectedTarget['url'];
    final targetUri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (targetUri == null ||
        targetUri.scheme != 'https' ||
        targetUri.host.isEmpty ||
        targetUri.userInfo.isNotEmpty) {
      throw StateError('更新包下载地址必须使用安全 HTTPS');
    }
    final size = selectedTarget['size'];
    if (size is! int || size <= 0 || size > 2 * 1024 * 1024 * 1024) {
      throw StateError('无效的更新包大小');
    }
    final hash = selectedTarget['sha256'];
    if (hash is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw StateError('清单缺少有效 SHA-256');
    }

    return <String, dynamic>{
      'schema': 1,
      'mode': 'ed25519',
      'target': matchedTargetKey,
      'format': format,
      'version': version,
      'releaseNotes': payload['release_notes'] is String
          ? payload['release_notes'] as String
          : '',
      'publishedAt': payload['published_at'] is String
          ? payload['published_at'] as String
          : null,
      'expiresUtc': payload['expires_at'] as String,
      'url': rawUrl,
      'size': size,
      'sha256': hash.toLowerCase(),
      'entry': selectedTarget['entry'],
    };
  }

  /// Checks configured release manifests (`latest.json` Ed25519 or `.p7m` CMS)
  /// without downloading the full installer binary. Returns `null` when the
  /// running [currentVersion] is already up to date.
  Future<SignedUpdateCheckResult?> checkAvailableUpdate(
    String currentVersion,
  ) async {
    if (unavailable != null) {
      throw StateError(unavailable!);
    }
    _cancelled = false;
    final feeds = _effectiveFeeds;
    Object? lastNetworkError;
    StackTrace? lastNetworkStack;

    for (final feedUri in feeds) {
      if (_cancelled) throw StateError('已取消更新检查');
      if (feedUri.path.toLowerCase().endsWith('.p7m')) {
        await _initialize();
        await _run('preflight');
        await _download(
          feedUri,
          File(p.join(_session!.path, 'release.p7m')),
          2 * 1024 * 1024,
          (_, __) {},
        );
        final manifest =
            Map<String, dynamic>.from(jsonDecode(await _run('manifest')) as Map);
        final expires = DateTime.tryParse(manifest['expiresUtc'] as String? ?? '');
        if (expires == null || !expires.isAfter(_now())) {
          throw StateError('签名清单已过期或未声明有效期');
        }
        final version = manifest['version'];
        if (version is! String || !_newer(version, currentVersion)) {
          return null;
        }
        return SignedUpdateCheckResult(
          version: version,
          releaseNotes: manifest['releaseNotes']?.toString() ?? '',
          publishedAt: manifest['publishedAt']?.toString(),
        );
      }

      try {
        final bytes = await _downloadMemory(feedUri, 2 * 1024 * 1024);
        final verified = _parseAndVerifyEd25519Manifest(bytes);
        final version = verified['version'] as String;
        if (!_newer(version, currentVersion)) {
          return null;
        }
        return SignedUpdateCheckResult(
          version: version,
          releaseNotes: verified['releaseNotes'] as String? ?? '',
          publishedAt: verified['publishedAt'] as String?,
        );
      } on SocketException catch (error, stack) {
        lastNetworkError = error;
        lastNetworkStack = stack;
        continue;
      } on HttpException catch (error, stack) {
        lastNetworkError = error;
        lastNetworkStack = stack;
        continue;
      } on TimeoutException catch (error, stack) {
        lastNetworkError = error;
        lastNetworkStack = stack;
        continue;
      }
    }

    if (lastNetworkError != null && lastNetworkStack != null) {
      Error.throwWithStackTrace(lastNetworkError, lastNetworkStack);
    }
    throw StateError('无法获取有效的签名发布清单');
  }

  Future<String> prepare(
    String currentVersion,
    void Function(String, double?) progress,
  ) async {
    _cancelled = false;
    await _initialize();
    _ed25519Mode = !_usesCmsFeed;
    await _run('preflight');
    progress('获取签名发布清单', null);

    if (_ed25519Mode) {
      Map<String, dynamic>? verified;
      Object? lastError;
      StackTrace? lastStack;
      for (final feedUri in _effectiveFeeds) {
        try {
          final bytes = await _downloadMemory(feedUri, 2 * 1024 * 1024);
          verified = _parseAndVerifyEd25519Manifest(bytes);
          break;
        } on SocketException catch (error, stack) {
          lastError = error;
          lastStack = stack;
        } on HttpException catch (error, stack) {
          lastError = error;
          lastStack = stack;
        } on TimeoutException catch (error, stack) {
          lastError = error;
          lastStack = stack;
        }
      }
      if (verified == null) {
        if (lastError != null && lastStack != null) {
          Error.throwWithStackTrace(lastError, lastStack);
        }
        throw StateError('无法获取签名更新清单');
      }
      _manifest = verified;
      final version = verified['version'] as String;
      if (!_newer(version, currentVersion)) {
        throw StateError('没有比当前版本更新的兼容发布');
      }
      final size = verified['size'] as int;
      final hash = verified['sha256'] as String;
      final format = verified['format'] as String;
      final archive = File(
        p.join(
          _session!.path,
          format == 'inno-exe' ? 'package.exe' : 'package.zip',
        ),
      );
      await _download(
        Uri.parse(verified['url'] as String),
        archive,
        size,
        (received, total) => progress('下载完整应用 $version', received / total),
      );
      if (await archive.length() != size ||
          (await sha256.bind(archive.openRead()).first).toString() !=
              hash.toLowerCase()) {
        if (await archive.exists()) {
          await archive.delete();
        }
        throw StateError('更新包大小或哈希不匹配');
      }
      progress('校验 Ed25519 与 SHA-256 签名并准备更新', null);
      if (Platform.isWindows && format == 'inno-exe') {
        await _run('stageEd25519Installer');
      } else {
        await _run('stageEd25519');
      }
      return version;
    }

    await _download(
      _effectiveFeeds.first,
      File(p.join(_session!.path, 'release.p7m')),
      2 * 1024 * 1024,
      (_, __) {},
    );
    _manifest =
        Map<String, dynamic>.from(jsonDecode(await _run('manifest')) as Map);
    final manifest = _manifest!;
    final targetKeys = _platformTargetKeys();
    final formats = Platform.isWindows
        ? ['portable-zip', 'inno-exe']
        : Platform.isMacOS
            ? ['macos-app-zip']
            : ['portable-zip'];
    if (manifest['schema'] != 1 ||
        !targetKeys.contains(manifest['target']) ||
        !formats.contains(manifest['format'])) {
      throw StateError('发布清单平台或格式不兼容');
    }
    final version = manifest['version'];
    if (version is! String || !_newer(version, currentVersion)) {
      throw StateError('没有比当前版本更新的兼容发布');
    }
    final expires = DateTime.tryParse(manifest['expiresUtc'] as String? ?? '');
    if (expires == null || !expires.isAfter(_now())) {
      throw StateError('签名清单已过期或未声明有效期');
    }
    final size = manifest['size'];
    if (size is! int || size <= 0 || size > 2 * 1024 * 1024 * 1024) {
      throw StateError('无效的完整更新包大小');
    }
    final hash = manifest['sha256'];
    if (hash is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw StateError('清单缺少有效 SHA-256');
    }
    final archive = File(
      p.join(
        _session!.path,
        manifest['format'] == 'inno-exe' ? 'package.exe' : 'package.zip',
      ),
    );
    await _download(
      Uri.parse(manifest['url'] as String),
      archive,
      size,
      (received, total) => progress('下载完整应用 $version', received / total),
    );
    if (await archive.length() != size ||
        (await sha256.bind(archive.openRead()).first).toString() !=
            hash.toLowerCase()) {
      throw StateError('更新包大小或哈希不匹配');
    }
    if (manifest['format'] == 'inno-exe') {
      final rollback = manifest['rollback'];
      if (rollback is! Map ||
          rollback['version'] !=
              currentVersion.replaceFirst(RegExp(r'^v'), '')) {
        throw StateError('完整安装器更新必须提供与你当前版本精确匹配的签名回滚安装包');
      }
      final rollbackSize = rollback['size'];
      final rollbackHash = rollback['sha256'];
      if (rollbackSize is! int ||
          rollbackSize <= 0 ||
          rollbackSize > 2 * 1024 * 1024 * 1024 ||
          rollbackHash is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(rollbackHash)) {
        throw StateError('回滚安装包描述无效');
      }
      final rollbackFile = File(p.join(_session!.path, 'rollback.exe'));
      await _download(
        Uri.parse(rollback['url'] as String),
        rollbackFile,
        rollbackSize,
        (received, total) => progress('预先下载当前版本回滚安装包', received / total),
      );
      if (await rollbackFile.length() != rollbackSize ||
          (await sha256.bind(rollbackFile.openRead()).first).toString() !=
              rollbackHash.toLowerCase()) {
        throw StateError('回滚安装包大小或哈希不匹配');
      }
      progress('验证新旧安装器发布签名，准备可恢复更新', null);
      await _run('stageInstaller');
    } else {
      progress('核对签名、完整文件清单并准备新版本', null);
      await _run('stage');
    }
    return version;
  }

  static bool _newer(String candidate, String current) {
    RegExpMatch parse(String version) {
      final match = RegExp(
        r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
      ).firstMatch(version);
      if (match == null) throw StateError('发布版本号必须符合 SemVer');
      return match;
    }

    final next = parse(candidate), old = parse(current);
    for (var i = 1; i <= 3; i++) {
      final a = int.parse(next.group(i)!), b = int.parse(old.group(i)!);
      if (a != b) return a > b;
    }
    final a = next.group(4), b = old.group(4);
    if (a == b) return false;
    if (a == null) return true;
    if (b == null) return false;
    final left = a.split('.'), right = b.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      if (left[i] == right[i]) continue;
      final x = int.tryParse(left[i]), y = int.tryParse(right[i]);
      if (x != null && y != null) return x > y;
      if (x != null) return false;
      if (y != null) return true;
      return left[i].compareTo(right[i]) > 0;
    }
    return left.length > right.length;
  }

  Future<void> launch({bool rollback = false}) async {
    await _initialize();
    await _run('preflight');
    final installerRollback = rollback &&
        await File(p.join(_root!, 'installed-previous.json')).exists();
    if (rollback) {
      await _run(installerRollback ? 'checkInstallerRollback' : 'checkRollback');
    }
    if (!rollback && _manifest == null) throw StateError('尚未准备更新');
    final String action;
    if (rollback) {
      action = installerRollback ? 'rollbackInstaller' : 'rollback';
    } else if (_ed25519Mode) {
      action = (Platform.isWindows && _manifest!['format'] == 'inno-exe')
          ? 'applyEd25519Installer'
          : 'applyEd25519';
    } else {
      action = _manifest!['format'] == 'inno-exe' ? 'applyInstaller' : 'apply';
    }
    final job = await _job(action, {});
    // The worker waits for handleExit to finish; existing Agent/Core teardown
    // remains owned by the application controller.
    await Process.start(
      Platform.isWindows ? 'powershell.exe' : 'python3',
      Platform.isWindows
          ? [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              _script!,
              job,
            ]
          : [_script!, job],
      mode: ProcessStartMode.detached,
    );
  }

  Future<bool> hasRollback() async {
    await _initialize();
    return await File(p.join(_root!, 'previous.json')).exists() ||
        await File(p.join(_root!, 'installed-previous.json')).exists();
  }

  Future<String?> lastResult() async {
    await _initialize();
    final file = File(p.join(_root!, 'last-result.json'));
    if (!await file.exists()) return null;
    final result = jsonDecode(await file.readAsString()) as Map;
    return result['state'] == 'failed'
        ? '上次更新未完成：${result['reason']}'
        : result['state'] == 'installing'
            ? '上次安装过程尚未记录完成。请查看 Windows 安装器；不要并发启动另一次更新。'
            : '上次更新已启动。';
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}
