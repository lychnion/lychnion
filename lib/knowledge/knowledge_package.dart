import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';
import 'language.dart';

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

/// Country names for foreign source labels, by language.
const _countries = <String, Map<String, String>>{
  'GB': {'ja': '英国', 'en': 'UK'},
  'US': {'ja': '米国', 'en': 'US'},
  'CA': {'ja': 'カナダ', 'en': 'Canada'},
  'AU': {'ja': 'オーストラリア', 'en': 'Australia'},
  'NZ': {'ja': 'ニュージーランド', 'en': 'New Zealand'},
  'CH': {'ja': 'スイス', 'en': 'Switzerland'},
  'AT': {'ja': 'オーストリア', 'en': 'Austria'},
  'DE': {'ja': 'ドイツ', 'en': 'Germany'},
};

/// "Source from {country}" per language; other languages use English.
const _foreignLabel = <String, String Function(String)>{'ja': _ja, 'en': _en};
String _ja(String country) => '海外の資料（$country）';
String _en(String country) => 'Source from $country';

/// 「海外の資料（英国）」 / "Source from UK", or null for a local source.
String? foreignLabel(Source s, String user, {required String lang}) {
  if (localityLevel(s.region, user) > 0) return null;
  final code = s.region.split('-').first;
  final name = pick(_countries[code] ?? const <String, String>{}, lang) ?? code;
  return (_foreignLabel[lang] ?? _en)(name);
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
    this.text, {
    this.matchAll = const {},
    this.translations = const {},
  });
  final String id;
  final Source source;

  /// The official text, word for word.
  final String text;

  /// Trigger words per language: every group needs at least one word
  /// present in the question.
  final Map<String, List<List<String>>> matchAll;

  /// Our translations (not official), by language.
  final Map<String, String> translations;

  /// The text to show for [lang]: our translation if there is one, else
  /// the official text.
  String textIn(String lang) => translations[lang] ?? text;
  bool translatedFor(String lang) => translations.containsKey(lang);

  /// Whether [question] has a word from every group of one language. An
  /// empty or blank word never matches: `"".contains` is true for any
  /// question, so one empty word would put this line above every answer
  /// (lychnion/lychnion#66).
  bool matches(String question) {
    final lower = question.toLowerCase();
    bool has(String w) =>
        w.trim().isNotEmpty && (question.contains(w) || lower.contains(w));
    bool all(List<List<String>> groups) =>
        groups.isNotEmpty && groups.every((g) => g.any(has));
    return matchAll.values.any(all);
  }
}

class PackageInfo {
  const PackageInfo(
    this.id,
    this.title,
    this.version,
    this.passages, {
    this.notice = const {},
    this.name = const {},
    this.icon = '',
    this.suggestions = const {},
  });
  final String id, title, version;
  final int passages;

  /// Shown name per language (falls back to [title]), an icon name (see
  /// lib/ui/package_icons.dart) and suggested first questions per language:
  /// all from the package's manifest, so any publisher can bring them.
  final Map<String, String> name;
  final String icon;
  final Map<String, List<({String icon, String text})>> suggestions;

  String nameIn(String lang) => pick(name, lang) ?? title;
  List<({String icon, String text})> suggestionsIn(String lang) =>
      pick(suggestions, lang) ?? const [];

  /// What the package is not for, per language ('ja', 'en'): shown before
  /// people rely on it (see lib/app/notices.dart).
  final Map<String, List<String>> notice;

