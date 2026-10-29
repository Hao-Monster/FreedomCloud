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
    String? protocolSummary,
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

const _canonicalProtocolLabels = <String, String>{
  'vless': 'VLESS',
  'vmess': 'VMess',
  'ss': 'Shadowsocks',
  'shadowsocks': 'Shadowsocks',
  'ssr': 'ShadowsocksR',
  'shadowsocksr': 'ShadowsocksR',
  'trojan': 'Trojan',
  'hysteria2': 'Hysteria2',
  'hysteria': 'Hysteria',
  'tuic': 'TUIC',
  'anytls': 'AnyTLS',
  'wireguard': 'WireGuard',
  'amneziawg': 'AmneziaWG',
  'snell': 'Snell',
  'mieru': 'Mieru',
  'socks5': 'SOCKS5',
  'http': 'HTTP',
  'ssh': 'SSH',
};

const _canonicalTransports = <String, String>{
  'tcp': 'TCP',
  'ws': 'WS',
  'grpc': 'gRPC',
  'h2': 'H2',
  'http': 'HTTP',
  'httpupgrade': 'HTTPUpgrade',
  'splithttp': 'SplitHTTP',
  'xhttp': 'XHTTP',
  'quic': 'QUIC',
  'kcp': 'KCP',
  'udp': 'UDP',
};

const _allowedFlows = <String>{
  'xtls-rprx-vision',
  'xtls-rprx-vision-udp443',
  'xtls-rprx-direct',
  'xtls-rprx-splice',
};

const _allowedCiphers = <String>{
  'auto',
  'none',
  'zero',
  'dummy',
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'chacha20',
  'chacha20-ietf',
  'xchacha20',
  'rc4-md5',
  'salsa20',
};

const _allowedSsrProtocols = <String>{
  'origin',
  'auth_sha1_v4',
  'auth_aes128_md5',
  'auth_aes128_sha1',
  'auth_chain_a',
  'auth_chain_b',
};

const _allowedSsrObfs = <String>{
  'plain',
  'http_simple',
  'http_post',
  'random_head',
  'tls1.2_ticket_auth',
};

const _allowedFingerprints = <String>{
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  '360',
  'qq',
  'random',
  'randomized',
};

const _congestionLabels = <String, String>{
  'bbr': 'BBR',
  'cubic': 'CUBIC',
  'new_reno': 'NewReno',
};

const _packetEncodingLabels = <String, String>{
  'xudp': 'XUDP',
  'packetaddr': 'PacketAddr',
};

final _safeUnknownTypePattern = RegExp(r'^[A-Za-z0-9_-]{1,24}$');

const _hysteriaV1Protocols = <String, String>{
  'udp': 'QUIC',
  'faketcp': 'FakeTCP',
  'wechat-video': 'WeChat-Video',
};

const _v2rayPluginTransports = <String, String>{
  'websocket': 'WS',
  'ws': 'WS',
  'grpc': 'gRPC',
  'quic': 'QUIC',
};

Map<String, Object?>? _normalizeFieldMap(Object? raw) {
  if (raw is! Map) return null;
  final normalized = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String) {
      normalized[key.trim().toLowerCase().replaceAll('_', '-')] = entry.value;
    }
  }
  return normalized;
}

Map<String, Object?>? _nonEmptyFieldMap(Object? raw) {
  final map = _normalizeFieldMap(raw);
  return map == null || map.isEmpty ? null : map;
}

/// Normalizes a proxy `type` (e.g. Mihomo's `'Vless'`, `'Shadowsocks'`) to a
/// canonical closed-world protocol display label.
String canonicalProtocolLabel(String rawType) {
  final trimmed = rawType.trim();
  if (trimmed.isEmpty) return rawType;
  return _canonicalProtocolLabels[trimmed.toLowerCase()] ??
      (_safeUnknownTypePattern.hasMatch(trimmed) ? trimmed : rawType);
}

