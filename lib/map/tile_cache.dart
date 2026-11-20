import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk caches of the map layers: one folder per map file and layer.
///
/// vector_map_tiles keys its cached files by tile number only (raw tiles)
/// or by theme id and tile number (raster images), not by map file. With a
/// folder per map file, another area or a new release never reads the old
/// files; with a folder per layer, the two layers never read a file while
/// the other one writes it.
class MapTileCache {
  MapTileCache._();

  static const _root = 'lychnion-map-tiles';

  /// A folder name for [tilesId]: letters, digits, `.` and `-` only, never
  /// `.` or `..`.
  static String folderName(String tilesId) =>
      'm-${tilesId.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '-')}';

  /// The cache folder of [layer] for the map file [tilesId].
  static Future<Directory> folder(String tilesId, String layer) async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/$_root/${folderName(tilesId)}/$layer');
  }

  /// Deletes the caches of other map files, and the folder vector_map_tiles
  /// used before (`.vector_map`). Best effort: the system may clear the
  /// temporary folder anyway.
  static Future<void> keepOnly(String tilesId) async {
    try {
      final tmp = await getTemporaryDirectory();
      await removeOthers(Directory('${tmp.path}/$_root'), folderName(tilesId));
      final old = Directory('${tmp.path}/.vector_map');
      if (await old.exists()) await old.delete(recursive: true);
    } catch (e) {
      debugPrint('map tile cache: $e');
    }
  }

  /// Deletes everything in [root] except the folder [keep].
  @visibleForTesting
  static Future<void> removeOthers(Directory root, String keep) async {
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (e.uri.pathSegments.where((s) => s.isNotEmpty).last == keep) {
        continue;
      }
      await e.delete(recursive: true);
    }
  }
}
