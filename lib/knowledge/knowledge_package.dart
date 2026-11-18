import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';

class Source {
  Source(
    this.id,
    this.title,
    this.publisher,
    this.url,
    this.licence,
    this.attribution, {
    this.region = 'JP',
  });
  final String id, title, publisher, url, licence, attribution;

  /// Where the source's advice applies, as an ISO 3166 code: 'JP' (Japan),
  /// 'JP-13' (Tokyo), 'GB', 'US'. More local sources rank a little higher;
  /// foreign ones are labelled (see [localityLevel]).
  final String region;
}

/// How local a source is for someone in [user] (an ISO 3166 code such as
/// 'JP' or 'JP-13'): 0 another country, 1 the same country (or another
/// region in it), 2 and more for each further level that matches.
int localityLevel(String region, String user) {
  final r = region.split('-'), u = user.split('-');
  if (r.first != u.first) return 0;
  var level = 1;
  for (var i = 1; i < r.length && i < u.length && r[i] == u[i]; i++) {
    level++;
  }
  return level;
}

/// A small nudge, never a filter: relevance decides, and between passages
/// that are about equally relevant the more local one goes first. In RRF
/// terms 3 % moves a passage up about two places per level.
double localityBoost(String region, String user) =>
    1 + 0.03 * localityLevel(region, user);

/// Names for foreign source labels, e.g. 「海外の資料（英国）」.
const _countries = <String, (String, String)>{
  'GB': ('英国', 'UK'),
  'US': ('米国', 'US'),
  'CA': ('カナダ', 'Canada'),
  'AU': ('オーストラリア', 'Australia'),
  'NZ': ('ニュージーランド', 'New Zealand'),
  'CH': ('スイス', 'Switzerland'),
  'AT': ('オーストリア', 'Austria'),
  'DE': ('ドイツ', 'Germany'),
};

/// "海外の資料（英国）" / "Source from the UK", or null for a local source.
String? foreignLabel(Source s, String user, {required bool en}) {
  if (localityLevel(s.region, user) > 0) return null;
  final code = s.region.split('-').first;
  final name = _countries[code];
  return en ? 'Source from ${name?.$2 ?? code}' : '海外の資料（${name?.$1 ?? code}）';
}

class Passage {
  Passage(
    this.id,
    this.source,
    this.heading,
    this.text, {
    this.original,
    this.originalHeading,
    this.texts = const {},
  });
  final int id;
  final Source source;
  final String heading, text;

  /// For a passage translated when the package was built (foreign sources):
  /// the source's own text. [text] is then our translation (not official).
  final String? original, originalHeading;

  bool get translated => original != null;

  /// The passage in other languages, made when the package was built
  /// (never by the phone model): lang → (heading, text).
  final Map<String, (String, String)> texts;

  /// The text to read for a question in [lang] ('ja', 'en').
  String textIn(String lang) => texts[lang]?.$2 ?? text;
  String headingIn(String lang) => texts[lang]?.$1 ?? heading;
}

/// A fixed safety line, quoted word for word from its source.
class Alert {
  Alert(
    this.id,
    this.source,
    this.text,
    this.matchAll,
    this.textEn,
    this.matchAllEn,
  );
  final String id;
  final Source source;
  final String text;

  /// Every group needs at least one word present in the question.
  final List<List<String>> matchAll;

  /// Our English translation (not official) and its trigger words.
  final String? textEn;
  final List<List<String>> matchAllEn;

  bool matches(String question) {
    bool all(List<List<String>> groups, String q) =>
        groups.isNotEmpty && groups.every((g) => g.any(q.contains));
    return all(matchAll, question) || all(matchAllEn, question.toLowerCase());
  }
}

class PackageInfo {
  const PackageInfo(
    this.id,
    this.title,
    this.version,
    this.passages, {
    this.notice = const {},
  });
  final String id, title, version;
  final int passages;

  /// What the package is not for, per language ('ja', 'en'): shown before
  /// people rely on it (see lib/app/notices.dart).
  final Map<String, List<String>> notice;

