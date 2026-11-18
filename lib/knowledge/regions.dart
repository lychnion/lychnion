import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Which prefecture or state a position is in, offline.
///
/// From `assets/regions/regions.sqlite`, built by `tool/build_regions.py`
/// from Natural Earth admin-1 boundaries (public domain): ISO 3166-2 codes
/// such as 'JP-28' (Hyōgo) or 'US-CA', with every point of the 1:10m
/// outlines (about 1 km precision). Used to rank sources tagged for the user's region a little
/// higher ([localityBoost]). The position is only used on this device.
class RegionLookup {
  RegionLookup._(this._regions);

  final List<_Region> _regions;

  /// No regions: every lookup gives null.
  static final empty = RegionLookup._(const []);

  /// Opens the file and keeps codes, names and bounding boxes in memory;
  /// outlines are decoded only for regions whose box contains a point.
  factory RegionLookup.open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return RegionLookup._([
        for (final r in db.select(
          'SELECT code, country, name_en, name_ja, '
          'min_lon, min_lat, max_lon, max_lat, rings FROM regions',
        ))
          _Region(
            code: r['code'] as String,
            country: r['country'] as String,
            names: {
              'en': r['name_en'] as String,
              'ja': ?r['name_ja'] as String?,
            },
            minLon: (r['min_lon'] as num).toDouble(),
            minLat: (r['min_lat'] as num).toDouble(),
            maxLon: (r['max_lon'] as num).toDouble(),
            maxLat: (r['max_lat'] as num).toDouble(),
            encoded: r['rings'] as Uint8List,
          ),
      ]);
    } finally {
      db.close();
    }
  }

  int get length => _regions.length;

  /// The region code at [lat]/[lon] ('JP-28'), or null at sea or where the
  /// data has no region. Points just off the coast (within [nearDeg],
  /// about 2 km: the outlines are coarse) count for the nearest region.
  String? codeAt(double lat, double lon, {double nearDeg = 0.02}) {
    _Region? nearest;
    var nearestD = nearDeg;
    for (final r in _regions) {
      if (lon < r.minLon - nearDeg ||
          lon > r.maxLon + nearDeg ||
          lat < r.minLat - nearDeg ||
          lat > r.maxLat + nearDeg) {
        continue;
      }
      if (r.contains(lon, lat)) return r.code;
      final d = r.distance(lon, lat);
      if (d < nearestD) {
        nearestD = d;
        nearest = r;
      }
    }
    return nearest?.code;
  }

  /// Codes of [country]'s regions in code order (JP-01 … JP-47).
  List<String> regionsOf(String country) => [
    for (final r in _regions)
      if (r.country == country && !r.code.endsWith('~')) r.code,
  ]..sort();

  /// The region's name in [lang] (English when there is none), e.g. 兵庫県.
  String? nameOf(String code, String lang) {
    for (final r in _regions) {
      if (r.code == code) return r.names[lang] ?? r.names['en'];
    }
    return null;
  }
}

class _Region {
  _Region({
    required this.code,
    required this.country,
    required this.names,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
    required this.encoded,
  });

  final String code, country;
  final Map<String, String> names;
  final double minLon, minLat, maxLon, maxLat;
  final Uint8List encoded;
  List<Float64List>? _rings;

  /// Rings as [lon, lat, lon, lat, ...] (see `encode_rings` in the tool).
  List<Float64List> get rings => _rings ??= decodeRings(encoded);

  /// Even-odd rule over all rings, so holes (lakes, enclaves) work.
  bool contains(double x, double y) {
    var inside = false;
    for (final r in rings) {
      final n = r.length ~/ 2;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final xi = r[2 * i], yi = r[2 * i + 1];
        final xj = r[2 * j], yj = r[2 * j + 1];
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
          inside = !inside;
        }
      }
    }
    return inside;
  }

  /// Distance in degrees to the nearest edge (good enough for "just off
  /// the coast").
  double distance(double x, double y) {
    var best = double.infinity;
    for (final r in rings) {
      final n = r.length ~/ 2;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final d = _segment(
          x,
          y,
          r[2 * j],
          r[2 * j + 1],
          r[2 * i],
          r[2 * i + 1],
        );
        if (d < best) best = d;
      }
    }
    return best;
  }

  static double _segment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax, dy = by - ay;
    final len = dx * dx + dy * dy;
    var t = len == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx - px, cy = ay + t * dy - py;
    return math.sqrt(cx * cx + cy * cy);
  }
}

/// Decodes `encode_rings` from `tool/build_regions.py`: varint ring count;
/// per ring a varint point count, then zigzag varint deltas of lon and lat
/// in 1e-4 degrees.
List<Float64List> decodeRings(Uint8List b) {
  var pos = 0;
  int varint() {
    var shift = 0, out = 0;
    while (true) {
      final byte = b[pos++];
      out |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return out;
      shift += 7;
    }
  }

  int zigzag(int n) => (n >> 1) ^ -(n & 1);
  final rings = <Float64List>[];
  final count = varint();
  for (var r = 0; r < count; r++) {
    final n = varint();
    final ring = Float64List(n * 2);
    var x = 0, y = 0;
    for (var i = 0; i < n; i++) {
      x += zigzag(varint());
      y += zigzag(varint());
      ring[2 * i] = x / 1e4;
      ring[2 * i + 1] = y / 1e4;
    }
    rings.add(ring);
  }
  return rings;
}
