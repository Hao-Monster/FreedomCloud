import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Fixed data-route origin country (Mainland China).
const String kEarthOriginCountryCode = 'CN';
const double kEarthOriginLon = 111.5;
const double kEarthOriginLat = 32.5;

/// Safe default overseas exit target when neither IP detection nor node name
/// yields an overseas country code.
const String kEarthDefaultExitCountryCode = 'JP';

/// Computes a responsive frameless diameter for the floating 3D Earth switch.
double computeFloatingEarthDiameter({
  required double viewportWidth,
  required double viewportHeight,
}) {
  final shortest = math.min(viewportWidth, viewportHeight);
  return (shortest * 0.28).clamp(112.0, 152.0).roundToDouble();
}

/// Centroid coordinates (`lon`, `lat` in degrees) for proxy destination countries.
const Map<String, ({double lon, double lat})> kEarthCountryCentroids =
    <String, ({double lon, double lat})>{
  'CN': (lon: 111.5, lat: 32.5),
  'HK': (lon: 114.2, lat: 22.3),
  'TW': (lon: 121.5, lat: 25.0),
  'MO': (lon: 113.5, lat: 22.2),
  'JP': (lon: 139.7, lat: 35.7),
  'SG': (lon: 103.8, lat: 1.3),
  'KR': (lon: 127.0, lat: 37.5),
  'US': (lon: -118.2, lat: 34.1),
  'GB': (lon: -0.1, lat: 51.5),
  'DE': (lon: 8.7, lat: 50.1),
  'FR': (lon: 2.35, lat: 48.86),
  'NL': (lon: 4.9, lat: 52.37),
  'CA': (lon: -79.4, lat: 43.7),
  'AU': (lon: 150.2, lat: -33.9),
  'RU': (lon: 37.6, lat: 55.75),
  'MY': (lon: 101.7, lat: 3.14),
  'TH': (lon: 100.5, lat: 13.75),
  'IN': (lon: 77.2, lat: 28.6),
  'VN': (lon: 106.7, lat: 10.8),
  'PH': (lon: 121.0, lat: 14.6),
  'ID': (lon: 106.8, lat: -6.2),
  'TR': (lon: 28.98, lat: 41.01),
  'AE': (lon: 55.3, lat: 25.27),
  'IT': (lon: 12.5, lat: 41.9),
  'ES': (lon: -3.7, lat: 40.4),
  'CH': (lon: 8.54, lat: 47.37),
  'SE': (lon: 18.06, lat: 59.33),
  'IE': (lon: -6.26, lat: 53.35),
  'BR': (lon: -46.6, lat: -23.55),
  'AR': (lon: -58.4, lat: -34.6),
  'ZA': (lon: 28.04, lat: -26.2),
  'NZ': (lon: 174.76, lat: -36.85),
  'PL': (lon: 21.01, lat: 52.23),
  'UA': (lon: 30.52, lat: 50.45),
  'FI': (lon: 24.94, lat: 60.17),
  'NO': (lon: 10.75, lat: 59.91),
  'AT': (lon: 16.37, lat: 48.21),
  'BE': (lon: 4.35, lat: 50.85),
  'PT': (lon: -9.14, lat: 38.72),
  'IL': (lon: 34.78, lat: 32.08),
  'MX': (lon: -99.13, lat: 19.43),
  'CL': (lon: -70.66, lat: -33.45),
  'CO': (lon: -74.07, lat: 4.71),
  'PE': (lon: -77.04, lat: -12.05),
  'RO': (lon: 26.10, lat: 44.43),
  'HU': (lon: 19.04, lat: 47.50),
  'CZ': (lon: 14.42, lat: 50.08),
  'BG': (lon: 23.32, lat: 42.70),
  'GR': (lon: 23.73, lat: 37.98),
  'DK': (lon: 12.57, lat: 55.68),
  'IS': (lon: -21.94, lat: 64.15),
  'LU': (lon: 6.13, lat: 49.61),
  'PK': (lon: 73.05, lat: 33.68),
  'BD': (lon: 90.41, lat: 23.81),
  'NG': (lon: 3.38, lat: 6.52),
  'EG': (lon: 31.24, lat: 30.04),
  'SA': (lon: 46.67, lat: 24.71),
  'KZ': (lon: 76.93, lat: 43.24),
  'KP': (lon: 125.76, lat: 39.04),
  'MN': (lon: 106.92, lat: 47.92),
  'KH': (lon: 104.92, lat: 11.56),
  'LA': (lon: 102.63, lat: 17.97),
  'MM': (lon: 96.16, lat: 16.84),
  'NP': (lon: 85.32, lat: 27.72),
  'LK': (lon: 79.86, lat: 6.93),
  'EE': (lon: 24.75, lat: 59.44),
  'LV': (lon: 24.11, lat: 56.95),
  'LT': (lon: 25.28, lat: 54.69),
  'RS': (lon: 20.46, lat: 44.82),
  'HR': (lon: 15.98, lat: 45.81),
  'SK': (lon: 17.11, lat: 48.15),
  'SI': (lon: 14.51, lat: 46.05),
};

/// Lightweight 3D unit/position vector for Earth spherical math.
@immutable
class EarthVec3 {
  const EarthVec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  EarthVec3 operator +(EarthVec3 other) =>
      EarthVec3(x + other.x, y + other.y, z + other.z);

  EarthVec3 operator -(EarthVec3 other) =>
      EarthVec3(x - other.x, y - other.y, z - other.z);

  EarthVec3 operator *(double scalar) =>
      EarthVec3(x * scalar, y * scalar, z * scalar);

  double dot(EarthVec3 other) => x * other.x + y * other.y + z * other.z;

  EarthVec3 cross(EarthVec3 other) => EarthVec3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  double get lengthSq => x * x + y * y + z * z;

  double get length => math.sqrt(lengthSq);

  EarthVec3 normalized() {
    final len = length;
    if (len <= 1e-8) return const EarthVec3(0, 1, 0);
    return EarthVec3(x / len, y / len, z / len);
  }

  double angleTo(EarthVec3 other) {
    final d = normalized().dot(other.normalized()).clamp(-1.0, 1.0);
    return math.acos(d);
  }
}

/// Converts geographic `(lonDeg, latDeg)` into a unit sphere vector aligned with
/// equirectangular texture UV mapping (`+Y` North Pole, `+Z` `-90W`, `+X` `0E`).
EarthVec3 latLonToUnitVec3(double lonDeg, double latDeg) {
  final phi = (180.0 + lonDeg) * (math.pi / 180.0);
  final theta = (90.0 - latDeg) * (math.pi / 180.0);
  final sinTheta = math.sin(theta);
  return EarthVec3(
    -sinTheta * math.cos(phi),
    math.cos(theta),
    sinTheta * math.sin(phi),
  );
}

/// Computes globe `(baseYaw, basePitch)` to orient [frameDir] toward the camera
/// with headroom above the equator for the elevated great-circle arc.
({double baseYaw, double basePitch}) computeEarthFramingAngles(
  EarthVec3 frameDir, {
  double pitchBias = -0.16,
}) {
  final dir = frameDir.normalized();
  final baseYaw = math.atan2(-dir.x, dir.z);
  final latRad = math.atan2(dir.y, math.sqrt(dir.x * dir.x + dir.z * dir.z));
  final basePitch = (latRad + pitchBias).clamp(-0.35, 0.72);
  return (baseYaw: baseYaw, basePitch: basePitch);
}

/// Applies `'XYZ'` Euler rotation `R_x(pitchX) * R_y(yawY)` to [v].
EarthVec3 transformByEulerXYZ(EarthVec3 v, double pitchX, double yawY) {
  final cosY = math.cos(yawY);
  final sinY = math.sin(yawY);
  final cosX = math.cos(pitchX);
  final sinX = math.sin(pitchX);

  final x1 = v.x * cosY + v.z * sinY;
  final y1 = v.y;
  final z1 = -v.x * sinY + v.z * cosY;

  return EarthVec3(
    x1,
    y1 * cosX - z1 * sinX,
    y1 * sinX + z1 * cosX,
  );
}

/// Read-only inspection snapshot for widget & performance unit tests.
@immutable
class EarthProxySwitchDebugSnapshot {
  const EarthProxySwitchDebugSnapshot({
    required this.originCountryCode,
    required this.targetCountryCode,
    required this.yaw,
    required this.pitch,
    required this.activeMix,
    required this.sweepProgress,
    required this.lineReveal,
    required this.targetRipple,
    required this.isTickerActive,
    required this.visualActive,
    required this.paintCount,
  });

  final String originCountryCode;
  final String targetCountryCode;
  final double yaw;
  final double pitch;
  final double activeMix;
  final double sweepProgress;
  final double lineReveal;
  final double targetRipple;
  final bool isTickerActive;
  final bool visualActive;
  final int paintCount;
}

