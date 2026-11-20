import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/map_state.dart';
import 'package:lychnion/map/tile_cache.dart';

// test/support/contours-tiny.pmtiles: a few tiles of contour lines around
// Nishinomiya city hall (z4–11), cut from the lychnion-data build.
// 出典：国土地理院最適化ベクトルタイルを加工して作成 (国土地理院コンテンツ利用規約).
// The tests also use it as the base map: only loading is tested here.
const fixture = 'test/support/contours-tiny.pmtiles';
// The real built-in sites of Nishinomiya (also used by evac_sites_test).
const sites = 'assets/maps/jp.map.nishinomiya.sites.sqlite';

void main() {
  late Directory tmp;
  late String base, contours;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('map_state_test');
    // The tile cache cleanup goes to this test's folder.
    MapTileCache.rootForTest = () async => Directory('${tmp.path}/cache');
    base = '${tmp.path}/area.pmtiles';
    contours = '${tmp.path}/area.contours.pmtiles';
    File(fixture).copySync(base);
  });

  tearDown(() async {
    await MapTileCache.idle;
    MapTileCache.rootForTest = null;
    tmp.deleteSync(recursive: true);
  });

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
    expect(s.contourTiles, isNot(same(s.tiles)));
  });

  test(
    'an empty contours file (download cut off) leaves only the contours out',
    () async {
      File(contours).writeAsBytesSync(const []);
      final s = area();
      await s.load();
      expectMapLoaded(s);
      expect(s.contourTiles, isNull);
    },
  );

  test('a broken contours file leaves only the contours out', () async {
    File(contours).writeAsStringSync('not a PMTiles file');
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
  });

  test(
    'a contours file with a cut header leaves only the contours out',
    () async {
      final bytes = File(fixture).readAsBytesSync();
      File(contours).writeAsBytesSync(bytes.sublist(0, 60));
      final s = area();
      await s.load();
      expectMapLoaded(s);
      expect(s.contourTiles, isNull);
    },
  );

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
