import 'dart:convert';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/catalog.dart';
import '../download/download_store.dart';
import '../download/downloader.dart';
import '../download/publisher_list.dart';
import '../knowledge/knowledge_package.dart';
import 'local_publisher.dart';

// Signs a package or map area that was built elsewhere (lychnion-data
// tools, later the package studio) and installs it on this computer, so
// the base passes it on to phones (docs/distribution.md, step 4b).

/// What the user fills in (prefilled from the package file).
class PublishRequest {
  const PublishRequest({
    required this.kind,
    required this.id,
    required this.version,
    required this.titles,
    required this.files,
    this.notes = const {},
    this.licence = '',
    this.notice = const {},
  });

  final ItemKind kind;
  final String id, version, licence;

  /// Language code → text.
  final Map<String, String> titles, notes;

  /// Language → lines shown before the package is relied on.
  final Map<String, List<String>> notice;
  final List<File> files;
}

/// Why something cannot be published.
class PublishError implements Exception {
  PublishError(this.code, [this.detail = '']);

  /// `id`, `version`, `older`, `files`, `meta`, `package`, `taken`,
  /// `title`, `key`.
  final String code;
  final String detail;
  @override
  String toString() =>
      'PublishError($code${detail.isEmpty ? '' : ': $detail'})';
}