/// Shared one-time GPU earth texture & shader cache (~1 MB total VRAM).
class _EarthSharedGpuAssets {
  _EarthSharedGpuAssets._({
    required this.colorfulImage,
    required this.dormantImage,
    required this.colorfulShader,
    required this.dormantShader,
  });

  static const int textureWidth = 512;
  static const int textureHeight = 256;

  static _EarthSharedGpuAssets? _instance;
  static int rasterizeCount = 0;

  final ui.Image colorfulImage;
  final ui.Image dormantImage;
  final ui.ImageShader colorfulShader;
  final ui.ImageShader dormantShader;

  static _EarthSharedGpuAssets ensureInitialized() {
    final existing = _instance;
    if (existing != null) return existing;

    rasterizeCount++;
    final colorful = _rasterizeEarthTexture(dormant: false);
    final dormant = _rasterizeEarthTexture(dormant: true);
    final identityMatrix = Float64List.fromList(<double>[
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final created = _EarthSharedGpuAssets._(
      colorfulImage: colorful,
      dormantImage: dormant,
      colorfulShader: ui.ImageShader(
        colorful,
        TileMode.clamp,
        TileMode.clamp,
        identityMatrix,
        filterQuality: FilterQuality.medium,
      ),
      dormantShader: ui.ImageShader(
        dormant,
        TileMode.clamp,
        TileMode.clamp,
        identityMatrix,
        filterQuality: FilterQuality.medium,
      ),
    );
    _instance = created;
    return created;
  }

  static Offset _toCanvasXY(double lon, double lat) => Offset(
        ((lon + 180.0) / 360.0) * textureWidth,
        ((90.0 - lat) / 180.0) * textureHeight,
      );

  static const List<List<List<double>>> _continentPolygons =
      <List<List<double>>>[
    // North & Central America
    [
      [-168, 66], [-162, 71], [-140, 70], [-125, 71], [-110, 74], [-92, 72],
      [-78, 63], [-64, 60], [-55, 52], [-66, 44], [-75, 36], [-81, 25],
      [-83, 29], [-90, 29], [-97, 26], [-96, 19], [-88, 21], [-83, 14],
      [-78, 9], [-84, 8], [-92, 14], [-105, 19], [-112, 27], [-117, 32],
      [-124, 41], [-125, 49], [-136, 58], [-152, 60], [-164, 55], [-168, 63],
    ],
    // Greenland
    [
      [-55, 61], [-45, 60], [-32, 68], [-20, 76], [-28, 83], [-52, 82],
      [-68, 77], [-58, 68],
    ],
    // South America
    [
      [-79, 9], [-72, 12], [-62, 10], [-51, 2], [-35, -6], [-38, -14],
      [-41, -22], [-48, -28], [-54, -34], [-63, -41], [-67, -50], [-71, -55],
      [-75, -48], [-73, -38], [-71, -20], [-78, -12], [-81, -4], [-79, 5],
    ],
    // Eurasia (with clear Korean peninsula, China coast & Malay/SG tip)
    [
      [-9, 37], [-9, 43], [-2, 43], [-4, 48], [2, 51], [8, 54], [10, 58],
      [5, 61], [12, 67], [22, 71], [32, 70], [45, 68], [62, 70], [75, 73],
      [95, 76], [115, 74], [140, 72], [170, 67], [178, 64], [163, 59],
      [156, 51], [142, 54], [136, 44], [129, 39], [129.3, 35.1],
      [126.2, 34.8], [126.0, 38.0], [122, 37], [121.6, 31.2], [119.5, 24.5],
      [114.2, 22.0], [109.5, 20.5], [108.5, 12], [103.5, 10.2], [104.2, 1.2],
      [101.2, 3.0], [99.2, 8.5], [96, 16], [90, 22], [81, 14], [77, 8],
      [72, 20], [67, 24], [58, 25], [50, 29], [56, 23], [54, 17], [44, 13],
      [35, 29], [36, 36], [27, 36], [23, 38], [18, 40], [15, 38], [12, 43],
      [8, 44], [3, 43], [-5, 36],
    ],
    // Great Britain & Ireland
    [
      [-6, 50], [1.6, 51], [1.2, 53.5], [-1.8, 58.2], [-5.5, 58], [-4.5, 52.8],
    ],
    // Taiwan
    [
      [120.2, 22.0], [121.9, 25.1], [121.6, 22.7],
    ],
    // Japan archipelago
    [
      [130.2, 31.4], [135.5, 33.6], [140.8, 35.5], [141.6, 40.6],
      [145.5, 44.0], [141.6, 45.4], [139.6, 39.6], [136.6, 36.8],
      [131.5, 34.0],
    ],
    // Africa
    [
      [-17, 15], [-13, 28], [-6, 35], [10, 37], [12, 33], [22, 32], [32, 31],
      [39, 20], [43, 12], [51, 11], [45, 2], [40, -10], [35, -24], [28, -33],
      [18, -34], [14, -22], [12, -6], [9, 4], [2, 6], [-8, 5], [-16, 11],
    ],
    // Madagascar
    [
      [44, -25], [47, -25], [50, -14], [47, -15],
    ],
    // SE Asia Islands (Sumatra / Java / Borneo / Philippines / New Guinea)
    [
      [96, 5], [105, -2], [114, -7], [106, -7], [99, 0],
    ],
    [
      [109, -3], [117, -3], [118, 6], [112, 3],
    ],
    [
      [120.5, 12], [122.5, 18], [126, 7], [122, 7],
    ],
    [
      [132, -2], [141, -3], [149, -10], [139, -8],
    ],
    // Australia
    [
      [114, -22], [122, -17], [131, -12], [136, -15], [142, -11], [147, -18],
      [153.2, -27], [150.4, -37], [141, -38], [131, -32], [122, -34],
      [115, -34], [114, -27],
    ],
    // Antarctica
    [
      [-180, -74], [-120, -73], [-60, -68], [-20, -72], [40, -69],
      [100, -68], [155, -72], [180, -74], [180, -90], [-180, -90],
    ],
  ];

  static Path _buildPolyPath(List<List<double>> poly) {
    final path = Path();
    for (var i = 0; i < poly.length; i++) {
      final pt = _toCanvasXY(poly[i][0], poly[i][1]);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  static ui.Image _rasterizeEarthTexture({required bool dormant}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, textureWidth.toDouble(), textureHeight.toDouble()),
    );
    final w = textureWidth.toDouble();
    final h = textureHeight.toDouble();

    // 1. Deep ocean background gradient
    final oceanPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, h),
        dormant
            ? const [
                Color(0xFF28313F),
                Color(0xFF334155),
                Color(0xFF3B4960),
                Color(0xFF334155),
                Color(0xFF26303D),
              ]
            : const [
                Color(0xFF0C4A6E),
                Color(0xFF0369A1),
                Color(0xFF0284C7),
                Color(0xFF0369A1),
                Color(0xFF0F3D5E),
              ],
        const [0.0, 0.22, 0.5, 0.78, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), oceanPaint);

    // 2. Subtle bathymetric depth ripples
    final scaleX = w / 2048.0;
    final scaleY = h / 1024.0;
    for (var i = 0; i < 28; i++) {
      final cx = ((i * 217) % 2048) * scaleX;
      final cy = (90 + ((i * 151) % (1024 - 180))) * scaleY;
      final rx = (120 + (i % 5) * 55) * scaleX;
      final ry = (48 + (i % 3) * 28) * scaleY;
      final col = dormant
          ? (i.isEven ? const Color(0x2864748B) : const Color(0x22475569))
          : (i.isEven ? const Color(0x3D06B6D4) : const Color(0x380E7490));
      final ripplePaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          rx,
          [col, col.withValues(alpha: 0.0)],
        );
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate((i % 6) * 0.25);
      canvas.scale(1.0, ry / rx);
      canvas.translate(-cx, -cy);
      canvas.drawCircle(Offset(cx, cy), rx, ripplePaint);
      canvas.restore();
    }