  List<String> noticeIn({required bool en}) =>
      notice[en ? 'en' : 'ja'] ?? notice['ja'] ?? const [];

  /// Changes when the notice text changes, so people see it again.
  String get noticeKey => 'pkg:$id:${_fnv(jsonEncode(notice))}';
}

/// A hash that stays the same between app runs (String.hashCode may not).
String _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

/// The notice from a package's meta table. Packages built before notices
/// existed get the one from their manifest here, so the released file (and
/// its checksum in the download catalog) can stay as it is until the next
/// data release.
Map<String, List<String>> parseNotice(String? json, {String? id}) {
  final n = {
    for (final e in (jsonDecode(json ?? '{}') as Map).entries)
      e.key as String: List<String>.from(e.value as List),
  };
  return n.isEmpty ? (_noticesOfOlderPackages[id] ?? const {}) : n;
}

/// Copied from `tool/packages/<id>.json` ("notice").
const _noticesOfOlderPackages = <String, Map<String, List<String>>>{
  'jp.bousai.core': {
    'ja': ['避難するかどうかは、自治体の避難情報と気象庁の警報・注意報を優先して判断してください。'],
    'en': [
      "For evacuation, follow your city's evacuation information and the "
          "Japan Meteorological Agency's warnings first.",
    ],
  },
};

/// A knowledge package: one SQLite file built by tool/build_package.py.
///
/// Small enough to keep in memory; SQLite is the file format.
class KnowledgePackage {
  KnowledgePackage._(
    this.id,
    this.title,
    this.version,
    this.sources,
    this.passages,
    this.alerts,
    this.synonyms,
    this.vectors, {
    List<PackageInfo>? parts,
    Map<String, List<String>> notice = const {},
  }) : parts =
           parts ??
           [PackageInfo(id, title, version, passages.length, notice: notice)];

  final String id, title, version;

  /// The packages this one was made of (itself, unless merged).
  final List<PackageInfo> parts;
  final Map<String, Source> sources;
  final List<Passage> passages;
  final List<Alert> alerts;

  /// Words to add to a question before keyword search (飲み水 → 飲料水).
  final Map<String, List<String>> synonyms;

  /// Precomputed passage vectors per embedding model file name, in passage
  /// order (tool/add_vectors.py). Saves phones from indexing the package.
  final Map<String, List<List<double>>> vectors;

  /// One package searched as a whole: all passages, sources, safety lines
  /// and synonyms together. Passage ids are renumbered so they stay unique.
  /// Shipped vectors are kept for a model only when every package has them
  /// (otherwise the app embeds the passages once and caches them).
  static KnowledgePackage merge(List<KnowledgePackage> packages) {
    if (packages.isEmpty) throw ArgumentError('no packages');
    if (packages.length == 1) return packages.first;
    final sources = <String, Source>{};
    final passages = <Passage>[];
    final synonyms = <String, List<String>>{};
    for (final pkg in packages) {
      sources.addAll(pkg.sources);
      for (final p in pkg.passages) {
        passages.add(
          Passage(
            passages.length + 1,
            p.source,
            p.heading,
            p.text,
            original: p.original,
            originalHeading: p.originalHeading,
            texts: p.texts,
          ),
        );
      }
      pkg.synonyms.forEach((word, alts) {
        final all = synonyms[word] ??= [];
        for (final a in alts) {
          if (!all.contains(a)) all.add(a);
        }
      });
    }
    final vectors = <String, List<List<double>>>{};
    for (final model in packages.first.vectors.keys) {
      if (packages.every(
        (p) => p.vectors[model]?.length == p.passages.length,
      )) {
        vectors[model] = [for (final p in packages) ...p.vectors[model]!];
      }
    }
    return KnowledgePackage._(
      [for (final p in packages) p.id].join('+'),
      [for (final p in packages) p.title].join('・'),
      [for (final p in packages) p.version].join('+'),
      sources,
      passages,
      [for (final p in packages) ...p.alerts],
      synonyms,
      vectors,
      parts: [for (final p in packages) ...p.parts],
    );
  }