/// The meta table of a package file, or null when it is not one.
Map<String, String>? packageMeta(File f) {
  try {
    final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
    try {
      return {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
    } finally {
      db.close();
    }
  } on Object {
    return null;
  }
}

/// Why the app could not use the guide [f] (it opens it as it does to
/// answer), or null when it can: tables or columns missing, a passage
/// without its source, or no passages at all.
String? guideProblem(File f) {
  try {
    final p = KnowledgePackage.open(f.path);
    if (p.passages.isEmpty) return 'no passages';
    return null;
  } on SqliteException catch (e) {
    return e.message;
  } on Object catch (e) {
    return '${e.runtimeType}';
  }
}

/// A form prefilled from a package file: id, version, titles (the
/// package's `name` per language, else its `title`) and notice.
PublishRequest? requestFromPackage(File f) {
  final meta = packageMeta(f);
  if (meta == null || (meta['id'] ?? '').isEmpty) return null;
  // Any JSON that is not an object (null, a list, broken text) counts as
  // empty: the form is only prefilled from it.
  Map<String, Object?> json(String k) {
    try {
      final v = jsonDecode(meta[k] ?? '{}');
      return v is Map ? v.cast<String, Object?>() : const {};
    } on Object {
      return const {};
    }
  }

  final names = {
    for (final e in json('name').entries)
      if (e.value is String && (e.value as String).isNotEmpty)
        e.key: e.value as String,
  };
  final title = meta['title'] ?? '';
  return PublishRequest(
    kind: ItemKind.package,
    id: meta['id']!,
    version: meta['version'] ?? '',
    titles: names.isNotEmpty ? names : {if (title.isNotEmpty) 'ja': title},
    notice: {
      for (final e in json('notice').entries)
        if (e.value is List) e.key: [for (final l in e.value as List) '$l'],
    },
    files: [f],
  );
}

/// Where this publisher keeps the records it signed:
/// `<dir>/records/<id>/<version>.json`, the layout of lychnion-data.
File recordFile(Directory dir, String id, String version) =>
    File('${dir.path}/records/$id/$version.json');

/// The newest version of [id] this publisher signed, if any.
String? lastPublished(Directory dir, String id) {
  final d = Directory('${dir.path}/records/$id');
  if (!d.existsSync()) return null;
  String? best;
  for (final f in d.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.json')) continue;
    final v = name.substring(0, name.length - 5);
    try {
      if (best == null || compareVersions(v, best) > 0) best = v;
    } on FormatException {
      continue;
    }
  }
  return best;
}

/// Signs [req] as [publisher], copies its files into [store] and records
/// them as installed. Returns the signed record.
///
/// Refuses (PublishError): a version that is not higher than one already
/// signed or installed (versions only go up), an id installed from another
/// publisher, a package file whose meta does not match the form, and
/// files that are not named after the id.
Future<PackageRecord> publish(
  PublishRequest req, {
  required LocalPublisher publisher,
  required DownloadStore store,
  required Directory publisherDir,
}) async {
  // The record's shape, with the real file names: ids and names end up in
  // file paths.
  try {
    PackageRecord.fromJson({
      'format': 1,
      'id': req.id,
      'kind': req.kind.name,
      'version': req.version,
      'publisher': publisher.name,
      'key': 'x',
      'signed': 'x',
      'signature': 'x',
      'files': [
        for (final f in req.files)
          {'name': f.uri.pathSegments.last, 'size': 1, 'sha256': '0' * 64},
      ],
    });
  } on FormatException catch (e) {
    final m = e.message;
    throw PublishError(
      m.contains('version')
          ? 'version'
          : m.contains('file') || m.contains('files')
          ? 'files'
          : 'id',
      m,
    );
  }
  if (req.titles.values.every((t) => t.trim().isEmpty)) {
    throw PublishError('title');
  }
  final names = [for (final f in req.files) f.uri.pathSegments.last];
  for (final (i, f) in req.files.indexed) {
    final name = names[i];
    if (!name.startsWith('${req.id}.') ||
        DownloadStore.isReservedName(name) ||
        !f.existsSync()) {
      throw PublishError('files', name);
    }
  }
  if (names.map((n) => n.toLowerCase()).toSet().length != names.length) {
    throw PublishError('files');
  }
  // What the app needs to use it: a guide is `<id>.sqlite`; a map area
  // has at least its tiles and its evacuation sites.
  final need = switch (req.kind) {
    ItemKind.package => ['${req.id}.sqlite'],
    ItemKind.map => ['${req.id}.pmtiles', '${req.id}.sites.sqlite'],
    ItemKind.model => const <String>[],
  };
  for (final n in need) {
    if (!names.contains(n)) throw PublishError('files', n);
  }
  if (req.kind == ItemKind.package) {
    if (req.files.length != 1) throw PublishError('files');
    final meta = packageMeta(req.files.single);
    if (meta == null ||
        meta['id'] != req.id ||
        (meta['version'] ?? '') != req.version) {
      throw PublishError('meta', '${meta?['id']} ${meta?['version']}');
    }
    // Phones must be able to use what is signed and passed on: the app
    // opens the guide as it would to answer, and it needs passages.
    if (guideProblem(req.files.single) case final p?) {
      throw PublishError('package', p);
    }
  }
  // This computer must trust its own publisher to install what it signs.
  // A name already added with another key is refused.
  final trusted = store.publishers.problemWith(publisher.link);
  if (trusted != null && trusted != PublisherProblem.known) {
    throw PublishError('key', trusted.name);
  }

  // Versions only go up: past this publisher's own records and what is
  // installed here.
  final installed = store.installed(req.kind, req.id);
  for (final have in [
    lastPublished(publisherDir, req.id),
    installed?.version,
    // Also an install no longer trusted or incomplete: files are replaced
    // below, before the install is recorded.
    store.recordedVersionOf(req.kind, req.id),
  ]) {
    if (have != null && compareVersions(req.version, have) <= 0) {
      throw PublishError('older', have);
    }
  }

  // 1. Copy each file next to its target and hash the copy: the record
  //    describes exactly what gets installed.
  final dir = store.dirFor(req.kind);
  await dir.create(recursive: true);
  final copies = <(File copy, File target)>[];
  try {
    final files = <Map<String, Object?>>[];
    for (final f in req.files) {
      final name = f.uri.pathSegments.last;
      final target = File('${dir.path}/$name');
      var copy = f;
      if (f.absolute.path != target.absolute.path) {
        copy = await f.copy('${target.path}.publishing');
        copies.add((copy, target));
      }
      files.add({
        'name': name,
        'size': await copy.length(),
        'sha256': await sha256OfFile(copy),
      });
    }

    // 2. Sign.
    final record = await PackageRecord.sign({
      'format': 1,
      'id': req.id,
      'kind': req.kind.name,
      'version': req.version,
      'publisher': publisher.name,
      'title': {
        for (final e in req.titles.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      },
      if (req.notes.values.any((n) => n.trim().isNotEmpty))
        'note': {
          for (final e in req.notes.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
        },
      'licence': req.licence.trim(),
      if (req.notice.isNotEmpty) 'notice': req.notice,
      'files': files,
      'signed': _now(),
    }, await publisher.keyPair());
    final item = CatalogItem.fromRecord(record);

    // The id and every file name must not belong to another publisher's
    // item here (files of a kind share one folder).
    if (store.isTaken(item)) throw PublishError('taken', req.id);

    // 3. Keep the signed record first (atomically): it remembers that this
    //    version is used, even if the install below fails.
    final out = recordFile(publisherDir, req.id, req.version);
    await out.parent.create(recursive: true);
    final tmp = File('${out.path}.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(record.json)}\n',
      flush: true,
    );
    await tmp.rename(out.path);

    // 4. Trust the own publisher, put the files in place, record the install.
    if (trusted == null) await store.publishers.add(publisher.link);
    for (final (copy, target) in copies) {
      try {
        await copy.rename(target.path); // replaces the old version (POSIX)
      } on FileSystemException {
        // Windows may not replace on rename.
        if (!await target.exists()) rethrow;
        await target.delete();
        await copy.rename(target.path);
      }
    }
    copies.clear();
    await store.markInstalled(item);
    return record;
  } finally {
    // Copies not moved into place (an error on the way) are removed.
    for (final (copy, _) in copies) {
      if (await copy.exists()) await copy.delete();
    }
  }
}

/// `2026-11-18T09:00:00+09:00`
String _now() {
  final t = DateTime.now();
  final o = t.timeZoneOffset;
  String two(int n) => n.abs().toString().padLeft(2, '0');
  return '${t.toIso8601String().substring(0, 19)}'
      '${o.isNegative ? '-' : '+'}${two(o.inHours)}:${two(o.inMinutes % 60)}';
}