    // 3. Subtle 20-deg graticule lines
    final gridPaint = Paint()
      ..color =
          dormant ? const Color(0x2094A3B8) : const Color(0x287DD3FC)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (var lon = -160; lon <= 160; lon += 20) {
      final p = _toCanvasXY(lon.toDouble(), 0);
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, h), gridPaint);
    }
    for (var lat = -60; lat <= 60; lat += 20) {
      final p = _toCanvasXY(0, lat.toDouble());
      canvas.drawLine(Offset(0, p.dy), Offset(w, p.dy), gridPaint);
    }

    // 4. Continents
    final paths = [
      for (final poly in _continentPolygons) _buildPolyPath(poly),
    ];

    if (!dormant) {
      final coastalHaloPaint = Paint()
        ..color = const Color(0x5522D3EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2;
      for (final path in paths) {
        canvas.drawPath(path, coastalHaloPaint);
      }
    }

    final landPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h * 0.15),
        Offset(w, h * 0.85),
        dormant
            ? const [
                Color(0xFF7B8798),
                Color(0xFF6B7789),
                Color(0xFF94A3B8),
                Color(0xFF7E8B9C),
                Color(0xFFA0AEC0),
              ]
            : const [
                Color(0xFF10B981),
                Color(0xFF059669),
                Color(0xFF34D399),
                Color(0xFF10B981),
                Color(0xFF84CC16),
              ],
        const [0.0, 0.32, 0.55, 0.78, 1.0],
      )
      ..style = PaintingStyle.fill;

    final polarPaint = Paint()
      ..color = dormant ? const Color(0xFFAEB9C7) : const Color(0xFFA7F3D0)
      ..style = PaintingStyle.fill;

    final coastStrokePaint = Paint()
      ..color = dormant ? const Color(0xFFCBD5E1) : const Color(0xFF6EE7B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final polarStrokePaint = Paint()
      ..color = dormant ? const Color(0xFFE2E8F0) : const Color(0xFFD1FAE5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    for (var i = 0; i < paths.length; i++) {
      final isAntarctica = i == paths.length - 1;
      canvas.drawPath(paths[i], isAntarctica ? polarPaint : landPaint);
      canvas.drawPath(
        paths[i],
        isAntarctica ? polarStrokePaint : coastStrokePaint,
      );
    }

    // 5. Biome accents & urban network hubs
    if (!dormant) {
      const accents = [
        (lon: 14.0, lat: 22.0, r: 24.0, col: Color(0x5CFACC15)),
        (lon: 46.0, lat: 24.0, r: 15.0, col: Color(0x4DF59E0B)),
        (lon: 108.0, lat: 33.0, r: 22.0, col: Color(0x6B84CC16)),
        (lon: -102.0, lat: 40.0, r: 23.0, col: Color(0x57A3E635)),
        (lon: -60.0, lat: -8.0, r: 22.0, col: Color(0x6B34D399)),
        (lon: 134.0, lat: -25.0, r: 16.0, col: Color(0x57FBBF24)),
      ];
      for (final a in accents) {
        final c = _toCanvasXY(a.lon, a.lat);
        final p = Paint()
          ..shader = ui.Gradient.radial(
            c,
            a.r,
            [a.col, const Color(0x0010B981)],
          );
        canvas.drawCircle(c, a.r, p);
      }

      const hubs = [
        (111.5, 32.5),
        (116.4, 39.9),
        (121.5, 31.2),
        (114.2, 22.3),
        (139.7, 35.7),
        (127.0, 37.5),
        (103.8, 1.3),
        (8.7, 50.1),
        (-0.1, 51.5),
        (-74.0, 40.7),
        (-118.2, 34.1),
        (150.2, -33.9),
        (-46.6, -23.5),
        (55.3, 25.3),
      ];
      for (final (lon, lat) in hubs) {
        final c = _toCanvasXY(lon, lat);
        final p = Paint()
          ..shader = ui.Gradient.radial(
            c,
            4.2,
            const [
              Color(0xFFFEF08A),
              Color(0xD967E8F9),
              Color(0x0022D3EE),
            ],
            const [0.0, 0.4, 1.0],
          );
        canvas.drawCircle(c, 4.2, p);
      }
    }

    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(textureWidth, textureHeight);
    } finally {
      picture.dispose();
    }
  }
}

/// Pre-allocated unit-sphere geometry & reusable per-frame typed buffers (0 GC).
class _EarthRenderScratch {
  _EarthRenderScratch() {
    var vIdx = 0;
    final origin = latLonToUnitVec3(kEarthOriginLon, kEarthOriginLat);
    for (var iy = 0; iy <= rows; iy++) {
      final vFrac = iy / rows;
      final theta = vFrac * math.pi;
      final sinT = math.sin(theta);
      final cosT = math.cos(theta);
      final texY = vFrac * _EarthSharedGpuAssets.textureHeight;

      for (var ix = 0; ix <= cols; ix++) {
        final uFrac = ix / cols;
        final phi = uFrac * math.pi * 2.0;
        final nx = -sinT * math.cos(phi);
        final ny = cosT;
        final nz = sinT * math.sin(phi);

        final o3 = vIdx * 3;
        unitNormals[o3] = nx;
        unitNormals[o3 + 1] = ny;
        unitNormals[o3 + 2] = nz;

        final o2 = vIdx * 2;
        texCoords[o2] = uFrac * _EarthSharedGpuAssets.textureWidth;
        texCoords[o2 + 1] = texY;

        final dx = nx - origin.x;
        final dy = ny - origin.y;
        final dz = nz - origin.z;
        sweepDistFromOrigin[vIdx] = math.sqrt(dx * dx + dy * dy + dz * dz) * 0.5;
        vIdx++;
      }
    }
  }

  static const int cols = 32;
  static const int rows = 20;
  static const int stride = cols + 1;
  static const int vertexCount = stride * (rows + 1);
  static const int maxIndexCount = cols * rows * 6;
  static const int arcSegmentCount = 28;

  final Float32List unitNormals = Float32List(vertexCount * 3);
  final Float32List texCoords = Float32List(vertexCount * 2);
  final Float32List sweepDistFromOrigin = Float32List(vertexCount);

  final Float32List screenPositions = Float32List(vertexCount * 2);
  final Int32List dormantColors = Int32List(vertexCount);
  final Int32List colorfulColors = Int32List(vertexCount);
  final Int32List sweepColors = Int32List(vertexCount);
  final Uint16List frontIndices = Uint16List(maxIndexCount);
  final List<Offset?> arcScreenPoints =
      List<Offset?>.filled(arcSegmentCount + 1, null);
  int frontIndexCount = 0;

  // Cached radial shaders to eliminate steady-state gradient allocations.
  ui.Shader? shadowShader;
  Offset? shadowCenter;
  double shadowRadius = -1;
  double shadowMix = -1;
  bool? shadowDark;

  ui.Shader? atmoShader;
  Offset? atmoCenter;
  double atmoRadius = -1;
  double atmoMix = -1;
  bool? atmoHovered;

  ui.Shader? glintShader;
  Offset? glintOffset;
  double glintRadius = -1;
  double glintMix = -1;
}

class _EarthArcSpec {
  _EarthArcSpec({
    required this.originCode,
    required this.targetCode,
    required this.points,
    required this.baseYaw,
    required this.basePitch,
  });

  final String originCode;
  final String targetCode;
  final List<EarthVec3> points;
  final double baseYaw;
  final double basePitch;

  static _EarthArcSpec build({
    required String targetCode,
  }) {
    final normalizedTarget = targetCode.toUpperCase();
    final destCoord = kEarthCountryCentroids[normalizedTarget] ??
        kEarthCountryCentroids[kEarthDefaultExitCountryCode]!;
    final vStart = latLonToUnitVec3(kEarthOriginLon, kEarthOriginLat);
    var vEnd = latLonToUnitVec3(destCoord.lon, destCoord.lat);
    var angle = vStart.angleTo(vEnd);
    if (angle < 1e-4) {
      // Safeguard against degenerate CN -> CN route producing zero-length arc.
      final fallback = kEarthCountryCentroids[kEarthDefaultExitCountryCode]!;
      vEnd = latLonToUnitVec3(fallback.lon, fallback.lat);
      angle = vStart.angleTo(vEnd);
    }

    final midSum = vStart + vEnd;
    final midDir = midSum.lengthSq > 0.01
        ? midSum.normalized()
        : const EarthVec3(0, 1, 0);

    var orthoRaw = vStart.cross(vEnd);
    if (orthoRaw.lengthSq <= 1e-6) {
      orthoRaw = const EarthVec3(0, 1, 0).cross(vStart);
    }
    final ortho = orthoRaw.normalized();

    final shortRatio = 1.0 - (angle / 0.9).clamp(0.0, 1.0);
    final longRatio = (angle / 2.2).clamp(0.0, 1.0);
    final lift = 0.36 + (0.46 - 0.36) * longRatio;

    // Rodrigues rotation axis to interpolate along great circle without alloc bloat.
    final axis = vStart.cross(vEnd).normalized();
    const segs = _EarthRenderScratch.arcSegmentCount;
    final pts = List<EarthVec3>.generate(segs + 1, (i) {
      final t = i / segs;
      final subAngle = angle * t;
      final cosA = math.cos(subAngle);
      final sinA = math.sin(subAngle);
      final axisCrossV = axis.cross(vStart);
      final axisDotV = axis.dot(vStart);
      final dir = vStart * cosA +
          axisCrossV * sinA +
          axis * (axisDotV * (1.0 - cosA));

      final archSine = math.sin(math.pi * t);
      final bowed = EarthVec3(
        dir.x + ortho.x * 0.14 * shortRatio * archSine,
        dir.y +
            ortho.y * 0.14 * shortRatio * archSine +
            (0.08 + 0.10 * longRatio) * archSine,
        dir.z + ortho.z * 0.14 * shortRatio * archSine,
      ).normalized();
      final radius = 1.018 + lift * math.pow(archSine, 0.78);
      return bowed * radius;
    }, growable: false);

    final framing = computeEarthFramingAngles(
      midDir,
      pitchBias: angle > 1.2 ? -0.22 : -0.14,
    );

    return _EarthArcSpec(
      originCode: kEarthOriginCountryCode,
      targetCode: normalizedTarget,
      points: pts,
      baseYaw: framing.baseYaw,
      basePitch: framing.basePitch,
    );
  }

