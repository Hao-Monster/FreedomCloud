import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Key identifier embedded into Stage-1 FreedomNet signed envelopes.
const String fnStage1KeyId = 'fn-2026-v1';

/// Pinned Stage-1 Ed25519 public key (base64 standard encoding, 32 bytes).
const String fnStage1PublicKeyBase64 =
    '8eQ/Pe9ABxs/drZReKxG5XpNrASXxF2SuPn02ykbGXI=';

/// Pinned Stage-1 Ed25519 public key (lowercase hex, 64 characters).
const String fnStage1PublicKeyHex =
    'f1e43f3def40071b3f76b65178ac46e57a4dac0497c45d92b8f9f4db291b1972';

/// Default Ed25519-signed Stage-1 bootstrap envelope embedded for cold starts.
const String fnDefaultSignedBootstrapJson =
    '{"payload":{"expires_at":"2028-11-16T00:00:00Z","issued_at":"2026-11-16T00:00:00Z","key_id":"fn-2026-v1","origins":[{"capabilities":["api","sub","update","geox"],"origin":"https://api.westernmoviefans.com","priority":10,"role":"primary"},{"capabilities":["api","sub","update","geox"],"origin":"https://fast.hjy.ca:8443","priority":20,"role":"direct"}],"schema_version":1,"tenant_id":"freedomnet-prod"},"signature":"0E50yFNR0krp7CYFtG_s4XiSEMOVir0OR5cpRvpTKq7MQYs6cHwjqcZELJ5gIrt3IY54WgBIOpMZj6Y7NB6uDQ"}';

/// Returns a copy of the pinned Stage-1 Ed25519 32-byte verifying key.
Uint8List get fnStage1PublicKeyBytes =>
    Uint8List.fromList(base64Decode(fnStage1PublicKeyBase64));

/// Default trusted key map containing only the pinned Stage-1 verifying key.
Map<String, Uint8List> get fnDefaultTrustedKeys => <String, Uint8List>{
      fnStage1KeyId: fnStage1PublicKeyBytes,
    };

/// Encodes [value] into compact UTF-8 JSON with map keys recursively sorted in
/// ascending UTF-8 byte order (matching Go `encoding/json` with
/// `SetEscapeHTML(false)`).
String canonicalJsonEncode(Object? value) {
  final buffer = StringBuffer();
  _writeCanonicalJson(buffer, value);
  return buffer.toString();
}

void _writeCanonicalJson(StringBuffer buffer, Object? value) {
  if (value is Map) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw ArgumentError.value(
          key,
          'value',
          'Canonical JSON objects require String keys',
        );
      }
      keys.add(key);
    }
    keys.sort(_compareUtf8Bytes);
    buffer.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buffer.write(',');
      final key = keys[i];
      buffer
        ..write(jsonEncode(key))
        ..write(':');
      _writeCanonicalJson(buffer, value[key]);
    }
    buffer.write('}');
    return;
  }
  if (value is List) {
    buffer.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buffer.write(',');
      _writeCanonicalJson(buffer, value[i]);
    }
    buffer.write(']');
    return;
  }
  buffer.write(jsonEncode(value));
}

int _compareUtf8Bytes(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  final minLen = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
  for (var i = 0; i < minLen; i++) {
    final diff = aBytes[i] - bBytes[i];
    if (diff != 0) return diff;
  }
  return aBytes.length - bBytes.length;
}

