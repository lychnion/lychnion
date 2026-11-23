import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:lychnion_guide/lychnion_guide.dart';
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
  /// `title`, `key`, `kind` (a model: only Lychnion publishes those; the
  /// form does not offer it, so it has no text of its own).
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

/// Why the app could not use the guide at [path] (it is opened as the
/// app does to answer), or null when it can. Read in another isolate: a
/// large guide takes a while.
Future<String?> guideProblem(String path) =>
    Isolate.run(() => _guideProblem(path));

String? _guideProblem(String path) {
  String short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;
  // The shared check first (lychnion-studio runs the same): it says what
  // is wrong. Then the app's own reader, as it opens guides to answer.
  try {
    checkGuide(path);
  } on GuideProblem catch (e) {
    return short(e.message);
  } on Object catch (e) {
    return short('$e');
  }
  try {
    final p = KnowledgePackage.open(path);
    // Opens, but gives the app nothing to answer with.
    if (p.passages.isEmpty) return 'no passages';
    return null;
  } on SqliteException catch (e) {
    return short(e.message); // "no such table: sources"
  } on FormatException {
    return 'broken JSON in a table';
  } on TypeError {
    return 'a missing value, or a passage or alert without its source';
  } on Object catch (e) {
    return short('$e');
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
  // This computer's publisher is an added one: guides and maps only, no
  // models (#67). The form does not offer models; this keeps it so.
  if (builtInOnlyKinds.contains(req.kind.name)) {
    throw PublishError('kind', req.kind.name);
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
      // Phones must be able to use what is signed and passed on: the
      // copy that gets signed is opened as the app does to answer.
      if (req.kind == ItemKind.package) {
        if (await guideProblem(copy.path) case final p?) {
          throw PublishError('package', p);
        }
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
      'signed': nowStamp(),
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

/// Safe to run again (after a failure, or when Publish your own opens):
/// what was done already is skipped.
///
/// After this computer's publisher key was replaced or revoked
/// ([LocalPublisher.replaceKey], [LocalPublisher.revokeAndRenew]): this
/// computer learns the key statements, so it trusts the new key; it adds
/// the new link when the old key was revoked; and it re-signs the newest
/// record of each item it published with the new key. An item installed
/// here with the same files is recorded with the new record, so it stays
/// in use and is passed on signed by the new key. Returns the ids
/// re-signed. Throws [PublishError] (`key`) when the new key cannot be
/// trusted here, and the save's error when the publisher list cannot be
/// saved.
Future<List<String>> adoptNewKey(
  DownloadStore store,
  Directory publisherDir,
  LocalPublisher publisher,
) async {
  if (publisher.statements.isNotEmpty) {
    await LocalPublisher.writeKeysFile(publisherDir, publisher.statements);
  }
  // All of them (`any`): they are this computer's own, and before the
  // first publish its key is not trusted here yet, so a plain learn
  // would drop them; then a replaced key would not be known as replaced,
  // and could be replaced a second time (#59). Only those about this
  // publisher: `any` must not get statements about anyone else.
  final own = [
    for (final s in publisher.statements)
      if (s.publisher == publisher.name) s,
  ];
  await store.publishers.learn(own, any: true);
  // Kept past the limit too (learn), up to its hard limit: if even that
  // is full, the user must know, since the refusals in key_actions.dart
  // rely on them. Said at the end: the new key is still trusted and the
  // records signed again.
  final kept = {for (final s in store.publishers.statements) s.id};
  final notKept = !own.every((s) => kept.contains(s.id));
  final out = await _adoptLink(store, publisherDir, publisher);
  if (notKept) {
    throw PublishError(
      'key',
      'statements not kept: the publisher list is full',
    );
  }
  return out;
}

/// The rest of [adoptNewKey]: trusts [publisher]'s link and signs its
/// records again; the ids re-signed.
Future<List<String>> _adoptLink(
  DownloadStore store,
  Directory publisherDir,
  LocalPublisher publisher,
) async {
  switch (store.publishers.problemWith(publisher.link)) {
    case null:
      await store.publishers.add(publisher.link);
    case PublisherProblem.known:
      break;
    case final p:
      throw PublishError('key', p.name);
  }
  final pair = await publisher.keyPair();
  final out = <String>[];
  final records = Directory('${publisherDir.path}/records');
  if (!await records.exists()) return out;
  await for (final d in records.list()) {
    if (d is! Directory) continue;
    final id = d.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final version = lastPublished(publisherDir, id);
    if (version == null) continue;
    final f = recordFile(publisherDir, id, version);
    final PackageRecord old;
    try {
      old = PackageRecord.fromJson(
        (jsonDecode(await f.readAsString()) as Map).cast(),
      );
    } on Object {
      continue;
    }
    if (old.publisher != publisher.name || old.keyId == publisher.keyId) {
      continue;
    }
    final r = await PackageRecord.sign({
      ...old.json,
      'signed': nowStamp(),
    }, pair);
    final tmp = File('${f.path}.$pid.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(r.json)}\n',
      flush: true,
    );
    await tmp.rename(f.path);
    out.add(id);
    await _reinstall(store, r);
  }
  return out;
}

/// Records [r] as installed when the same version of its item is
/// installed here from the same publisher and every file still matches.
Future<void> _reinstall(DownloadStore store, PackageRecord r) async {
  final ItemKind kind;
  try {
    kind = ItemKind.values.byName(r.kind);
  } on ArgumentError {
    return;
  }
  final here = store.recordOnDisk(kind, r.id);
  if (here == null ||
      here.publisher != r.publisher ||
      here.version != r.version ||
      canonicalJson([for (final f in here.files) f.toJson()]) !=
          canonicalJson([for (final f in r.files) f.toJson()])) {
    return;
  }
  final item = CatalogItem.fromRecord(r);
  for (final f in item.files) {
    final file = File('${store.dirFor(kind).path}/${f.name}');
    if (!await file.exists() || await sha256OfFile(file) != f.sha256) return;
  }
  await store.markInstalled(item);
}
