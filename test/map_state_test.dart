import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/map_state.dart';

// test/support/contours-tiny.pmtiles: a few tiles of contour lines around
// Nishinomiya city hall (z4–11), cut from the lychnion-data build.
// 出典：国土地理院最適化ベクトルタイルを加工して作成 (国土地理院コンテンツ利用規約).
// The tests also use it as the base map: only loading is tested here.
const fixture = 'test/support/contours-tiny.pmtiles';
const sites = 'assets/maps/jp.map.nishinomiya.sites.sqlite';

void main() {
  late Directory tmp;
  late String base, contours;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('map_state_test');
    base = '${tmp.path}/area.pmtiles';
    contours = '${tmp.path}/area.contours.pmtiles';
    File(fixture).copySync(base);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  MapState area() => MapState(
    pmtilesPath: base,
    sitesAsset: 'unused',
    sitesPath: sites,
    mockLocation: '34.7376,135.3417',
  );

  /// The rest of the map loaded: base map, sites and the position (the
  /// last step of load()).
  void expectMapLoaded(MapState s) {
    expect(s.error, isNull);
    expect(s.ready, isTrue);
    expect(s.here, isNotNull);
  }

  test('without a contours file the map loads without contours', () async {
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
  });

  test('a contours file next to the base map is opened', () async {
    File(fixture).copySync(contours);
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNotNull);
  });

  test('a broken contours file leaves only the contours out', () async {
    File(contours).writeAsStringSync('not a PMTiles file');
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
  });

  test('a cut-off contours file leaves only the contours out', () async {
    final bytes = File(fixture).readAsBytesSync();
    File(contours).writeAsBytesSync(bytes.sublist(0, 60));
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
  });

  test('loading again after the file is gone drops the contours', () async {
    File(fixture).copySync(contours);
    final s = area();
    await s.load();
    expect(s.contourTiles, isNotNull);
    File(contours).deleteSync();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
  });
}
