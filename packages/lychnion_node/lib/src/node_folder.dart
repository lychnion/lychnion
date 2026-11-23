import 'dart:convert';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';

/// A node's folder, the same layout everywhere (docs/distribution.md):
///
/// ```text
/// catalog.json             signed records, files listed by hash
/// blobs/sha256/<sha256>    every file, named by its SHA-256
/// ```
///
/// lychnion-data's `tool/records.dart export` writes the same layout, so
/// a folder from a USB stick can be served as it is.
class NodeFolder {
  NodeFolder(this.dir);

  final Directory dir;

  File get catalogFile => File('${dir.path}/catalog.json');
  Directory get blobs => Directory('${dir.path}/blobs/sha256');

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// The file of [sha256], or null when that is not a hash (so no path
  /// from a request or a record ever reaches the file system).
  File? blob(String sha256) =>
      _hex64.hasMatch(sha256) ? File('${blobs.path}/$sha256') : null;

  /// Every record in catalog.json by its shape, signature not checked
  /// (who had what here); empty when there is no catalog yet.
  Future<List<PackageRecord>> allRecords() async {
    final doc = await _document();
    if (doc == null) return const [];
    final out = <PackageRecord>[];
    for (final raw in doc.records) {
      try {
        out.add(PackageRecord.fromJson((raw as Map).cast()));
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// The records in catalog.json that [trust] accepts (others are left
  /// out); empty when there is no catalog yet.
  Future<List<PackageRecord>> records(TrustedKeys trust) async {
    final doc = await _document();
    if (doc == null) return const [];
    final t = trust.withStatements(await relevantStatements(trust, doc.keys));
    return [for (final raw in doc.records) ?await t.check(raw)];
  }

  /// The key statements in catalog.json that [trust] counts (see
  /// relevantStatements); empty when there is no catalog yet.
  Future<List<KeyStatement>> keys(TrustedKeys trust) async {
    final doc = await _document();
    return doc == null ? const [] : relevantStatements(trust, doc.keys);
  }

  /// The attestations in catalog.json that [trust] counts (signed by a key it
  /// has for Lychnion, after the catalog's key statements); empty when
  /// there is no catalog yet. Labels only (lychnion/lychnion#119).
  Future<List<Attestation>> attestations(TrustedKeys trust) async {
    final doc = await _document();
    if (doc == null) return const [];
    final t = trust.withStatements(await relevantStatements(trust, doc.keys));
    return Attestation.checkAll(doc.attestations, t);
  }

  /// The publisher statuses in catalog.json that [trust] counts (signed by
  /// a key it has for their publisher, after the catalog's key statements);
  /// empty when there is no catalog yet (lychnion/lychnion#117).
  Future<List<PublisherStatus>> status(TrustedKeys trust) async {
    final doc = await _document();
    if (doc == null) return const [];
    final t = trust.withStatements(await relevantStatements(trust, doc.keys));
    return PublisherStatus.checkAll(doc.status, t);
  }

  Future<CatalogDocument?> _document() async {
    if (!await catalogFile.exists()) return null;
    try {
      return CatalogDocument.parse(await catalogFile.readAsString());
    } on FormatException {
      throw FormatException('${catalogFile.path}: not a format 2 catalog');
    }
  }

  /// Records set aside by `pull` because their publisher was not given,
  /// or because their files are not all here (lychnion/lychnion#75): not
  /// served, their files kept, their versions still count.
  /// `.kept.json` (not served).
  File get keptFile => File('${dir.path}/.kept.json');

  Future<List<PackageRecord>> keptRecords() async {
    try {
      final j = jsonDecode(await keptFile.readAsString()) as List;
      return [for (final raw in j) ?_shape(raw)];
    } on Object {
      return const [];
    }
  }

  static PackageRecord? _shape(Object? raw) {
    try {
      return PackageRecord.fromJson((raw as Map).cast());
    } on Object {
      return null;
    }
  }

  Future<void> writeKept(List<PackageRecord> records) async {
    if (records.isEmpty) {
      if (await keptFile.exists()) await keptFile.delete();
      return;
    }
    final tmp = File('${keptFile.path}.$pid.tmp');
    await tmp.writeAsString(
      jsonEncode([for (final r in records) r.json]),
      flush: true,
    );
    await tmp.rename(keptFile.path);
  }

  /// Writes catalog.json (next to it, then renamed: a cut write leaves
  /// the old one). Every file is listed at its place in this folder.
  /// [keys]: key statements to pass on (replaced and revoked keys);
  /// [attestations]: Lychnion's attestations to pass on; [status]:
  /// publishers' statuses to pass on (the newest of each is written).
  /// Returns how many of each were left out to fit.
  Future<({int keys, int attestations, int status})> writeCatalog(
    List<PackageRecord> records, {
    List<String> mirrors = const [],
    Iterable<KeyStatement> keys = const [],
    Iterable<Attestation> attestations = const [],
    Iterable<PublisherStatus> status = const [],
  }) async {
    await dir.create(recursive: true);
    final doc = CatalogDocument.byHash(
      records,
      keys: keys,
      attestations: attestations,
      status: status,
      mirrors: mirrors,
    ).fitted();
    final text = doc.encode();
    final tmp = File('${catalogFile.path}.$pid.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(catalogFile.path);
    return (
      keys: CatalogDocument.keysLeftOut(keys, doc),
      attestations: CatalogDocument.attestationsLeftOut(attestations, doc),
      status: CatalogDocument.statusLeftOut(status, doc),
    );
  }
}