  /// Only the name, version and notice of a package file (no passages).
  static PackageInfo readInfo(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      return PackageInfo(
        meta['id']!,
        meta['title'] ?? '',
        meta['version'] ?? '',
        0,
        notice: parseNotice(meta['notice'], id: meta['id']),
      );
    } finally {
      db.close();
    }
  }

  /// Copies a bundled package out of the assets (SQLite needs a real file) and loads it.
  static Future<KnowledgePackage> fromAsset(String name) async {
    final store = await DownloadStore.instance();
    return open(await store.copyBundled('packages', name));
  }

  static KnowledgePackage open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      final rows = db.select('SELECT * FROM sources');
      // Packages built before regions existed are Japanese.
      final hasRegion = rows.columnNames.contains('region');
      final sources = {
        for (final r in rows)
          r['id'] as String: Source(
            r['id'],
            r['title'],
            r['publisher'],
            r['url'],
            r['licence'],
            r['attribution'],
            region: (hasRegion ? r['region'] as String? : null) ?? 'JP',
          ),
      };
      final passageRows = db.select('SELECT * FROM passages ORDER BY id');
      // Packages built before translations existed have no such columns.
      final hasOriginal = passageRows.columnNames.contains('original');
      // Texts in other languages (tool/add_translations.py), and for a
      // translated foreign source its original, in the package language.
      final texts = <int, Map<String, (String, String)>>{};
      if (db
          .select("SELECT 1 FROM sqlite_master WHERE name = 'passage_texts'")
          .isNotEmpty) {
        for (final r in db.select('SELECT * FROM passage_texts')) {
          (texts[r['passage_id'] as int] ??= {})[r['lang'] as String] = (
            r['heading'] as String? ?? '',
            r['text'] as String,
          );
        }
      }
      final language = meta['language'] ?? 'ja';
      final passages = [
        for (final r in passageRows)
          Passage(
            r['id'],
            sources[r['source_id']]!,
            r['heading'] ?? '',
            r['text'],
            original: hasOriginal ? r['original'] as String? : null,
            originalHeading: hasOriginal
                ? r['original_heading'] as String?
                : null,
            texts: {
              if (hasOriginal && r['original'] != null)
                language: (
                  r['original_heading'] as String? ?? '',
                  r['original'] as String,
                ),
              ...?texts[r['id'] as int],
            },
          ),
      ];
      List<List<String>> groups(Object? json) => [
        for (final g in jsonDecode(json as String? ?? '[]') as List)
          List<String>.from(g as List),
      ];
      final alerts = [
        for (final r in db.select('SELECT * FROM alerts'))
          Alert(
            r['id'],
            sources[r['source_id']]!,
            r['text'],
            groups(r['match_all']),
            r['text_en'] as String?,
            groups(r['match_all_en']),
          ),
      ];
      final synonyms = {
        for (final e in (jsonDecode(meta['synonyms'] ?? '{}') as Map).entries)
          e.key as String: List<String>.from(e.value as List),
      };
      final vectors = <String, List<List<double>>>{};
      final hasVectors = db
          .select("SELECT 1 FROM sqlite_master WHERE name = 'vectors'")
          .isNotEmpty;
      if (hasVectors) {
        for (final r in db.select(
          'SELECT model, vec FROM vectors ORDER BY model, passage_id',
        )) {
          final bytes = r['vec'] as Uint8List;
          final floats = bytes.buffer.asFloat32List(
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ 4,
          );
          (vectors[r['model'] as String] ??= []).add(List<double>.from(floats));
        }
      }
      return KnowledgePackage._(
        meta['id']!,
        meta['title'] ?? '',
        meta['version'] ?? '',
        sources,
        passages,
        alerts,
        synonyms,
        vectors,
        notice: parseNotice(meta['notice'], id: meta['id']),
      );
    } finally {
      db.close();
    }
  }
}
