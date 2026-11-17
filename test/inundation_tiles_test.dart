import 'dart:io';
import 'dart:typed_data';

import 'package:lychnion/map/inundation_tiles.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('reads tiles with MBTiles rows counted from the south', () {
    final dir = Directory.systemTemp.createTempSync('fk_tiles');
    final path = '${dir.path}/t.mbtiles';
    final db = sqlite3.open(path)
      ..execute(
        'CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, '
        'tile_row INTEGER, tile_data BLOB)',
      );
    final data = Uint8List.fromList([1, 2, 3]);
    // Zoom 14, column 14540, XYZ row 6503 → TMS row 2^14 - 1 - 6503.
    db.execute('INSERT INTO tiles VALUES (?, ?, ?, ?)', [
      14,
      14540,
      (1 << 14) - 1 - 6503,
      data,
    ]);
    db.close();

    final tiles = InundationTiles.open(path);
    final layer = TileLayer();
    final hit =
        tiles.getImage(const TileCoordinates(14540, 6503, 14), layer)
            as MemoryImage;
    expect(hit.bytes, data);
    final miss =
        tiles.getImage(const TileCoordinates(14540, 6504, 14), layer)
            as MemoryImage;
    expect(miss.bytes.sublist(1, 4), 'PNG'.codeUnits); // transparent tile
    tiles.dispose();
    dir.deleteSync(recursive: true);
  });
}