/// Decodes a 64-byte Ed25519 signature encoded as base64url (with or without
/// padding), standard base64, or 128-char hex; returns null when invalid.
Uint8List? decodeEd25519Signature(String encoded) {
  final trimmed = encoded.trim();
  if (trimmed.isEmpty) return null;

  if (RegExp(r'^[0-9a-fA-F]{128}$').hasMatch(trimmed)) {
    final bytes = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      bytes[i] = int.parse(trimmed.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  try {
    final Uint8List raw;
    if (trimmed.contains('-') || trimmed.contains('_')) {
      if (trimmed.contains('+') || trimmed.contains('/')) return null;
      raw = Uint8List.fromList(base64Url.decode(base64Url.normalize(trimmed)));
    } else {
      raw = Uint8List.fromList(base64Decode(base64.normalize(trimmed)));
    }
    return raw.length == 64 ? raw : null;
  } on FormatException {
    return null;
  }
}

/// Verifies an Ed25519-signed `{"payload": ..., "signature": ...}` JSON map
/// against [trustedKeys] (defaulting to [fnDefaultTrustedKeys]) and checks
/// payload expiration unless [checkExpiry] is false.
bool verifySignedJsonEnvelope(
  Map<String, dynamic> envelope, {
  Map<String, Uint8List>? trustedKeys,
  DateTime? now,
  bool checkExpiry = true,
}) {
  final payloadRaw = envelope['payload'];
  final signatureRaw = envelope['signature'];
  if (payloadRaw is! Map || signatureRaw is! String) {
    return false;
  }
  final signature = decodeEd25519Signature(signatureRaw);
  if (signature == null) return false;

  final keyId = payloadRaw['key_id'];
  if (keyId is! String || keyId.isEmpty) return false;
  final keyRing = trustedKeys ?? fnDefaultTrustedKeys;
  final publicKey = keyRing[keyId];
  if (publicKey == null || publicKey.length != 32) return false;

  if (checkExpiry) {
    final expiresRaw = payloadRaw['expires_at'];
    if (expiresRaw is! String || expiresRaw.trim().isEmpty) return false;
    final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
    if (expiresAt == null) return false;
    final currentUtc = (now ?? DateTime.now()).toUtc();
    if (currentUtc.isAfter(expiresAt)) return false;

    final issuedRaw = payloadRaw['issued_at'];
    if (issuedRaw is String && issuedRaw.trim().isNotEmpty) {
      if (DateTime.tryParse(issuedRaw) == null) return false;
    }
  }

  final canonicalBytes = utf8.encode(canonicalJsonEncode(payloadRaw));
  return ed25519Verify(
    publicKey: publicKey,
    message: Uint8List.fromList(canonicalBytes),
    signature: signature,
  );
}

/// Verifies an RFC 8032 Ed25519 [signature] (64 bytes) over [message] using
/// [publicKey] (32 bytes).
bool ed25519Verify({
  required Uint8List publicKey,
  required Uint8List message,
  required Uint8List signature,
}) {
  if (publicKey.length != 32 || signature.length != 64) {
    return false;
  }

  final pointA = _decodePoint(publicKey);
  if (pointA == null) return false;

  final rBytes = signature.sublist(0, 32);
  final pointR = _decodePoint(rBytes);
  if (pointR == null) return false;

  final scalarS = _decodeLittleEndian(signature, 32, 32);
  if (scalarS >= _l) return false;

  final digestInput = Uint8List(64 + message.length)
    ..setRange(0, 32, rBytes)
    ..setRange(32, 64, publicKey)
    ..setRange(64, 64 + message.length, message);
  final h = Uint8List.fromList(sha512.convert(digestInput).bytes);
  final scalarK = _decodeLittleEndian(h, 0, 64) % _l;

  final sb = _scalarMult(_basePoint, scalarS);
  final ka = _scalarMult(pointA, scalarK);
  final rhs = _pointAdd(pointR, ka);
  return _pointsEqual(sb, rhs);
}

// Curve25519 / Ed25519 field prime p = 2^255 - 19 and subgroup order L.
final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l = (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final BigInt _pMinus5Div8 = (_p - BigInt.from(5)) >> 3;
final BigInt _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) >> 2, _p);

// Edwards curve parameter d = -121665 / 121666 mod p.
final BigInt _d =
    ((_p - BigInt.from(121665)) * BigInt.from(121666).modInverse(_p)) % _p;
final BigInt _d2 = (_d * BigInt.two) % _p;

// Base point B coordinates per RFC 8032 Section 5.1.
final BigInt _bx = BigInt.parse(
  '15112221349535400772501151409588531511454012693041857206046113283949847762202',
);
final BigInt _by = (BigInt.from(4) * BigInt.from(5).modInverse(_p)) % _p;
final _ExtPoint _basePoint = _ExtPoint(
  _bx,
  _by,
  BigInt.one,
  (_bx * _by) % _p,
);

class _ExtPoint {
  const _ExtPoint(this.x, this.y, this.z, this.t);

  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;

  static final _ExtPoint identity =
      _ExtPoint(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);
}

BigInt _decodeLittleEndian(Uint8List bytes, int offset, int length) {
  var result = BigInt.zero;
  for (var i = length - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[offset + i]);
  }
  return result;
}

