import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../util/paths.dart';
import 'catalog.dart';
import 'downloader.dart';

/// Record of a verified download, kept next to its files as
/// `<id>.installed.json`. Loaders only use files that have one.
class Installed {
  Installed(this.id, this.kind, this.version, this.role, this.files);

  final String id;
  final ItemKind kind;
  final String version;
  final String? role;

  /// File name → size.
  final Map<String, int> files;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'version': version,
    'role': role,
    'files': files,
  };

  factory Installed.fromJson(Map<String, Object?> j) => Installed(
    j['id']! as String,
    ItemKind.values.byName(j['kind']! as String),
    j['version']! as String,
    j['role'] as String?,
    (j['files']! as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
  );

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
class DownloadStore {
  DownloadStore(this.root);

  final Directory root;

  static DownloadStore? _instance;
  static Future<DownloadStore> instance() async =>
      _instance ??= DownloadStore(await appSupportDirectory());

  Directory dirFor(ItemKind kind) => Directory(
    '${root.path}/${switch (kind) {
      ItemKind.model => 'models',
      ItemKind.package => 'packages',
      ItemKind.map => 'maps',
    }}',
  );

  File _marker(ItemKind kind, String id) =>
      File('${dirFor(kind).path}/$id.installed.json');

  /// The install record, if every file is still there at its size.
  Installed? installed(ItemKind kind, String id) {
    final m = _marker(kind, id);
    if (!m.existsSync()) return null;
    try {
      final i = Installed.fromJson(
        (jsonDecode(m.readAsStringSync()) as Map).cast(),
      );
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

  Future<void> markInstalled(CatalogItem item) async {
    await dirFor(item.kind).create(recursive: true);
    await _marker(item.kind, item.id).writeAsString(
      jsonEncode(
        Installed(item.id, item.kind, item.version, item.role, {
          for (final f in item.files) f.name: f.size,
        }).toJson(),
      ),
    );
  }

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

  /// Large files only over Wi-Fi (or a cable). Default on.
  bool get wifiOnly => _settings()['wifi_only'] as bool? ?? true;
  Future<void> setWifiOnly(bool v) => _set('wifi_only', v);

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

  /// Tiles and sites of the first installed map area, or null.
  ({String pmtiles, String sites})? mapPaths() {
    for (final i in allInstalled(ItemKind.map)) {
      final t = i.fileEnding('.pmtiles'), s = i.fileEnding('.sqlite');
      if (t != null && s != null) {
        return (pmtiles: path(i, t), sites: path(i, s));
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
