import 'dart:convert';

import '../knowledge/language.dart';
import 'downloader.dart';
import 'publishers.dart';
import 'record.dart';

enum ItemKind { model, package, map }

/// One file of a catalog item. [url] may be relative to the catalog's base.
class CatalogFile {
  const CatalogFile(this.name, this.size, this.sha256, this.url);
  final String name;
  final int size;
  final String sha256;
  final String url;
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
    this.record,
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

  /// The signed record this item comes from. Only items with a verified
  /// record can be installed.
  final PackageRecord? record;

  int get size => files.fold(0, (a, f) => a + f.size);
  String title(String lang) => pick(titles, lang) ?? id;
  String note(String lang) => pick(notes, lang) ?? '';

  /// [urls]: file SHA-256 → download address (absolute, or relative to
  /// the catalog). Files not listed there are fetched by name.
  factory CatalogItem.fromRecord(
    PackageRecord r, [
    Map<String, String> urls = const {},
  ]) => CatalogItem(
    id: r.id,
    kind: ItemKind.values.byName(r.kind),
    titles: r.texts('title'),
    version: r.version,
    licence: r.licence,
    role: r.role,
    desktop: r.desktop,
    notes: r.texts('note'),
    record: r,
    files: [
      for (final f in r.files)
        CatalogFile(f.name, f.size, f.sha256, urls[f.sha256] ?? f.name),
    ],
  );
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

  /// Records whose shape or signature is wrong, or whose publisher is not
  /// trusted, are left out and listed here (id or position, and why).
  final List<String> rejected = [];

  /// Parses a catalog (format 2: signed records, see tool/records.dart).
  ///
  /// [baseOverride] (dev flag DOWNLOAD_BASE_URL) wins over the catalog's own
  /// `base`; a catalog fetched from the network defaults to its own URL.
  /// [trust] defaults to the publishers built into the app.
  static Future<Catalog> parse(
    String json, {
    Uri? fetchedFrom,
    Uri? baseOverride,
    TrustedKeys? trust,
  }) async {
    final j = jsonDecode(json) as Map<String, Object?>;
    if (j['format'] != 2) throw FormatException('Unknown catalog format');
    Uri? uri(Object? s) => s is String && s.isNotEmpty ? Uri.parse(s) : null;
    final urls = ((j['urls'] as Map?) ?? const {}).cast<String, String>();
    final keys = trust ?? builtInPublishers;
    final items = <CatalogItem>[];
    final rejected = <String>[];
    final raw = j['records']! as List;
    for (var n = 0; n < raw.length; n++) {
      final r = await keys.check(raw[n]);
      final id = raw[n] is Map ? (raw[n] as Map)['id'] : null;
      if (r == null) {
        rejected.add('${id ?? '#$n'}: bad signature or record');
      } else if (!ItemKind.values.any((k) => k.name == r.kind)) {
        rejected.add('${r.id}: unknown kind ${r.kind}');
      } else if (items.any((i) => i.id == r.id)) {
        rejected.add('${r.id}: listed twice');
      } else {
        items.add(CatalogItem.fromRecord(r, urls));
      }
    }
    return Catalog(
      items,
      base: baseOverride ?? uri(j['base']) ?? fetchedFrom,
      refreshUrl: uri(j['refresh']),
    )..rejected.addAll(rejected);
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

  /// This catalog plus the items of [other] (for example a shelter's), with
  /// [other]'s file addresses made absolute. An item of [other] wins when
  /// its version is the same or newer: a shelter on the local Wi-Fi is
  /// faster and works without internet. Records are checked as before.
  Catalog mergedWith(Catalog other) {
    final byId = {for (final i in items) i.id: i};
    for (final o in other.items) {
      final mine = byId[o.id];
      if (mine != null && isOlder(o.version, mine.version)) continue;
      final files = [
        for (final f in o.files)
          if (other.urlOf(f) case final u?)
            CatalogFile(f.name, f.size, f.sha256, '$u'),
      ];
      if (files.length != o.files.length || o.record == null) continue;
      byId[o.id] = CatalogItem.fromRecord(o.record!, {
        for (final f in files) f.sha256: f.url,
      });
    }
    return Catalog([...byId.values], base: base, refreshUrl: refreshUrl)
      ..rejected.addAll([...rejected, ...other.rejected]);
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
