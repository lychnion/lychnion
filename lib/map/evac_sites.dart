import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';
import 'route_graph.dart';

/// Hazard types as the GSI data defines them. Names shown to people come
/// from the app texts (`hazardName`, keyed by [name]).
enum Hazard {
  tsunami,
  earthquake,
  flood,
  landslide,
  stormSurge,
  fire,
  inlandFlood,
  volcano;

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

  /// A height in metres as shown: one decimal below 10 m.
  static String formatHeight(double m) =>
      m.abs() < 10 ? m.toStringAsFixed(1) : m.round().toString();

  /// Walking minutes at 60 m a minute (1 m/s): slower than everyday
  /// walking, as tsunami evacuation plans assume.
  int? get minutes => walk == null ? null : max(1, (walk! / 60).round());

  /// 8-point compass direction as a key (`n`, `ne`, … `nw`); the app texts
  /// (`compassPoint`) name it.
  String get compassPoint {
    const points = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'];
    return points[(((bearing % 360) + 22.5) ~/ 45) % 8];
  }
}

/// Evacuation sites for one map area, built by lychnion-data/tool/build_map.py.
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
