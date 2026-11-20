import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/map_state.dart';
import 'package:lychnion/map/offline_theme.dart';
import 'package:lychnion/map/tile_cache.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  final theme = offlineLightTheme(lang: 'en');

  test('splitLabels puts symbol layers on top and the rest in raster', () {
    final d = splitLabels(theme, lang: 'en');
    expect(d.labels.layers, isNotEmpty);
    expect(d.shapes.layers, isNotEmpty);
    expect(
      d.labels.layers.map((l) => l.type),
      everyElement(ThemeLayerType.symbol),
    );
    expect(
      d.shapes.layers.map((l) => l.type),
      isNot(contains(ThemeLayerType.symbol)),
    );
    // Nothing lost, nothing drawn twice.
    expect(
      d.shapes.layers.length + d.labels.layers.length,
      theme.layers.length,
    );
  });

  test('the labels id names the language, the shapes id does not', () {
    final en = splitLabels(theme, lang: 'en');
    final ja = splitLabels(offlineLightTheme(lang: 'ja'), lang: 'ja');
    expect(en.labels.id, isNot(ja.labels.id));
    expect(en.shapes.id, ja.shapes.id);
    expect(en.shapes.id, isNot(en.labels.id));
  });

  test('cache folder names are safe file names', () {
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

  test('removeOthers keeps only the current map file', () async {
    final root = await Directory.systemTemp.createTemp('tile_cache_test');
    addTearDown(() => root.delete(recursive: true));
    for (final d in ['old-1/shapes', 'keep/shapes', 'keep/labels']) {
      await File('${root.path}/$d/0_0_0.pbf').create(recursive: true);
    }
    await File('${root.path}/stray.png').create();
    await MapTileCache.removeOthers(root, 'keep');
    final left = root
        .listSync(recursive: true)
        .map((e) => e.path.substring(root.path.length + 1))
        .toSet();
    expect(left, {
      'keep',
      'keep/shapes',
      'keep/labels',
      'keep/shapes/0_0_0.pbf',
      'keep/labels/0_0_0.pbf',
    });
  });

  test('a load that ends after dispose stays quiet', () async {
    final s = MapState(pmtilesPath: '/nonexistent.pmtiles', sitesAsset: '');
    var notified = 0;
    s.addListener(() => notified++);
    final loading = s.load();
    s.dispose();
    await loading; // must not throw on the disposed notifier
    expect(notified, 0);
    expect(s.tilesId, isNull);
  });
}
