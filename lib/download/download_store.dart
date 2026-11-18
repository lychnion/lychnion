import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../util/paths.dart';
import '../util/versioned_file.dart';
import 'catalog.dart';
import 'downloader.dart';
import 'followed_catalogs.dart';
import 'publisher_list.dart';
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
  }) // A named parameter cannot be private, so no initializing formal.
    // ignore: prefer_initializing_formals
    : _trust = trust,
       publishers =
           publishers ??
           PublisherList(File('${root.path}/downloads/publishers.json')),
       followed =
           followed ?? FollowedCatalogs(Directory('${root.path}/downloads'));

  final Directory root;

  /// Fixed keys (tests); otherwise the publishers' keys.
  final TrustedKeys? _trust;

  /// Publishers the user added (a city, a club), next to Lychnion.
  final PublisherList publishers;

  /// Catalogs the user follows, next to Lychnion's.
  final FollowedCatalogs followed;

  /// Publishers whose records are accepted: built in, plus the added ones.
  TrustedKeys get trust => _trust ?? publishers.trust;

  /// Install records checked in this run, as canonical JSON (the whole
  /// record, so an edit after the check does not pass). Checking is async,
  /// [installed] is not: [verifyInstalled] and [markInstalled] check,
  /// [installed] only accepts records checked here.
  final _verified = <String>{};

  static Future<DownloadStore>? _instance;
  static Future<DownloadStore> instance() => _instance ??= () async {
    final s = DownloadStore(await appSupportDirectory());
    await s.publishers.load();
    await s.followed.load();
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

  /// The marker [text] as JSON if this build reads its format (1 or 2).
  static Map<String, Object?>? _markerJson(String text) {
    final f = _markerFormatOf(text);
    if (f == null || f < 1 || f > markerFormat) return null;
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
  /// [hash] may throw [DownloadCancelled]: then nothing changes and the
  /// marker is checked again at the next start.
  Future<OldMarker> upgradeOldMarker(
    ItemKind kind,
    String id,
    CatalogItem? item, {
    Future<String> Function(File file)? hash,
  }) async {
    final m = _marker(kind, id);
    if (!m.existsSync() || (_markerFormatOf(_readOr(m)) ?? 0) != 0) {
      return OldMarker.kept;
    }
    Future<OldMarker> retire() async {
      await m.rename('${m.path}.old');
      return OldMarker.retired;
    }

    final r = item?.record;
    if (item == null ||
        r == null ||
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
  /// publisher was removed.
  PackageRecord? _onDisk(ItemKind kind, String id) {
    try {
      final j = _markerJson(_marker(kind, id).readAsStringSync())!;
      return PackageRecord.fromJson((j['record'] as Map).cast());
    } on Object {
      return null;
    }
  }

  /// Version in the install marker of [item]'s id, also when its record
  /// is no longer trusted (versions only go up).
  String? recordedVersion(CatalogItem item) =>
      recordedVersionOf(item.kind, item.id);

  /// [recordedVersion] by kind and id.
  String? recordedVersionOf(ItemKind kind, String id) =>
      _onDisk(kind, id)?.version;

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
    final mine = _onDisk(item.kind, item.id);
    if (mine != null && mine.publisher != r.publisher) return true;
    final names = {for (final f in r.files) f.name.toLowerCase()};
    final ownId = item.id.toLowerCase();
    final dir = dirFor(item.kind);
    if (!dir.existsSync()) return false;
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.installed.json')) continue;
      final id = name.substring(0, name.length - 15);
      if (id == item.id) continue;
      // Another id that differs only in case is the same marker file there.
      if (id.toLowerCase() == ownId) return true;
      final other = _onDisk(item.kind, id);
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
    final have = installedVersion(item) ?? _onDisk(item.kind, item.id)?.version;
    if (have != null && isOlder(r.version, have)) {
      throw OlderVersion(item.id, r.version, have);
    }
    await dirFor(item.kind).create(recursive: true);
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

  /// Removes the files, any partial download and the record.
  Future<void> delete(CatalogItem item) async {
    final dir = dirFor(item.kind);
    final m = _marker(item.kind, item.id);
    if (await m.exists()) await m.delete();
    final old = File('${m.path}.old');
    if (await old.exists()) await old.delete();
    for (final f in item.files) {
      final file = File('${dir.path}/${f.name}');
      if (await file.exists()) await file.delete();
      await Downloader.deletePart(dir, f.name);
    }
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
    final s = _settings()
      ..[key] = value
      ..['format'] = settingsFormat;
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

  /// The chat model in use: the one picked, else the first installed.
  Installed? activeChat() {
    final chats = [
      for (final i in allInstalled(ItemKind.model))
        if (i.role == 'chat') i,
    ];
    if (chats.isEmpty) return null;
    final want = chatModelId;
    return chats.firstWhere((i) => i.id == want, orElse: () => chats.first);
  }

  /// Path of [activeChat], or null.
  String? chatModelPath() {
    final c = activeChat();
    return c == null ? null : path(c, c.fileEnding('.gguf')!);
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

  /// Tiles and sites of the first installed map area, or null. Newer map
  /// versions also have a walking graph and tsunami inundation tiles.
  ({String pmtiles, String sites, String? routes, String? inundation})?
  mapPaths() {
    for (final i in allInstalled(ItemKind.map)) {
      final t = i.fileEnding('.pmtiles'), s = i.fileEnding('.sites.sqlite');
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
