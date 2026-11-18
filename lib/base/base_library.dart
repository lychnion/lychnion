import 'dart:io';

import '../download/catalog.dart';
import '../download/download_store.dart';

import 'package:lychnion_format/lychnion_format.dart';

/// What a base computer passes on to phones on its Wi-Fi: everything it
/// has installed from Downloads, as a catalog of the publishers' signed
/// records with the files addressed by their hash
/// (docs/distribution.md, step 2).
///
/// Phones trust the signatures, not the base: a record or file that was
/// changed fails their checks like a bad download from anywhere else.
class BaseLibrary {
  BaseLibrary(this.store);

  final DownloadStore store;

  List<Installed> get items => [
    for (final k in ItemKind.values) ...store.allInstalled(k),
  ];

  /// A format-2 catalog: the signed records unchanged, for each file its
  /// address on this base (relative to the catalog's own URL), and the
  /// key statements this computer knows, so phones learn of replaced and
  /// revoked publisher keys here too.
  Map<String, Object?> catalog() {
    final all = items;
    // Phones ask for the files of the catalog they got: those are known.
    _remember(all);
    return CatalogDocument.byHash(
      [for (final i in all) i.record],
      keys: store.publishers.statements.take(KeyStatement.maxPerSource),
    ).toJson();
  }

  /// The installed file with this SHA-256, or null. Only files listed in a
  /// signed install record are served (no paths from the request).
  ///
  /// Looked up in a map from hash to file, made again with every
  /// [catalog] and when a hash is not in it, at most every
  /// [rescanAfter]: a phone asking
  /// for random hashes does not make the base read every install marker
  /// each time. A file whose size changed (updated meanwhile) is not
  /// served from the map.
  File? blob(String sha256) {
    final hit = _bySha?[sha256];
    if (hit != null && _fits(hit)) return hit.$1;
    if (_bySha == null || _sinceMade.elapsed >= rescanAfter || hit != null) {
      _remember(items);
    }
    final again = _bySha![sha256];
    return again != null && _fits(again) ? again.$1 : null;
  }

  /// How often a hash not known yet makes the map be made again.
  static const rescanAfter = Duration(seconds: 5);

  Map<String, (File, int)>? _bySha;

  /// Not the wall clock: it may be set back.
  final _sinceMade = Stopwatch();

  void _remember(List<Installed> all) {
    _bySha = {
      for (final i in all)
        for (final f in i.record.files)
          f.sha256: (File(store.path(i, f.name)), f.size),
    };
    _sinceMade
      ..reset()
      ..start();
  }

  static bool _fits((File, int) e) {
    try {
      return e.$1.lengthSync() == e.$2;
    } on FileSystemException {
      return false;
    }
  }
}
