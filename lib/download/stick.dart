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
/// catalog.json is at the top (a node folder copied as it is) or when the
/// picked folder is the `lychnion` folder.
Directory stickFolder(Directory picked) {
  final inner = Directory('${picked.path}/lychnion');
  if (File('${inner.path}/catalog.json').existsSync()) return inner;
  if (File('${picked.path}/catalog.json').existsSync()) return picked;
  if (picked.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ==
      'lychnion') {
    return picked;
  }
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

  /// Items not copied: the stick holds another publisher's item of the
  /// same id, trusted here.
  final clashed = <String>[];

  /// Items whose files were missing, did not match or could not be
  /// written.
  final failed = <String>[];

  /// Loading learned key statements that changed which keys are trusted:
  /// install records and catalogs must be checked again.
  var keysChanged = false;
}

/// A stick whose catalog.json cannot be read (broken, too large, or from a
/// newer version of the app): nothing is written to it.
class UnreadableStick implements Exception {
  const UnreadableStick(this.reason);
  final String reason;
  @override
  String toString() => 'catalog.json on the stick: $reason';
}

/// Copies everything installed in [store] to [stick]: the stick keeps what
/// it has, an item is replaced only by a newer version (versions only go
/// up), and files no record lists any more are removed from it.
///
/// Records on the stick this device does not trust are kept, unless one of
/// this device's items has the same id: then this device's record takes
/// its place. A stick whose catalog cannot be read is not touched
/// ([UnreadableStick]).
Future<StickResult> copyToStick(DownloadStore store, Directory stick) async {
  final result = StickResult();
  final folder = stickFolder(stick);
  final blobs = Directory('${folder.path}/blobs/sha256');
  // A linked folder would send the writes and the clean-up elsewhere.
  for (final d in [
    if (folder.path != stick.path) folder,
    Directory('${folder.path}/blobs'),
    blobs,
  ]) {
    if (FileSystemEntity.typeSync(d.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const UnreadableStick('a linked folder');
    }
  }
  final old = await _readCatalog(folder);
  await blobs.create(recursive: true);
  // Key statements on the stick stay, and this device adds the ones it
  // knows, so other devices learn of replaced and revoked keys.
  // This device's own first, so statements on the stick cannot crowd
  // them out; of those on the stick, only ones made by keys trusted here.
  final oldStatements = await relevantStatements(store.trust, old?.keys);
  final statements = <KeyStatement>[];
  final seen = <String>{};
  for (final s in [...store.publishers.statements, ...oldStatements]) {
    if (statements.length >= KeyStatement.maxPerSource) break;
    if (seen.add(s.id)) statements.add(s);
  }
  final trust = store.trust.withStatements(oldStatements);

  // What the stick has, by id (signatures are kept as they are: the
  // device reading the stick checks them).
  final onStick = <String, PackageRecord>{};
  final trusted = <String>{};
  for (final raw in old?.records ?? const []) {
    final r = _shape(raw);
    if (r == null) continue;
    final ok = await trust.check(raw) != null;
    final have = onStick[r.id];
    // A trusted record wins over an untrusted one with the same id.
    if (have == null ||
        (ok && !trusted.contains(r.id)) ||
        (ok == trusted.contains(r.id) && isOlder(have.version, r.version))) {
      onStick[r.id] = r;
      if (ok) trusted.add(r.id);
    }
  }

  for (final kind in ItemKind.values) {
    for (final i in store.allInstalled(kind)) {
      final r = i.record;
      final there = onStick[r.id];
      if (there != null &&
          trusted.contains(r.id) &&
          there.publisher != r.publisher) {
        result.clashed.add('${r.id} (${there.publisher})');
        continue;
      }
      final kept =
          there != null &&
          trusted.contains(r.id) &&
          there.publisher == r.publisher &&
          !isOlder(there.version, r.version);
      if (kept && isOlder(r.version, there.version)) {
        // Newer on the stick: kept, but its files must be there.
        result.notNewer++;
        var ok = false;
        try {
          ok = await _onStick(there, blobs);
        } on FileSystemException {
          // Cannot be read: reported below.
        }
        if (!ok) result.failed.add('${there.id} ${there.version}');
        continue;
      }
      // New, newer here, or the same version (its files on the stick are
      // checked, and copied again when missing or damaged).
      var ok = false;
      try {
        ok = await _copyItem(store, i, r, blobs);
      } on FileSystemException {
        // Stick full, a file too large for it, or pulled out: the items
        // copied so far are still listed below.
      }
      if (!ok) {
        result.failed.add('${r.id} ${r.version}');
        continue;
      }
      if (kept) {
        result.notNewer++;
        continue;
      }
      onStick[r.id] = r;
      trusted.add(r.id);
      result.added++;
    }
  }

  final records = onStick.values.toList();
  final String text;
  try {
    text = CatalogDocument.byHash(records, keys: statements).encode();
  } on CatalogTooLarge {
    // Larger, and no device would read the stick any more.
    throw const FileSystemException('catalog.json would be over 2 MB');
  }
  final bytes = utf8.encode(text);
  final tmp = File('${folder.path}/catalog.json.copy');
  _clear(tmp);
  await tmp.writeAsBytes(bytes, flush: true);
  await _replace(tmp, File('${folder.path}/catalog.json'));

  // Files of versions replaced on the stick, and copies left by a stick
  // pulled out earlier.
  final keep = {
    for (final r in records)
      for (final f in r.files) f.sha256,
  };
  // A node folder keeps the files of records whose publisher it was not
  // given (.kept.json); when that cannot be read, nothing is removed.
  final setAside = _keptHashes(folder);
  if (setAside == null) return result;
  keep.addAll(setAside);
  final hash = RegExp(r'^[0-9a-f]{64}(\.copy)?$');
  for (final f in blobs.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (hash.hasMatch(name) && !keep.contains(name)) f.deleteSync();
  }
  return result;
}

/// Copies the files of [i] to [blobs]; false when a file here is missing.
Future<bool> _copyItem(
  DownloadStore store,
  Installed i,
  PackageRecord r,
  Directory blobs,
) async {
  for (final f in r.files) {
    final target = File('${blobs.path}/${f.sha256}');
    // A file already on the stick is used only when it is right (it may
    // be from a copy that was cut off, or damaged).
    if (_isFile(target) &&
        target.lengthSync() == f.size &&
        await sha256OfFile(target) == f.sha256) {
      continue;
    }
    final source = File(store.path(i, f.name));
    if (!source.existsSync() || source.lengthSync() != f.size) return false;
    final part = File('${target.path}.copy');
    _clear(part);
    try {
      await source.copy(part.path);
      // A file here damaged since it was installed is not passed on.
      if (await sha256OfFile(part) != f.sha256) return false;
      await _replace(part, target);
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }
  return true;
}

/// The file hashes of the records a node set aside in `.kept.json`
/// (empty when there is none); null when it cannot be read.
Set<String>? _keptHashes(Directory folder) {
  final f = File('${folder.path}/.kept.json');
  if (!f.existsSync()) return {};
  try {
    final j = jsonDecode(f.readAsStringSync());
    return {
      for (final r in j as List)
        for (final file in (r as Map)['files'] as List)
          (file as Map)['sha256'] as String,
    };
  } on Object {
    return null;
  }
}

/// Whether every file of [r] is in [blobs] and matches its hash.
Future<bool> _onStick(PackageRecord r, Directory blobs) async {
  for (final f in r.files) {
    final b = File('${blobs.path}/${f.sha256}');
    if (!_isFile(b) ||
        b.lengthSync() != f.size ||
        await sha256OfFile(b) != f.sha256) {
      return false;
    }
  }
  return true;
}

/// Removes whatever is at [f] (a link is removed, not what it points to),
/// so a write there cannot reach another file.
void _clear(File f) {
  switch (FileSystemEntity.typeSync(f.path, followLinks: false)) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.link:
      Link(f.path).deleteSync();
    default:
      f.deleteSync();
  }
}

/// Installs from [stick] what is newer than what [store] has: records of
/// trusted publishers only, every file checked by its hash, versions only
/// go up, ids and file names stay with their publisher. The files of one
/// item are all checked before any of them replaces an installed one, and
/// the installed files come back if the install fails half way.
Future<StickResult> loadFromStick(DownloadStore store, Directory stick) async {
  final result = StickResult();
  final folder = stickFolder(stick);
  final cat = await _readCatalog(folder);
  if (cat == null) throw const FileSystemException('no catalog');

  // Key statements first: they decide which records are trusted.
  final statements = await relevantStatements(store.trust, cat.keys);
  try {
    result.keysChanged = await store.publishers.learn(statements);
  } on Object {
    // Not saved: they still apply to the records on this stick.
  }
  final trust = store.trust.withStatements(statements);
  for (final raw in cat.records) {
    final r = await trust.check(raw);
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
    try {
      if (await _install(store, item, r, folder, cat.urls)) {
        result.added++;
      } else {
        result.failed.add('${r.id} ${r.version}');
      }
    } on Object {
      // Disk full, the stick pulled out, or refused by the store.
      result.failed.add('${r.id} ${r.version}');
    }
  }
  return result;
}

/// Copies, checks and installs one item; false when a file on the stick
/// is missing or does not match. On any failure the item stays as it was.
Future<bool> _install(
  DownloadStore store,
  CatalogItem item,
  PackageRecord r,
  Directory folder,
  Map<Object?, Object?> urls,
) async {
  // Names that differ only in case are one file on macOS and Windows.
  final names = {for (final f in r.files) f.name.toLowerCase()};
  if (names.length != r.files.length) return false;
  final dir = store.dirFor(item.kind);
  await dir.create(recursive: true);
  final staged = <(File part, File target)>[];
  final kept = <(File backup, File target)>[];
  final placed = <File>[];
  var done = false;
  try {
    for (final f in r.files) {
      final source = _blobOnStick(folder, f, urls[f.sha256]);
      final target = File('${dir.path}/${f.name}');
      final part = File('${target.path}.part');
      if (source == null || source.lengthSync() != f.size) return false;
      staged.add((part, target));
      await source.copy(part.path);
      if (await sha256OfFile(part) != f.sha256) return false;
    }
    // The installed files go aside (`.tmp` is a name no record may use)
    // until the install is recorded.
    for (final (part, target) in staged) {
      if (target.existsSync()) {
        final backup = File('${target.path}.tmp');
        await _replace(target, backup);
        kept.add((backup, target));
      }
      await _replace(part, target);
      placed.add(target);
    }
    await store.markInstalled(item);
    done = true;
    return true;
  } finally {
    for (final (part, _) in staged) {
      if (part.existsSync()) await part.delete();
    }
    if (done) {
      for (final (backup, _) in kept) {
        if (backup.existsSync()) await backup.delete();
      }
    } else {
      for (final f in placed) {
        if (f.existsSync()) await f.delete();
      }
      for (final (backup, target) in kept) {
        if (backup.existsSync()) await _replace(backup, target);
      }
    }
  }
}

/// Renames [from] to [to], replacing [to] (Windows may not replace on
/// rename).
Future<void> _replace(File from, File to) async {
  try {
    await from.rename(to.path);
  } on FileSystemException {
    if (!to.existsSync()) rethrow;
    await to.delete();
    await from.rename(to.path);
  }
}

/// A plain file, not a link, a folder or a device.
bool _isFile(File f) =>
    FileSystemEntity.typeSync(f.path, followLinks: false) ==
    FileSystemEntityType.file;

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
    if (_isFile(file)) return file;
  }
  return null;
}

/// The records and `urls` of the catalog in [folder]; null when there is
/// none. Throws [UnreadableStick] when it is there but cannot be read.
Future<CatalogDocument?> _readCatalog(Directory folder) async {
  final file = File('${folder.path}/catalog.json');
  if (!file.existsSync()) return null;
  if (file.lengthSync() > maxCatalogBytes) {
    throw const UnreadableStick('too large');
  }
  try {
    return CatalogDocument.parse(await file.readAsString());
  } on FormatException catch (e) {
    throw UnreadableStick(
      e.message.endsWith('not JSON') ? 'not JSON' : 'not a format 2 catalog',
    );
  }
}

PackageRecord? _shape(Object? raw) {
  try {
    return PackageRecord.fromJson((raw as Map).cast());
  } on Object {
    return null;
  }
}
