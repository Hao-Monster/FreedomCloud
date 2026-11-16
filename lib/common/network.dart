import 'dart:async';
import 'dart:io';

const List<String> _virtualOrTunnelInterfaceKeywords = [
  'freedomnet',
  'flclash',
  'mihomo',
  'wintun',
  'clash',
  'vethernet',
  'wsl',
  'hyper-v',
  'vmware',
  'vmnet',
  'vboxnet',
  'virtualbox',
  'tailscale',
  'zerotier',
  'wireguard',
  'tap-windows',
  'loopback',
  'docker',
  'podman',
];

bool isVirtualOrTunnelInterfaceName(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized.startsWith('utun') ||
      RegExp(r'^tun\d*$').hasMatch(normalized)) {
    return true;
  }
  return _virtualOrTunnelInterfaceKeywords.any(normalized.contains);
}

bool _isWifiInterfaceName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.contains('wlan') ||
      normalized.contains('wi-fi') ||
      normalized.contains('wifi') ||
      normalized.contains('无线') ||
      normalized == 'en0';
}

bool _isEthernetInterfaceName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.contains('ethernet') ||
      normalized.contains('以太网') ||
      normalized.startsWith('eth') ||
      normalized.startsWith('en');
}

int _physicalInterfacePriority(String name) {
  if (_isWifiInterfaceName(name)) {
    return 0;
  }
  if (_isEthernetInterfaceName(name)) {
    return 1;
  }
  return 2;
}

bool _isUsablePhysicalAddress(InternetAddress addr) {
  if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) {
    return false;
  }
  final raw = addr.rawAddress;
  if (raw.length == 4) {
    if (raw[0] == 0 || raw[0] == 127) {
      return false;
    }
    // RFC 3927 IPv4 link-local (APIPA 169.254.0.0/16).
    if (raw[0] == 169 && raw[1] == 254) {
      return false;
    }
    // RFC 2544 / Clash TUN & Fake-IP benchmark range (198.18.0.0/15).
    if (raw[0] == 198 && (raw[1] == 18 || raw[1] == 19)) {
      return false;
    }
    return true;
  }
  if (raw.length == 16) {
    final allZero = raw.every((byte) => byte == 0);
    if (allZero) {
      return false;
    }
    // IPv6 link-local fe80::/10.
    if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) {
      return false;
    }
    // Clash / sing-tun default private tunnel prefix fdfe:dcba:9876::/48.
    if (raw[0] == 0xfd &&
        raw[1] == 0xfe &&
        raw[2] == 0xdc &&
        raw[3] == 0xba &&
        raw[4] == 0x98 &&
        raw[5] == 0x76) {
      return false;
    }
    return true;
  }
  return false;
}

extension NetworkInterfaceExt on NetworkInterface {
  bool get isWifi => _isWifiInterfaceName(name);

  bool get includesIPv4 => addresses.any((addr) => addr.isIPv4);
}

extension InternetAddressExt on InternetAddress {
  bool get isIPv4 => type == InternetAddressType.IPv4;
}

String selectPreferredPhysicalLocalIp(
  Iterable<({String name, List<InternetAddress> addresses})> interfaces,
) {
  final candidates = <({String name, List<InternetAddress> usable})>[];
  for (final iface in interfaces) {
    if (isVirtualOrTunnelInterfaceName(iface.name)) {
      continue;
    }
    final usable = iface.addresses.where(_isUsablePhysicalAddress).toList();
    if (usable.isEmpty) {
      continue;
    }
    usable.sort((a, b) {
      if (a.isIPv4 && !b.isIPv4) return -1;
      if (!a.isIPv4 && b.isIPv4) return 1;
      return 0;
    });
    candidates.add((name: iface.name, usable: usable));
  }

  if (candidates.isEmpty) {
    return '';
  }

  candidates.sort((a, b) {
    final priorityCmp = _physicalInterfacePriority(a.name)
        .compareTo(_physicalInterfacePriority(b.name));
    if (priorityCmp != 0) {
      return priorityCmp;
    }
    final aHasIPv4 = a.usable.any((addr) => addr.isIPv4);
    final bHasIPv4 = b.usable.any((addr) => addr.isIPv4);
    if (aHasIPv4 && !bHasIPv4) return -1;
    if (!aHasIPv4 && bHasIPv4) return 1;
    return 0;
  });

  return candidates.first.usable.first.address;
}

