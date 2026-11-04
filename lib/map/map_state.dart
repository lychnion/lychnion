import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../util/paths.dart';
import 'evac_sites.dart';

/// Map data and position, shared by the map tab and the answers.
class MapState extends ChangeNotifier {
  MapState({
    required this.pmtilesPath,
    required this.sitesAsset,
    this.mockLocation,
  });

  final String pmtilesPath;
  final String sitesAsset;

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
      sites = await EvacSites.fromAsset(sitesAsset);
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

  List<SiteDistance> nearest(Hazard? h, {int limit = 5}) {
    final s = sites, f = from;
    if (s == null || f == null) return const [];
    return s.nearest(f, hazard: h, limit: limit);
  }

  /// Switches the map to [h] and centres it on [point].
  void showOnMap(Hazard? h, LatLng point) {
    hazard = h;
    focus = point;
    notifyListeners();
  }
}
