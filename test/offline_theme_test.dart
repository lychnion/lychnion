import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  List<String> ids(bool contours) => offlineLightTheme(
    lang: 'ja',
    contours: contours,
  ).layers.map((l) => l.id).toList();

  test('without contours the theme has no contour layers', () {
    expect(ids(false).where((id) => id.startsWith('contours')), isEmpty);
  });

  test('contour lines go under the roads, labels under the other labels', () {
    final plain = ids(false), withC = ids(true);
    expect(withC.length, plain.length + 4);
    expect(withC.where((id) => !id.startsWith('contours')), plain);
    final roads = withC.indexOf('roads_tunnels_other_casing');
    for (final id in ['contours_low', 'contours_minor', 'contours_index']) {
      expect(withC.indexOf(id), lessThan(roads), reason: id);
    }
    final label = withC.indexOf('contours_label');
    final firstOtherSymbol = offlineLightTheme(lang: 'ja', contours: true)
        .layers
        .indexWhere((l) => l.type.name == 'symbol' && l.id != 'contours_label');
    expect(label, lessThan(firstOtherSymbol));
  });

  test('with contours, both ids name it and the lines are shapes', () {
    final plain = splitLabels(theme, lang: 'en');
    final withC = splitLabels(
      offlineLightTheme(lang: 'en', contours: true),
      lang: 'en',
      contours: true,
    );
    // Raster images are cached by theme id: on and off must not share.
    expect(withC.shapes.id, isNot(plain.shapes.id));
    expect(withC.labels.id, isNot(plain.labels.id));
    expect(
      withC.shapes.layers.map((l) => l.id),
      containsAll(['contours_low', 'contours_minor', 'contours_index']),
    );
    expect(withC.labels.layers.map((l) => l.id), contains('contours_label'));
  });

  test('removeOtherLayers drops the folders of old contours files', () async {
    final root = await Directory.systemTemp.createTemp('tile_cache_test');
    addTearDown(() => root.delete(recursive: true));
    final now = MapTileCache.layerName('shapes', 'c.pmtiles-2-2');
    final old = MapTileCache.layerName('shapes', 'c.pmtiles-1-1');
    for (final d in ['shapes', 'labels', now, old]) {
      await File('${root.path}/$d/0_0_0.png').create(recursive: true);
    }
    await MapTileCache.removeOtherLayers(root, 'c.pmtiles-2-2');
    final left = root
        .listSync()
        .map((e) => e.uri.pathSegments[e.uri.pathSegments.length - 2])
        .toSet();
    expect(left, {'shapes', 'labels', now});
    // Without contours (file gone): only the plain folders stay.
    await MapTileCache.removeOtherLayers(root, null);
    expect(root.listSync().length, 2);
  });
}