  EarthVec3 sampleAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final maxIdx = points.length - 1;
    final scaled = clamped * maxIdx;
    final idx0 = scaled.floor().clamp(0, maxIdx - 1);
    final idx1 = (idx0 + 1).clamp(0, maxIdx);
    final frac = scaled - idx0;
    final p0 = points[idx0];
    final p1 = points[idx1];
    return EarthVec3(
      p0.x + (p1.x - p0.x) * frac,
      p0.y + (p1.y - p0.y) * frac,
      p0.z + (p1.z - p0.z) * frac,
    );
  }
}

/// Pure circle-aware hit proxy:
/// - `rNorm > 1.0` (outer corners outside orb): passes clicks/taps through.
/// - `interactiveRatio < rNorm <= 1.0` (feathered rim): absorbs stray taps without toggling.
/// - `rNorm <= interactiveRatio` (core Earth orb): accepts tap/drag.
class _CircularEarthHitBox extends SingleChildRenderObjectWidget {
  const _CircularEarthHitBox({
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCircularEarthHitBox();
}

class _RenderCircularEarthHitBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final radius = math.min(cx, cy);
    if (radius <= 0) return false;
    final dx = position.dx - cx;
    final dy = position.dy - cy;
    if (dx * dx + dy * dy > radius * radius) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// Interactive 3D naked Earth proxy master switch (`CN -> ExitCountry`).
class EarthProxySwitch extends StatefulWidget {
  const EarthProxySwitch({
    super.key,
    required this.isRunning,
    required this.pendingTarget,
    required this.startCancelable,
    required this.canPress,
    required this.semanticsLabel,
    required this.onToggle,
    this.diameter = 152.0,
    this.fallbackCountryCode,
    this.surfaceKey,
    this.railKey,
    this.thumbKey,
    this.continuousAnimationInTests = false,
  });

  final bool isRunning;
  final bool? pendingTarget;
  final bool startCancelable;
  final bool canPress;
  final String semanticsLabel;
  final VoidCallback? onToggle;
  final double diameter;
  final String? fallbackCountryCode;
  final Key? surfaceKey;
  final Key? railKey;
  final Key? thumbKey;
  final bool continuousAnimationInTests;

  @visibleForTesting
  static int get debugSharedTextureRasterizeCount =>
      _EarthSharedGpuAssets.rasterizeCount;

  @visibleForTesting
  static EarthProxySwitchDebugSnapshot? debugSnapshotOf(BuildContext context) {
    if (context is StatefulElement && context.state is _EarthProxySwitchState) {
      return (context.state as _EarthProxySwitchState)._debugSnapshot();
    }
    return null;
  }

  @override
  State<EarthProxySwitch> createState() => _EarthProxySwitchState();
}

class _EarthProxySwitchState extends State<EarthProxySwitch>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _packetCount = 5;
  static const double _dragThresholdPx = 5.0;
  static const double _interactiveCoreRatio = 0.84;
  static const double _steadyFrameStepSec = 0.0315; // ~30fps steady throttling
  static final bool _runningInFlutterTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  late final _EarthSharedGpuAssets _gpuAssets;
  late final _EarthRenderScratch _scratch;
  late final ValueNotifier<int> _frameNotifier;
  late final Ticker _ticker;

  late _EarthArcSpec _arcSpec;
  String _resolvedTargetCode = kEarthDefaultExitCountryCode;

  // Animation & physics scalars
  double _activeMix = 0.0;
  double _targetMix = 0.0;
  double _sweepProgress = 0.0;
  double _lineReveal = 0.0;
  double _scaleSpring = 1.0;
  double _scaleVel = 0.0;
  double _targetRipple = 0.0;
  double _yaw = 0.0;
  double _pitch = 0.18;
  double _userRotVelocity = 0.0;
  double _lastDragTime = -10.0;
  double _elapsed = 0.0;
  bool _hasPendingRecenter = false;
  final List<double> _packetPhases = List<double>.generate(
    _packetCount,
    (i) => i / _packetCount,
  );

  // Power & lifecycle gates
  bool _tickerModeEnabled = true;
  bool _appPausedOrHidden = false;
  bool _reduceMotion = false;
  Duration? _lastTickElapsed;
  double _steadyAccumulatorSec = 0.0;
  int _paintCount = 0;

  // Pointer & focus state
  int? _activePointerId;
  Offset _pointerDownLocal = Offset.zero;
  Offset _pointerLastLocal = Offset.zero;
  bool _pointerDragging = false;
  bool _pointerStartedInCore = false;
  bool _isFocused = false;
  bool _isHovered = false;

  bool get _visualActive => widget.isRunning || widget.pendingTarget != null;

  bool get _hasFiniteTransitionPending {
    if (_reduceMotion) return false;
    if ((_activeMix - _targetMix).abs() > 0.004) return true;
    if ((1.0 - _scaleSpring).abs() > 0.002 || _scaleVel.abs() > 0.008) {
      return true;
    }
    if (_pointerDragging || _userRotVelocity.abs() > 0.0004) return true;
    if (_targetMix > 0.5) {
      if (_sweepProgress < 0.996 || _lineReveal < 0.996) return true;
      if (_hasPendingRecenter) return true;
      final allowSway =
          !_runningInFlutterTest || widget.continuousAnimationInTests;
      final desiredYaw = _arcSpec.baseYaw +
          (allowSway ? math.sin(_elapsed * 0.55) * 0.09 : 0.0);
      final desiredPitch = _arcSpec.basePitch +
          (allowSway ? math.cos(_elapsed * 0.42) * 0.03 : 0.0);
      final dy = math.atan2(
        math.sin(desiredYaw - _yaw),
        math.cos(desiredYaw - _yaw),
      );
      final settleEps = allowSway ? 0.02 : 0.006;
      if (dy.abs() > settleEps || (desiredPitch - _pitch).abs() > settleEps) {
        return true;
      }
    } else {
      if (_lineReveal > 0.004 || _targetRipple > 0.004) return true;
    }
    return false;
  }

  bool get _shouldTickerRun {
    if (!mounted) return false;
    if (!_tickerModeEnabled || _appPausedOrHidden || _reduceMotion) {
      return false;
    }
    if (_hasFiniteTransitionPending) return true;
    if (_targetMix > 0.5 &&
        (!_runningInFlutterTest || widget.continuousAnimationInTests)) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gpuAssets = _EarthSharedGpuAssets.ensureInitialized();
    _scratch = _EarthRenderScratch();
    _frameNotifier = ValueNotifier<int>(0);
    _ticker = createTicker(_onTick);

    _resolvedTargetCode = _resolveTargetCountryCode();
    _arcSpec = _EarthArcSpec.build(targetCode: _resolvedTargetCode);

    final active = _visualActive;
    _activeMix = active ? 1.0 : 0.0;
    _targetMix = active ? 1.0 : 0.0;
    _sweepProgress = active ? 1.0 : 0.0;
    _lineReveal = active ? 1.0 : 0.0;
    _yaw = _arcSpec.baseYaw;
    _pitch = _arcSpec.basePitch;

    detectionState.state.addListener(_onDetectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextTickerEnabled = TickerMode.of(context);
    final nextReduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final changed =
        nextTickerEnabled != _tickerModeEnabled || nextReduceMotion != _reduceMotion;
    _tickerModeEnabled = nextTickerEnabled;
    _reduceMotion = nextReduceMotion;
    if (_reduceMotion) {
      _snapToTargetImmediately();
    }
    if (changed || !_ticker.isActive) {
      _syncTickerState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextHidden = switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        true,
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
    };
    if (nextHidden != _appPausedOrHidden) {
      _appPausedOrHidden = nextHidden;
      _syncTickerState();
    }
  }

  @override
  void didUpdateWidget(covariant EarthProxySwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.isRunning || oldWidget.pendingTarget != null;
    final isActive = _visualActive;
    if (wasActive != isActive) {
      _targetMix = isActive ? 1.0 : 0.0;
      if (_reduceMotion) {
        _snapToTargetImmediately();
      } else {
        _scaleSpring = 0.90;
        _scaleVel = 2.6;
        if (isActive) {
          _sweepProgress = 0.0;
          _lineReveal = 0.0;
          _hasPendingRecenter = false;
        }
      }
    }
    if (oldWidget.fallbackCountryCode != widget.fallbackCountryCode ||
        oldWidget.continuousAnimationInTests != widget.continuousAnimationInTests ||
        wasActive != isActive) {
      _refreshResolvedTargetCountry();
    }
    _syncTickerState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    detectionState.state.removeListener(_onDetectionChanged);
    _ticker.dispose();
    _frameNotifier.dispose();
    super.dispose();
  }

  void _onDetectionChanged() {
    _refreshResolvedTargetCountry();
  }

  String _resolveTargetCountryCode() {
    final explicitFallback = _normalizeSupportedCountry(
      widget.fallbackCountryCode,
    );
    final inferredFallback =
        explicitFallback ?? _inferActiveNodeCountryFromGlobalState();
    final detectedCode = _normalizeSupportedCountry(
      detectionState.state.value.ipInfo?.countryCode,
    );

    if (_visualActive) {
      if (detectedCode != null) {
        if (detectedCode != kEarthOriginCountryCode) {
          return detectedCode;
        }
        // Guard against stale domestic direct IP while core is connecting.
        if (inferredFallback != null &&
            inferredFallback != kEarthOriginCountryCode) {
          return inferredFallback;
        }
      }
      if (inferredFallback != null &&
          inferredFallback != kEarthOriginCountryCode) {
        return inferredFallback;
      }
      return kEarthDefaultExitCountryCode;
    }

    if (inferredFallback != null &&
        inferredFallback != kEarthOriginCountryCode) {
      return inferredFallback;
    }
    if (detectedCode != null && detectedCode != kEarthOriginCountryCode) {
      return detectedCode;
    }
    return kEarthDefaultExitCountryCode;
  }

  static String? _normalizeSupportedCountry(String? raw) {
    final normalized = normalizeIsoCountryCode(raw);
    if (normalized == null) return null;
    if (!kEarthCountryCentroids.containsKey(normalized)) return null;
    return normalized;
  }

  static String? _inferActiveNodeCountryFromGlobalState() {
    if (!globalState.isAppStateInitialized || !globalState.isConfigInitialized) {
      return null;
    }
    final profile = globalState.config.currentProfile;
    if (profile == null) return null;
    final preferredGroup = profile.currentGroupName;
    final groups = globalState.appState.groups;

    String? activeCandidate;
    if (groups.isNotEmpty) {
      Group? targetGroup;
      if (preferredGroup != null) {
        targetGroup =
            groups.where((g) => g.name == preferredGroup).firstOrNull;
      }
      targetGroup ??=
          groups.where((g) => g.type == GroupType.Selector).firstOrNull;
      if (targetGroup != null) {
        final selected = (targetGroup.type == GroupType.Selector
                ? profile.selectedMap[targetGroup.name]
                : null) ??
            targetGroup.now ??
            profile.selectedMap[targetGroup.name];
        if (selected != null && !isManagedSmartGroupName(selected)) {
          activeCandidate = selected;
        }
      }
    }
    activeCandidate ??= preferredGroup != null
        ? profile.selectedMap[preferredGroup]
        : profile.selectedMap.values.firstOrNull;
    if (activeCandidate == null || isManagedSmartGroupName(activeCandidate)) {
      return null;
    }
    return _normalizeSupportedCountry(
      inferCountryCodeFromText(activeCandidate),
    );
  }

  void _refreshResolvedTargetCountry() {
    final nextCode = _resolveTargetCountryCode();
    if (nextCode == _resolvedTargetCode) return;
    _resolvedTargetCode = nextCode;
    _arcSpec = _EarthArcSpec.build(targetCode: nextCode);
    _hasPendingRecenter = false;
    if (_reduceMotion) {
      _snapToTargetImmediately();
    } else if (_visualActive) {
      _lineReveal = 0.0;
      _scaleSpring = 0.96;
      _scaleVel = 1.4;
    } else {
      _yaw = _arcSpec.baseYaw;
      _pitch = _arcSpec.basePitch;
    }
    _frameNotifier.value++;
    _syncTickerState();
  }

  void _snapToTargetImmediately() {
    _activeMix = _targetMix;
    _sweepProgress = _targetMix > 0.5 ? 1.0 : 0.0;
    _lineReveal = _targetMix > 0.5 ? 1.0 : 0.0;
    _scaleSpring = 1.0;
    _scaleVel = 0.0;
    _userRotVelocity = 0.0;
    _hasPendingRecenter = false;
    _yaw = _arcSpec.baseYaw;
    _pitch = _arcSpec.basePitch;
    _frameNotifier.value++;
  }

  void _syncTickerState() {
    final want = _shouldTickerRun;
    if (want && !_ticker.isActive) {
      _lastTickElapsed = null;
      _steadyAccumulatorSec = 0.0;
      _ticker.start();
    } else if (!want && _ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (prev == null) {
      // First tick after start/resume advances by a nominal frame step.
      _stepSimulation(0.016);
      return;
    }
    final rawDt = (elapsed - prev).inMicroseconds / 1e6;
    final dt = rawDt.clamp(0.001, 0.05);

    final transient = _hasFiniteTransitionPending;
    if (!transient) {
      _steadyAccumulatorSec += dt;
      if (_steadyAccumulatorSec < _steadyFrameStepSec) {
        return;
      }
      final stepDt = _steadyAccumulatorSec;
      _steadyAccumulatorSec = 0.0;
      _stepSimulation(stepDt);
    } else {
      _steadyAccumulatorSec = 0.0;
      _stepSimulation(dt);
    }
  }

  void _stepSimulation(double dt) {
    _elapsed += dt;

    final mixSpeed = _targetMix > 0.5 ? 4.2 : 3.2;
    _activeMix += (_targetMix - _activeMix) * math.min(1.0, dt * mixSpeed);
    if ((_activeMix - _targetMix).abs() <= 0.002) {
      _activeMix = _targetMix;
    }

    if (_targetMix > 0.5) {
      _sweepProgress = math.min(1.0, _sweepProgress + dt * 1.45);
      _lineReveal = math.min(1.0, _lineReveal + dt * 2.6);
    } else {
      _lineReveal = math.max(0.0, _lineReveal - dt * 3.8);
      if (_lineReveal <= 0.001) {
        _sweepProgress = 0.0;
      }
    }

    final springForce = (1.0 - _scaleSpring) * 85.0;
    _scaleVel = (_scaleVel + springForce * dt) * math.exp(-8.5 * dt);
    _scaleSpring += _scaleVel * dt;
    if ((1.0 - _scaleSpring).abs() <= 0.001 && _scaleVel.abs() <= 0.005) {
      _scaleSpring = 1.0;
      _scaleVel = 0.0;
    }

    if (!_pointerDragging) {
      if (_targetMix > 0.5) {
        final holdElapsed = _elapsed - _lastDragTime;
        if (!_hasPendingRecenter || holdElapsed > 1.8) {
          final allowSway =
              !_runningInFlutterTest || widget.continuousAnimationInTests;
          final swayYaw = allowSway ? math.sin(_elapsed * 0.55) * 0.09 : 0.0;
          final swayPitch = allowSway ? math.cos(_elapsed * 0.42) * 0.03 : 0.0;
          final desiredYaw = _arcSpec.baseYaw + swayYaw;
          final desiredPitch = _arcSpec.basePitch + swayPitch;
          final dy = math.atan2(
            math.sin(desiredYaw - _yaw),
            math.cos(desiredYaw - _yaw),
          );
          final dp = desiredPitch - _pitch;
          final damp = math.min(1.0, dt * 5.6);
          _yaw += dy * damp;
          _pitch += dp * damp;
          _userRotVelocity = 0.0;
          if (_hasPendingRecenter && dy.abs() <= 0.006 && dp.abs() <= 0.006) {
            _yaw = desiredYaw;
            _pitch = desiredPitch;
            _hasPendingRecenter = false;
          }
        } else {
          _yaw += _userRotVelocity;
          _userRotVelocity *= math.exp(-5.0 * dt);
          if (_userRotVelocity.abs() <= 0.0002) {
            _userRotVelocity = 0.0;
          }
        }
      } else {
        _yaw += _userRotVelocity;
        _userRotVelocity *= math.exp(-5.0 * dt);
        if (_userRotVelocity.abs() <= 0.0002) {
          _userRotVelocity = 0.0;
        }
      }
    }

    _targetRipple = math.max(0.0, _targetRipple - dt * 2.2);

    final runParticles = _activeMix > 0.03 &&
        _lineReveal > 0.05 &&
        (!_runningInFlutterTest || widget.continuousAnimationInTests);
    if (runParticles) {
      final flowRate = 0.48 * 1.2 * (0.3 + 0.7 * _activeMix);
      for (var p = 0; p < _packetCount; p++) {
        _packetPhases[p] += dt * flowRate;
        if (_packetPhases[p] >= 1.0) {
          _packetPhases[p] -= 1.0;
          _targetRipple = 1.0;
        }
      }
    }

    _frameNotifier.value++;

    if (!_shouldTickerRun && _ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointerId != null) return;
    _activePointerId = event.pointer;
    _pointerDownLocal = event.localPosition;
    _pointerLastLocal = event.localPosition;
    _pointerDragging = false;

    final half = widget.diameter * 0.5;
    final dx = event.localPosition.dx - half;
    final dy = event.localPosition.dy - half;
    final rNorm = math.sqrt(dx * dx + dy * dy) / math.max(1.0, half);
    _pointerStartedInCore = rNorm <= _interactiveCoreRatio;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId) return;
    final totalDelta = event.localPosition - _pointerDownLocal;
    if (!_pointerDragging && totalDelta.distance >= _dragThresholdPx) {
      _pointerDragging = true;
      _hasPendingRecenter = true;
      _userRotVelocity = 0.0;
      setState(() {});
    }
    if (_pointerDragging) {
      final step = event.localPosition - _pointerLastLocal;
      _yaw += step.dx * 0.0085;
      _pitch = (_pitch + step.dy * 0.006).clamp(-0.65, 0.75);
      _userRotVelocity = step.dx * 0.003;
      _lastDragTime = _elapsed;
      _frameNotifier.value++;
    }
    _pointerLastLocal = event.localPosition;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) return;
    final wasDragging = _pointerDragging;
    final inCore = _pointerStartedInCore;
    _activePointerId = null;
    _pointerStartedInCore = false;
    if (wasDragging) {
      _pointerDragging = false;
      _lastDragTime = _elapsed;
      _hasPendingRecenter = true;
      setState(() {});
      _syncTickerState();
      return;
    }
    if (inCore && widget.canPress) {
      widget.onToggle?.call();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    final wasDragging = _pointerDragging;
    _activePointerId = null;
    _pointerDragging = false;
    _pointerStartedInCore = false;
    if (wasDragging) {
      _lastDragTime = _elapsed;
      _hasPendingRecenter = true;
      setState(() {});
      _syncTickerState();
    }
  }

  EarthProxySwitchDebugSnapshot _debugSnapshot() =>
      EarthProxySwitchDebugSnapshot(
        originCountryCode: _arcSpec.originCode,
        targetCountryCode: _arcSpec.targetCode,
        yaw: _yaw,
        pitch: _pitch,
        activeMix: _activeMix,
        sweepProgress: _sweepProgress,
        lineReveal: _lineReveal,
        targetRipple: _targetRipple,
        isTickerActive: _ticker.isActive,
        visualActive: _visualActive,
        paintCount: _paintCount,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBusy = widget.pendingTarget != null;
    final isPendingStart = widget.pendingTarget ?? false;
    final busyText = isPendingStart
        ? appLocalizations.tunStatusStarting
        : appLocalizations.tunStatusStopping;

    final cursor = _pointerDragging
        ? SystemMouseCursors.grabbing
        : (widget.canPress ? SystemMouseCursors.grab : SystemMouseCursors.basic);

    final Widget content = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: MouseRegion(
            cursor: cursor,
            onEnter: (_) {
              if (!_isHovered) setState(() => _isHovered = true);
            },
            onExit: (_) {
              if (_isHovered) setState(() => _isHovered = false);
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: RepaintBoundary(
                child: CustomPaint(
                  key: widget.surfaceKey,
                  painter: _EarthSwitchPainter(
                    state: this,
                    repaint: _frameNotifier,
                    isDark: isDark,
                    focusColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
          if (isBusy)
            Positioned(
              bottom: 6,
              child: IgnorePointer(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.diameter - 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF0F172A) : Colors.white)
                          .withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (isPendingStart
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B))
                            .withValues(alpha: 0.65),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        busyText,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPendingStart
                              ? (isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF047857))
                              : (isDark
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFFB45309)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );

    return Semantics(
      container: true,
      button: true,
      enabled: widget.canPress,
      toggled: widget.isRunning,
      label: widget.semanticsLabel,
      onTap: widget.canPress ? widget.onToggle : null,
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        child: _CircularEarthHitBox(
          child: FocusableActionDetector(
            enabled: widget.canPress,
            onShowFocusHighlight: (value) {
              final isKeyboardMode = FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional;
              final effectiveFocus = value && isKeyboardMode;
              if (_isFocused != effectiveFocus) {
                setState(() => _isFocused = effectiveFocus);
                _frameNotifier.value++;
              }
            },
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (widget.canPress) {
                    widget.onToggle?.call();
                  }
                  return null;
                },
              ),
            },
            child: ExcludeSemantics(child: content),
          ),
        ),
      ),
    );
  }
}

