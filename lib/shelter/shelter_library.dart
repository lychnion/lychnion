import 'dart:io';

import '../download/catalog.dart';
import '../download/download_store.dart';

/// What a shelter computer passes on to phones on its Wi-Fi: everything it
/// has installed from Downloads, as a catalog of the publishers' signed
/// records with the files addressed by their hash
/// (docs/distribution.md, step 2).
///
/// Phones trust the signatures, not the shelter: a record or file that was
/// changed fails their checks like a bad download from anywhere else.
class ShelterLibrary {
  ShelterLibrary(this.store);

  final DownloadStore store;

  List<Installed> get items => [
    for (final k in ItemKind.values) ...store.allInstalled(k),
  ];

  /// A format-2 catalog: the signed records unchanged, and for each file
  /// its address on this shelter, relative to the catalog's own URL.
  Map<String, Object?> catalog() {
    final all = items;
    return {
      'format': 2,
      'records': [for (final i in all) i.record.json],
      'urls': {
        for (final i in all)
          for (final f in i.record.files) f.sha256: 'blobs/sha256/${f.sha256}',
      },
    };
  }

  /// The installed file with this SHA-256, or null. Only files listed in a
  /// signed install record are served (no paths from the request).
  File? blob(String sha256) {
    for (final i in items) {
      for (final f in i.record.files) {
        if (f.sha256 == sha256) return File(store.path(i, f.name));
      }
    }
    return null;
  }
}
