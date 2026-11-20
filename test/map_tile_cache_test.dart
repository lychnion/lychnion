import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/map_state.dart';
import 'package:lychnion/map/tile_cache.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tile_cache_test');
    MapTileCache.rootForTest = () async => root;
  });

  tearDown(() async {
    await MapTileCache.idle;
    MapTileCache.rootForTest = null;
    await root.delete(recursive: true);
  });

  Future<void> makeFolder(String tilesId) async {
    final d = await MapTileCache.folder(tilesId, 'shapes');
    await File('${d.path}/0_0_0.pbf').create(recursive: true);
  }

  Future<Set<String>> folders() async => {
    for (final e in root.listSync()) e.path.split(RegExp(r'[/\\]')).last,
  };

  test('folder names are safe file names', () {
    expect(
      MapTileCache.folderName('jp.map.a.pmtiles-10-20'),
      'm-jp.map.a.pmtiles-10-20',
    );
    expect(MapTileCache.folderName('../x y:1'), 'm-..-x-y-1');
    expect(MapTileCache.folderName('..'), 'm-..');
    final long = '${'x' * 300}.pmtiles-1-2';
    final a = MapTileCache.folderName(long);
    expect(a.length, lessThanOrEqualTo(82));
    expect(a, matches(RegExp(r'^m-[a-zA-Z0-9.-]+$')));
    // Same start, other size: another folder.
    expect(MapTileCache.folderName('${'x' * 300}.pmtiles-9-2'), isNot(a));
  });

  test('keepOnly keeps only the current map file', () async {
    await makeFolder('old');
    await makeFolder('keep');
    await File('${root.path}/stray.png').create();
    await MapTileCache.keepOnly('keep');
    await MapTileCache.idle;
    expect(await folders(), {MapTileCache.folderName('keep')});
    expect(
      File('${(await MapTileCache.folder('keep', 'shapes')).path}/0_0_0.pbf')
          .existsSync(),
      isTrue,
    );
  });

  test('the last keepOnly wins', () async {
    await makeFolder('a');
    await makeFolder('b');
    final first = MapTileCache.keepOnly('a');
    final second = MapTileCache.keepOnly('b');
    await Future.wait([first, second]);
    expect(await folders(), {MapTileCache.folderName('b')});
  });

  group('MapState', () {
    const fixture = 'test/support/contours-tiny.pmtiles';
    const sites = 'assets/maps/jp.map.nishinomiya.sites.sqlite';

    MapState state() => MapState(
      pmtilesPath: fixture,
      sitesAsset: '',
      sitesPath: sites,
      mockLocation: '34.7376,135.3417',
    );

    test('a load sets tilesId and deletes other maps\' caches', () async {
      await makeFolder('other');
      final s = state();
      addTearDown(s.dispose);
      await s.load();
      await MapTileCache.idle;
      expect(s.error, isNull);
      expect(s.tiles, isNotNull);
      expect(s.tilesId, startsWith('contours-tiny.pmtiles-'));
      expect(
        await folders(),
        isNot(contains(MapTileCache.folderName('other'))),
      );
      expect(s.here, isNotNull);
    });

    test(
      'a load that ends after dispose leaves state and caches alone',
      () async {
        await makeFolder('other');
        final s = state();
        var notified = 0;
        s.addListener(() => notified++);
        final loading = s.load();
        s.dispose(); // while the map file is still being opened
        await loading;
        await MapTileCache.idle;
        expect(notified, 0);
        expect(s.tiles, isNull);
        expect(s.tilesId, isNull);
        expect(s.here, isNull);
        expect(await folders(), contains(MapTileCache.folderName('other')));
      },
    );

    test('a failed load after dispose stays quiet', () async {
      final s = MapState(pmtilesPath: '/nonexistent.pmtiles', sitesAsset: '');
      final loading = s.load();
      s.dispose();
      await loading; // must not throw on the disposed notifier
      expect(s.error, isNull);
    });
  });
}
