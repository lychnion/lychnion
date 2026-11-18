import '../knowledge/language.dart';
import 'download_store.dart';
import 'downloader.dart';

import 'package:lychnion_format/lychnion_format.dart';

enum ItemKind { model, package, map }

/// One file of a catalog item. [url] may be relative to the catalog's base.
class CatalogFile {
  const CatalogFile(
    this.name,
    this.size,
    this.sha256,
    this.url, [
    this.more = const [],
  ]);
  final String name;
  final int size;
  final String sha256;

  /// The first address to try.
  final String url;

  /// Further addresses of the same file (for example the internet copy
  /// behind a base's), tried in order when [url] fails.
  final List<String> more;

  List<String> get urls => [url, ...more];
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

  /// Places the item is for ('JP', 'JP-30'); empty means anywhere.
  List<String> get area => record?.area ?? const [];
  String title(String lang) => pick(titles, lang) ?? id;
  String note(String lang) => pick(notes, lang) ?? '';

  /// [urls]: file SHA-256 → download addresses (absolute, or relative to
  /// the catalog), in the order to try them. Files not listed there are
  /// fetched by name.
  factory CatalogItem.fromRecord(
    PackageRecord r, [
    Map<String, List<String>> urls = const {},
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
        switch (urls[f.sha256]) {
          [final first, ...final rest] => CatalogFile(
            f.name,
            f.size,
            f.sha256,
            first,
            rest,
          ),
          _ => CatalogFile(f.name, f.size, f.sha256, f.name),
        },
    ],
  );
}

/// The list of downloads. Bundled with the app (assets/downloads/catalog.json)
/// and refreshed from [refreshUrl] when online, so packages can be updated
/// without an app release.
class Catalog {
  Catalog(
    this.items, {
    this.base,
    this.refreshUrl,
    this.mirrors = const [],
    this.statements = const [],
  });

  /// Key statements in the catalog's `keys` made by keys the device
  /// trusts (see relevantStatements); the device keeps them.
  final List<KeyStatement> statements;

  final List<CatalogItem> items;

  /// Nodes that keep files by hash (`<mirror>blobs/sha256/<sha256>`), tried
  /// for every file after its own addresses. Unsigned: the hash in the
  /// signed record decides whether a file from a mirror is right.
  final List<Uri> mirrors;

  /// Relative file URLs are resolved against this. Null: only absolute
  /// URLs (the models on Hugging Face) can be downloaded.
  final Uri? base;
  final Uri? refreshUrl;

  /// Records whose shape or signature is wrong, or whose publisher is not
  /// trusted, are left out and listed here (id or position, and why).
  final List<String> rejected = [];

