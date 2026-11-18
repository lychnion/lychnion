import 'dart:convert';

import '../knowledge/language.dart';
import 'downloader.dart';

enum ItemKind { model, package, map }

/// One file of a catalog item. [url] may be relative to the catalog's base.
class CatalogFile {
  const CatalogFile(this.name, this.size, this.sha256, this.url);
  final String name;
  final int size;
  final String sha256;
  final String url;

  factory CatalogFile.fromJson(Map<String, Object?> j) => CatalogFile(
    j['name']! as String,
    (j['size']! as num).toInt(),
    (j['sha256']! as String).toLowerCase(),
    j['url']! as String,
  );
}

/// Something the app can download: a model, a knowledge package or a map
/// area (a map area has two files: tiles and evacuation sites).
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.kind,
    required this.titles,
    required this.version,
    required this.licence,
    required this.files,
    this.role,
    this.desktop = false,
    this.notes = const {},
  });

  final String id;
  final ItemKind kind;
  final String version, licence;

  /// Title and note by language code (`{ja: …, en: …}`).
  final Map<String, String> titles, notes;

  /// Models only: `chat` or `embed`.
  final String? role;

  /// Too large for most phones; shown with a note there.
  final bool desktop;
  final List<CatalogFile> files;

  int get size => files.fold(0, (a, f) => a + f.size);
  String title(String lang) => pick(titles, lang) ?? id;
  String note(String lang) => pick(notes, lang) ?? '';

  factory CatalogItem.fromJson(Map<String, Object?> j) {
    Map<String, String> texts(Object? m) => {
      for (final e in ((m as Map?) ?? const {}).entries)
        if (e.value is String) e.key as String: e.value as String,
    };
    return CatalogItem(
      id: j['id']! as String,
      kind: ItemKind.values.byName(j['kind']! as String),
      titles: texts(j['title']!),
      version: j['version']! as String,
      licence: j['licence'] as String? ?? '',
      role: j['role'] as String?,
      desktop: j['desktop'] as bool? ?? false,
      notes: texts(j['note']),
      files: [
        for (final f in j['files']! as List)
          CatalogFile.fromJson((f as Map).cast()),
      ],
    );
  }
}

/// The list of downloads. Bundled with the app (assets/downloads/catalog.json)
/// and refreshed from [refreshUrl] when online, so packages can be updated
/// without an app release.
class Catalog {
  Catalog(this.items, {this.base, this.refreshUrl});

  final List<CatalogItem> items;

  /// Relative file URLs are resolved against this. Null: only absolute
  /// URLs (the models on Hugging Face) can be downloaded.
  final Uri? base;
  final Uri? refreshUrl;

  /// [baseOverride] (dev flag DOWNLOAD_BASE_URL) wins over the catalog's own
  /// `base`; a catalog fetched from the network defaults to its own URL.
  factory Catalog.parse(String json, {Uri? fetchedFrom, Uri? baseOverride}) {
    final j = jsonDecode(json) as Map<String, Object?>;
    if (j['format'] != 1) throw FormatException('Unknown catalog format');
    Uri? uri(Object? s) => s is String && s.isNotEmpty ? Uri.parse(s) : null;
    return Catalog(
      [
        for (final i in j['items']! as List)
          CatalogItem.fromJson((i as Map).cast()),
      ],
      base: baseOverride ?? uri(j['base']) ?? fetchedFrom,
      refreshUrl: uri(j['refresh']),
    );
  }

  CatalogItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Download address of [f], or null when it is relative and there is no base.
  Uri? urlOf(CatalogFile f) {
    final u = Uri.parse(f.url);
    if (u.hasScheme) return u;
    return base?.resolveUri(u);
  }

  bool canDownload(CatalogItem item) =>
      item.files.every((f) => urlOf(f) != null);

  FileSpec spec(CatalogFile f) =>
      FileSpec(url: urlOf(f)!, name: f.name, size: f.size, sha256: f.sha256);
}

/// "2.8 GB", "310 MB" (decimal, as shops and Hugging Face show sizes).
String formatBytes(int b) {
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
  if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(b >= 1e8 ? 0 : 1)} MB';
  if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
  return '$b B';
}
