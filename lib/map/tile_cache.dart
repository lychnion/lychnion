import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk caches of the map layers: one folder per map file and layer, in the
/// app's own cache folder.
///
/// vector_map_tiles keys its cached files by tile number only (raw tiles)
/// or by theme id and tile number (raster images), not by map file. With a
/// folder per map file, another area or a new release never reads the old
/// files; with a folder per layer, the two layers never read a file while
/// the other one writes it.
///
/// The cache does not last: with `fileCacheTtl: Duration.zero` each layer
/// empties its folder 3 s after it starts. Tiles still being loaded by a
/// layer that was just removed may write into its old folder again; the
/// next [keepOnly] removes it.
class MapTileCache {
  MapTileCache._();

  static const _root = 'map-tiles';

  /// A folder name for [tilesId]: letters, digits, `.` and `-` only, never
  /// `.` or `..`, at most 82 characters (long ids end in a hash).
  static String folderName(String tilesId) {
    final safe = tilesId.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '-');
    if (safe.length <= 80) return 'm-$safe';
    final hash = sha256.convert(utf8.encode(tilesId)).toString();
    return 'm-${safe.substring(0, 60)}-${hash.substring(0, 16)}';
  }

  /// Where the folders go; tests point it at a temporary folder.
  @visibleForTesting
  static Future<Directory> Function()? rootForTest;

  static Future<Directory> _rootDir(Future<Directory> Function()? test) async {
    if (test != null) return test();
    final cache = await getApplicationCacheDirectory();
    return Directory('${cache.path}/$_root');
  }

  /// The cache folder of [layer] for the map file [tilesId].
  static Future<Directory> folder(String tilesId, String layer) async =>
      Directory(
        '${(await _rootDir(rootForTest)).path}/${folderName(tilesId)}/$layer',
      );

  static String? _latest;
  static Future<void> _cleaning = Future.value();

  /// Deletes the caches of other map files. Calls run one after another, and
  /// each delete checks the newest call first, so a cleanup still running
  /// never deletes the folder of a map asked for later. MapState calls this
  /// only while it is in use.
  static Future<void> keepOnly(String tilesId) {
    _latest = tilesId;
    // The root as it is now: a test that ends never sends a late cleanup
    // to the real cache folder.
    final test = rootForTest;
    return _cleaning = _cleaning.then((_) => _clean(test));
  }

  /// Done when every cleanup asked for so far has run.
  @visibleForTesting
  static Future<void> get idle => _cleaning;

  static Future<void> _clean(Future<Directory> Function()? test) async {
    if (_latest == null) return;
    try {
      await removeOthers(await _rootDir(test), () => folderName(_latest!));
    } catch (e) {
      debugPrint('map tile cache: $e');
    }
    if (test != null) return;
    // Folders used before: this app's own (in the temporary folder, so
    // app-specific in name), and vector_map_tiles' default `.vector_map`,
    // only where the temporary folder belongs to this app alone (not
    // Windows or Linux, where other apps may use that name).
    try {
      final old = Directory(
        '${(await getTemporaryDirectory()).path}/lychnion-map-tiles',
      );
      if (await old.exists()) await old.delete(recursive: true);
    } catch (e) {
      debugPrint('map tile cache: $e');
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final old = Directory(
          '${(await getTemporaryDirectory()).path}/'
          '.vector_map',
        );
        if (await old.exists()) await old.delete(recursive: true);
      } catch (e) {
        debugPrint('map tile cache: $e');
      }
    }
  }

  /// Deletes everything in [root] except the entry named [keep] (asked
  /// again before each delete). One entry that cannot be deleted does not
  /// stop the others.
  @visibleForTesting
  static Future<void> removeOthers(
    Directory root,
    String Function() keep,
  ) async {
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (e.path.split(RegExp(r'[/\\]')).last == keep()) continue;
      try {
        await e.delete(recursive: true);
      } catch (err) {
        debugPrint('map tile cache: $err');
      }
    }
  }
}