  List<String> noticeIn(String lang) => pick(notice, lang) ?? const [];

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

/// Name, icon and suggestions from a package's meta table.
({
  Map<String, String> name,
  String icon,
  Map<String, List<({String icon, String text})>> suggestions,
})
parseLabels(Map<String, String> meta) => (
  name: (jsonDecode(meta['name'] ?? '{}') as Map).cast<String, String>(),
  icon: meta['icon'] ?? '',
  suggestions: {
    for (final e in (jsonDecode(meta['suggestions'] ?? '{}') as Map).entries)
      e.key as String: [
        for (final s in e.value as List)
          (icon: (s as Map)['icon'] as String, text: s['text'] as String),
      ],
  },
);

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

/// Copied from `lychnion-data/packages/<id>.json` ("notice").
const _noticesOfOlderPackages = <String, Map<String, List<String>>>{
  'jp.bousai.core': {
    'ja': ['避難するかどうかは、自治体の避難情報と気象庁の警報・注意報を優先して判断してください。'],
    'en': [
      "For evacuation, follow your city's evacuation information and the "
          "Japan Meteorological Agency's warnings first.",
    ],
  },
};

/// A knowledge package: one SQLite file built by lychnion-data/tool/build_package.py.
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
    Map<String, String> meta = const {},
  }) : parts =
           parts ??
           [
             PackageInfo(
               id,
               title,
               version,
               passages.length,
               notice: notice,
               name: parseLabels(meta).name,
               icon: parseLabels(meta).icon,
               suggestions: parseLabels(meta).suggestions,
             ),
           ];

  final String id, title, version;

  /// The packages this one was made of (itself, unless merged).
  final List<PackageInfo> parts;
  final Map<String, Source> sources;
  final List<Passage> passages;
  final List<Alert> alerts;

  /// Words to add to a question before keyword search (飲み水 → 飲料水).
  final Map<String, List<String>> synonyms;

  /// Precomputed passage vectors per embedding model file name, in passage
  /// order (lychnion-data/tool/add_vectors.py). Saves phones from indexing the package.
  final Map<String, List<List<double>>> vectors;

  /// This package without its safety lines: for a package from a
  /// publisher the user added. Its guides are searched and quoted with
  /// their source, but only Lychnion's packages supply the fixed official
  /// safety line above an answer (lychnion/lychnion#66).
  KnowledgePackage withoutAlerts() => alerts.isEmpty
      ? this
      : KnowledgePackage._(
          id,
          title,
          version,
          sources,
          passages,
          const [],
          synonyms,
          vectors,
          parts: parts,
        );

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
    bool complete(KnowledgePackage p, String key) =>
        p.vectors[key]?.length == p.passages.length;
    for (final model in packages.first.vectors.keys.where(
      (k) => !k.contains('@'),
    )) {
      if (packages.every((p) => complete(p, model))) {
        vectors[model] = [for (final p in packages) ...p.vectors[model]!];
      }
    }
    // Vectors of the texts in another language (`<model>@<lang>`) are kept
    // where some packages ship them: an empty vector stands for none, so
    // one package without them does not turn them off for all
    // (lychnion/lychnion#85).
    final textKeys = {
      for (final p in packages)
        for (final k in p.vectors.keys)
          if (k.contains('@') && vectors.containsKey(k.split('@').first)) k,
    };
    for (final key in textKeys) {
      vectors[key] = [
        for (final p in packages)
          if (complete(p, key))
            ...p.vectors[key]!
          else
            for (final _ in p.passages) const <double>[],
      ];
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
        name: parseLabels(meta).name,
        icon: parseLabels(meta).icon,
        suggestions: parseLabels(meta).suggestions,
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
            r['id'] as String,
            r['title'] as String,
            r['publisher'] as String,
            r['url'] as String,
            r['licence'] as String,
            r['attribution'] as String,
            region: (hasRegion ? r['region'] as String? : null) ?? 'JP',
          ),
      };
      final passageRows = db.select('SELECT * FROM passages ORDER BY id');
      // Packages built before translations existed have no such columns.
      final hasOriginal = passageRows.columnNames.contains('original');
      // Texts in other languages (lychnion-data/tool/add_translations.py), and for a
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
            r['id'] as int,
            sources[r['source_id'] as String]!,
            r['heading'] as String? ?? '',
            r['text'] as String,
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
            r['id'] as String,
            sources[r['source_id'] as String]!,
            r['text'] as String,
            // The package language's trigger words, plus English ones.
            matchAll: {
              meta['language'] ?? 'ja': groups(r['match_all']),
              'en': groups(r['match_all_en']),
            },
            translations: {'en': ?r['text_en'] as String?},
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
        meta: meta,
      );
    } finally {
      db.close();
    }
  }
}
