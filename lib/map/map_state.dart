import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../facts/fact.dart';
import '../facts/fact_store.dart';
import '../util/paths.dart';
import 'evac_sites.dart';

/// Map data and position, shared by the map tab and the answers.
class MapState extends ChangeNotifier {
  MapState({
    required this.pmtilesPath,
    required this.sitesAsset,
    this.sitesPath,
    this.mockLocation,
    this.facts,
  }) {
    facts?.addListener(notifyListeners);
  }

  @override
  void dispose() {
    facts?.removeListener(notifyListeners);
    super.dispose();
  }

  /// Current facts, e.g. a shelter that is full.
  final FactStore? facts;

  /// The current status fact of a site, if any.
  Fact? statusOf(EvacSite site) => facts?.shelterStatus(site.uid);

  /// Whether to steer people away from a site (full or closed).
  bool avoid(EvacSite site) => statusOf(site)?.shelterStatus?.avoid ?? false;

  final String pmtilesPath;
  final String sitesAsset;

  /// A downloaded sites file; wins over [sitesAsset].
  final String? sitesPath;

  /// "lat,lon" for testing without a GPS fix.
  final String? mockLocation;

  EvacSites? sites;
  PmTilesVectorTileProvider? tiles;
  LatLng? here;
  bool hereIsMock = false;
  double? accuracy;
  String? error;
  Hazard? hazard = Hazard.tsunami;

  /// Where the map should move next (set by "show on map").
  LatLng? focus;

  bool get ready => sites != null && tiles != null;
  LatLng? get from => here ?? sites?.center;

  Future<void> load() async {
    try {
      final sp = sitesPath;
      sites = sp != null
          ? EvacSites.open(sp)
          : await EvacSites.fromAsset(sitesAsset);
      tiles = await PmTilesVectorTileProvider.fromSource(
        await resolvePath(pmtilesPath),
      );
      notifyListeners();
      await locate();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> locate() async {
    final mock = mockLocation;
    if (mock != null && mock.isNotEmpty) {
      final p = mock.split(',').map(double.parse).toList();
      here = LatLng(p[0], p[1]);
      hereIsMock = true;
      notifyListeners();
      return;
    }
    try {
      // GPS works without a network; only the satellite fix takes time.
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        error = 'no-permission';
        notifyListeners();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      here = LatLng(pos.latitude, pos.longitude);
      accuracy = pos.accuracy;
      focus = here;
      notifyListeners();
    } catch (_) {
      error = 'no-location';
      notifyListeners();
    }
  }

  void selectHazard(Hazard? h) {
    hazard = h;
    notifyListeners();
  }

  /// The user's city when it has no site for [h] in the data, else null.
  String? cityWithoutSiteFor(Hazard? h) {
    final s = sites, f = from;
    if (s == null || f == null || h == null) return null;
    final city = s.cityAt(f);
    return city.isEmpty || s.cityHasSiteFor(city, h) ? null : city;
  }

  /// Nearest sites for [h]. With [skipAvoided], full or closed sites are
  /// left out, so the suggestion is a place that can take people.
  List<SiteDistance> nearest(
    Hazard? h, {
    int limit = 5,
    bool skipAvoided = false,
  }) {
    final s = sites, f = from;
    if (s == null || f == null) return const [];
    final all = s.nearest(f, hazard: h, limit: limit + 20);
    return [
      for (final n in all)
        if (!skipAvoided || !avoid(n.site)) n,
    ].take(limit).toList();
  }

  /// Switches the map to [h] and centres it on [point].
  void showOnMap(Hazard? h, LatLng point) {
    hazard = h;
    focus = point;
    notifyListeners();
  }
}
