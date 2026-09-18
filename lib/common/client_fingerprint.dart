/// Migrates the removed root-level Mihomo fingerprint setting into the
/// per-proxy field expected by current cores.
///
/// Only proxy entries that can carry TLS client settings are changed. Existing
/// per-proxy values always win. The obsolete root key is removed whenever a
/// proxy list is present because current cores reject that root-level key.
bool migrateDeprecatedGlobalClientFingerprint(Map<String, dynamic> config) {
  final value = config['global-client-fingerprint'];
  if (value is! String || value.trim().isEmpty) return false;

  final proxies = config['proxies'];
  if (proxies is! List) return false;

  const tlsProxyTypes = {
    'vmess',
    'vless',
    'trojan',
    'hysteria',
    'hysteria2',
    'tuic',
    'anytls',
    'shadowtls',
  };
  var migrated = false;
  for (final proxy in proxies) {
    if (proxy is! Map) continue;
    final type = proxy['type'];
    final tlsCapable = (type is String && tlsProxyTypes.contains(type)) ||
        proxy['tls'] == true;
    if (!tlsCapable || proxy['client-fingerprint'] != null) continue;
    proxy['client-fingerprint'] = value;
    migrated = true;
  }
  config.remove('global-client-fingerprint');
  return migrated;
}
