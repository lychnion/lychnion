import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../knowledge/bundled_packages.dart' show bundledPackages;
import '../llm/engines.dart';
import '../util/paths.dart';
import '../util/versioned_file.dart';
import 'catalog.dart';
import 'downloader.dart';
import 'followed_catalogs.dart';
import 'publisher_list.dart';
import 'attestation_list.dart';
import 'status_list.dart';

import 'package:lychnion_format/lychnion_format.dart';

/// Record of a verified download, kept next to its files as
/// `<id>.installed.json`: the publisher's signed record. Loaders only use
/// files that have one whose signature still checks out.
class Installed {
  Installed(this.record)
    : id = record.id,
      kind = ItemKind.values.byName(record.kind),
      files = {for (final f in record.files) f.name: f.size};

  final PackageRecord record;
  final String id;
  final ItemKind kind;
  String get version => record.version;
  String? get role => record.role;

  /// Signed by a built-in publisher (Lychnion), not by one the user added.
  /// Only such packages supply the fixed official safety line
  /// (lychnion/lychnion#66).
  bool get builtInPublisher =>
      builtInPublishers.publishers.contains(record.publisher);

  /// Whether the model runs on [os] (`Platform.operatingSystem`); see
  /// [CatalogItem.platforms].
  bool runsOn(String os) =>
      record.platforms.isEmpty || record.platforms.contains(os);

  /// The chat model's file: `.litertlm` (LiteRT-LM) or `.gguf` (llama.cpp).
  String? get chatFile => fileEnding('.litertlm') ?? fileEnding('.gguf');

  /// File name → size.
  final Map<String, int> files;

  /// First file with this extension, e.g. `.pmtiles`.
  String? fileEnding(String ext) {
    for (final f in files.keys) {
      if (f.endsWith(ext)) return f;
    }
    return null;
  }
}

/// The chat model to use among [models]: [want] if it is one, else one
/// made for [os], else the first. LiteRT-LM models count only when
/// [liteRt] says the engine runs here; [skip] leaves out ids (a model that
/// failed to load).
Installed? pickChat(
  Iterable<Installed> models, {
  required String? want,
  required String os,
  required bool liteRt,
  Set<String> skip = const {},
}) {
  bool usable(Installed i) {
    final f = i.chatFile;
    return i.role == 'chat' &&
        i.runsOn(os) &&
        !skip.contains(i.id) &&
        f != null &&
        (liteRt || !isLiteRtFile(f));
  }

  final chats = models.where(usable).toList();
  if (chats.isEmpty) return null;
  return chats.where((i) => i.id == want).firstOrNull ??
      chats.where((i) => i.record.platforms.contains(os)).firstOrNull ??
      chats.first;
}

/// Where downloads live and what is installed.
///
/// Folders under the app's support directory, the same ones the app used
/// before downloads existed:
///   models/    GGUF files
///   packages/  knowledge packages (SQLite)
///   maps/      .pmtiles and evacuation sites (SQLite)
///   downloads/ settings and the cached catalog
/// Bundled assets are copied to `bundled/` instead, so they never overwrite
/// a download.
/// What the app does with new versions of installed downloads.
enum UpdateMode {
  /// Download new versions by themselves: on phones on Wi-Fi only, on a
  /// computer on any connection.
  auto,

  /// Check at start and show a badge (default).
  notify,

  /// Do not check by itself.
  off,
}

/// Whether downloads may use mobile data.
enum MobileData {
  /// Only on Wi-Fi or a cable (default).
  never,

  /// Ask before a large download over mobile data.
  ask,

  /// Download over any connection.
  always,
}

class DownloadStore {
  DownloadStore(
    this.root, {
    TrustedKeys? trust,
    PublisherList? publishers,
    FollowedCatalogs? followed,
    AttestationList? attestations,
    StatusList? status,
  }) // A named parameter cannot be private, so no initializing formal.
    // ignore: prefer_initializing_formals
    : _trust = trust,
       publishers =
           publishers ??
           PublisherList(File('${root.path}/downloads/publishers.json')),
       followed =
           followed ?? FollowedCatalogs(Directory('${root.path}/downloads')),
       attestations =
           attestations ??
           AttestationList(File('${root.path}/downloads/attestations.json')),
       status =
           status ?? StatusList(File('${root.path}/downloads/status.json'));

