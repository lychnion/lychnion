import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// Offline walking graph for one map area, built by tool/build_routes.py
/// from OpenStreetMap. Nodes are points on roads and paths; every edge can be
/// walked both ways.
class RouteGraph {
  RouteGraph._(this._lat, this._lon, this._offsets, this._targets, this._len) {
    // Nodes come sorted by 0.001° cell: remember where each cell starts.
    for (var i = 0; i < _lat.length; i++) {
      final c = _cellOf(_lat[i], _lon[i]);
      _cellStart.putIfAbsent(c, () => i);
      _cellEnd[c] = i + 1;
    }
  }

  final Int32List _lat, _lon;
  final Uint32List _offsets, _targets;

  /// Edge lengths in decimetres.
  final Uint16List _len;
  final _cellStart = <int, int>{};
  final _cellEnd = <int, int>{};

  int get nodeCount => _lat.length;

  /// Parses a routes.bin file (see tool/build_routes.py for the format).
  factory RouteGraph.parse(Uint8List bytes) {
    final b = ByteData.sublistView(bytes);
    if (bytes.length < 16 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'FKRG' ||
        b.getUint32(4, Endian.little) != 1) {
      throw const FormatException('not a fieldkit route graph');
    }
    final n = b.getUint32(8, Endian.little);
    final e = b.getUint32(12, Endian.little);
    var at = 16;
    // Copy into aligned lists (works whatever the buffer's alignment).
    Int32List i32(int count) {
      final out = Int32List(count);
      for (var k = 0; k < count; k++, at += 4) {
        out[k] = b.getInt32(at, Endian.little);
      }
      return out;
    }

    Uint32List u32(int count) {
      final out = Uint32List(count);
      for (var k = 0; k < count; k++, at += 4) {
        out[k] = b.getUint32(at, Endian.little);
      }
      return out;
    }

    final lat = i32(n), lon = i32(n);
    final offsets = u32(n + 1), targets = u32(e);
    final len = Uint16List(e);
    for (var k = 0; k < e; k++, at += 2) {
      len[k] = b.getUint16(at, Endian.little);
    }
    if (offsets[n] != e) throw const FormatException('broken route graph');
    return RouteGraph._(lat, lon, offsets, targets, len);
  }

  static Future<RouteGraph> load(String path) async =>
      RouteGraph.parse(await File(path).readAsBytes());

  static int _cellOf(int latE6, int lonE6) =>
      (latE6 ~/ 1000) * 1000000 + (lonE6 ~/ 1000);

  LatLng point(int i) => LatLng(_lat[i] / 1e6, _lon[i] / 1e6);

  /// Metres between node [i] and [p] (flat approximation, fine below ~10 km).
  double _metersTo(int i, LatLng p) {
    const r = 6371008.8 * pi / 180;
    final dLat = (_lat[i] / 1e6 - p.latitude) * r;
    final dLon = (_lon[i] / 1e6 - p.longitude) * r * cos(p.latitude * pi / 180);
    return sqrt(dLat * dLat + dLon * dLon);
  }

  /// Nodes within [meters] of [p].
  Iterable<int> nodesNear(LatLng p, double meters) sync* {
    final dLat = (meters / 111000 * 1000).ceil() + 1;
    final dLon =
        (meters / (111000 * cos(p.latitude * pi / 180)) * 1000).ceil() + 1;
    final cLat = (p.latitude * 1e6).round() ~/ 1000;
    final cLon = (p.longitude * 1e6).round() ~/ 1000;
    for (var y = cLat - dLat; y <= cLat + dLat; y++) {
      for (var x = cLon - dLon; x <= cLon + dLon; x++) {
        final c = y * 1000000 + x;
        final s = _cellStart[c];
        if (s == null) continue;
        for (var i = s; i < _cellEnd[c]!; i++) {
          if (_metersTo(i, p) <= meters) yield i;
        }
      }
    }
  }

