import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/common/zashboard_archive.dart';
import 'package:flclashx/state.dart';
import 'package:path/path.dart' as p;

// Public zashboard instance — kept only as a defensive fallback. With external-ui
// always pointed at a local dir (see patchRawConfig), the local panel is used.
const publicZashboardBase = 'https://board.zash.run.place';

// zashboard compiled bundle; the app downloads this into the external-ui dir on
// demand so the core serves it at /ui/ (same origin/http as the backend).
const zashboardDistUrl =
    'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip';

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

Future<bool> ensureZashboardUi({
  String? directory,
  Dio? client,
  CancelToken? cancelToken,
  ZashboardLimits limits = const ZashboardLimits(),
}) {
  final dir = (directory ?? globalState.effectiveExternalUi.value).trim();
  if (dir.isEmpty) return Future.value(false);
  final target = p.normalize(p.absolute(dir));
  final key = Platform.isWindows ? target.toLowerCase() : target;
  return _dashboardInstalls.putIfAbsent(
      key,
      () => _installDashboard(target, client, cancelToken, limits)
              .whenComplete(() {
            _dashboardInstalls.remove(key);
          }));
}

Future<bool> _installDashboard(String dir, Dio? suppliedClient,
    CancelToken? cancelToken, ZashboardLimits limits) async {
  if (dir.isEmpty) return false;
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

  try {
    checkCancelled();
    if (await index.exists()) return true;
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
    final resp = await client
        .get<ResponseBody>(
      zashboardDistUrl,
      cancelToken: token,
      options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: limits.timeout,
          sendTimeout: limits.timeout),
    )
        .timeout(limits.timeout, onTimeout: () {
      token.cancel('Dashboard timeout');
      throw TimeoutException('Dashboard download timed out');
    });
    final body = resp.data;
    if (body == null) return false;
    final declared =
        int.tryParse(resp.headers.value(Headers.contentLengthHeader) ?? '');
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
    await target.parent.create(recursive: true);
    staging = await target.parent.createTemp('.flclashx-dashboard-');
    await extractZashboardArchive(
      buffer.takeBytes(),
      staging,
      limits: limits,
      checkCancelled: checkCancelled,
    );
    checkCancelled();
    // Another process may have installed the panel while we downloaded.
    if (await index.exists()) return true;
    if (await target.exists()) {
      // Non-recursive removal refuses an unexpected concurrent file writer.
      await target.delete();
    }
    await staging.rename(dir);
    staging = null;
    return await index.exists();
  } catch (e) {
    commonPrint.log('zashboard ui download failed: $e');
    return false;
  } finally {
    deadline.cancel();
    await cancellation?.cancel();
    if (!token.isCancelled) token.cancel('Dashboard operation finished');
    if (suppliedClient == null) client.close(force: true);
    if (staging != null) {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
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
String? buildZashboardUrl() {
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
  final hasLocalUi = globalState.effectiveExternalUi.value.trim().isNotEmpty;
  if (!hasLocalUi) {
    return '$publicZashboardBase/#/setup?$query';
  }
  return 'http://$host:$port/ui/#/setup?$query';
}
