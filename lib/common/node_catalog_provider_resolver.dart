import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_test_plan.dart';
import 'package:path/path.dart' as p;

typedef CatalogProviderFetch = Future<Uint8List> Function(Uri uri,
    Map<String, List<String>> headers, int maxBytes, bool Function() isCurrent);

class CatalogProviderData {
  const CatalogProviderData(this.proxies, this.issues);
  final List<Map<String, dynamic>> proxies;
  final List<CatalogProviderIssue> issues;
}

/// Used only by an explicitly requested all-profile test. It never writes a
/// provider cache or starts/updates a live Core provider.
class CatalogProviderResolver {
  CatalogProviderResolver({
    required this.homeDirectory,
    required this.httpCachePath,
    required this.parse,
    CatalogProviderFetch? fetch,
  }) : fetch = fetch ?? fetchCatalogProvider;

  static const maxBytes = 8 * 1024 * 1024;
  final Future<String> Function() homeDirectory;
  final Future<String> Function(String profileId, String url) httpCachePath;
  final Future<String> Function(
      String contentBase64, Map<String, dynamic> definition) parse;
  final CatalogProviderFetch fetch;

  Future<CatalogProviderData> resolve(
      String profileId, String name, Map<String, dynamic> definition,
      {required bool Function() isCurrent}) async {
    void check() {
      if (!isCurrent()) throw const CatalogBuildException('cancelled');
    }

    check();
    try {
      final type = definition['type'];
      var bytes = Uint8List(0);
      if (type == 'http') {
        final source = definition['url'];
        final uri = source is String ? Uri.tryParse(source) : null;
        if (uri == null ||
            !const {'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const CatalogBuildException('providerUnsafeUrl');
        }
        final cached =
            await _readLocal(await httpCachePath(profileId, source as String));
        check();
        if (cached != null) {
          bytes = cached;
        } else {
          // A named proxy may refer to an inactive configuration. Falling back
          // to the active proxy would silently change its download semantics.
          if ((definition['proxy'] as String?)?.isNotEmpty == true) {
            throw const CatalogBuildException('providerOptionsUnsupported');
          }
          final headers = <String, List<String>>{};
          final supplied = definition['header'];
          if (supplied != null && supplied is! Map) {
            throw const CatalogBuildException('parseFailed');
          }
          for (final entry in (supplied as Map? ?? const {}).entries) {
            if (entry.key is! String ||
                entry.value is! List ||
                (entry.value as List).any((v) => v is! String)) {
              throw const CatalogBuildException('parseFailed');
            }
            headers[entry.key as String] =
                List<String>.from(entry.value as List);
          }
          final requested = definition['size-limit'];
          final limit =
              requested is num && requested > 0 && requested < maxBytes
                  ? requested.toInt()
                  : maxBytes;
          bytes = await fetch(uri, headers, limit, isCurrent);
          if (bytes.length > limit)
            throw const CatalogBuildException('providerTooLarge');
        }
      } else if (type == 'file') {
        final path = definition['path'];
        if (path is! String || path.isEmpty) {
          throw const CatalogBuildException('providerUnsafePath');
        }
        final local = await _readLocal(path);
        if (local == null)
          throw const CatalogBuildException('providerNotCached');
        bytes = local;
      } else if (type != 'inline') {
        throw const CatalogBuildException('providerOptionsUnsupported');
      }
      check();
      final decoded = jsonDecode(await parse(base64Encode(bytes), definition));
      check();
      if (decoded is! Map ||
          decoded['proxies'] is! List ||
          decoded['rejected'] is! int ||
          (decoded['rejected'] as int) < 0) {
        throw const CatalogBuildException('invalidResponse');
      }
      final proxies = <Map<String, dynamic>>[];
      for (final raw in decoded['proxies'] as List) {
        if (raw is! Map) throw const CatalogBuildException('invalidResponse');
        proxies.add(Map<String, dynamic>.from(raw));
      }
      return CatalogProviderData(proxies, [
        if (decoded['rejected'] > 0)
          CatalogProviderIssue(
              providerName: name,
              reason: 'parseFailed',
              count: decoded['rejected'] as int),
      ]);
    } on CatalogBuildException catch (error) {
      check();
      return CatalogProviderData(
          [], [CatalogProviderIssue(providerName: name, reason: error.reason)]);
    } catch (_) {
      check();
      return CatalogProviderData([],
          [CatalogProviderIssue(providerName: name, reason: 'parseFailed')]);
    }
  }

  Future<Uint8List?> _readLocal(String path) async {
    final home = p.normalize(p.absolute(await homeDirectory()));
    final requested =
        p.normalize(p.isAbsolute(path) ? path : p.join(home, path));
    bool same(String a, String b) => Platform.isWindows
        ? p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase()
        : p.equals(a, b);
    // Lexical containment is checked before following the trusted home alias.
    final relative = p.relative(requested, from: home);
    if (relative == '.' ||
        relative == '..' ||
        p.isAbsolute(relative) ||
        p.split(relative).contains('..')) {
      throw const CatalogBuildException('providerUnsafePath');
    }
    String canonicalHome;
    try {
      canonicalHome = await Directory(home).resolveSymbolicLinks();
    } on FileSystemException {
      throw const CatalogBuildException('providerNotCached');
    }
    var current = canonicalHome;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      final kind = await FileSystemEntity.type(current, followLinks: false);
      if (kind == FileSystemEntityType.notFound) return null;
      if (kind == FileSystemEntityType.link ||
          !same(await File(current).resolveSymbolicLinks(), current)) {
        throw const CatalogBuildException('providerUnsafePath');
      }
    }
    final file = File(current);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file)
      throw const CatalogBuildException('providerUnsafePath');
    if (stat.size > maxBytes)
      throw const CatalogBuildException('providerTooLarge');
    final result = BytesBuilder(copy: false);
    await for (final part in file.openRead()) {
      if (result.length + part.length > maxBytes)
        throw const CatalogBuildException('providerTooLarge');
      result.add(part);
    }
    // Reject a replaced path after the read as well; never use returned data
    // from a provider path that no longer resolves to the accepted location.
    if (!same(await file.resolveSymbolicLinks(), current)) {
      throw const CatalogBuildException('providerUnsafePath');
    }
    return result.takeBytes();
  }
}

