import 'dart:io';
import 'dart:typed_data';

import 'package:fieldkit/map/route_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Writes a graph in the routes.bin format. [edges] are undirected.
Uint8List encode(List<LatLng> nodes, List<(int, int)> edges) {
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
  u32(1);
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
  return b.toBytes();
}

int _sqrt(int v) {
  var x = 0;
  while ((x + 1) * (x + 1) <= v) {
    x++;
  }
  return x;
}

void main() {
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
    expect(t.pathTo(nodes[5])!, isNot(contains(nodes[4])));
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
