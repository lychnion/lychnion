import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';

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
  EvacSite(this.name, this.address, this.point, this.emergency, this.hazards);
  final String name, address;
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
  SiteDistance(this.site, this.meters, this.bearing);
  final EvacSite site;
  final double meters;
  final double bearing;

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
          ),
      ];
      return EvacSites._(meta, sites);
    } finally {
      db.close();
    }
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
