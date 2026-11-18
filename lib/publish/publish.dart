import 'dart:convert';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/catalog.dart';
import '../download/download_store.dart';
import '../download/downloader.dart';
import '../download/publisher_list.dart';
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

  /// `id`, `version`, `older`, `files`, `meta`, `taken`, `title`, `key`.
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

/// A form prefilled from a package file: id, version, titles (the
/// package's `name` per language, else its `title`) and notice.
PublishRequest? requestFromPackage(File f) {
  final meta = packageMeta(f);
  if (meta == null || (meta['id'] ?? '').isEmpty) return null;
  Map<String, Object?> json(String k) {
    try {
      return (jsonDecode(meta[k] ?? '{}') as Map).cast();
    } on FormatException {
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
  final probe = {
    'format': 1,
    'id': req.id,
    'kind': req.kind.name,
    'version': req.version,
    'publisher': publisher.name,
    'key': 'x',
    'signed': 'x',
    'signature': 'x',
    'files': [
      {'name': 'x', 'size': 1, 'sha256': '0' * 64},
    ],
  };
  try {
    PackageRecord.fromJson(probe);
  } on FormatException catch (e) {
    throw PublishError(
      e.message.contains('version') ? 'version' : 'id',
      e.message,
    );
  }
  if (req.titles.values.every((t) => t.trim().isEmpty)) {
    throw PublishError('title');
  }
  if (req.files.isEmpty) throw PublishError('files');
  for (final f in req.files) {
    final name = f.uri.pathSegments.last;
    if (!name.startsWith('${req.id}.') || !f.existsSync()) {
      throw PublishError('files', name);
    }
  }
  if (req.kind == ItemKind.package) {
    if (req.files.length != 1) throw PublishError('files');
    final meta = packageMeta(req.files.single);
    if (meta == null ||
        meta['id'] != req.id ||
        (meta['version'] ?? '') != req.version) {
      throw PublishError('meta', '${meta?['id']} ${meta?['version']}');
    }
  }

  // Versions only go up: past this publisher's own records and what is
  // installed here.
  final installed = store.installed(req.kind, req.id);
  if (installed != null && installed.record.publisher != publisher.name) {
    throw PublishError('taken', installed.record.publisher);
  }
  for (final have in [
    lastPublished(publisherDir, req.id),
    installed?.version,
  ]) {
    if (have != null && compareVersions(req.version, have) <= 0) {
      throw PublishError('older', have);
    }
  }

  // This computer trusts its own publisher, so it installs and serves the
  // records it signs. A name already added with another key is refused.
  switch (store.publishers.problemWith(publisher.link)) {
    case null:
      await store.publishers.add(publisher.link);
    case PublisherProblem.known:
      break;
    case final p:
      throw PublishError('key', p.name);
  }

  final files = <Map<String, Object?>>[];
  for (final f in req.files) {
    files.add({
      'name': f.uri.pathSegments.last,
      'size': await f.length(),
      'sha256': await sha256OfFile(f),
    });
  }
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

  // Copy in (each file next to its target, then renamed), then record it.
  final dir = store.dirFor(req.kind);
  await dir.create(recursive: true);
  for (final f in req.files) {
    final target = File('${dir.path}/${f.uri.pathSegments.last}');
    if (f.absolute.path == target.absolute.path) continue;
    final part = File('${target.path}.publishing');
    await f.copy(part.path);
    try {
      await part.rename(target.path); // replaces the old version (POSIX)
    } on FileSystemException {
      // Windows does not replace on rename.
      if (!await target.exists()) rethrow;
      await target.delete();
      await part.rename(target.path);
    }
  }
  await store.markInstalled(CatalogItem.fromRecord(record));

  final out = recordFile(publisherDir, req.id, req.version);
  await out.parent.create(recursive: true);
  await out.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(record.json)}\n',
  );
  return record;
}

/// `2026-11-18T09:00:00+09:00`
String _now() {
  final t = DateTime.now();
  final o = t.timeZoneOffset;
  String two(int n) => n.abs().toString().padLeft(2, '0');
  return '${t.toIso8601String().substring(0, 19)}'
      '${o.isNegative ? '-' : '+'}${two(o.inHours)}:${two(o.inMinutes % 60)}';
}