class _EarthSwitchPainter extends CustomPainter {
  _EarthSwitchPainter({
    required this.state,
    required Listenable repaint,
    required this.isDark,
    required this.focusColor,
  }) : super(repaint: repaint);

  static const double _camY = 0.32;
  static const double _camZ = 5.02;
  static const double _camDist = 5.030188863253546; // sqrt(0.32^2 + 5.02^2)
  static const double _fwdY = -_camY / _camDist;
  static const double _fwdZ = -_camZ / _camDist;
  static const double _upY = -_fwdZ;
  static const double _upZ = _fwdY;
  static const double _invTanHalfFov = 3.7320508075688776; // 1 / tan(15 deg)

  static const double _lightX = 0.4913;
  static const double _lightY = 0.5806;
  static const double _lightZ = 0.6431;

  final _EarthProxySwitchState state;
  final bool isDark;
  final Color focusColor;

  final Paint _baseDormantPaint = Paint()
    ..filterQuality = FilterQuality.medium;
  final Paint _baseColorfulPaint = Paint()
    ..filterQuality = FilterQuality.medium;
  final Paint _atmoPaint = Paint();
  final Paint _shadowPaint = Paint();
  final Paint _glintPaint = Paint();
  final Paint _rimPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _sheathPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _corePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _beaconPaint = Paint()..style = PaintingStyle.fill;
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _particlePaint = Paint()..style = PaintingStyle.fill;
  final Paint _focusPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    state._paintCount++;
    final side = math.min(size.width, size.height);
    if (side <= 8) return;

