import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/common/zashboard_archive.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

// Public zashboard instance — kept only as a defensive fallback. With external-ui
// always pointed at a local dir (see patchRawConfig), the local panel is used.
const publicZashboardBase = 'https://board.zash.run.place';

// zashboard compiled bundle; supports build-time mirror/custom URL overrides
// plus local bundled dist.zip lookup before falling back to upstream GitHub.
const zashboardDistUrl = String.fromEnvironment(
  'FCX_ZASHBOARD_DIST_URL',
  defaultValue:
      'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip',
);
const zashboardMirrorDistUrl = String.fromEnvironment('FCX_ZASHBOARD_MIRROR_URL');

const zashboardChinaFallbackMessage =
    '本地 zashboard 面板资源下载失败（国内网络可能无法直连 GitHub）。请先开启代理后重试，或点击使用在线版面板。';

enum ZashboardInstallSource {
  alreadyInstalled,
  bundled,
  mirror,
  upstream,
  failed,
}

class ZashboardInstallResult {
  const ZashboardInstallResult({
    required this.ok,
    required this.source,
    this.messageZh = '',
    this.usedUrl,
    this.errorCode,
  });

  final bool ok;
  final ZashboardInstallSource source;
  final String messageZh;
  final String? usedUrl;
  final String? errorCode;
}

List<String> resolveZashboardDistUrls({List<String>? mirrorUrls}) {
  final candidates = <String>[];
  void addIfValid(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    if (!candidates.contains(trimmed)) {
      candidates.add(trimmed);
    }
  }

  if (mirrorUrls != null) {
    for (final url in mirrorUrls) {
      addIfValid(url);
    }
  }
  addIfValid(zashboardMirrorDistUrl);
  addIfValid(zashboardDistUrl);
  return List<String>.unmodifiable(candidates);
}

