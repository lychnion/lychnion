import 'dart:convert';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';

import 'catalog.dart';
import 'download_store.dart';
import 'downloader.dart';

// A USB stick between places without any network (docs/distribution.md,
// step 5d). The stick holds a normal node folder, so the app, the headless
// node and lychnion-data's export all read and write the same thing:
//
//   lychnion/catalog.json            signed records, files by hash
//   lychnion/blobs/sha256/<sha256>   every file
//
// Nothing on a stick is trusted: records are checked against the
// publishers this device trusts, every file against its hash.

/// The folder on a stick: `<stick>/lychnion`, or the stick itself when its
/// catalog.json is at the top (a node folder copied as it is).
Directory stickFolder(Directory picked) {
  final inner = Directory('${picked.path}/lychnion');
  if (File('${inner.path}/catalog.json').existsSync()) return inner;
  if (File('${picked.path}/catalog.json').existsSync()) return picked;
  return inner;
}

/// What a copy or a load did.
class StickResult {
  /// Copied to the stick, or installed from it.
  var added = 0;

  /// On the stick already (same or newer), or here already.
  var notNewer = 0;

  /// Records not signed by a publisher this device trusts.
  var notTrusted = 0;

  /// Ids or files that belong to another publisher here.
  var taken = 0;

  /// Items whose files were missing or did not match.
  final failed = <String>[];
}

/// Copies everything installed in [store] to [stick]: the stick keeps what
/// it has, an item is replaced only by a newer version (versions only go
/// up), and files no record lists any more are removed from it.
Future<StickResult> copyToStick(DownloadStore store, Directory stick) async {
  final result = StickResult();
  final folder = stickFolder(stick);
  final blobs = Directory('${folder.path}/blobs/sha256');
  await blobs.create(recursive: true);

  // What the stick has, by id (signatures are kept as they are: the
  // device reading the stick checks them).
  final onStick = <String, PackageRecord>{};
  for (final r in await _records(folder)) {
    final have = onStick[r.id];
    if (have == null || isOlder(have.version, r.version)) onStick[r.id] = r;
  }

  for (final kind in ItemKind.values) {
    for (final i in store.allInstalled(kind)) {
      final r = i.record;
      final there = onStick[r.id];
      if (there != null && !isOlder(there.version, r.version)) {
        result.notNewer++;
        continue;
      }
      var ok = true;
      for (final f in r.files) {
        final target = File('${blobs.path}/${f.sha256}');
        if (target.existsSync() && target.lengthSync() == f.size) continue;
        final source = File(store.path(i, f.name));
        if (!source.existsSync() || source.lengthSync() != f.size) {
          ok = false;
          break;
        }
        final part = File('${target.path}.copy');
        await source.copy(part.path);
        await part.rename(target.path);
      }
      if (!ok) {
        result.failed.add('${r.id} ${r.version}');
        continue;
      }
      onStick[r.id] = r;
      result.added++;
    }
  }

  final records = onStick.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final tmp = File('${folder.path}/catalog.json.copy');
  await tmp.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'format': 2,
      'records': [for (final r in records) r.json],
      'urls': {for (final r in records)
        for (final f in r.files) f.sha256: 'blobs/sha256/${f.sha256}'},
    })}\n',
    flush: true,
  );
  await tmp.rename('${folder.path}/catalog.json');

  // Files of versions replaced on the stick.
  final keep = {
    for (final r in records)
      for (final f in r.files) f.sha256,
  };
  final hash = RegExp(r'^[0-9a-f]{64}$');
  for (final f in blobs.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (hash.hasMatch(name) && !keep.contains(name)) f.deleteSync();
  }
  return result;
}

/// Installs from [stick] what is newer than what [store] has: records of
/// trusted publishers only, every file checked by its hash, versions only
/// go up, ids and file names stay with their publisher. The files of one
/// item are all checked before any of them replaces an installed one.
Future<StickResult> loadFromStick(DownloadStore store, Directory stick) async {
  final result = StickResult();
  final folder = stickFolder(stick);
  final file = File('${folder.path}/catalog.json');
  if (!file.existsSync()) throw const FileSystemException('no catalog');
  final j = jsonDecode(await file.readAsString());
  if (j is! Map || j['format'] != 2 || j['records'] is! List) {
    throw const FormatException('not a format 2 catalog');
  }
  final urls = j['urls'] is Map ? (j['urls'] as Map) : const {};

  for (final raw in j['records'] as List) {
    final r = await store.trust.check(raw);
    if (r == null) {
      result.notTrusted++;
      continue;
    }
    if (!ItemKind.values.any((k) => k.name == r.kind)) continue;
    final item = CatalogItem.fromRecord(r);
    if (store.isTaken(item)) {
      result.taken++;
      continue;
    }
    final have = store.installedVersion(item) ?? store.recordedVersion(item);
    if (have != null && !isOlder(have, r.version)) {
      result.notNewer++;
      continue;
    }
    final dir = store.dirFor(item.kind);
    await dir.create(recursive: true);
    final staged = <(File, File)>[];
    var ok = true;
    for (final f in r.files) {
      final source = _blobOnStick(folder, f, urls[f.sha256]);
      final target = File('${dir.path}/${f.name}');
      final part = File('${target.path}.part');
      if (source == null || source.lengthSync() != f.size) {
        ok = false;
        break;
      }
      await source.copy(part.path);
      if (await sha256OfFile(part) != f.sha256) {
        await part.delete();
        ok = false;
        break;
      }
      staged.add((part, target));
    }
    if (!ok) {
      for (final (part, _) in staged) {
        if (part.existsSync()) await part.delete();
      }
      result.failed.add('${r.id} ${r.version}');
      continue;
    }
    for (final (part, target) in staged) {
      try {
        await part.rename(target.path);
      } on FileSystemException {
        // Windows may not replace on rename.
        if (target.existsSync()) await target.delete();
        await part.rename(target.path);
      }
    }
    await store.markInstalled(item);
    result.added++;
  }
  return result;
}

/// The file of [f] on the stick: its `urls` entry when that is a path in
/// the folder, else `blobs/sha256/<hash>`; null when it is not there.
File? _blobOnStick(Directory folder, RecordFile f, Object? listed) {
  final candidates = [
    if (listed is String &&
        !listed.contains('..') &&
        !listed.startsWith('/') &&
        !(Uri.tryParse(listed)?.hasScheme ?? true))
      listed,
    'blobs/sha256/${f.sha256}',
  ];
  for (final c in candidates) {
    final file = File('${folder.path}/$c');
    if (file.existsSync()) return file;
  }
  return null;
}

/// The records on a stick by their shape (signatures are checked by the
/// device that loads them).
Future<List<PackageRecord>> _records(Directory folder) async {
  final file = File('${folder.path}/catalog.json');
  if (!file.existsSync()) return const [];
  try {
    final j = jsonDecode(await file.readAsString()) as Map;
    return [
      for (final raw in (j['records'] as List?) ?? const []) ?_shape(raw),
    ];
  } on Object {
    return const [];
  }
}

PackageRecord? _shape(Object? raw) {
  try {
    return PackageRecord.fromJson((raw as Map).cast());
  } on Object {
    return null;
  }
}