    final center = Offset(size.width * 0.5, size.height * 0.5);
    final activeMix = state._activeMix.clamp(0.0, 1.0);
    final sweepProgress = state._sweepProgress.clamp(0.0, 1.0);
    final springScale = state._scaleSpring.clamp(0.75, 1.15);
    final earthCenterProjRadius = (side * 0.5) * (_invTanHalfFov / _camDist) * springScale;

    // 1. Soft bottom planetary drop shadow
    _paintDropShadow(canvas, center, earthCenterProjRadius, activeMix);

    // 2. Smooth-feathered R=1.18 atmosphere halo (reaches alpha=0 well before box edge)
    _paintAtmosphere(canvas, center, earthCenterProjRadius, activeMix);

    // 3. Textured 3D UV sphere via pre-allocated Vertices.raw + single/dual GPU calls
    _paintSphereMesh(
      canvas: canvas,
      center: center,
      halfViewport: side * 0.5 * springScale,
      activeMix: activeMix,
      sweepProgress: sweepProgress,
    );

    // 4. Subtle fresnel limb glow & ocean solar glint
    _paintSpecularAndRim(
      canvas: canvas,
      center: center,
      radius: earthCenterProjRadius,
      activeMix: activeMix,
    );

    // 5. Elevated 3D great-circle route, origin/destination beacons & comet-tail particles
    _paintRouteAndParticles(
      canvas: canvas,
      center: center,
      halfViewport: side * 0.5 * springScale,
      earthRadiusPx: earthCenterProjRadius,
      activeMix: activeMix,
    );

