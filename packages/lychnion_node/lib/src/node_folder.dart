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
    if (!await catalogFile.exists()) return const [];
    final j = jsonDecode(await catalogFile.readAsString());
    if (j is! Map || j['format'] != 2) {
      throw FormatException('${catalogFile.path}: not a format 2 catalog');
    }
    final out = <PackageRecord>[];
    for (final raw in (j['records'] as List?) ?? const []) {
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
    if (!await catalogFile.exists()) return const [];
    final j = jsonDecode(await catalogFile.readAsString());
    if (j is! Map || j['format'] != 2) {
      throw FormatException('${catalogFile.path}: not a format 2 catalog');
    }
    return [
      for (final raw in (j['records'] as List?) ?? const [])
        ?await trust.check(raw),
    ];
  }

  /// Records set aside by `pull` because their publisher was not given:
  /// not served, their files kept. `.kept.json` (not served).
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
  Future<void> writeCatalog(
    List<PackageRecord> records, {
    List<String> mirrors = const [],
  }) async {
    await dir.create(recursive: true);
    final sorted = [...records]..sort((a, b) => a.id.compareTo(b.id));
    final tmp = File('${catalogFile.path}.$pid.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'format': 2,
        'records': [for (final r in sorted) r.json],
        'urls': {for (final r in sorted)
          for (final f in r.files) f.sha256: 'blobs/sha256/${f.sha256}'},
        if (mirrors.isNotEmpty) 'mirrors': mirrors,
      })}\n',
      flush: true,
    );
    await tmp.rename(catalogFile.path);
  }
}