  final Directory root;

  /// Fixed keys (tests); otherwise the publishers' keys.
  final TrustedKeys? _trust;

  /// Publishers the user added (a city, a club), next to Lychnion.
  final PublisherList publishers;

  /// Catalogs the user follows, next to Lychnion's.
  final FollowedCatalogs followed;

  /// Lychnion's attestations for official publishers (labels only, #119).
  final AttestationList attestations;

  /// Publishers' statuses: what is newest from each (#117).
  final StatusList status;

  /// Keeps the newest of [learned] for each publisher (see StatusList).
  Future<bool> learnStatus(Iterable<PublisherStatus> learned) =>
      status.learn(learned, () => trust);

  /// Keeps [learned] attestations signed by a key trusted here for Lychnion
  /// (see [AttestationList.learn]).
  Future<bool> learnAttestations(Iterable<Attestation> learned) =>
      attestations.learn(learned, () => trust);

  /// Publishers whose records are accepted: built in, plus the added ones.
  TrustedKeys get trust => _trust ?? publishers.trust;

  /// Install records checked in this run, as canonical JSON (the whole
  /// record, so an edit after the check does not pass). Checking is async,
  /// [installed] is not: [verifyInstalled] and [markInstalled] check,
  /// [installed] only accepts records checked here.
  final _verified = <String>{};

  /// Ids that belong to Lychnion (lower case): an added publisher never
  /// installs an item under one of them, from a USB stick, a followed
  /// catalog or a base, and a copy installed that way before is not used
  /// (lychnion/lychnion#68).
  final _reserved = <String>{};

  /// File names of Lychnion's items (lower case): an added publisher's
  /// file of that name, under any id, would block Lychnion's install.
  final _reservedFiles = <String>{};

  /// Reserves [ids] (and their [files]) for the built-in publishers (see
  /// [isReservedFor]).
  void reserve(Iterable<String> ids, {Iterable<String> files = const []}) {
    _reserved.addAll(ids.map((i) => i.toLowerCase()));
    _reservedFiles.addAll(files.map((f) => f.toLowerCase()));
  }

  /// Reserves Lychnion's items of a checked catalog: ids Lychnion added
  /// since the app started count at once (Downloads refreshes).
  void reserveFrom(Iterable<CatalogItem> items) {
    for (final i in items) {
      final r = i.record;
      if (r == null || !_builtIn(r.publisher)) continue;
      reserve([r.id], files: [for (final f in r.files) f.name]);
    }
  }

  static bool _builtIn(String publisher) =>
      builtInPublishers.publishers.contains(publisher);

  /// Whether [id] is Lychnion's and [publisher] is not a built-in one.
  bool isReservedFor(String id, String publisher) =>
      !_builtIn(publisher) && _reserved.contains(id.toLowerCase());

  /// Lychnion's ids: the bundled packages, every item of the bundled
  /// catalog, and Lychnion's items in the catalog fetched last (ids it
  /// added since this build). Their file names go to [files] if given.
  Future<Set<String>> lychnionIds({Set<String>? files}) async {
    final ids = <String>{...bundledPackages};
    void addFrom(String text) {
      final records = (jsonDecode(text) as Map)['records'];
      if (records is! List) return;
      for (final r in records.whereType<Map<String, Object?>>()) {
        final id = r['id'], publisher = r['publisher'];
        if (id is String && _builtIn('$publisher')) {
          ids.add(id);
          for (final f in (r['files'] as List?) ?? const []) {
            if (f is Map && f['name'] is String) {
              files?.add(f['name'] as String);
            }
          }
        }
      }
    }

    try {
      addFrom(await rootBundle.loadString('assets/downloads/catalog.json'));
    } on Object {
      // No bundled catalog (tests): the bundled packages still count.
    }
    try {
      if (await cachedCatalog.exists()) {
        final j = jsonDecode(await cachedCatalog.readAsString()) as Map;
        addFrom(j['body'] as String);
      }
    } on Object {
      // A broken cache adds nothing; reserving less never lets more in
      // than before this check existed.
    }
    return ids;
  }

