import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/offline_theme.dart';
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
}
