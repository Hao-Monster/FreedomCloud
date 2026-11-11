import 'dart:io';

bool _isTunnelInterfaceName(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.contains('flclash') ||
      normalized.contains('mihomo') ||
      normalized.contains('wintun') ||
      normalized.contains('clash') ||
      normalized.startsWith('utun') ||
      RegExp(r'^tun\d*$').hasMatch(normalized);
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
    if (_isTunnelInterfaceName(iface.name)) {
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