/// Extracts a human-readable protocol stack summary using ONLY closed-world
/// canonical tokens. Raw strings for hosts, ports, credentials, paths, SNI,
/// keys, or unknown tokens are never echoed.
String? extractSafeProtocolSummary(Map<Object?, Object?> proxy) {
  final fields = _normalizeFieldMap(proxy);
  if (fields == null) return null;
  final rawType = fields['type'];
  if (rawType is! String) return null;
  final trimmedType = rawType.trim();
  if (trimmedType.isEmpty) return null;
  final typeLower = trimmedType.toLowerCase();
  final protocolLabel = _canonicalProtocolLabels[typeLower] ??
      (_safeUnknownTypePattern.hasMatch(trimmedType) ? trimmedType : null);
  if (protocolLabel == null) return null;

  final parts = <String>[protocolLabel];

  final isShadowsocks = typeLower == 'ss' || typeLower == 'shadowsocks';
  final rawPlugin = fields['plugin'];
  final pluginLower =
      isShadowsocks && rawPlugin is String ? rawPlugin.trim().toLowerCase() : null;
  final pluginOpts =
      isShadowsocks ? _nonEmptyFieldMap(fields['plugin-opts']) : null;

  String? transport;
  final rawNetwork = fields['network'] ??
      (typeLower == 'mieru' ? fields['transport'] : null);
  if (rawNetwork is String) {
    transport = _canonicalTransports[rawNetwork.trim().toLowerCase()];
  }
  if (transport == null && pluginLower == 'v2ray-plugin') {
    final rawMode = pluginOpts?['mode'];
    if (rawMode is String) {
      transport = _v2rayPluginTransports[rawMode.trim().toLowerCase()];
    } else {
      transport = 'WS';
    }
  }
  if (transport == null && typeLower == 'hysteria') {
    final rawProto = fields['protocol'];
    transport = rawProto is String
        ? (_hysteriaV1Protocols[rawProto.trim().toLowerCase()] ?? 'QUIC')
        : 'QUIC';
  }
  if (transport == null) {
    if (_nonEmptyFieldMap(fields['ws-opts']) != null) {
      transport = 'WS';
    } else if (_nonEmptyFieldMap(fields['grpc-opts']) != null) {
      transport = 'gRPC';
    } else if (_nonEmptyFieldMap(fields['h2-opts']) != null) {
      transport = 'H2';
    } else if (_nonEmptyFieldMap(fields['http-opts']) != null) {
      transport = 'HTTP';
    } else if (const {'vless', 'vmess', 'trojan', 'http', 'socks5'}
        .contains(typeLower)) {
      transport = 'TCP';
    } else if (const {'hysteria2', 'tuic'}.contains(typeLower)) {
      transport = 'QUIC';
    } else if (const {'wireguard', 'amneziawg'}.contains(typeLower)) {
      transport = 'UDP';
    }
  }
  if (transport != null) {
    parts.add(transport);
  }

  final realityOpts = _nonEmptyFieldMap(fields['reality-opts']);
  final realityPublicKey = realityOpts?['public-key'];
  final hasReality =
      realityPublicKey is String && realityPublicKey.trim().isNotEmpty;
  final hasPluginTls =
      pluginLower == 'v2ray-plugin' && pluginOpts?['tls'] == true;
  final hasTls = fields['tls'] == true ||
      hasPluginTls ||
      const {'trojan', 'hysteria2', 'hysteria', 'tuic', 'anytls'}
          .contains(typeLower);
  if (hasReality) {
    parts.add('REALITY');
  } else if (hasTls) {
    parts.add('TLS');
  }

  final rawFlow = fields['flow'];
  if (rawFlow is String) {
    final normalizedFlow = rawFlow.trim().toLowerCase();
    if (_allowedFlows.contains(normalizedFlow)) {
      parts.add(normalizedFlow);
    }
  }

  if (const {'ss', 'shadowsocks', 'ssr', 'shadowsocksr', 'vmess'}
      .contains(typeLower)) {
    final rawCipher = fields['cipher'];
    if (rawCipher is String) {
      final normalizedCipher = rawCipher.trim().toLowerCase();
      if (_allowedCiphers.contains(normalizedCipher)) {
        parts.add(normalizedCipher);
      }
    }
  }

  if (typeLower == 'ssr' || typeLower == 'shadowsocksr') {
    final rawProtocol = fields['protocol'];
    if (rawProtocol is String) {
      final normalized = rawProtocol.trim().toLowerCase();
      if (_allowedSsrProtocols.contains(normalized)) {
        parts.add(normalized);
      }
    }
    final rawObfs = fields['obfs'];
    if (rawObfs is String) {
      final normalized = rawObfs.trim().toLowerCase();
      if (_allowedSsrObfs.contains(normalized)) {
        parts.add(normalized);
      }
    }
  }

  if (isShadowsocks && pluginLower != null) {
    if (pluginLower == 'obfs' || pluginLower == 'simple-obfs') {
      String? modeSuffix;
      final rawMode = pluginOpts?['mode'];
      if (rawMode is String) {
        final modeLower = rawMode.trim().toLowerCase();
        if (modeLower == 'tls') {
          modeSuffix = 'TLS';
        } else if (modeLower == 'http') {
          modeSuffix = 'HTTP';
        }
      }
      parts.add(
          modeSuffix == null ? 'simple-obfs' : 'simple-obfs ($modeSuffix)');
    } else if (pluginLower == 'v2ray-plugin') {
      parts.add('v2ray-plugin');
    } else if (pluginLower == 'shadow-tls') {
      final rawVer = pluginOpts?['version'];
      final ver = rawVer is int
          ? rawVer
          : rawVer is String
              ? int.tryParse(rawVer.trim())
              : null;
      parts.add(
          ver != null && ver >= 1 && ver <= 3 ? 'ShadowTLS v$ver' : 'ShadowTLS');
    } else if (pluginLower == 'restls') {
      parts.add('Restls');
    } else if (pluginLower == 'kcptun') {
      parts.add('kcptun');
    } else if (pluginLower == 'gost-plugin') {
      parts.add('gost-plugin');
    }
  } else if (typeLower == 'hysteria2') {
    final rawObfs = fields['obfs'];
    if (rawObfs is String && rawObfs.trim().toLowerCase() == 'salamander') {
      parts.add('salamander');
    }
  } else if (typeLower == 'tuic') {
    final rawCongestion = fields['congestion-controller'];
    if (rawCongestion is String) {
      final label = _congestionLabels[rawCongestion.trim().toLowerCase()];
      if (label != null) {
        parts.add(label);
      }
    }
  } else if (typeLower == 'snell') {
    final rawVersion = fields['version'];
    final version = rawVersion is int
        ? rawVersion
        : rawVersion is String
            ? int.tryParse(rawVersion.trim())
            : null;
    if (version != null && version >= 1 && version <= 5) {
      parts.add('v$version');
    }
  }

  final rawFp = fields['client-fingerprint'];
  if (rawFp is String) {
    final fpLower = rawFp.trim().toLowerCase();
    if (_allowedFingerprints.contains(fpLower)) {
      parts.add('uTLS:$fpLower');
    }
  }

  final smux = _nonEmptyFieldMap(fields['smux']);
  if (smux != null && smux['enabled'] == true) {
    final rawSmuxProto = smux['protocol'];
    final smuxLower =
        rawSmuxProto is String ? rawSmuxProto.trim().toLowerCase() : null;
    if (smuxLower != null &&
        const {'h2mux', 'yamux', 'smux'}.contains(smuxLower)) {
      parts.add(smuxLower);
    } else {
      parts.add('Mux');
    }
  }

  final rawPacketEncoding = fields['packet-encoding'];
  if (rawPacketEncoding is String) {
    final label = _packetEncodingLabels[rawPacketEncoding.trim().toLowerCase()];
    if (label != null) {
      parts.add(label);
    }
  }

  if (fields['udp'] == true && transport != 'UDP') {
    parts.add('UDP');
  }

  return parts.join(' · ');
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
    protocolSummary: extractSafeProtocolSummary(proxy),
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
