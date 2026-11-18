import 'dart:io';
import 'dart:typed_data';

import 'package:lychnion/map/route_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:lychnion/map/map_labels.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;

/// Writes a graph in the routes.bin format. [edges] are undirected.
/// With [heights] (metres per node) it writes version 2, with [flood]
/// as well version 3.
Uint8List encode(
  List<LatLng> nodes,
  List<(int, int)> edges, {
  List<double>? heights,
  List<int>? flood,
  int floodVersion = 3,
}) {
  const r = 111195.0; // metres per degree, near enough for tests
  final adj = [for (final _ in nodes) <int>[]];
  for (final (a, b) in edges) {
    adj[a].add(b);
    adj[b].add(a);
  }
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void i32(int v) =>
      b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());
  b.add('FKRG'.codeUnits);
  u32(flood != null ? floodVersion : (heights == null ? 1 : 2));
  u32(nodes.length);
  u32(adj.fold(0, (s, a) => s + a.length));
  for (final n in nodes) {
    i32((n.latitude * 1e6).round());
  }
  for (final n in nodes) {
    i32((n.longitude * 1e6).round());
  }
  var off = 0;
  u32(0);
  for (final a in adj) {
    off += a.length;
    u32(off);
  }
  for (final a in adj) {
    a.forEach(u32);
  }
  for (var i = 0; i < nodes.length; i++) {
    for (final j in adj[i]) {
      final dy = (nodes[i].latitude - nodes[j].latitude) * r;
      final dx = (nodes[i].longitude - nodes[j].longitude) * r * 0.82;
      final dm = ((dx * dx + dy * dy) * 100).round();
      b.add(
        (ByteData(
          2,
        )..setUint16(0, _sqrt(dm), Endian.little)).buffer.asUint8List(),
      );
    }
  }
  if (heights != null) {
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
    for (final h in heights) {
      b.add(
        (ByteData(
          2,
        )..setInt16(0, (h * 10).round(), Endian.little)).buffer.asUint8List(),
      );
    }
  }
  if (flood != null) {
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
    b.add(flood);
  }
  return b.toBytes();
}

/// Whether [path] passes [p] (coordinates are stored to 6 decimals).
Matcher passes(LatLng p) => predicate<List<LatLng>>(
  (path) => path.any(
    (q) =>
        (q.latitude - p.latitude).abs() < 2e-6 &&
        (q.longitude - p.longitude).abs() < 2e-6,
  ),
  'passes $p',
);