    // 6. Optional keyboard-only focus ring
    if (state._isFocused) {
      _focusPaint.color = focusColor.withValues(alpha: 0.72);
      canvas.drawCircle(
        center,
        earthCenterProjRadius * 1.14,
        _focusPaint,
      );
    }
  }

  void _paintDropShadow(
    Canvas canvas,
    Offset center,
    double earthRadiusPx,
    double activeMix,
  ) {
    final scratch = state._scratch;
    final shadowCenter = Offset(center.dx, center.dy + earthRadiusPx * 0.96);
    final shadowRadius = earthRadiusPx * 0.94;
    final qMix = (activeMix * 100.0).roundToDouble() / 100.0;
    if (scratch.shadowShader == null ||
        scratch.shadowCenter != shadowCenter ||
        (scratch.shadowRadius - shadowRadius).abs() > 0.25 ||
        scratch.shadowMix != qMix ||
        scratch.shadowDark != isDark) {
      final coreColor = Color.lerp(
        isDark ? const Color(0x52000000) : const Color(0x300F172A),
        const Color(0x470284C7),
        qMix,
      )!;
      scratch
        ..shadowCenter = shadowCenter
        ..shadowRadius = shadowRadius
        ..shadowMix = qMix
        ..shadowDark = isDark
        ..shadowShader = ui.Gradient.radial(
          shadowCenter,
          shadowRadius,
          [coreColor, coreColor.withValues(alpha: 0.0)],
        );
    }
    _shadowPaint.shader = scratch.shadowShader;
    canvas.save();
    canvas.translate(shadowCenter.dx, shadowCenter.dy);
    canvas.scale(1.12, 0.26);
    canvas.translate(-shadowCenter.dx, -shadowCenter.dy);
    canvas.drawCircle(shadowCenter, shadowRadius, _shadowPaint);
    canvas.restore();
  }

  void _paintAtmosphere(
    Canvas canvas,
    Offset center,
    double earthRadiusPx,
    double activeMix,
  ) {
    final scratch = state._scratch;
    final atmoRadius = earthRadiusPx * 1.18;
    final qMix = (activeMix * 100.0).roundToDouble() / 100.0;
    if (scratch.atmoShader == null ||
        scratch.atmoCenter != center ||
        (scratch.atmoRadius - atmoRadius).abs() > 0.25 ||
        scratch.atmoMix != qMix ||
        scratch.atmoHovered != state._isHovered) {
      final hoverGain = state._isHovered ? 1.12 : 1.0;
      final strength = (0.32 + (0.86 - 0.32) * qMix) * hoverGain;
      final glowColor = Color.lerp(
        const Color(0xFF7A8FA6),
        const Color(0xFF10C8B8),
        qMix,
      )!;
      scratch
        ..atmoCenter = center
        ..atmoRadius = atmoRadius
        ..atmoMix = qMix
        ..atmoHovered = state._isHovered
        ..atmoShader = ui.Gradient.radial(
          center,
          atmoRadius,
          [
            glowColor.withValues(alpha: (0.84 * strength).clamp(0.0, 1.0)),
            glowColor.withValues(alpha: (0.86 * strength).clamp(0.0, 1.0)),
            glowColor.withValues(alpha: (0.58 * strength).clamp(0.0, 1.0)),
            glowColor.withValues(alpha: (0.28 * strength).clamp(0.0, 1.0)),
            glowColor.withValues(alpha: (0.08 * strength).clamp(0.0, 1.0)),
            glowColor.withValues(alpha: 0.0),
          ],
          const [0.0, 0.84, 0.895, 0.935, 0.975, 1.0],
        );
    }
    _atmoPaint.shader = scratch.atmoShader;
    canvas.drawCircle(center, atmoRadius, _atmoPaint);
  }

  void _paintSphereMesh({
    required Canvas canvas,
    required Offset center,
    required double halfViewport,
    required double activeMix,
    required double sweepProgress,
  }) {
    final scratch = state._scratch;
    final cosY = math.cos(state._yaw);
    final sinY = math.sin(state._yaw);
    final cosX = math.cos(state._pitch);
    final sinX = math.sin(state._pitch);

    final isSteadyOff = activeMix <= 0.01;
    final isSteadyOn = activeMix >= 0.99 && sweepProgress >= 0.99;
    final needsDormantPass = !isSteadyOn;
    final needsColorfulPass = !isSteadyOff;

    final nArr = scratch.unitNormals;
    final posArr = scratch.screenPositions;
    final dormantColors = scratch.dormantColors;
    final colorfulColors = scratch.colorfulColors;
    final sweepColors = scratch.sweepColors;
    final distArr = scratch.sweepDistFromOrigin;

    for (var i = 0; i < _EarthRenderScratch.vertexCount; i++) {
      final o3 = i * 3;
      final lx = nArr[o3];
      final ly = nArr[o3 + 1];
      final lz = nArr[o3 + 2];

      final x1 = lx * cosY + lz * sinY;
      final z1 = -lx * sinY + lz * cosY;
      final wx = x1;
      final wy = ly * cosX - z1 * sinX;
      final wz = ly * sinX + z1 * cosX;

      final camDx = wx;
      final camDy = wy - _camY;
      final camDz = wz - _camZ;
      final dotForward = camDy * _fwdY + camDz * _fwdZ;
      final dotUp = camDy * _upY + camDz * _upZ;
      final scale = (halfViewport * _invTanHalfFov) / math.max(0.5, dotForward);

      final o2 = i * 2;
      posArr[o2] = center.dx + camDx * scale;
      posArr[o2 + 1] = center.dy - dotUp * scale;

      final diff = math.max(0.0, wx * _lightX + wy * _lightY + wz * _lightZ);
      final powDiff = diff > 0.0 ? math.pow(diff, 0.85).toDouble() : 0.0;

      if (needsDormantPass) {
        final lumDormant = (0.58 + 0.42 * powDiff).clamp(0.0, 1.0);
        final c = (lumDormant * 255).round();
        dormantColors[i] = (0xFF << 24) | (c << 16) | (c << 8) | c;
      }

      if (needsColorfulPass) {
        final lambert = (0.64 + 0.36 * powDiff).clamp(0.0, 1.0);
        if (isSteadyOn) {
          final c = (lambert * 255).round();
          colorfulColors[i] = (0xFF << 24) | (c << 16) | (c << 8) | c;
        } else {
          final d = distArr[i];
          var swept = 1.0;
          if (sweepProgress < 0.99) {
            swept = 1.0 - _smoothstep(sweepProgress - 0.06, sweepProgress + 0.06, d);
          }
          final blend = math.min(activeMix, swept).clamp(0.0, 1.0);
          final waveEdge = _smoothstep(sweepProgress - 0.14, sweepProgress, d) *
              (1.0 - _smoothstep(sweepProgress, sweepProgress + 0.08, d));
          final rBoost = (lambert + waveEdge * activeMix * 0.22).clamp(0.0, 1.0);
          final gBoost = (lambert + waveEdge * activeMix * 0.55).clamp(0.0, 1.0);
          final bBoost = (lambert + waveEdge * activeMix * 0.52).clamp(0.0, 1.0);
          final a = (blend * 255).round();
          final r = (rBoost * 255).round();
          final g = (gBoost * 255).round();
          final b = (bBoost * 255).round();
          sweepColors[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
      }
    }

    final indices = scratch.frontIndices;
    var indexCount = 0;
    const stride = _EarthRenderScratch.stride;
    for (var iy = 0; iy < _EarthRenderScratch.rows; iy++) {
      final rowBase = iy * stride;
      for (var ix = 0; ix < _EarthRenderScratch.cols; ix++) {
        final a = rowBase + ix;
        final b = a + 1;
        final c = a + stride;
        final d = c + 1;

        final ax = posArr[a * 2];
        final ay = posArr[a * 2 + 1];
        final bx = posArr[b * 2];
        final by = posArr[b * 2 + 1];
        final cx = posArr[c * 2];
        final cy = posArr[c * 2 + 1];
        if ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax) > 0.0) {
          indices[indexCount++] = a;
          indices[indexCount++] = b;
          indices[indexCount++] = c;
        }

        final dx = posArr[d * 2];
        final dy = posArr[d * 2 + 1];
        if ((dx - bx) * (cy - by) - (dy - by) * (cx - bx) > 0.0) {
          indices[indexCount++] = b;
          indices[indexCount++] = d;
          indices[indexCount++] = c;
        }
      }
    }
    scratch.frontIndexCount = indexCount;
    if (indexCount < 3) return;

    final subIndices = Uint16List.sublistView(indices, 0, indexCount);

    if (needsDormantPass) {
      _baseDormantPaint.shader = state._gpuAssets.dormantShader;
      final verts = ui.Vertices.raw(
        ui.VertexMode.triangles,
        posArr,
        colors: dormantColors,
        textureCoordinates: scratch.texCoords,
        indices: subIndices,
      );
      canvas.drawVertices(verts, BlendMode.modulate, _baseDormantPaint);
      verts.dispose();
    }

    if (needsColorfulPass) {
      _baseColorfulPaint.shader = state._gpuAssets.colorfulShader;
      final verts = ui.Vertices.raw(
        ui.VertexMode.triangles,
        posArr,
        colors: isSteadyOn ? colorfulColors : sweepColors,
        textureCoordinates: scratch.texCoords,
        indices: subIndices,
      );
      canvas.drawVertices(verts, BlendMode.modulate, _baseColorfulPaint);
      verts.dispose();
    }
  }

  void _paintSpecularAndRim({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double activeMix,
  }) {
    if (activeMix > 0.02) {
      final scratch = state._scratch;
      final glintOffset = Offset(
        center.dx + radius * 0.30,
        center.dy - radius * 0.32,
      );
      final glintRadius = radius * 0.56;
      final qMix = (activeMix * 100.0).roundToDouble() / 100.0;
      if (scratch.glintShader == null ||
          scratch.glintOffset != glintOffset ||
          (scratch.glintRadius - glintRadius).abs() > 0.25 ||
          scratch.glintMix != qMix) {
        scratch
          ..glintOffset = glintOffset
          ..glintRadius = glintRadius
          ..glintMix = qMix
          ..glintShader = ui.Gradient.radial(
            glintOffset,
            glintRadius,
            [
              Color.fromRGBO(210, 248, 255, 0.24 * qMix),
              const Color(0x00D2F8FF),
            ],
          );
      }
      _glintPaint.shader = scratch.glintShader;
      canvas.drawCircle(glintOffset, glintRadius, _glintPaint);
    }

    final rimCol = Color.lerp(
      const Color(0xFF94A3B8),
      const Color(0xFF22D3EE),
      activeMix,
    )!;
    _rimPaint
      ..color = rimCol.withValues(alpha: 0.14 + 0.34 * activeMix)
      ..strokeWidth = 1.3;
    canvas.drawCircle(center, radius * 0.995, _rimPaint);
  }

  void _paintRouteAndParticles({
    required Canvas canvas,
    required Offset center,
    required double halfViewport,
    required double earthRadiusPx,
    required double activeMix,
  }) {
    final spec = state._arcSpec;
    final reveal = state._lineReveal.clamp(0.0, 1.0);
    final pts = spec.points;
    final maxIdx = ((pts.length - 1) * reveal).ceil().clamp(1, pts.length - 1);

    final screenPts = state._scratch.arcScreenPoints;
    final cosY = math.cos(state._yaw);
    final sinY = math.sin(state._yaw);
    final cosX = math.cos(state._pitch);
    final sinX = math.sin(state._pitch);

    Offset? projectIfVisible(EarthVec3 localPos) {
      final x1 = localPos.x * cosY + localPos.z * sinY;
      final z1 = -localPos.x * sinY + localPos.z * cosY;
      final wx = x1;
      final wy = localPos.y * cosX - z1 * sinX;
      final wz = localPos.y * sinX + z1 * cosX;

      if (_isOccludedByEarthSphere(wx, wy, wz)) {
        return null;
      }

      final camDx = wx;
      final camDy = wy - _camY;
      final camDz = wz - _camZ;
      final dotForward = camDy * _fwdY + camDz * _fwdZ;
      if (dotForward <= 0.3) return null;
      final dotUp = camDy * _upY + camDz * _upZ;
      final scale = (halfViewport * _invTanHalfFov) / dotForward;
      return Offset(center.dx + camDx * scale, center.dy - dotUp * scale);
    }

    for (var i = 0; i <= maxIdx; i++) {
      screenPts[i] = projectIfVisible(pts[i]);
    }

    // Draw visible segments of the 3D fiber arc
    if (reveal > 0.02 || activeMix > 0.02) {
      final standbyCol = const Color(0xFF64748B).withValues(
        alpha: 0.28 * (1.0 - activeMix),
      );
      if (activeMix > 0.03 && reveal > 0.02) {
        final sheathWidth = earthRadiusPx * 0.088;
        final coreWidth = earthRadiusPx * 0.036;
        _sheathPaint.strokeWidth = sheathWidth;
        _corePaint.strokeWidth = coreWidth;

        for (var i = 0; i < maxIdx; i++) {
          final p0 = screenPts[i];
          final p1 = screenPts[i + 1];
          if (p0 == null || p1 == null) continue;
          final segFrac = (i + 0.5) / (pts.length - 1);
          final edgeFade =
              reveal < 0.99 ? _smoothstep(reveal, reveal - 0.08, segFrac) : 1.0;
          final alphaSheath = (0.42 * activeMix * edgeFade).clamp(0.0, 1.0);
          final alphaCore = (0.92 * activeMix * edgeFade).clamp(0.0, 1.0);
          if (alphaCore <= 0.01) continue;

          _sheathPaint.color = Color.lerp(
            const Color(0xFFFBBF24),
            const Color(0xFF10B981),
            (segFrac * 2.5).clamp(0.0, 1.0),
          )!
              .withValues(alpha: alphaSheath);
          canvas.drawLine(p0, p1, _sheathPaint);

          final wave = 0.5 +
              0.5 * math.sin(segFrac * 10.0 - state._elapsed * 1.2 * 3.4);
          _corePaint.color = Color.lerp(
            const Color(0xFF38BDF8),
            const Color(0xFFE0F7FF),
            wave * 0.72,
          )!
              .withValues(alpha: alphaCore);
          canvas.drawLine(p0, p1, _corePaint);
        }
      } else if (activeMix <= 0.03) {
        _corePaint
          ..color = standbyCol
          ..strokeWidth = earthRadiusPx * 0.028;
        for (var i = 0; i < pts.length - 1; i++) {
          final p0 = projectIfVisible(pts[i]);
          final p1 = projectIfVisible(pts[i + 1]);
          if (p0 != null && p1 != null) {
            canvas.drawLine(p0, p1, _corePaint);
          }
        }
      }
    }

    // Draw origin (CN warm amber) & exit country (emerald + ripple) beacons
    final originPos = screenPts.first;
    final targetPos = projectIfVisible(pts.last);
    final orbRadius = math.max(2.0, earthRadiusPx * 0.046);

    if (originPos != null) {
      final pulse = 0.68 + 0.32 * math.sin(state._elapsed * 4.2);
      final beaconCol = Color.lerp(
        const Color(0xFF64748B),
        const Color(0xFFFBBF24),
        activeMix,
      )!;
      _beaconPaint.color = beaconCol.withValues(alpha: 0.45 + 0.52 * activeMix);
      canvas.drawCircle(originPos, orbRadius, _beaconPaint);
      if (activeMix > 0.05) {
        _ringPaint
          ..color = const Color(0xFFFBBF24)
              .withValues(alpha: pulse * activeMix * 0.85)
          ..strokeWidth = 1.4;
        canvas.drawCircle(originPos, orbRadius * 1.75, _ringPaint);
      }
    }

    if (targetPos != null) {
      final ripple = state._targetRipple.clamp(0.0, 1.0);
      final beaconCol = Color.lerp(
        const Color(0xFF64748B),
        const Color(0xFF34D399),
        activeMix,
      )!;
      _beaconPaint.color = beaconCol.withValues(alpha: 0.45 + 0.52 * activeMix);
      canvas.drawCircle(targetPos, orbRadius, _beaconPaint);
      if (activeMix > 0.05) {
        final ringRadius = orbRadius * (1.7 + ripple * 1.6);
        _ringPaint
          ..color = const Color(0xFF34D399)
              .withValues(alpha: math.max(0.42, ripple) * activeMix * 0.88)
          ..strokeWidth = 1.5;
        canvas.drawCircle(targetPos, ringRadius, _ringPaint);
      }
    }

    // Streaming comet-tail particles from CN -> ExitCountry
    if (activeMix > 0.03 && reveal > 0.05) {
      const trailSteps = 7;
      for (var p = 0; p < _EarthProxySwitchState._packetCount; p++) {
        final headT = state._packetPhases[p];
        for (var s = 0; s < trailSteps; s++) {
          final t = headT - s * 0.018;
          if (t < 0.0 || t > reveal) continue;
          final ptScreen = projectIfVisible(spec.sampleAt(t));
          if (ptScreen == null) continue;

          final frac = s / (trailSteps - 1);
          final edgeFade = t > 0.92 ? (1.0 - t) / 0.08 : 1.0;
          final alpha = ((1.0 - frac * 0.84) * activeMix * edgeFade)
              .clamp(0.0, 1.0);
          if (alpha <= 0.02) continue;

          final col = s == 0
              ? Colors.white
              : (frac < 0.45
                  ? Color.lerp(const Color(0xFF38BDF8), Colors.white, 0.35)!
                  : Color.lerp(
                      const Color(0xFF38BDF8),
                      const Color(0xFF10B981),
                      (frac - 0.45) / 0.55,
                    )!);
          final pr =
              math.max(1.2, earthRadiusPx * (s == 0 ? 0.048 : 0.036 * (1.0 - frac * 0.65))) *
                  activeMix;
          _particlePaint.color = col.withValues(alpha: alpha);
          canvas.drawCircle(ptScreen, pr, _particlePaint);
        }
      }
    }
  }

  static bool _isOccludedByEarthSphere(double wx, double wy, double wz) {
    final dx = wx;
    final dy = wy - _camY;
    final dz = wz - _camZ;
    final dd = dx * dx + dy * dy + dz * dz;
    if (dd <= 1e-6) return false;
    final tClosest = -(_camY * dy + _camZ * dz) / dd;
    if (tClosest <= 0.0 || tClosest >= 1.0) return false;
    final cx = tClosest * dx;
    final cy = _camY + tClosest * dy;
    final cz = _camZ + tClosest * dz;
    return cx * cx + cy * cy + cz * cz < 0.992;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    if (edge0 == edge1) return x >= edge1 ? 1.0 : 0.0;
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  @override
  bool shouldRepaint(covariant _EarthSwitchPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.focusColor != focusColor;
}
