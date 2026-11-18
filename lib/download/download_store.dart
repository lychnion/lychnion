import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../util/paths.dart';
import 'catalog.dart';
import 'downloader.dart';
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
  /// Download new versions by themselves, on Wi-Fi only.
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
  DownloadStore(this.root, {TrustedKeys? trust})
    : trust = trust ?? builtInPublishers;

  final Directory root;

  /// Publishers whose records are accepted.
  final TrustedKeys trust;

  /// Install records checked in this run, as canonical JSON (the whole
  /// record, so an edit after the check does not pass). Checking is async,
  /// [installed] is not: [verifyInstalled] and [markInstalled] check,
  /// [installed] only accepts records checked here.
  final _verified = <String>{};

  static Future<DownloadStore>? _instance;
  static Future<DownloadStore> instance() => _instance ??= () async {
    final s = DownloadStore(await appSupportDirectory());
    await s.verifyInstalled();
    return s;
  }();

  /// Checks the signatures of all install records (once per app start).
  Future<void> verifyInstalled() async {
    for (final kind in ItemKind.values) {
      final dir = dirFor(kind);
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.installed.json')) continue;
        try {
          final j = jsonDecode(await f.readAsString()) as Map;
          final r = await trust.check(j['record']);
          if (r != null) _verified.add(canonicalJson(r.json));
        } catch (_) {}
      }
    }
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

  /// The install record, if its signature checks out and every file is
  /// still there at its size. Records from before signing (no `record`)
  /// count as not installed: the files then show as unverified and are
  /// checked again against a signed record.
  Installed? installed(ItemKind kind, String id) {
    final m = _marker(kind, id);
    if (!m.existsSync()) return null;
    try {
      final j = jsonDecode(m.readAsStringSync()) as Map;
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

  /// Records [item] as installed. Call only after every file was checked
  /// against the item's SHA-256. Throws [UnsignedItem] for an item without
  /// a verified record.
  Future<void> markInstalled(CatalogItem item) async {
    final r = item.record;
    if (r == null || !await trust.verify(r)) throw UnsignedItem(item.id);
    final have = installedVersion(item);
    if (have != null && isOlder(r.version, have)) {
      throw OlderVersion(item.id, r.version, have);
    }
    await dirFor(item.kind).create(recursive: true);
    await _marker(
      item.kind,
      item.id,
    ).writeAsString(jsonEncode({'record': r.json}));
    _verified.add(canonicalJson(r.json));
  }

  /// Version of [item] installed now, if any.
  String? installedVersion(CatalogItem item) =>
      installed(item.kind, item.id)?.version;

  /// Removes the files, any partial download and the record.
  Future<void> delete(CatalogItem item) async {
    final dir = dirFor(item.kind);
    final m = _marker(item.kind, item.id);
    if (await m.exists()) await m.delete();
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

  Map<String, Object?> _settings() {
    try {
      return (jsonDecode(_settingsFile.readAsStringSync()) as Map).cast();
    } catch (_) {
      return {};
    }
  }

  Future<void> _set(String key, Object? value) async {
    final s = _settings()..[key] = value;
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

/// The item has no record signed by a trusted publisher.
class UnsignedItem implements Exception {
  UnsignedItem(this.id);
  final String id;
  @override
  String toString() => 'No valid signature for $id';
}

/// The item is older than the installed version (versions only go up).
class OlderVersion implements Exception {
  OlderVersion(this.id, this.version, this.installed);
  final String id, version, installed;
  @override
  String toString() => '$id $version is older than installed $installed';
}