bool isGlobalUnicastIpv6Address(InternetAddress addr) {
  if (addr.type != InternetAddressType.IPv6 ||
      addr.isLoopback ||
      addr.isLinkLocal ||
      addr.isMulticast) {
    return false;
  }
  final raw = addr.rawAddress;
  if (raw.length != 16) return false;
  if (raw.every((b) => b == 0)) return false;
  // Exclude link-local fe80::/10 and ULA fc00::/7.
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return false;
  if ((raw[0] & 0xfe) == 0xfc) return false;
  // Exclude IPv4-mapped ::ffff:0:0/96.
  final isV4Mapped = raw[0] == 0 &&
      raw[1] == 0 &&
      raw[2] == 0 &&
      raw[3] == 0 &&
      raw[4] == 0 &&
      raw[5] == 0 &&
      raw[6] == 0 &&
      raw[7] == 0 &&
      raw[8] == 0 &&
      raw[9] == 0 &&
      raw[10] == 0xff &&
      raw[11] == 0xff;
  if (isV4Mapped) return false;
  // Restrict to Global Unicast 2000::/3.
  return (raw[0] & 0xe0) == 0x20;
}

/// Probes whether the active physical network has working global IPv6 internet
/// egress so broken/blackholed dual-stack ISP networks do not stall DNS or
/// connections when `ipv6: true` is configured.
class Ipv6ReachabilityGuard {
  Ipv6ReachabilityGuard({
    Future<List<InternetAddress>> Function()? listLocalIpv6Addresses,
    Future<bool> Function(
      String host,
      int port, {
      required Duration timeout,
    })? tryConnectIpv6,
    this.probeTimeout = const Duration(milliseconds: 800),
    this.cacheTtl = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _listLocalIpv6Addresses = listLocalIpv6Addresses ?? _defaultLocalIpv6s,
        _tryConnectIpv6 = tryConnectIpv6 ?? _defaultTryConnectIpv6,
        _clock = clock ?? DateTime.now;

  static final Ipv6ReachabilityGuard shared = Ipv6ReachabilityGuard();

  static const List<(String, int)> _probeTargets = <(String, int)>[
    ('2400:3200::1', 443),
    ('2001:4860:4860::8888', 443),
  ];

  final Future<List<InternetAddress>> Function() _listLocalIpv6Addresses;
  final Future<bool> Function(String host, int port, {required Duration timeout})
      _tryConnectIpv6;
  final Duration probeTimeout;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  bool? _cachedReachable;
  String? _cachedFingerprint;
  DateTime? _cachedAt;
  Future<bool>? _inFlight;

  static Future<List<InternetAddress>> _defaultLocalIpv6s() async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv6,
      );
      final addrs = <InternetAddress>[];
      for (final iface in ifaces) {
        if (isVirtualOrTunnelInterfaceName(iface.name)) continue;
        addrs.addAll(iface.addresses);
      }
      return addrs;
    } catch (_) {
      return const <InternetAddress>[];
    }
  }

  static Future<bool> _defaultTryConnectIpv6(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(host),
        port,
        timeout: timeout,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  void invalidate() {
    _cachedReachable = null;
    _cachedFingerprint = null;
    _cachedAt = null;
  }

  Future<bool> isGlobalIpv6Reachable({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final pending = _inFlight;
      if (pending != null) return pending;
    }
    final future = _evaluate(forceRefresh: forceRefresh).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<bool> _evaluate({required bool forceRefresh}) async {
    final localAddrs = await _listLocalIpv6Addresses();
    final globalAddrs = localAddrs.where(isGlobalUnicastIpv6Address).toList();
    if (globalAddrs.isEmpty) {
      _cachedReachable = false;
      _cachedFingerprint = '';
      _cachedAt = _clock();
      return false;
    }

    final sorted = globalAddrs.map((a) => a.address).toList()..sort();
    final fingerprint = sorted.join(',');
    final now = _clock();
    if (!forceRefresh &&
        _cachedReachable != null &&
        _cachedFingerprint == fingerprint &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < cacheTtl) {
      return _cachedReachable!;
    }

    var reachable = false;
    for (final (host, port) in _probeTargets) {
      try {
        if (await _tryConnectIpv6(host, port, timeout: probeTimeout)) {
          reachable = true;
          break;
        }
      } catch (_) {
        // Probe failed cleanly; continue to next target or downgrade IPv6.
      }
    }

    _cachedReachable = reachable;
    _cachedFingerprint = fingerprint;
    _cachedAt = _clock();
    return reachable;
  }
}