/// Bounded, cancellable download using the existing OS routing. Credentials are
/// never forwarded to a different origin; TLS validation is always enforced.
Future<Uint8List> fetchCatalogProvider(
    Uri uri,
    Map<String, List<String>> headers,
    int maxBytes,
    bool Function() isCurrent) async {
  if (!const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty)
    throw const CatalogBuildException('providerUnsafeUrl');
  final client = HttpClient()
    ..badCertificateCallback = ((_, __, ___) => false)
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = Duration.zero;
  final cancelled = Completer<Uint8List>();
  final watcher = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (!isCurrent() && !cancelled.isCompleted) {
      client.close(force: true);
      cancelled.completeError(const CatalogBuildException('cancelled'));
    }
  });
  Future<Uint8List> request() async {
    var current = uri;
    for (var hop = 0; hop <= 5; hop++) {
      if (!isCurrent()) throw const CatalogBuildException('cancelled');
      final request = await client.getUrl(current);
      request.followRedirects = false;
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null)
          throw const CatalogBuildException('providerDownloadFailed');
        final next = current.resolve(location);
        if (next.origin != uri.origin || next.userInfo.isNotEmpty) {
          throw const CatalogBuildException('providerUnsafeUrl');
        }
        // Cancel the redirect body rather than draining an unbounded stream.
        await response.listen((_) {}).cancel();
        current = next;
        continue;
      }
      if (response.statusCode != HttpStatus.ok)
        throw const CatalogBuildException('providerDownloadFailed');
      if (response.contentLength > maxBytes)
        throw const CatalogBuildException('providerTooLarge');
      final result = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (!isCurrent()) throw const CatalogBuildException('cancelled');
        if (result.length + chunk.length > maxBytes)
          throw const CatalogBuildException('providerTooLarge');
        result.add(chunk);
      }
      return result.takeBytes();
    }
    throw const CatalogBuildException('providerDownloadFailed');
  }

  try {
    return await Future.any([request(), cancelled.future]).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw const CatalogBuildException('deadlineExceeded'));
  } on CatalogBuildException {
    rethrow;
  } catch (_) {
    throw const CatalogBuildException('providerDownloadFailed');
  } finally {
    watcher.cancel();
    client.close(force: true);
  }
}
