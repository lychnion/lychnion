import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../facts/fact.dart';
import '../facts/fact_store.dart';
import '../util/paths.dart';
import 'evac_sites.dart';
import 'route_graph.dart';

/// "lat,lon" subject of a point fact (blocked road, water point).
LatLng? pointOf(String subject) {
  final p = subject.split(',');
  if (p.length != 2) return null;
  final lat = double.tryParse(p[0]), lon = double.tryParse(p[1]);
  return lat == null || lon == null ? null : LatLng(lat, lon);
}

/// Map data and position, shared by the map tab and the answers.
class MapState extends ChangeNotifier {
  MapState({
    required this.pmtilesPath,
    required this.sitesAsset,
    this.sitesPath,
    this.routesPath,
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

  /// Walking graph (tool/build_routes.py). Default: next to the PMTiles
  /// file, `<id>.routes.bin`. Without it, distances are straight lines.
  final String? routesPath;

  RouteGraph? routes;

  /// Walks from the current position (normal and tsunami), kept until the
  /// position or the blocked roads change.
  final _trees = <bool, WalkTree>{};
  String? _treeKey;

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
      await _loadRoutes();
      await locate();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> _loadRoutes() async {
    final path = await resolvePath(
      routesPath ??
          pmtilesPath.replaceFirst(RegExp(r'\.pmtiles$'), '.routes.bin'),
    );
    if (!path.endsWith('.routes.bin') || !await File(path).exists()) return;
    try {
      final sw = Stopwatch()..start();
      routes = await RouteGraph.load(path);
      debugPrint(
        'routes: ${routes!.nodeCount} nodes in ${sw.elapsedMilliseconds} ms',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('routes: $e');
    }
  }

  /// Nodes near blocked roads are not walked through.
  static const blockedRadius = 25.0;

  /// Points of current blocked-road facts.
  List<LatLng> get blockedPoints => [
    for (final f in facts?.currentOf({FactKind.roadBlocked}) ?? const <Fact>[])
      ?pointOf(f.subject),
  ];

  /// Tsunami routes keep to higher ground (when the graph has heights).
  bool prefersHigh(Hazard? h) =>
      h == Hazard.tsunami &&
      ((routes?.hasHeights ?? false) || (routes?.hasFlood ?? false));

  /// Tsunami inundation at the current position ([RouteGraph.floodOf]), or
  /// null without inundation data or a position on the road network.
  int? get floodHere {
    final g = routes, f = from;
    if (g == null || !g.hasFlood || f == null) return null;
    final n = g.nearestNode(f);
    return n == null ? null : g.floodOf(n.node);
  }

  /// For tsunami: the best walk out of the inundation area, when the
  /// current position is in it or close to it.
  RouteInfo? wayOut(Hazard? h) =>
      h == Hazard.tsunami ? walksFor(h)?.wayOut : null;

  /// Best walks from the current position for hazard [h], or null without
  /// a graph.
  WalkTree? walksFor(Hazard? h) {
    final g = routes, f = from;
    if (g == null || f == null) return null;
    final blocked = blockedPoints;
    final key = '${f.latitude},${f.longitude}|${blocked.join(';')}';
    if (key != _treeKey) {
      _trees.clear();
      _treeKey = key;
    }
    final high = prefersHigh(h);
    return _trees.putIfAbsent(high, () {
      final sw = Stopwatch()..start();
      final t = g.walkFrom(
        f,
        preferHigh: high,
        blocked: {for (final p in blocked) ...g.nodesNear(p, blockedRadius)},
      );
      debugPrint(
        'routes: walk tree${high ? ' (high ground)' : ''} '
        'in ${sw.elapsedMilliseconds} ms',
      );
      return t;
    });
  }

  /// Whether routes take at least one blocked road into account.
  bool get avoidsBlocked => routes != null && blockedPoints.isNotEmpty;

  Future<void> locate() async {
    final mock = mockLocation;
    if (mock != null && mock.isNotEmpty) {
      final p = mock.split(',').map(double.parse).toList();
      here = LatLng(p[0], p[1]);
      hereIsMock = true;
      focus = here;
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

  /// Nearest sites for [h], by walking distance when the area has a
  /// walking graph, else by straight line. With [skipAvoided], full or
  /// closed sites are left out, so the suggestion is a place that can take
  /// people.
  List<SiteDistance> nearest(
    Hazard? h, {
    int limit = 5,
    bool skipAvoided = false,
  }) {
    final s = sites, f = from;
    if (s == null || f == null) return const [];
    var all = s.nearest(f, hazard: h, limit: limit + 20);
    final tree = walksFor(h);
    if (tree != null && tree.onNetwork) {
      // The nearest by walking is almost always among the 25 nearest in a
      // straight line. Sites without a route go last.
      // Sorted by what the search minimised: for tsunami that favours
      // higher ground over the shortest walk.
      all = [for (final n in all) n.withRoute(tree.routeTo(n.site.point))]
        ..sort(
          (a, b) => (a.route?.cost ?? 1e9 + a.meters).compareTo(
            b.route?.cost ?? 1e9 + b.meters,
          ),
        );
    }
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