  static Future<DownloadStore>? _instance;
  static Future<DownloadStore> instance() => _instance ??= () async {
    final s = DownloadStore(await appSupportDirectory());
    await s.publishers.load();
    // After the publishers: their key statements decide Lychnion's keys.
    await s.attestations.load(s.trust);
    await s.status.load(s.trust);
    await s.followed.load();
    final files = <String>{};
    s.reserve(await s.lychnionIds(files: files), files: files);
    await s.verifyInstalled();
    return s;
  }();

  /// Checks all install records again, after a publisher was added or
  /// removed: a removed publisher's downloads are then no longer used.
  Future<void> reverify() async {
    // Checked into a new set and swapped in when done, so installed items
    // do not vanish for loaders or the base while the check runs.
    final fresh = await _check();
    _verified
      ..clear()
      ..addAll(fresh);
    // A revoked Lychnion key's attestations lapse.
    attestations.recheck(trust);
    status.recheck(trust);
  }

  /// Checks the signatures of all install records (once per app start).
  Future<void> verifyInstalled() async => _verified.addAll(await _check());

  Future<Set<String>> _check() async {
    final ok = <String>{};
    for (final kind in ItemKind.values) {
      final dir = dirFor(kind);
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.installed.json')) continue;
        try {
          final j = _markerJson(await f.readAsString());
          if (j == null) continue;
          final r = await trust.check(j['record']);
          if (r != null) ok.add(canonicalJson(r.json));
        } catch (_) {}
      }
    }
    return ok;
  }

  Directory dirFor(ItemKind kind) => Directory(
    '${root.path}/${switch (kind) {
      ItemKind.model => 'models',
      ItemKind.package => 'packages',
      ItemKind.map => 'maps',
    }}',
  );

  File _marker(ItemKind kind, String id) =>
      File('${dirFor(kind).path}/$id.installed.json');

  /// Format of install markers (see versioned_file.dart):
  /// 0: `{id, kind, version, role, files: {name: size}}`, unsigned, from
  ///    before signed records; never trusted, see [upgradeOldMarker];
  /// 1: `{record}`, the publisher's signed record;
  /// 2: `{format: 2, record}`.
  static const markerFormat = 2;

  /// Format of the marker text [text], or null when it cannot be read.
  static int? _markerFormatOf(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      if (j.containsKey('format')) {
        return j['format'] is int ? j['format'] as int : null;
      }
      return j['record'] is Map ? 1 : 0;
    } on Object {
      return null;
    }
  }

  /// The marker [text] as JSON if this build reads its format (1 or 2),
  /// or with [newer] also a newer format (only for its record, see
  /// [_onDisk]).
  static Map<String, Object?>? _markerJson(String text, {bool newer = false}) {
    final f = _markerFormatOf(text);
    if (f == null || f < 1 || (f > markerFormat && !newer)) return null;
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  /// Markers this build cannot use but can check against a catalog:
  /// format 0 (unsigned, from before signed records) and unreadable ones.
  /// Markers from a newer build are left alone.
  List<({ItemKind kind, String id})> oldMarkers() => [
    for (final kind in ItemKind.values)
      if (dirFor(kind).existsSync())
        for (final f in dirFor(kind).listSync())
          if (f is File && f.path.endsWith('.installed.json'))
            if ((_markerFormatOf(_readOr(f)) ?? 0) == 0)
              (
                kind: kind,
                id: () {
                  final name = f.uri.pathSegments.last;
                  return name.substring(0, name.length - 15);
                }(),
              ),
  ];

  static String _readOr(File f) {
    try {
      return f.readAsStringSync();
    } on Object {
      return '';
    }
  }

  /// Upgrades the old marker of [id] (see [oldMarkers]): if [item], from
  /// a catalog, has a trusted record for the same id and kind, and every
  /// file is there with its size and SHA-256 ([hash], by default
  /// [sha256OfFile]), the signed record is written as the marker. Else the
  /// marker is renamed to `<id>.installed.json.old`, so it is not checked
  /// at every start, and the item shows as not installed. An unsigned
  /// marker is never trusted as it is.
  ///
  /// [hash] may throw [DownloadCancelled], and so does a [cancel] that
  /// is set when hashing is done: then nothing changes and the marker is
  /// checked again at the next start.
  Future<OldMarker> upgradeOldMarker(
    ItemKind kind,
    String id,
    CatalogItem? item, {
    Future<String> Function(File file)? hash,
    CancelToken? cancel,
  }) async {
    final m = _marker(kind, id);
    if (!m.existsSync() || (_markerFormatOf(_readOr(m)) ?? 0) != 0) {
      return OldMarker.kept;
    }
    Future<OldMarker> retire() async {
      await m.rename('${m.path}.old');
      return OldMarker.retired;
    }

    // Not in the catalog now (a base's or a followed catalog not read
    // yet): checked again at the next start, files stay in use by none.
    if (item == null) return OldMarker.kept;
    final r = item.record;
    if (r == null ||
        item.id != id ||
        item.kind != kind ||
        !await trust.verify(r) ||
        !hasUnverifiedFiles(item)) {
      return retire();
    }
    for (final f in item.files) {
      final file = File('${dirFor(kind).path}/${f.name}');
      final sum = await (hash ?? sha256OfFile)(file);
      if (sum != f.sha256) return retire();
    }
    // Stopped after the last file was hashed: nothing is written.
    if (cancel?.isCancelled ?? false) throw DownloadCancelled();
    try {
      await markInstalled(item);
    } on UnsignedItem {
      return retire();
    } on TakenItem {
      return retire();
    } on OlderVersion {
      return retire();
    }
    return OldMarker.upgraded;
  }

  /// The install record, if its signature checks out and every file is
  /// still there at its size. Records from before signing (no `record`)
  /// count as not installed: the files then show as unverified and are
  /// checked again against a signed record.
  Installed? installed(ItemKind kind, String id) {
    final m = _marker(kind, id);
    if (!m.existsSync()) return null;
    try {
      final j = _markerJson(m.readAsStringSync())!;
      final r = PackageRecord.fromJson((j['record'] as Map).cast());
      if (!_verified.contains(canonicalJson(r.json))) return null;
      if (r.id != id || r.kind != kind.name) return null;
      // An added publisher's copy of a Lychnion id (installed before this
      // check, #68): not used, and Lychnion's own may replace it.
      if (isReservedFor(id, r.publisher)) return null;
      // An added publisher's model (installed by an older build): never
      // loaded or picked as the chat or search model (#67).
      if (!mayPublishKind(r.publisher, r.kind)) return null;
      final i = Installed(r);
      for (final e in i.files.entries) {
        final f = File('${dirFor(kind).path}/${e.key}');
        if (!f.existsSync() || f.lengthSync() != e.value) return null;
      }
      return i;
    } catch (_) {
      return null;
    }
  }

  List<Installed> allInstalled(ItemKind kind) {
    final dir = dirFor(kind);
    if (!dir.existsSync()) return const [];
    final out = <Installed>[];
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.installed.json')) continue;
      final i = installed(kind, name.substring(0, name.length - 15));
      if (i != null) out.add(i);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  String path(Installed i, String file) => '${dirFor(i.kind).path}/$file';

  /// The record in the install marker of [id], read without checking its
  /// signature: who installed it and which version, also after its
  /// publisher was removed. Also from a newer build's marker when its
  /// record can be read: the checks for other publishers' items and
  /// older versions must hold for those too.
  PackageRecord? _onDisk(ItemKind kind, String id) {
    try {
      final j = _markerJson(_marker(kind, id).readAsStringSync(), newer: true)!;
      return PackageRecord.fromJson((j['record'] as Map).cast());
    } on Object {
      return null;
    }
  }

  /// The record in the install marker of [id], signature not checked
  /// (for re-signing an item with a publisher's new key).
  PackageRecord? recordOnDisk(ItemKind kind, String id) => _onDisk(kind, id);

  /// Version in the install marker of [item]'s id, also when its record
  /// is no longer trusted (versions only go up).
  String? recordedVersion(CatalogItem item) =>
      recordedVersionOf(item.kind, item.id);

  /// [recordedVersion] by kind and id. Not an added publisher's copy of a
  /// Lychnion id: it could claim any version and so block Lychnion's own
  /// updates, in Downloads, from a USB stick or here (#68).
  String? recordedVersionOf(ItemKind kind, String id) {
    final d = _onDisk(kind, id);
    if (d == null || isReservedFor(id, d.publisher)) return null;
    return d.version;
  }

  /// File endings the store and the downloader use for their own files:
  /// a download must never be named like one.
  static const reservedEndings = [
    '.installed.json',
    '.part',
    '.part.json',
    '.publishing',
    '.tmp',
    '.broken',
    '.old',
    '.newer',
  ];

  static bool isReservedName(String name) {
    final n = name.toLowerCase();
    return reservedEndings.any(n.endsWith);
  }

  /// Whether [item] would clash with what another publisher installed
  /// here: its id, or one of its file names (files of a kind share one
  /// folder; compared without case, as on macOS and Windows), or a file
  /// named like the store's own files. Then it must not be downloaded or
  /// installed, so an added publisher can never replace Lychnion's items
  /// or files.
  bool isTaken(CatalogItem item) {
    final r = item.record;
    if (r == null) return false;
    if (r.files.any((f) => isReservedName(f.name))) return true;
    // Lychnion's ids and file names are Lychnion's, also when not
    // installed yet (#68).
    if (isReservedFor(item.id, r.publisher)) return true;
    // Models are Lychnion's only, from every route (#67).
    if (!mayPublishKind(r.publisher, r.kind)) return true;
    final lychnion = _builtIn(r.publisher);
    if (!lychnion &&
        r.files.any((f) => _reservedFiles.contains(f.name.toLowerCase()))) {
      return true;
    }
    final mine = _onDisk(item.kind, item.id);
    // Another publisher's copy blocks the id, except an added publisher's
    // copy of a Lychnion id, which Lychnion's own replaces.
    if (mine != null &&
        mine.publisher != r.publisher &&
        !isReservedFor(item.id, mine.publisher)) {
      return true;
    }
    final names = {for (final f in r.files) f.name.toLowerCase()};
    final ownId = item.id.toLowerCase();
    final dir = dirFor(item.kind);
    if (!dir.existsSync()) return false;
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.installed.json')) continue;
      final id = name.substring(0, name.length - 15);
      if (id == item.id) continue;
      final other = _onDisk(item.kind, id);
      // Lychnion's own item is never blocked by an added publisher's (an
      // id in other case, or a file of the same name): Lychnion's wins.
      if (lychnion && other != null && !_builtIn(other.publisher)) continue;
      // Another id that differs only in case is the same marker file there.
      if (id.toLowerCase() == ownId) return true;
      if (other != null &&
          other.files.any((x) => names.contains(x.name.toLowerCase()))) {
        return true;
      }
    }
    return false;
  }

  /// Records [item] as installed. Call only after every file was checked
  /// against the item's SHA-256. Throws [UnsignedItem] for an item without
  /// a verified record, [TakenItem] when it clashes with another
  /// publisher's item, [OlderVersion] when it is older than what is there.
  Future<void> markInstalled(CatalogItem item) async {
    final r = item.record;
    if (r == null || !await trust.verify(r)) throw UnsignedItem(item.id);
    if (isTaken(item)) throw TakenItem(item.id);
    // Also against a record no longer trusted (its publisher was removed):
    // versions only go up.
    final have = installedVersion(item) ?? recordedVersion(item);
    if (have != null && isOlder(r.version, have)) {
      throw OlderVersion(item.id, r.version, have);
    }
    await dirFor(item.kind).create(recursive: true);
    // Lychnion's item may replace an added publisher's copy of its id (#68):
    // remembered now, its leftover files removed once the new record is in.
    final before = _onDisk(item.kind, item.id);
    final shadow = before != null && isReservedFor(item.id, before.publisher)
        ? before
        : null;
    // Written next to it first: a full disk must not leave a cut-off
    // record of what was installed before.
    final marker = _marker(item.kind, item.id);
    // A marker from a newer build: kept as a copy, never written over
    // without one.
    if (marker.existsSync() &&
        (_markerFormatOf(_readOr(marker)) ?? 0) > markerFormat &&
        await keepAside(marker, 'newer') == null) {
      throw FileSystemException('cannot keep newer marker', marker.path);
    }
    final tmp = File('${marker.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'format': markerFormat, 'record': r.json}),
      flush: true,
    );
    try {
      await tmp.rename(marker.path);
    } on FileSystemException {
      // Windows may not replace on rename.
      if (!marker.existsSync()) rethrow;
      await marker.delete();
      await tmp.rename(marker.path);
    }
    _verified.add(canonicalJson(r.json));
    if (shadow != null) await _removeLeftovers(item.kind, item.id, shadow, r);
  }

  /// The files of [shadow] (an added publisher's copy of Lychnion's [id])
  /// that Lychnion's [record] does not use and no other item lists. Names
  /// compared in lower case: on macOS and Windows `JP.X.sqlite` is the file
  /// Lychnion just wrote as `jp.x.sqlite`. Best effort: a file that cannot
  /// be removed (in use) only stays behind.
  Future<void> _removeLeftovers(
    ItemKind kind,
    String id,
    PackageRecord shadow,
    PackageRecord record,
  ) async {
    final keep = {for (final f in record.files) f.name.toLowerCase()};
    for (final f in shadow.files) {
      if (keep.contains(f.name.toLowerCase()) ||
          isReservedName(f.name) ||
          _usedByOther(kind, id, f.name)) {
        continue;
      }
      try {
        final file = File('${dirFor(kind).path}/${f.name}');
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Left behind; Lychnion's item is recorded either way.
      }
    }
  }

  /// Version of [item] installed now, if any.
  String? installedVersion(CatalogItem item) =>
      installed(item.kind, item.id)?.version;

  /// Deletes everything installed from [publisher] (files, partial
  /// downloads, install records), whether or not it is still trusted.
  /// Returns how many items were deleted.
  Future<int> deleteFrom(String publisher) async {
    var n = 0;
    for (final kind in ItemKind.values) {
      final dir = dirFor(kind);
      if (!await dir.exists()) continue;
      for (final f in dir.listSync()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.installed.json')) continue;
        final r = _onDisk(kind, name.substring(0, name.length - 15));
        if (r == null || r.publisher != publisher) continue;
        await delete(CatalogItem.fromRecord(r));
        n++;
      }
    }
    return n;
  }

  /// Removes the files, any partial download and the record. A file that
  /// another installed item also lists stays (Lychnion's item may have
  /// replaced an added publisher's file of that name, #68).
  Future<void> delete(CatalogItem item) async {
    final dir = dirFor(item.kind);
    final m = _marker(item.kind, item.id);
    if (await m.exists()) await m.delete();
    final old = File('${m.path}.old');
    if (await old.exists()) await old.delete();
    for (final f in item.files) {
      if (_usedByOther(item.kind, item.id, f.name)) continue;
      final file = File('${dir.path}/${f.name}');
      if (await file.exists()) await file.delete();
      await Downloader.deletePart(dir, f.name);
    }
  }

  /// Whether an install marker other than [id]'s lists [file] (names
  /// compared in lower case, as file systems may).
  bool _usedByOther(ItemKind kind, String id, String file) {
    final dir = dirFor(kind);
    if (!dir.existsSync()) return false;
    final want = file.toLowerCase(), self = id.toLowerCase();
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.installed.json')) continue;
      final other = name.substring(0, name.length - 15);
      if (other.toLowerCase() == self) continue;
      final r = _onDisk(kind, other);
      if (r != null && r.files.any((x) => x.name.toLowerCase() == want)) {
        return true;
      }
    }
    return false;
  }

  /// Bytes of partial downloads for [item].
  int partBytes(CatalogItem item, Catalog c) {
    var n = 0;
    for (final f in item.files) {
      final dir = dirFor(item.kind);
      if (File('${dir.path}/${f.name}').existsSync()) {
        n += f.size;
      } else if (c.urlOf(f) != null) {
        n += Downloader.partBytes(dir, c.spec(f));
      }
    }
    return n;
  }

  /// Files of [item] already in place without a record (copied by cable or
  /// picked with "Load GGUF file"). They can be checked and adopted.
  bool hasUnverifiedFiles(CatalogItem item) =>
      installed(item.kind, item.id) == null &&
      item.files.every((f) {
        final file = File('${dirFor(item.kind).path}/${f.name}');
        return file.existsSync() && file.lengthSync() == f.size;
      });

  // --- settings ---------------------------------------------------------

  File get _settingsFile => File('${root.path}/downloads/settings.json');

  /// Format of downloads/settings.json (see versioned_file.dart). 0: the
  /// same fields without a format number.
  static const settingsFormat = 1;

  Map<String, Object?> _settings() =>
      readVersionedSync(
        _settingsFile,
        settingsFormat,
        (json, _) => (json! as Map).cast<String, Object?>(),
      ) ??
      {};

  Future<void> _set(String key, Object? value) async {
    // Read first: the read may find a file it must keep (see mayReplace).
    final s = _settings()
      ..[key] = value
      ..['format'] = settingsFormat;
    if (!mayReplace(_settingsFile)) {
      throw FileSystemException('kept as it is', _settingsFile.path);
    }
    await _settingsFile.parent.create(recursive: true);
    await _settingsFile.writeAsString(jsonEncode(s));
  }

  /// Downloads over mobile data: never (default), ask first for large
  /// ones, or always. Settings from before kept "wifi_only" true/false.
  MobileData get mobileData {
    final s = _settings();
    if (s['mobile_data'] case final String v) {
      return MobileData.values.asNameMap()[v] ?? MobileData.never;
    }
    return s['wifi_only'] == false ? MobileData.always : MobileData.never;
  }

  Future<void> setMobileData(MobileData v) => _set('mobile_data', v.name);

  UpdateMode get updateMode =>
      UpdateMode.values.asNameMap()[_settings()['updates']] ??
      UpdateMode.notify;
  Future<void> setUpdateMode(UpdateMode v) => _set('updates', v.name);

  /// A base keeps every guide and map for phones (step 5), and the models
  /// too with [keepModels].
  bool get keepAll => _settings()['keep_all'] == true;
  Future<void> setKeepAll(bool v) => _set('keep_all', v);
  bool get keepModels => _settings()['keep_models'] == true;
  Future<void> setKeepModels(bool v) => _set('keep_models', v);

  /// The chat model the user picked, if any.
  String? get chatModelId => _settings()['chat_model'] as String?;
  Future<void> setChatModelId(String id) => _set('chat_model', id);

  File get cachedCatalog => File('${root.path}/downloads/catalog.json');

  // --- what the loaders use ---------------------------------------------

  /// The LiteRT-LM chat model being loaded right now, kept on disk until
  /// the load ends. Still set when the app starts: that load crashed the
  /// app (a native crash Dart cannot catch), so the model is skipped.
  String? get loadingChat => _settings()['loading_chat'] as String?;
  Future<void> setLoadingChat(String? id) => _set('loading_chat', id);

  /// Chat models that failed to load in this run (LiteRT-LM could not
  /// start them): left out until picked again or the app restarts, so the
  /// GGUF model takes over. Not saved.
  final failedChats = <String>{};

  /// The chat model in use: the one picked, else one made for this
  /// platform (the LiteRT-LM model on Android), else the first installed.
  /// Models for other platforms (and files the app cannot load) are left
  /// out, and so are LiteRT-LM models where the engine does not run
  /// ([Engines.liteRt]) and [failedChats].
  Installed? activeChat() => pickChat(
    allInstalled(ItemKind.model),
    want: chatModelId,
    os: Platform.operatingSystem,
    liteRt: Engines.liteRt,
    skip: failedChats,
  );

  /// Path of [activeChat], or null.
  String? chatModelPath() {
    final c = activeChat();
    return c == null ? null : path(c, c.chatFile!);
  }

  String? embedModelPath() {
    for (final i in allInstalled(ItemKind.model)) {
      if (i.role == 'embed') return path(i, i.fileEnding('.gguf')!);
    }
    return null;
  }

  /// Downloaded package [id], else the bundled copy of `assets/packages/[asset]`.
  Future<String> packagePath(String id, String asset) async {
    final i = installed(ItemKind.package, id);
    if (i != null) return path(i, i.fileEnding('.sqlite')!);
    return copyBundled('packages', asset);
  }

  /// The file to answer from for the bundled package [id]: a download of
  /// it signed by Lychnion, else the bundled file. A copy of that id
  /// installed from a publisher the user added is not used: it would
  /// replace Lychnion's guide and its safety lines (#66, #68). Decided
  /// from one look at what is installed. `shadowed` names that copy's
  /// publisher, for the log.
  /// Lychnion's download is used only when its official safety lines count
  /// ([givesSafetyLines], #125): one signed by a key without
  /// `safety-lines` (a stolen or everyday data key) must not take away the
  /// bundled file's lines, so the bundled file stays. `safetyLines`:
  /// whether the lines of what is returned count (always, now).
  Future<({String path, String? shadowed, bool safetyLines})>
  bundledPackageSource(String id, String asset) async {
    final i = installed(ItemKind.package, id);
    if (useInstalledBundled(i) && await givesSafetyLines(i!)) {
      return (
        path: path(i, i.fileEnding('.sqlite')!),
        shadowed: null,
        safetyLines: true,
      );
    }
    return (
      path: await copyBundled('packages', asset),
      shadowed: i?.record.publisher,
      safetyLines: true,
    );
  }

  /// Whether installed package [i]'s official safety lines count: signed
  /// by a built-in publisher (Lychnion, #66) with a key that may sign
  /// safety lines (KeyScope.safetyLines, #125). A key granted only `data`
  /// brings guides, not official lines.
  /// Checked like a record (TrustedKeys.verify), with the safety-lines
  /// scope and the number of signatures it needs.
  Future<bool> givesSafetyLines(Installed i) async =>
      i.builtInPublisher &&
      await trust.verify(i.record, scope: KeyScope.safetyLines);

  /// Whether the installed copy [i] of a bundled package is used: only
  /// when it is there, has its file and is signed by a built-in publisher.
  @visibleForTesting
  static bool useInstalledBundled(Installed? i) =>
      i != null && i.builtInPublisher && i.fileEnding('.sqlite') != null;

  /// Tiles and sites of the first installed map area, or null. Newer map
  /// versions also have a walking graph and tsunami inundation tiles.
  ({String pmtiles, String sites, String? routes, String? inundation})?
  mapPaths() {
    for (final i in allInstalled(ItemKind.map)) {
      // `<id>.contours.pmtiles` is an extra layer, never the base map.
      final t = i.files.keys
          .where(
            (f) => f.endsWith('.pmtiles') && !f.endsWith('.contours.pmtiles'),
          )
          .firstOrNull;
      final s = i.fileEnding('.sites.sqlite');
      if (t != null && s != null) {
        final r = i.fileEnding('.routes.bin');
        final f = i.fileEnding('.inundation.mbtiles');
        return (
          pmtiles: path(i, t),
          sites: path(i, s),
          routes: r == null ? null : path(i, r),
          inundation: f == null ? null : path(i, f),
        );
      }
    }
    return null;
  }

  /// SQLite needs a real file: copies `assets/[folder]/[name]` out once
  /// per app start into `bundled/[folder]/`.
  Future<String> copyBundled(String folder, String name) async {
    final dir = Directory('${root.path}/bundled/$folder');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    final data = await rootBundle.load('assets/$folder/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }
}

/// What [DownloadStore.upgradeOldMarker] did.
enum OldMarker {
  /// A signed marker was written: the item is installed.
  upgraded,

  /// Renamed to `.installed.json.old`: the item needs a download.
  retired,

  /// Nothing changed (no old marker).
  kept,
}

/// The item has no record signed by a trusted publisher.
class UnsignedItem implements Exception {
  UnsignedItem(this.id);
  final String id;
  @override
  String toString() => 'No valid signature for $id';
}

/// The item's id or a file name is already installed from another
/// publisher.
class TakenItem implements Exception {
  TakenItem(this.id);
  final String id;
  @override
  String toString() => '$id is installed from another publisher';
}

/// The item is older than the installed version (versions only go up).
class OlderVersion implements Exception {
  OlderVersion(this.id, this.version, this.installed);
  final String id, version, installed;
  @override
  String toString() => '$id $version is older than installed $installed';
}
