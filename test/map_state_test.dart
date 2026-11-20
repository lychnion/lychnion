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

  test('a new state after the file is gone has no contours', () async {
    // The app makes a new MapState for each load (app_shell).
    File(fixture).copySync(contours);
    final first = area();
    await first.load();
    expect(first.contourTiles, isNotNull);
    first.dispose();
    File(contours).deleteSync();
    final s = area();
    await s.load();
    expectMapLoaded(s);
    expect(s.contourTiles, isNull);
    expect(s.contoursId, isNull);
  });

  test(
    'a state dropped while opening the contours leaves the caches alone',
    () async {
      File(fixture).copySync(contours);
      // The cache of the map a newer state shows.
      final newer = await MapTileCache.folder('newer-map', 'shapes');
      await File('${newer.path}/0_0_0.png').create(recursive: true);
      final s = area();
      final loading = s.load();
      // Dropped once the base map is open, while the contours file opens.
      while (s.tiles == null && s.error == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(s.error, isNull);
      s.dispose();
      await loading;
      await MapTileCache.idle;
      expect(s.tilesId, isNull);
      expect(s.contourTiles, isNull);
      expect(newer.existsSync(), isTrue);
    },
  );
}
