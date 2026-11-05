import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';
import 'route_graph.dart';

/// Hazard types as the GSI data defines them.
enum Hazard {
  tsunami('津波', 'Tsunami'),
  earthquake('地震', 'Earthquake'),
  flood('洪水', 'Flood'),
  landslide('崖崩れ・土石流・地滑り', 'Landslide'),
  stormSurge('高潮', 'Storm surge'),
  fire('大規模な火事', 'Large fire'),
  inlandFlood('内水氾濫', 'Inland flooding'),
  volcano('火山現象', 'Volcano');

  const Hazard(this.ja, this.en);
  final String ja, en;

  static Hazard? fromKey(String key) => switch (key) {
    'tsunami' => tsunami,
    'earthquake' => earthquake,
    'flood' => flood,
    'landslide' => landslide,
    'storm_surge' => stormSurge,
    'fire' => fire,
    'inland_flood' => inlandFlood,
    'volcano' => volcano,
    _ => null,
  };
}

class EvacSite {
  EvacSite(
    this.name,
    this.address,
    this.point,
    this.emergency,
    this.hazards, {
    this.uid = '',
  });
  final String name, address;

  /// GSI 全国共通避難所・避難場所ID (共通ID), used by current facts.
  final String uid;
  final LatLng point;

  /// true: 指定緊急避難場所 (where to flee, per hazard). false: 指定避難所 (where to stay).
  final bool emergency;
  final Set<Hazard> hazards;

  /// Municipality from the address, e.g. 西宮市 or 大阪市 (GSI writes
  /// 都道府県 + 市区町村 first).
  late final String city = _city.firstMatch(address)?.group(2) ?? '';

  static final _city = RegExp(
    r'^(東京都|北海道|(?:京都|大阪)府|.{2,3}県)(.+?(?:市|郡.+?[町村]|[町村]))',
  );
}

class SiteDistance {
  SiteDistance(this.site, this.meters, this.bearing, {this.route});
  final EvacSite site;

  /// Straight-line metres.
  final double meters;
  final double bearing;

  /// The walking route, when the area has a walking graph and a route was
  /// found.
  final RouteInfo? route;

  SiteDistance withRoute(RouteInfo? route) =>
      SiteDistance(site, meters, bearing, route: route);

  /// Walking metres on the route.
  double? get walk => route?.meters;

  /// The walking route, from the current position to the site.
  List<LatLng>? get path => route?.path;

  /// A route that goes this many metres below the start is flagged. Less
  /// is within the noise of flat coastal ground.
  static const minDip = 2.0;

  /// "海抜 5 m" for the ground near the site, and how low the way goes when
  /// it dips [minDip] or more below the start. Empty without heights.
  String heightLabel(bool en) {
    final r = route, h = r?.endHeight;
    if (r == null || h == null) return '';
    final parts = [
      en ? '${_h(h)} m above sea level' : '海抜${_h(h)} m',
      if (r.dip >= minDip && r.lowest != null)
        en
            ? 'dips to ${_h(r.lowest!)} m on the way'
            : '途中で海抜${_h(r.lowest!)} mまで下がる',
    ];
    return parts.join(' · ');
  }

  static String _h(double m) =>
      m.abs() < 10 ? m.toStringAsFixed(1) : m.round().toString();

  /// Walking minutes at 60 m a minute (1 m/s): slower than everyday
  /// walking, as tsunami evacuation plans assume.
  int? get minutes => walk == null ? null : max(1, (walk! / 60).round());

  /// "Walk 850 m · about 14 min", or the straight line and direction.
  String label(bool en) {
    final w = walk;
    if (w != null) {
      return en
          ? '${_fmt(w)} walk · about $minutes min'
          : '徒歩${_fmt(w)}・約$minutes分';
    }
    return en
        ? '${_fmt(meters)} ${direction(true)} · straight line'
        : '${direction(false)}へ${_fmt(meters)} · 直線距離';
  }

  static String _fmt(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  /// 8-point compass direction in Japanese or English.
  String direction(bool en) {
    const ja = ['北', '北東', '東', '南東', '南', '南西', '西', '北西'];
    const enDirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final i = (((bearing % 360) + 22.5) ~/ 45) % 8;
    return en ? enDirs[i] : ja[i];
  }
}

/// Evacuation sites for one map area, built by tool/build_map.py.
class EvacSites {
  EvacSites._(this.meta, this.sites);

  final Map<String, String> meta;
  final List<EvacSite> sites;

  LatLng get center {
    final c = jsonDecode(meta['center']!) as List;
    return LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble());
  }

  String get notice => meta['sites_notice'] ?? '';
  String get attribution => meta['sites_attribution'] ?? '';
  String get basemapAttribution => meta['basemap_attribution'] ?? '';

  static Future<EvacSites> fromAsset(String name) async {
    final store = await DownloadStore.instance();
    return open(await store.copyBundled('maps', name));
  }

  static EvacSites open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      final sites = [
        for (final r in db.select('SELECT * FROM sites'))
          EvacSite(
            r['name'],
            r['address'] ?? '',
            LatLng(r['lat'], r['lon']),
            r['kind'] == 'emergency',
            {
              for (final k in (r['hazards'] as String).split(','))
                ?Hazard.fromKey(k),
            },
            uid: r['uid'] as String? ?? '',
          ),
      ];
      return EvacSites._(meta, sites);
    } finally {
      db.close();
    }
  }

  /// Site ids in a fixed order, shared by all devices with this map area
  /// (for the compact radio format of facts).
  List<String> get siteIds => sites.map((s) => s.uid).toList();

  EvacSite? byUid(String uid) {
    for (final s in sites) {
      if (s.uid == uid) return s;
    }
    return null;
  }

  /// The municipality the user is probably in: that of the nearest site.
  String cityAt(LatLng from) {
    const d = Distance();
    EvacSite? best;
    var bestM = double.infinity;
    for (final s in sites) {
      final m = d.as(LengthUnit.Meter, from, s.point);
      if (m < bestM) {
        bestM = m;
        best = s;
      }
    }
    return best?.city ?? '';
  }

  /// Whether [city] has any emergency site designated for [hazard] in the
  /// data. Some cities register sites without hazard types (Nishinomiya and
  /// Amagasaki have none for earthquakes), so "nearest" may lie in the next city.
  bool cityHasSiteFor(String city, Hazard hazard) => sites.any(
    (s) => s.emergency && s.city == city && s.hazards.contains(hazard),
  );

  /// Emergency sites for [hazard] (all emergency sites if null), nearest first.
  List<SiteDistance> nearest(LatLng from, {Hazard? hazard, int limit = 5}) {
    const d = Distance();
    final list = [
      for (final s in sites)
        if (s.emergency && (hazard == null || s.hazards.contains(hazard)))
          SiteDistance(
            s,
            d.as(LengthUnit.Meter, from, s.point),
            _bearing(from, s.point),
          ),
    ]..sort((a, b) => a.meters.compareTo(b.meters));
    return list.take(limit).toList();
  }

  static double _bearing(LatLng a, LatLng b) {
    final la1 = a.latitudeInRad, la2 = b.latitudeInRad;
    final dLon = b.longitudeInRad - a.longitudeInRad;
    final y = sin(dLon) * cos(la2);
    final x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}
