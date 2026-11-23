import 'dart:io';

import '../download/catalog.dart';
import '../download/download_store.dart';
import '../download/publisher_label.dart';
import '../knowledge/knowledge_package.dart' show Source, SourceLabel;

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
  /// revoked publisher keys here too, and Lychnion's vouches (#119).
  ///
  /// Made again only when the installed records, the key statements or
  /// the vouches changed: fitting it to 2 MB encodes the whole catalog,
  /// and every phone asks for it (lychnion/lychnion#59). The same map is returned
  /// until then: callers must not change it or what it holds.
  /// How this base labels the signer of [s]'s guide (#119), sent with
  /// its answers.
  SourceLabel? labelOf(Source s) =>
      store.sourceLabelOf(s.signer, s.signerKeyId);

  Map<String, Object?> catalog() {
    final all = items;
    // Phones ask for the files of the catalog they got: those are known.
    _remember(all);
    final keys = store.publishers.statements;
    // Only those of a key trusted now for Lychnion, also between a
    // revocation and the list's recheck.
    final vouches = store.vouches.vouchesFor(store.trust);
    // Each record by its signature, each statement and vouch as the same
    // object (PublisherList and VouchList keep them): exact, no hash that
    // could collide.
    final signatures = [for (final i in all) '${i.record.json['signature']}'];
    if (_cached case final c?
        when _same(c.signatures, signatures) &&
            _sameItems(c.keys, keys) &&
            _sameItems(c.vouches, vouches)) {
      return c.json;
    }
    final doc = CatalogDocument.byHash(
      [for (final i in all) i.record],
      keys: keys,
      vouches: vouches,
      // The order phones show, as before.
      sort: false,
    ).fitted();
    keysLeftOut = CatalogDocument.keysLeftOut(keys, doc);
    vouchesLeftOut = CatalogDocument.vouchesLeftOut(vouches, doc);
    final json = Map<String, Object?>.unmodifiable(doc.toJson());
    _cached = (
      signatures: signatures,
      keys: keys,
      vouches: vouches,
      json: json,
    );
    return json;
  }

  /// Key statements the last [catalog] left out to stay under 2 MB
  /// (revocations and theft proofs kept first; #59).
  var keysLeftOut = 0;

  /// Vouches the last [catalog] left out to stay under 2 MB (they go
  /// before key statements; withdrawals kept first).
  var vouchesLeftOut = 0;

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

  /// The last [catalog] and what it was made from (one isolate: no
  /// locking).
  ({
    List<String> signatures,
    List<KeyStatement> keys,
    List<Vouch> vouches,
    Map<String, Object?> json,
  })?
  _cached;

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameItems<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
    }
    return true;
  }
}
