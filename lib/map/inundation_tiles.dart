import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tsunami inundation areas as map tiles, from the MBTiles file written by
/// tool/build_inundation_tiles.py. Tiles with no inundation are not in the
/// file and draw nothing.
class InundationTiles extends TileProvider {
  InundationTiles._(this._db);

  final Database _db;

  static InundationTiles open(String path) =>
      InundationTiles._(sqlite3.open(path, mode: OpenMode.readOnly));

  /// Zoom levels in the file; the map scales the last one up.
  static const minZoom = 10, maxZoom = 16;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final c = coordinates;
    final rows = _db.select(
      'SELECT tile_data FROM tiles '
      'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
      // MBTiles counts rows from the south.
      [c.z, c.x, (1 << c.z) - 1 - c.y],
    );
    return MemoryImage(
      rows.isEmpty ? _empty : rows.first['tile_data'] as Uint8List,
    );
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  /// A transparent 1 × 1 PNG.
  static final _empty = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
  );

  /// Legend colours by lower depth bound (index into depthBounds), as in
  /// tool/build_inundation_tiles.py.
  static const colours = {
    0: Color(0xFFFFF5A0),
    1: Color(0xFFFFDC82),
    2: Color(0xFFFFB98C),
    3: Color(0xFFFF968C),
    4: Color(0xFFF07396),
    5: Color(0xFFD75FBE),
    6: Color(0xFFA050D2),
    7: Color(0xFF6E3CBE),
    8: Color(0xFF46288C),
  };
}
