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
Theme offlineLightTheme({required String lang, bool contours = false}) {
  final nameField = [
    'coalesce',
    ['get', 'name:$lang'],
    ['get', 'name'],
  ];
  final layers = <Map<String, Object>>[];
  var linesAdded = false, labelsAdded = false;
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
    // GSI contours (source "contours", layer Cntr): lines under the roads,
    // height labels under the other labels.
    if (contours && layer['id'] == 'roads_tunnels_other_casing') {
      layers.addAll(_contourLines);
      linesAdded = true;
    }
    if (contours && !labelsAdded && layer['type'] == 'symbol') {
      layers.add(_contourLabels);
      labelsAdded = true;
    }
    layers.add(copy);
  }
  if (contours && !labelsAdded) layers.add(_contourLabels);
  assert(
    !contours || linesAdded,
    'roads_tunnels_other_casing is gone from the Protomaps theme: '
    'choose another layer to put the contour lines under',
  );
  const debug = bool.fromEnvironment('MAP_THEME_LOG');
  return ProtomapsThemes(
    logger: debug ? const Logger.console() : null,
    sources: {
      // Same as the ProtomapsThemes default, which this map replaces.
      'protomaps': {
        'type': 'vector',
        'attribution': '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>',
        'url': 'https://example.com/tiles.json',
      },
      if (contours)
        'contours': {'type': 'vector', 'url': 'https://example.com/c.json'},
    },
  ).build(layers);
}

/// Raster tile images are cached by theme id: change this number when the
/// look of the shapes changes, so no image drawn with the old look shows.
const _shapesStyle = 1;

// Contour lines from the GSI optimal vector tiles (layer Cntr, height in
// vt_alti). The tiles hold 100 m lines up to z13 and 10 m lines from z14.
// Drawn: all lines at z11-13, 50 m index lines from z14, all lines from z15.
// maxzoom is inclusive in vector_tile_renderer.
final _index = [
  'match',
  ['get', 'vt_alti'],
  [for (var h = -500; h <= 4000; h += 50) h],
  true,
  false,
];
Map<String, Object> _contourLine(
  String id,
  int minzoom,
  int maxzoom,
  Object? filter,
  String color,
  double width,
) => {
  'id': id,
  'type': 'line',
  'source': 'contours',
  'source-layer': 'Cntr',
  'minzoom': minzoom,
  'maxzoom': maxzoom,
  'filter': ?filter,
  'paint': {'line-color': color, 'line-width': width, 'line-opacity': 0.85},
};
final _contourLines = <Map<String, Object>>[
  // z11-13: the tiles only hold 100 m lines.
  _contourLine('contours_low', 11, 13, null, '#a0724a', 0.8),
  _contourLine('contours_minor', 15, 24, ['!', _index], '#c8a07a', 0.6),
  _contourLine('contours_index', 14, 24, _index, '#a0724a', 1.0),
];
final _contourLabels = <String, Object>{
  'id': 'contours_label',
  'type': 'symbol',
  'source': 'contours',
  'source-layer': 'Cntr',
  'minzoom': 14,
  'filter': _index,
  'layout': {
    'symbol-placement': 'line',
    'text-field': [
      'to-string',
      ['get', 'vt_alti'],
    ],
    'text-font': ['Noto Sans Regular'],
    'text-size': 10,
  },
  'paint': {
    'text-color': '#8a5a32',
    'text-halo-color': '#ffffff',
    'text-halo-width': 1.5,
  },
};

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
/// vector_map_tiles only starts over when the theme id changes, and keys
/// its raster images by theme id: so the ids name whether [contours] are
/// drawn, and the labels id the language [lang]. The shapes have no text.
MapDrawing splitLabels(
  Theme theme, {
  required String lang,
  bool contours = false,
}) => (
  shapes: theme.copyWith(
    id: 'lychnion-shapes-$_shapesStyle${contours ? '-contours' : ''}',
    types: ThemeLayerType.values
        .where((t) => t != ThemeLayerType.symbol)
        .toSet(),
  ),
  labels: theme.copyWith(
    id: 'lychnion-labels-$lang${contours ? '-contours' : ''}',
    types: {ThemeLayerType.symbol},
  ),
);
