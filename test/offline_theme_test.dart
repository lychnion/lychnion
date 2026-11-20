import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/offline_theme.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  final theme = offlineLightTheme(lang: 'en');

  test('splitLabels puts symbol layers on top and the rest in raster', () {
    final d = splitLabels(theme, dataId: 'a.pmtiles-10-20');
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

  test('splitLabels names both parts after the map file', () {
    final a = splitLabels(theme, dataId: 'a.pmtiles-10-20');
    final b = splitLabels(theme, dataId: 'a.pmtiles-11-20');
    expect(a.shapes.id, isNot(b.shapes.id));
    expect(a.labels.id, isNot(b.labels.id));
    expect(a.shapes.id, isNot(a.labels.id));
    // The raster cache uses the id in file names.
    final odd = splitLabels(theme, dataId: 'x/y z:1');
    expect(odd.shapes.id, matches(RegExp(r'^[a-zA-Z0-9.-]+$')));
  });
}