int _sqrt(int v) {
  var x = 0;
  while ((x + 1) * (x + 1) <= v) {
    x++;
  }
  return x;
}

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  final en = lookupAppLocalizations(const Locale('en'));
  // A ladder of two parallel streets 100 m apart, joined at both ends and
  // in the middle:
  //
  //   0 --- 1 --- 2        (north street)
  //   |     |     |
  //   3 --- 4 --- 5        (south street)
  //
  // Nodes sorted by grid cell, as the builder writes them.
  const lat0 = 34.7, lon0 = 135.3;
  final nodes = [
    for (final la in [lat0 + 0.0009, lat0])
      for (final lo in [lon0, lon0 + 0.0012, lon0 + 0.0024]) LatLng(la, lo),
  ];
  final g = RouteGraph.parse(
    encode(nodes, [(0, 1), (1, 2), (3, 4), (4, 5), (0, 3), (1, 4), (2, 5)]),
  );

  test('finds the shortest walk and its path', () {
    final t = g.walkFrom(nodes[3]);
    final m = t.metersTo(nodes[2])!;
    // 3 → 4 → 5 → 2 or 3 → 0 → 1 → 2: about 220 + 100 m either way.
    expect(m, closeTo(320, 15));
    final path = t.pathTo(nodes[2])!;
    expect(path.first, nodes[3]);
    expect(path.last, nodes[2]);
    expect(path.length, 6); // from, 4 nodes, to
  });

  test('goes around a blocked node', () {
    final open = g.walkFrom(nodes[3]).metersTo(nodes[5])!;
    // Block node 4 on the south street: the walk goes round by the north.
    final t = g.walkFrom(nodes[3], blocked: g.nodesNear(nodes[4], 20).toSet());
    final m = t.metersTo(nodes[5])!;
    expect(open, closeTo(220, 15));
    expect(m, closeTo(420, 20));
    expect(t.pathTo(nodes[5])!, isNot(passes(nodes[4])));
  });

  test('snaps a position near a road and adds the gap', () {
    final near = LatLng(lat0 + 0.0002, lon0); // ~22 m north of node 3
    final m = g.walkFrom(near).metersTo(nodes[5])!;
    expect(m, closeTo(220 + 22, 15));
  });

  test('no route far from any road', () {
    final t = g.walkFrom(LatLng(lat0 + 0.05, lon0));
    expect(t.onNetwork, isFalse);
    expect(t.metersTo(nodes[0]), isNull);
  });

  test('tsunami: keeps to higher ground when it costs no more', () {
    // North street 20 m high, south street at sea level. From 3 to 2 both
    // ways are 320 m; with preferHigh the walk climbs first.
    final hg = RouteGraph.parse(
      encode(
        nodes,
        [(0, 1), (1, 2), (3, 4), (4, 5), (0, 3), (1, 4), (2, 5)],
        heights: [20, 20, 20, 0, 0, 0],
      ),
    );
    expect(hg.hasHeights, isTrue);
    expect(hg.heightOf(0), 20);
    final r = hg.walkFrom(nodes[3], preferHigh: true).routeTo(nodes[2])!;
    expect(r.path, passes(nodes[0]));
    expect(r.path, isNot(passes(nodes[4])));
    expect(r.meters, closeTo(320, 15));
    // No step down and nothing below 10 m on average: no extra cost.
    expect(r.cost, closeTo(r.meters, 1));
    expect(r.endHeight, 20);
  });

  test('tsunami: a long way round beats going down to the sea', () {
    // 0 (8 m) to 2 (8 m): straight through 1 (sea level), 240 m, or round
    // by 3 (9 m), about 1.4 times longer.
    final line = [
      const LatLng(lat0, lon0),
      const LatLng(lat0, lon0 + 0.0013),
      const LatLng(lat0, lon0 + 0.0026),
      const LatLng(lat0 + 0.0015, lon0 + 0.0013),
    ];
    final hg = RouteGraph.parse(
      encode(line, [(0, 1), (1, 2), (0, 3), (3, 2)], heights: [8, 0, 8, 9]),
    );
    final short = hg.walkFrom(line[0]).routeTo(line[2])!;
    expect(short.path, passes(line[1]));
    expect(short.dip, 8);
    expect(short.lowest, 0);
    final high = hg.walkFrom(line[0], preferHigh: true).routeTo(line[2])!;
    expect(high.path, passes(line[3]));
    expect(high.dip, 0);
    expect(high.meters, greaterThan(short.meters * 1.3));
  });

  test('inundation: the way out and avoiding deep water', () {
    // South street inside the inundation area (3–4 m at node 4), north
    // street clear. All flat at 2 m.
    final fg = RouteGraph.parse(
      encode(
        nodes,
        [(0, 1), (1, 2), (3, 4), (4, 5), (0, 3), (1, 4), (2, 5)],
        heights: [2, 2, 2, 2, 2, 2],
        flood: [0, 0, 0, 4, 6, 4],
      ),
    );
    expect(fg.hasFlood, isTrue);
    expect(fg.floodOf(4), 6);
    expect(depthLabel(ja, fg.depthOf(4)!), '3〜4 m');
    expect(fg.depthOf(0), isNull);
    // From 3 the nearest clear point is 0, straight north (100 m).
    final t = fg.walkFrom(nodes[3], preferHigh: true);
    final out = t.wayOut!;
    expect(out.startFlood, 4);
    expect(out.endFlood, 0);
    expect(out.meters, closeTo(100, 10));
    expect([out.path.last], passes(nodes[0]));
    // To 5 the tsunami walk leaves the area first instead of crossing 4.
    final r = t.routeTo(nodes[5])!;
    expect(r.path, isNot(passes(nodes[4])));
    expect(r.endFlood, 4);
    // Without tsunami: the short way through 4.
    expect(fg.walkFrom(nodes[3]).routeTo(nodes[5])!.path, passes(nodes[4]));
    // Already clear: no way out needed.
    expect(fg.walkFrom(nodes[0], preferHigh: true).wayOut, isNull);
  });

  test('version 4: depth as lower and upper bound', () {
    // 16 * hi + lo: 3–5 m (lo 4, hi 6), 10–20 m (7, 8), 5 m or more (6, 9).
    final fg = RouteGraph.parse(
      encode(
        nodes,
        [(0, 1), (1, 2), (3, 4), (4, 5), (0, 3), (1, 4), (2, 5)],
        heights: [2, 2, 2, 2, 2, 2],
        flood: [0, 1, 16 * 6 + 4, 16 * 8 + 7, 16 * 9 + 6, 16 * 1 + 0],
        floodVersion: 4,
      ),
    );
    expect(fg.floodOf(0), 0);
    expect(fg.floodOf(1), 1);
    expect(fg.floodOf(3), 2 + 7);
    expect(depthLabel(ja, fg.depthOf(2)!), '3〜5 m');
    expect(depthLabel(en, fg.depthOf(3)!), '10–20 m');
    expect(depthLabel(ja, fg.depthOf(4)!), '5 m以上');
    expect(depthLabel(en, fg.depthOf(5)!), 'under 0.3 m');
    expect(fg.deepest, 7);
    expect(depthFromLabel(ja, 7), '10 m〜');
  });

  test('version 1 files have no heights', () {
    expect(g.hasHeights, isFalse);
    expect(g.heightOf(0), isNull);
    final r = g.walkFrom(nodes[3], preferHigh: true).routeTo(nodes[5])!;
    expect(r.cost, r.meters);
    expect(r.endHeight, isNull);
  });

  test('rejects other files', () {
    expect(
      () => RouteGraph.parse(Uint8List.fromList('nope, not a graph'.codeUnits)),
      throwsFormatException,
    );
  });

  // The real area graph, when it has been built (tool/build_routes.py).
  final real = File('build/maps/jp.map.nishinomiya.routes.bin');
  test(
    'Nishinomiya graph: city hall to a site 1 km away',
    () async {
      var sw = Stopwatch()..start();
      final rg = await RouteGraph.load(real.path);
      // ignore: avoid_print
      print('load ${sw.elapsedMilliseconds} ms, ${rg.nodeCount} nodes');
      sw = Stopwatch()..start();
      const hall = LatLng(34.7376, 135.3417);
      final t = rg.walkFrom(hall);
      var reached = 0;
      for (var i = 0; i < rg.nodeCount; i += 100) {
        if (t.metersTo(rg.point(i)) != null) reached++;
      }
      // ignore: avoid_print
      print(
        'walk tree ${sw.elapsedMilliseconds} ms, ~${reached * 100} nodes reached',
      );
      const station = LatLng(34.7385, 135.3440); // ~230 m east (阪神西宮駅)
      final m = t.metersTo(station)!;
      expect(m, greaterThan(200));
      expect(m, lessThan(600));
    },
    skip: real.existsSync() ? false : 'area graph not built',
  );
}