  /// Parses a catalog (format 2: signed records, see lychnion-data/tool/records.dart).
  ///
  /// `urls` maps a file's SHA-256 to one address (a string: older apps
  /// read only that). `mirrors` lists nodes with the `blobs/sha256/`
  /// layout; older apps ignore it.
  ///
  /// [baseOverride] (dev flag DOWNLOAD_BASE_URL) wins over the catalog's own
  /// `base`; a catalog fetched from the network defaults to its own URL.
  /// [trust] defaults to the publishers built into the app.
  ///
  /// With [ownFilesOnly] (a base's or a nearby phone's catalog), every
  /// file address and mirror must be on the host it came from
  /// ([fetchedFrom]); others are left out, so a device on the Wi-Fi
  /// cannot make the phone contact hosts it picks.
  static Future<Catalog> parse(
    String json, {
    Uri? fetchedFrom,
    Uri? baseOverride,
    TrustedKeys? trust,
    bool ownFilesOnly = false,
  }) async {
    final doc = CatalogDocument.parse(json);
    Uri? uri(Object? s) => s is String && s.isNotEmpty ? Uri.parse(s) : null;
    if (ownFilesOnly && fetchedFrom == null) {
      throw ArgumentError('ownFilesOnly needs fetchedFrom');
    }
    bool own(String s) {
      if (!ownFilesOnly) return true;
      final u = Uri.tryParse(s);
      return u != null && _sameOrigin(fetchedFrom!.resolveUri(u), fetchedFrom);
    }

    final urls = <String, List<String>>{
      for (final e in doc.urls.entries)
        if (own(e.value)) e.key: [e.value],
    };
    // Key statements first: records signed by a successor key the
    // catalog announces are accepted at once. Older apps ignore `keys`.
    final given = trust ?? builtInPublishers;
    final statements = await relevantStatements(given, doc.keys);
    final keys = given.withStatements(statements);
    final items = <CatalogItem>[];
    final rejected = <String>[];
    final raw = doc.records;
    for (var n = 0; n < raw.length; n++) {
      final r = await keys.check(raw[n]);
      final id = raw[n] is Map ? (raw[n] as Map)['id'] : null;
      if (r == null) {
        rejected.add('${id ?? '#$n'}: bad signature or record');
      } else if (!ItemKind.values.any((k) => k.name == r.kind)) {
        rejected.add('${r.id}: unknown kind ${r.kind}');
      } else if (r.files.any((f) => DownloadStore.isReservedName(f.name))) {
        rejected.add('${r.id}: reserved file name');
      } else if (items.any((i) => i.id == r.id)) {
        rejected.add('${r.id}: listed twice');
      } else {
        items.add(CatalogItem.fromRecord(r, urls));
      }
    }
    // A base's own `base` and `refresh` are not followed either.
    final base = ownFilesOnly
        ? fetchedFrom
        : baseOverride ?? uri(doc.base) ?? fetchedFrom;
    return Catalog(
      items,
      base: base,
      refreshUrl: ownFilesOnly ? null : uri(doc.refresh),
      statements: statements,
      mirrors: [
        for (final m in _mirrors(doc.mirrors, fetchedFrom ?? base))
          if (!ownFilesOnly || _sameOrigin(m, fetchedFrom!)) m,
      ],
    )..rejected.addAll(rejected);
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  /// At most this many mirrors are used: each unreachable one costs time.
  static const maxMirrors = 10;

  /// Mirror addresses as folders (ending in `/`, no query), relative ones
  /// resolved against the catalog's own address; anything else is left
  /// out.
  static List<Uri> _mirrors(Object? raw, Uri? from) {
    final out = <Uri>[];
    for (final m in raw is List ? raw : const []) {
      if (out.length >= maxMirrors) break;
      if (m is! String || m.isEmpty) continue;
      var u = Uri.tryParse(m);
      if (u == null) continue;
      if (!u.hasScheme) {
        if (from == null) continue;
        u = from.resolveUri(u);
      }
      final path = u.path.endsWith('/') ? u.path : '${u.path}/';
      u = Uri(
        scheme: u.scheme,
        userInfo: u.userInfo,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: path,
      );
      if (_web(u) && !out.contains(u)) out.add(u);
    }
    return out;
  }

  CatalogItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The file's own addresses, absolute; relative ones are dropped when
  /// there is no base.
  List<Uri> _ownUrls(CatalogFile f) => [
    for (final s in f.urls)
      if (Uri.tryParse(s) case final u?)
        if (u.hasScheme)
          if (_web(u)) u else ...[]
        else if (base case final b?)
          if (_web(b.resolveUri(u))) b.resolveUri(u),
  ];

  static bool _web(Uri u) =>
      (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;

  /// Every address of [f], in the order to try them: its own, then each
  /// mirror's `blobs/sha256/<hash>`.
  List<Uri> urlsOf(CatalogFile f) {
    final out = <Uri>[];
    for (final u in [
      ..._ownUrls(f),
      for (final m in mirrors) m.resolve('blobs/sha256/${f.sha256}'),
    ]) {
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  /// First download address of [f], or null when there is none (a
  /// relative address without a base, and no mirrors).
  Uri? urlOf(CatalogFile f) => urlsOf(f).firstOrNull;

  /// This catalog plus the items of [other] (for example a base's). An
  /// item of [other] wins when its version is the same or newer: a base
  /// on the local Wi-Fi is faster and works without internet. Records are
  /// checked as before.
  ///
  /// Files are known by their hash, so every address either catalog has
  /// for a file is kept, absolute: [other]'s first, then this catalog's
  /// (the internet copy when the base's Wi-Fi is gone). Mirrors of both
  /// are kept too.
  ///
  /// With [preferOther] false (a followed catalog), this catalog keeps an
  /// item of the same version and its addresses come first; [other] only
  /// adds items and newer versions.
  Catalog mergedWith(Catalog other, {bool preferOther = true}) {
    final addresses = <String, List<String>>{};
    for (final c in preferOther ? [other, this] : [this, other]) {
      for (final i in c.items) {
        for (final f in i.files) {
          final list = addresses.putIfAbsent(f.sha256, () => []);
          for (final u in c._ownUrls(f)) {
            if (!list.contains('$u')) list.add('$u');
          }
        }
      }
    }
    final mirrors = [
      ...this.mirrors,
      for (final m in other.mirrors)
        if (!this.mirrors.contains(m)) m,
    ].take(maxMirrors).toList();
    bool reachable(CatalogItem i) => i.files.every(
      (f) => (addresses[f.sha256] ?? const []).isNotEmpty || mirrors.isNotEmpty,
    );
    final byId = {for (final i in items) i.id: i};
    for (final o in other.items) {
      final mine = byId[o.id];
      if (mine != null &&
          (preferOther
              ? isOlder(o.version, mine.version)
              : !isOlder(mine.version, o.version))) {
        continue;
      }
      // An id stays with its publisher: another publisher's item of the
      // same id (a city's catalog on a base) never replaces it.
      if (mine?.record case final m? when m.publisher != o.record?.publisher) {
        continue;
      }
      if (o.record == null || !reachable(o)) continue;
      byId[o.id] = o;
    }
    return Catalog(
      [
        for (final i in byId.values)
          if (i.record case final r?)
            CatalogItem.fromRecord(r, {
              for (final f in i.files)
                if (addresses[f.sha256] case final a? when a.isNotEmpty)
                  f.sha256: a,
            })
          else
            i,
      ],
      base: base,
      refreshUrl: refreshUrl,
      mirrors: mirrors,
    )..rejected.addAll([...rejected, ...other.rejected]);
  }

  bool canDownload(CatalogItem item) =>
      item.files.every((f) => urlOf(f) != null);

  /// What to fetch for [f]: its first address, the others as fallbacks.
  FileSpec spec(CatalogFile f) {
    final urls = urlsOf(f);
    return FileSpec(
      url: urls.first,
      fallbacks: urls.skip(1).toList(),
      name: f.name,
      size: f.size,
      sha256: f.sha256,
    );
  }
}

/// "2.8 GB", "310 MB" (decimal, as shops and Hugging Face show sizes).
String formatBytes(int b) {
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
  if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(b >= 1e8 ? 0 : 1)} MB';
  if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
  return '$b B';
}

/// How well an item's [area] fits the user's [region] ('JP-30', or 'JP'
/// when only the country is known): 3 made for that region, 2 for the
/// whole country (or the region is unknown and the item is in the
/// country), 1 anywhere (no area), 0 somewhere else.
int areaRank(List<String> area, String region) {
  if (area.isEmpty) return 1;
  if (area.contains(region)) return 3;
  final country = region.split('-').first;
  if (area.contains(country)) return 2;
  if (region == country && area.any((c) => c.startsWith('$country-'))) {
    return 2;
  }
  return 0;
}

/// [items] with the best fit for [region] first; otherwise in catalog
/// order.
List<CatalogItem> byArea(List<CatalogItem> items, String? region) {
  if (region == null) return items;
  final order = [for (var i = 0; i < items.length; i++) i]
    ..sort((a, b) {
      final d =
          areaRank(items[b].area, region) - areaRank(items[a].area, region);
      return d != 0 ? d : a - b;
    });
  return [for (final i in order) items[i]];
}