  /// The node nearest to [p] within [maxMeters], or null.
  ({int node, double meters})? nearestNode(LatLng p, {double maxMeters = 300}) {
    // Look close first: most positions are a few metres from a road.
    for (final r in [60.0, 150.0, maxMeters]) {
      if (r > maxMeters) continue;
      int? best;
      var bestM = double.infinity;
      for (final i in nodesNear(p, r)) {
        final m = _metersTo(i, p);
        if (m < bestM) {
          bestM = m;
          best = i;
        }
      }
      if (best != null) return (node: best, meters: bestM);
    }
    return null;
  }

  /// Shortest walks from [from] to every node up to [maxMeters] away.
  /// Nodes in [blocked] are never entered (e.g. near a blocked road).
  WalkTree walkFrom(
    LatLng from, {
    double maxMeters = 6000,
    Set<int> blocked = const {},
  }) {
    final start = nearestNode(from);
    final n = nodeCount;
    final dist = Float64List(n)..fillRange(0, n, double.infinity);
    final prev = Int32List(n)..fillRange(0, n, -1);
    if (start == null) return WalkTree._(this, from, null, 0, dist, prev);
    final heap = _Heap();
    dist[start.node] = 0;
    heap.push(0, start.node);
    while (heap.isNotEmpty) {
      final d = heap.topKey, v = heap.pop();
      if (d > dist[v]) continue; // stale entry
      if (d > maxMeters) break;
      for (var k = _offsets[v]; k < _offsets[v + 1]; k++) {
        final u = _targets[k];
        if (blocked.contains(u)) continue;
        final nd = d + _len[k] / 10;
        if (nd < dist[u]) {
          dist[u] = nd;
          prev[u] = v;
          heap.push(nd, u);
        }
      }
    }
    return WalkTree._(this, from, start.node, start.meters, dist, prev);
  }
}

/// Result of [RouteGraph.walkFrom]: walking distance and path to places.
class WalkTree {
  WalkTree._(
    this.graph,
    this.from,
    this._start,
    this._startMeters,
    this._dist,
    this._prev,
  );

  final RouteGraph graph;
  final LatLng from;
  final int? _start;

  /// From [from] to the first node on a road.
  final double _startMeters;
  final Float64List _dist;
  final Int32List _prev;

  /// The start position is on (or near) the road network.
  bool get onNetwork => _start != null;

  ({int node, double meters})? _end(LatLng to) =>
      graph.nearestNode(to, maxMeters: 250);

  /// Walking metres to [to], or null when no route was found in range.
  double? metersTo(LatLng to) {
    final e = _end(to);
    if (_start == null || e == null) return null;
    final d = _dist[e.node];
    return d.isFinite ? _startMeters + d + e.meters : null;
  }

  /// The path to [to] as points, from [from] to [to], or null.
  List<LatLng>? pathTo(LatLng to) {
    final e = _end(to);
    if (_start == null || e == null || !_dist[e.node].isFinite) return null;
    final nodes = <int>[];
    for (var v = e.node; v != -1; v = _prev[v]) {
      nodes.add(v);
    }
    return [from, for (final v in nodes.reversed) graph.point(v), to];
  }
}

/// Binary min-heap of (key, node).
class _Heap {
  final _keys = <double>[];
  final _nodes = <int>[];

  bool get isNotEmpty => _keys.isNotEmpty;
  double get topKey => _keys[0];

  void push(double key, int node) {
    var i = _keys.length;
    _keys.add(key);
    _nodes.add(node);
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= key) break;
      _keys[i] = _keys[p];
      _nodes[i] = _nodes[p];
      i = p;
    }
    _keys[i] = key;
    _nodes[i] = node;
  }

  int pop() {
    final top = _nodes[0];
    final lastKey = _keys.removeLast(), lastNode = _nodes.removeLast();
    if (_keys.isEmpty) return top;
    var i = 0;
    final n = _keys.length;
    while (true) {
      var c = 2 * i + 1;
      if (c >= n) break;
      if (c + 1 < n && _keys[c + 1] < _keys[c]) c++;
      if (_keys[c] >= lastKey) break;
      _keys[i] = _keys[c];
      _nodes[i] = _nodes[c];
      i = c;
    }
    _keys[i] = lastKey;
    _nodes[i] = lastNode;
    return top;
  }
}