Future<List<int>?> _loadBundledZashboardArchive(
  List<String> extraBundledDirs,
) async {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final searchDirs = <String>[
    ...extraBundledDirs,
    p.join(exeDir, 'zashboard'),
    p.join(exeDir, 'data', 'zashboard'),
    p.join(exeDir, 'data', 'flutter_assets', 'assets', 'zashboard'),
  ];
  for (final dir in searchDirs) {
    final candidate = p.join(dir, 'dist.zip');
    try {
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.file) {
        final bytes = await File(candidate).readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      // Ignore unreadable local bundle probes and try next source.
    }
  }
  try {
    final data = await rootBundle.load('assets/zashboard/dist.zip');
    if (data.lengthInBytes > 0) {
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
  } catch (_) {
    // Asset is optional in standard builds.
  }
  return null;
}

/// Whether the local zashboard bundle is already extracted into external-ui.
Future<bool> isZashboardUiReady() async {
  final dir = globalState.effectiveExternalUi.value.trim();
  if (dir.isEmpty) return false;
  return File(p.join(dir, 'index.html')).exists();
}

/// Downloads + extracts the zashboard bundle into the external-ui dir if it isn't
/// there yet. The core serves that dir at /ui/ live, so files appear immediately.
/// Returns true when index.html is present afterwards.
final _dashboardInstalls = <String, Future<bool>>{};
final _dashboardInstallResults = <String, Future<ZashboardInstallResult>>{};

Future<bool> ensureZashboardUi({
  String? directory,
  Dio? client,
  CancelToken? cancelToken,
  ZashboardLimits limits = const ZashboardLimits(),
  List<String>? mirrorUrls,
  Future<List<int>?> Function()? bundledArchiveLoader,
  List<String> extraBundledDirs = const [],
}) {
  final dir = (directory ?? globalState.effectiveExternalUi.value).trim();
  if (dir.isEmpty) return Future.value(false);
  final target = p.normalize(p.absolute(dir));
  final key = Platform.isWindows ? target.toLowerCase() : target;
  return _dashboardInstalls.putIfAbsent(
    key,
    () => ensureZashboardUiWithResult(
      directory: directory,
      client: client,
      cancelToken: cancelToken,
      limits: limits,
      mirrorUrls: mirrorUrls,
      bundledArchiveLoader: bundledArchiveLoader,
      extraBundledDirs: extraBundledDirs,
    ).then((result) => result.ok).whenComplete(() {
      _dashboardInstalls.remove(key);
    }),
  );
}

Future<ZashboardInstallResult> ensureZashboardUiWithResult({
  String? directory,
  Dio? client,
  CancelToken? cancelToken,
  ZashboardLimits limits = const ZashboardLimits(),
  List<String>? mirrorUrls,
  Future<List<int>?> Function()? bundledArchiveLoader,
  List<String> extraBundledDirs = const [],
}) {
  final dir = (directory ?? globalState.effectiveExternalUi.value).trim();
  if (dir.isEmpty) {
    return Future.value(
      const ZashboardInstallResult(
        ok: false,
        source: ZashboardInstallSource.failed,
        messageZh: zashboardChinaFallbackMessage,
        errorCode: 'emptyDirectory',
      ),
    );
  }
  final target = p.normalize(p.absolute(dir));
  final key = Platform.isWindows ? target.toLowerCase() : target;
  return _dashboardInstallResults.putIfAbsent(
      key,
      () => _installDashboard(
            target,
            client,
            cancelToken,
            limits,
            mirrorUrls: mirrorUrls,
            bundledArchiveLoader: bundledArchiveLoader,
            extraBundledDirs: extraBundledDirs,
          ).whenComplete(() {
            _dashboardInstallResults.remove(key);
          }));
}

Future<ZashboardInstallResult> _installDashboard(
  String dir,
  Dio? suppliedClient,
  CancelToken? cancelToken,
  ZashboardLimits limits, {
  List<String>? mirrorUrls,
  Future<List<int>?> Function()? bundledArchiveLoader,
  List<String> extraBundledDirs = const [],
}) async {
  if (dir.isEmpty) {
    return const ZashboardInstallResult(
      ok: false,
      source: ZashboardInstallSource.failed,
      messageZh: zashboardChinaFallbackMessage,
      errorCode: 'emptyDirectory',
    );
  }
  final index = File(p.join(dir, 'index.html'));
  final client = suppliedClient ?? Dio();
  final token = CancelToken();
  final clock = Stopwatch()..start();
  final deadline =
      Timer(limits.timeout, () => token.cancel('Dashboard timeout'));
  StreamSubscription<void>? cancellation;
  Directory? staging;
  void checkCancelled() {
    if (cancelToken?.isCancelled == true || token.isCancelled) {
      throw const HttpException('Dashboard installation cancelled');
    }
    if (clock.elapsed >= limits.timeout) {
      token.cancel('Dashboard timeout');
      throw TimeoutException('Dashboard installation timed out');
    }
  }

  Future<bool> stageAndCommitArchive(Uint8List archiveBytes) async {
    final target = Directory(dir);
    await target.parent.create(recursive: true);
    staging = await target.parent.createTemp('.flclashx-dashboard-');
    await extractZashboardArchive(
      archiveBytes,
      staging!,
      limits: limits,
      checkCancelled: checkCancelled,
    );
    checkCancelled();
    if (await index.exists()) return true;
    if (await target.exists()) {
      await target.delete();
    }
    await staging!.rename(dir);
    staging = null;
    return await index.exists();
  }

  try {
    checkCancelled();
    if (await index.exists()) {
      return const ZashboardInstallResult(
        ok: true,
        source: ZashboardInstallSource.alreadyInstalled,
      );
    }
    cancellation = cancelToken?.whenCancel.asStream().listen((_) {
      if (!token.isCancelled) token.cancel('Dashboard cancelled');
    });
    // Never extract through a pre-existing symlink or erase arbitrary files
    // from a user-supplied external-ui directory.
    var ancestor = dir;
    while (true) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('Dashboard directory contains a link');
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
    final target = Directory(dir);
    if (await target.exists() && !await target.list().isEmpty) {
      throw const FileSystemException(
          'Incomplete dashboard directory is not empty');
    }

    // Prefer locally bundled archive (zero network dependency in Mainland China).
    final bundledBytes = bundledArchiveLoader != null
        ? await bundledArchiveLoader()
        : await _loadBundledZashboardArchive(extraBundledDirs);
    if (bundledBytes != null && bundledBytes.isNotEmpty) {
      checkCancelled();
      final ok = await stageAndCommitArchive(Uint8List.fromList(bundledBytes));
      if (ok) {
        return const ZashboardInstallResult(
          ok: true,
          source: ZashboardInstallSource.bundled,
        );
      }
    }

    final urls = resolveZashboardDistUrls(mirrorUrls: mirrorUrls);
    if (urls.isEmpty) {
      return const ZashboardInstallResult(
        ok: false,
        source: ZashboardInstallSource.failed,
        messageZh: zashboardChinaFallbackMessage,
        errorCode: 'noUrlsConfigured',
      );
    }

    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      checkCancelled();
      final remaining = limits.timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Dashboard installation timed out');
      }
      try {
        final resp = await client
            .get<ResponseBody>(
          url,
          cancelToken: token,
          options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: remaining,
              sendTimeout: remaining),
        )
            .timeout(remaining, onTimeout: () {
          token.cancel('Dashboard timeout');
          throw TimeoutException('Dashboard download timed out');
        });
        final body = resp.data;
        if (body == null) {
          lastError = const HttpException('Empty response body');
          continue;
        }
        final declared = int.tryParse(
            resp.headers.value(Headers.contentLengthHeader) ?? '');
        if (declared != null && declared > limits.downloadBytes) {
          token.cancel('Dashboard download exceeds limit');
          throw const FormatException('Dashboard download exceeds limit');
        }
        final buffer = BytesBuilder(copy: false);
        await for (final chunk
            in body.stream.timeout(limits.timeout - clock.elapsed)) {
          checkCancelled();
          if (chunk.length > limits.downloadBytes - buffer.length) {
            token.cancel('Dashboard download exceeds limit');
            throw const FormatException('Dashboard download exceeds limit');
          }
          buffer.add(chunk);
        }
        checkCancelled();
        final ok = await stageAndCommitArchive(buffer.takeBytes());
        if (ok) {
          return ZashboardInstallResult(
            ok: true,
            source: url == zashboardDistUrl
                ? ZashboardInstallSource.upstream
                : ZashboardInstallSource.mirror,
            usedUrl: url,
          );
        }
        return const ZashboardInstallResult(
          ok: false,
          source: ZashboardInstallSource.failed,
          messageZh: zashboardChinaFallbackMessage,
          errorCode: 'missingIndex',
        );
      } catch (e) {
        lastError = e;
        if (cancelToken?.isCancelled == true || token.isCancelled) {
          rethrow;
        }
        if (e is FormatException || e is FileSystemException) {
          rethrow;
        }
        commonPrint.log('zashboard ui download failed ($url): $e');
        if (staging != null) {
          try {
            if (await staging!.exists()) await staging!.delete(recursive: true);
          } catch (_) {}
          staging = null;
        }
      }
    }
    commonPrint.log('zashboard ui download exhausted all sources: $lastError');
    return ZashboardInstallResult(
      ok: false,
      source: ZashboardInstallSource.failed,
      messageZh: zashboardChinaFallbackMessage,
      errorCode: lastError is TimeoutException ? 'timeout' : 'networkFailed',
    );
  } catch (e) {
    commonPrint.log('zashboard ui download failed: $e');
    return ZashboardInstallResult(
      ok: false,
      source: ZashboardInstallSource.failed,
      messageZh: cancelToken?.isCancelled == true
          ? '已取消下载本地 zashboard 面板。'
          : zashboardChinaFallbackMessage,
      errorCode: e is TimeoutException ? 'timeout' : 'installFailed',
    );
  } finally {
    deadline.cancel();
    await cancellation?.cancel();
    if (!token.isCancelled) token.cancel('Dashboard operation finished');
    if (suppliedClient == null) client.close(force: true);
    if (staging != null) {
      try {
        if (await staging!.exists()) await staging!.delete(recursive: true);
      } on FileSystemException catch (e) {
        commonPrint.log('zashboard staging cleanup failed: $e');
      }
    }
  }
}

