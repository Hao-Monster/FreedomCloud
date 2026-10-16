// ignore_for_file: invalid_annotation_target
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/node_catalog.freezed.dart';
part 'generated/node_catalog.g.dart';

enum CatalogNodeSource { inline, provider }

enum CatalogUnsupportedReason {
  none,
  chainUnsupported,
  typeUnsupported,
  parseFailed,
  providerNotCached,
  strictModeUnsupported,
}

const _isolatedCatalogTypes = {
  'ss',
  'ssr',
  'socks5',
  'http',
  'vmess',
  'vless',
  'trojan',
  'hysteria2',
  'ssh',
};

/// Preflight for isolated tests only, matching Core's catalog admission rules.
/// A supported shape still needs Core parsing; these restrictions must not
/// change the identities or health history of already-running adapters.
CatalogUnsupportedReason catalogIsolationUnsupportedReason(
    Map<Object?, Object?> proxy) {
  final type = proxy['type'];
  var hasRetainedTransport = false;
  for (final entry in proxy.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final field = key.toLowerCase().replaceAll('_', '-');
    // Chains take precedence regardless of the source map's key order.
    if (field == 'dialer-proxy') {
      return CatalogUnsupportedReason.chainUnsupported;
    }
    final value = entry.value;
    if (field == 'smux' ||
        (type == 'ss' &&
            field == 'plugin' &&
            value is String &&
            value.toLowerCase() == 'kcptun') ||
        (type == 'hysteria2' && field == 'realm-opts')) {
      hasRetainedTransport = true;
    }
  }
  if (type is! String || type.isEmpty) {
    return CatalogUnsupportedReason.parseFailed;
  }
  if (!_isolatedCatalogTypes.contains(type) || hasRetainedTransport) {
    return CatalogUnsupportedReason.typeUnsupported;
  }
  return CatalogUnsupportedReason.none;
}

@freezed
class CatalogNode with _$CatalogNode {
  const factory CatalogNode({
    required String identityKey,
    required String endpointKey,
    required String name,
    required String type,
    required CatalogNodeSource source,
    String? providerName,
    int? coreIndex,
    @Default(<String>[]) List<String> selectGroups,
    @Default(CatalogUnsupportedReason.none)
    CatalogUnsupportedReason unsupported,
  }) = _CatalogNode;

  factory CatalogNode.fromJson(Map<String, dynamic> json) =>
      _$CatalogNodeFromJson(json);
}

enum ProfileCatalogStatus { ready, loading, fileMissing, parseFailed, updating }

@freezed
class ProfileCatalog with _$ProfileCatalog {
  @JsonSerializable(explicitToJson: true)
  const factory ProfileCatalog({
    required String profileId,
    required String fingerprint,
    required ProfileCatalogStatus status,
    @Default(<CatalogNode>[]) List<CatalogNode> nodes,

    /// P0 records -1 for a provider whose cached nodes have not been loaded.
    @Default(<String, int>{}) Map<String, int> providerNodeCounts,
    String? errorSummary,
    String? coreCatalogId,
  }) = _ProfileCatalog;

  factory ProfileCatalog.fromJson(Map<String, dynamic> json) =>
      _$ProfileCatalogFromJson(json);
}

/// Read only identity/display fields; never retain the source map or credentials.
CatalogNode catalogNodeFromMap({
  required String profileId,
  required Map<Object?, Object?> proxy,
  CatalogNodeSource source = CatalogNodeSource.inline,
  String? providerName,
  List<String> selectGroups = const [],
}) {
  final name = proxy['name'];
  final type = proxy['type'];
  final server = proxy['server'];
  final rawPort = proxy['port'];
  final port = rawPort is int
      ? rawPort
      : rawPort is String
          ? int.tryParse(rawPort)
          : null;
  if (name is! String ||
      name.isEmpty ||
      type is! String ||
      type.isEmpty ||
      server is! String ||
      server.isEmpty ||
      port == null ||
      port < 1 ||
      port > 65535) {
    throw const FormatException('Invalid catalog node identity');
  }
  final endpoint = '$type|${server.toLowerCase()}|$port';
  String hash(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 32);
  return CatalogNode(
    identityKey: hash(
      'v1|$profileId|${source.name}|${providerName ?? ''}|$endpoint|$name',
    ),
    endpointKey: hash('v1|$endpoint'),
    name: name,
    type: type,
    source: source,
    providerName: providerName,
    selectGroups: List<String>.unmodifiable(selectGroups),
    unsupported: proxy.containsKey('dialer-proxy')
        ? CatalogUnsupportedReason.chainUnsupported
        : const {'wireguard', 'amneziawg'}.contains(type.toLowerCase())
            ? CatalogUnsupportedReason.typeUnsupported
            : CatalogUnsupportedReason.none,
  );
}

/// A display-only identity, deliberately outside the persistent health-key
/// namespace. No endpoint or source map can escape through a malformed item.
CatalogNode unparsedCatalogNode({
  required String profileId,
  required int sourceIndex,
  String? name,
  String? type,
  CatalogNodeSource source = CatalogNodeSource.inline,
  String? providerName,
}) {
  final displayName =
      name == null || name.isEmpty ? '#${sourceIndex + 1}' : name;
  final displayType = type == null || type.isEmpty ? 'unknown' : type;
  final key = sha256
      .convert(utf8.encode(jsonEncode([
        profileId,
        sourceIndex,
        displayName,
        displayType,
        if (source != CatalogNodeSource.inline || providerName != null)
          [source.name, providerName]
      ])))
      .toString()
      .substring(0, 32);
  return CatalogNode(
    identityKey: 'invalid:v1:$key',
    endpointKey: '',
    name: displayName,
    type: displayType,
    source: source,
    providerName: providerName,
    unsupported: CatalogUnsupportedReason.parseFailed,
  );
}