_ExtPoint? _decodePoint(Uint8List bytes) {
  if (bytes.length != 32) return null;
  final xSign = (bytes[31] >> 7) & 1;

  var y = BigInt.from(bytes[31] & 0x7f);
  for (var i = 30; i >= 0; i--) {
    y = (y << 8) | BigInt.from(bytes[i]);
  }
  if (y >= _p) return null;

  final y2 = (y * y) % _p;
  final u = (y2 - BigInt.one) % _p;
  final v = ((_d * y2) + BigInt.one) % _p;
  if (v == BigInt.zero) return null;

  final v3 = ((v * v % _p) * v) % _p;
  final v7 = ((v3 * v3 % _p) * v) % _p;
  final uv7 = (u * v7) % _p;
  var cand = ((u * v3 % _p) * uv7.modPow(_pMinus5Div8, _p)) % _p;

  final check = (v * (cand * cand % _p)) % _p;
  if (check != u) {
    final negU = (_p - u) % _p;
    if (check != negU) {
      return null;
    }
    cand = (cand * _sqrtM1) % _p;
  }

  if (cand == BigInt.zero && xSign == 1) {
    return null;
  }
  final x = (cand.isOdd ? 1 : 0) == xSign ? cand : (_p - cand) % _p;
  return _ExtPoint(x, y, BigInt.one, (x * y) % _p);
}

_ExtPoint _pointAdd(_ExtPoint p, _ExtPoint q) {
  final a = ((p.y - p.x) * (q.y - q.x)) % _p;
  final b = ((p.y + p.x) * (q.y + q.x)) % _p;
  final c = ((p.t * _d2 % _p) * q.t) % _p;
  final d = ((p.z * BigInt.two % _p) * q.z) % _p;
  final e = (b - a) % _p;
  final f = (d - c) % _p;
  final g = (d + c) % _p;
  final h = (b + a) % _p;
  return _ExtPoint(
    (e * f) % _p,
    (g * h) % _p,
    (f * g) % _p,
    (e * h) % _p,
  );
}

_ExtPoint _pointDouble(_ExtPoint p) {
  final a = (p.x * p.x) % _p;
  final b = (p.y * p.y) % _p;
  final c = (BigInt.two * (p.z * p.z % _p)) % _p;
  final d = (_p - a) % _p;
  final sum = (p.x + p.y) % _p;
  final e = (((sum * sum) % _p) - a - b) % _p;
  final g = (d + b) % _p;
  final f = (g - c) % _p;
  final h = (d - b) % _p;
  return _ExtPoint(
    (e * f) % _p,
    (g * h) % _p,
    (f * g) % _p,
    (e * h) % _p,
  );
}

_ExtPoint _scalarMult(_ExtPoint point, BigInt scalar) {
  if (scalar <= BigInt.zero) {
    return _ExtPoint.identity;
  }
  var acc = _ExtPoint.identity;
  for (var bit = scalar.bitLength - 1; bit >= 0; bit--) {
    acc = _pointDouble(acc);
    if (((scalar >> bit) & BigInt.one) == BigInt.one) {
      acc = _pointAdd(acc, point);
    }
  }
  return acc;
}

bool _pointsEqual(_ExtPoint p, _ExtPoint q) {
  final xzEqual = (p.x * q.z) % _p == (q.x * p.z) % _p;
  final yzEqual = (p.y * q.z) % _p == (q.y * p.z) % _p;
  return xzEqual && yzEqual;
}