/// Builds the zashboard URL pointed at this client's external-controller:
/// .../#/setup?hostname=host&port=port&secret=secret&http=1 — host/port and
/// secret are taken from the active profile's external-controller config.
/// Returns null when external-controller is not set.
String? buildZashboardUrl({bool preferPublicFallback = false}) {
  final ec = globalState.effectiveExternalController.value.trim();
  if (ec.isEmpty) return null;
  final idx = ec.lastIndexOf(':');
  var host = idx > 0 ? ec.substring(0, idx).trim() : '';
  final port = idx >= 0 ? ec.substring(idx + 1).trim() : ec.trim();
  // 0.0.0.0/empty bind addresses aren't browser-reachable; assume same device.
  if (host.isEmpty || host == '0.0.0.0' || host == '::') {
    host = '127.0.0.1';
  }
  final secret = globalState.effectiveSecret.value.trim();
  // `http=1` forces zashboard's backend protocol to plain HTTP. Without it,
  // getBackendFromUrl falls back to the page's own protocol — and the public
  // instance is served over HTTPS, so it would probe https://host:port and the
  // auto-verify fails ("Backend configuration failed") even though the core
  // only speaks HTTP. The value must be non-empty (JS treats "" as falsy).
  final query =
      'hostname=$host&port=$port&secret=${Uri.encodeQueryComponent(secret)}&http=1';
  // Local panel: when the profile sets external-ui, the core downloads the
  // dashboard (external-ui-url) and serves it at the FIXED `/ui/` path on the
  // same host:port as the controller (mihomo hardcodes /ui/ — the external-ui
  // value is just the on-disk dir, not a URL segment). Same origin as the
  // backend, plain http, so it also loads inside WKWebView. When external-ui is
  // unset, fall back to the public instance.
  final hasLocalUi =
      !preferPublicFallback && globalState.effectiveExternalUi.value.trim().isNotEmpty;
  if (!hasLocalUi) {
    return '$publicZashboardBase/#/setup?$query';
  }
  return 'http://$host:$port/ui/#/setup?$query';
}
