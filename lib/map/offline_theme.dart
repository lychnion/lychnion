// The v4 theme layers are not exported; Protomaps publishes them as CC0.
// ignore: implementation_imports
import 'package:vector_map_tiles_pmtiles/src/themes/v4/_package.dart' as v4;
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// Protomaps light theme made to work offline with this renderer.
///
/// - Labels: the original per-script `case` expressions are not drawn by
///   vector_tile_renderer 5, so each label becomes a plain name lookup in the
///   wanted language, falling back to the local name.
/// - No icons: the theme loads sprites from the internet.
/// - No minor-road labels: in Japan these are mostly road numbers.
Theme offlineLightTheme({required String lang}) {
  final nameField = [
    'coalesce',
    ['get', 'name:$lang'],
    ['get', 'name'],
  ];
  final layers = <Map<String, Object>>[];
  for (final layer in v4.themeLight) {
    // Minor roads mostly carry municipal road numbers (西1276 …): too noisy.
    if (layer['id'] == 'roads_labels_minor') continue;
    final copy = Map<String, Object>.from(layer);
    final layout = layer['layout'];
    if (layout is Map) {
      final l = Map<String, Object>.from(layout.cast<String, Object>());
      if (l.containsKey('text-field')) {
        l['text-field'] = nameField;
        l['text-font'] = ['Noto Sans Regular'];
      }
      l.remove('icon-image');
      copy['layout'] = l;
    }
    layers.add(copy);
  }
  const debug = bool.fromEnvironment('MAP_THEME_LOG');
  return const ProtomapsThemes(logger: debug ? Logger.console() : null)
      .build(layers);
}

/// The map in two parts: `shapes` for a raster-mode layer, `labels` for a
/// vector-mode layer on top. See [splitLabels].
typedef MapDrawing = ({Theme shapes, Theme labels});

/// Splits [theme] into its labels (symbol layers) and everything else.
///
/// Why: in vector mode every frame re-draws every path of every tile
/// (Impeller keeps no raster cache): about 12 fps when dragging at z15 on a
/// Pixel 5a. Raster mode draws each tile once into an image (60 fps); the
/// labels stay vectors on top, placed across tile edges (55-58 fps).
///
/// Raster mode saves the tile images on disk, keyed by theme id and tile
/// number only, so both parts get an id from the map file ([dataId]):
/// another map area or a new release never shows old images.
MapDrawing splitLabels(Theme theme, {required String dataId}) {
  final id = dataId.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '-');
  return (
    shapes: theme.copyWith(
      id: 'lychnion-shapes-$id',
      types: ThemeLayerType.values
          .where((t) => t != ThemeLayerType.symbol)
          .toSet(),
    ),
    labels: theme.copyWith(
      id: 'lychnion-labels-$id',
      types: {ThemeLayerType.symbol},
    ),
  );
}
