import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../llm/local_embedder.dart';
import 'knowledge_package.dart';
import 'retriever.dart';

final _japanese = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');

/// One passage with both scores, for ranking and for the spike logs.
class RankedHit extends Hit {
  RankedHit(
    super.passage,
    super.score, {
    required this.cosine,
    required this.keyword,
  });
  final double cosine;
  final double keyword;
}

/// Vector search (multilingual, so English questions find Japanese text)
/// combined with the bigram keyword search by reciprocal rank fusion.
///
/// [minCosine] is the relevance cut-off: passages less similar than this are
/// never given to the model. If none pass, the answer is "no source".
///
/// A question is compared with each passage's text in its own language
/// where the package has one (the English text, translated when the package
/// was built), and with the main text across languages: across languages
/// the same match scores about 0.02 lower, so that comparison counts 0.02
/// more. Measured on the answer eval's questions (lychnion/lychnion#85),
/// "water for four people for three days" in English: 0.674 against the
/// Japanese text, 0.724 against its English text.
class HybridRetriever {
  HybridRetriever(
    this.package,
    this.embedder, {
    this.minCosine = 0.0,
    this.embedTexts = false,
  }) : keywords = Retriever(package);

  final KnowledgePackage package;
  final LocalEmbedder embedder;
  final Retriever keywords;
  double minCosine;

  /// Embed the texts in other languages when the package does not ship
  /// their vectors (and none are cached), for lychnion-data to ship them
  /// (EMBED_TEXTS). Off in the app: a Pixel 5a took 133 s for 108 passages
  /// (docs/device-results.md); without them a question is compared across
  /// languages only.
  final bool embedTexts;

  /// Where the user is (ISO 3166); more local sources get a small nudge.
  String userRegion = 'JP';

  /// How much less the same match scores across languages (see the class).
  static const crossLanguage = 0.02;

  /// Vectors of each passage's main text (the one keyword search reads).
  late List<List<double>> _vectors;

  /// Vectors of the passages' texts in other languages, by language: null
  /// where a passage has no text in that language.
  var _textVectors = <String, List<List<double>?>>{};

  /// The main text is Japanese (for a translated foreign source, our
  /// translation); other languages are in [Passage.texts].
  static const _mainLang = 'ja';

  /// Uses the vectors shipped in the package if they match the embedding
  /// model (`<model>` for the main texts, `<model>@<lang>` for the texts in
  /// another language); otherwise embeds the passages once and caches them
  /// on disk (the texts in other languages only with [embedTexts]).
  Future<void> index() async {
    final passages = package.passages;
    _vectors = (await _load(embedder.modelName, [
      for (final p in passages) _docText(p, null),
    ]))!;
    final langs = {for (final p in passages) ...p.texts.keys}
        .where((l) => l != _mainLang);
    _textVectors = {};
    for (final lang in langs) {
      final has = [for (final p in passages) p.texts.containsKey(lang)];
      final key = '${embedder.modelName}@$lang';
      // Only the passages with a text in [lang] are embedded; the others
      // keep the main text's vector, so shipped and cached lists stay one
      // per passage.
      final all = await _load(
        key,
        embed: embedTexts,
        [
          for (var i = 0; i < passages.length; i++)
            if (has[i]) _docText(passages[i], lang),
        ],
        fill: (embedded) {
          final it = embedded.iterator;
          return [
            for (var i = 0; i < passages.length; i++)
              has[i] && it.moveNext() ? it.current : _vectors[i],
          ];
        },
      );
      if (all == null) continue;
      _textVectors[lang] = [
        for (var i = 0; i < passages.length; i++) has[i] ? all[i] : null,
      ];
    }
  }

  /// The vectors for [key]: shipped, cached, or (when [embed]) embedded
  /// from [texts], made one per passage by [fill], and cached; else null.
  Future<List<List<double>>?> _load(
    String key,
    List<String> texts, {
    bool embed = true,
    List<List<double>> Function(List<List<double>>)? fill,
  }) async {
    final n = package.passages.length;
    final shipped = package.vectors[key];
    if (shipped != null && shipped.length == n) return shipped;
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/packages',
    );
    await dir.create(recursive: true);
    final cache = File(
      '${dir.path}/${package.id}-${package.version}-$key.vectors.json',
    );
    if (await cache.exists()) {
      // A cache: one that cannot be read is made again.
      try {
        final data = jsonDecode(await cache.readAsString()) as List;
        if (data.length == n) {
          return [for (final v in data) List<double>.from(v as List)];
        }
      } on Object catch (e) {
        debugPrint('vectors cache not read, made again: $e');
      }
    }
    if (!embed) return null;
    final embedded = await embedder.documents(texts);
    final vectors = fill == null ? embedded : fill(embedded);
    await cache.writeAsString(jsonEncode(vectors));
    return vectors;
  }

  /// Vectors given directly, for tests: [main] one per passage, [byLang]
  /// with null where a passage has no text in that language.
  @visibleForTesting
  void useVectors(
    List<List<double>> main, [
    Map<String, List<List<double>?>> byLang = const {},
  ]) {
    _vectors = main;
    _textVectors = byLang;
  }

  static String _docText(Passage p, String? lang) {
    final heading = lang == null ? p.heading : p.headingIn(lang);
    final text = lang == null ? p.text : p.textIn(lang);
    return [p.source.title, if (heading.isNotEmpty) heading, text].join('\n');
  }

  /// All passages ranked, before the cut-off (used by the eval logs).
  /// [RankedHit.cosine] is the similarity the cut-off is applied to: the
  /// better of the comparison in the question's language and the one across
  /// languages plus [crossLanguage].
  ///
  /// [lang] is the question's language ('ja', 'en'; default: Japanese when
  /// the question has Japanese script). [original] is the question as
  /// asked when [query] is a translation of it: each passage then keeps the
  /// better of both similarities, so a bad translation cannot hide the
  /// right passages (the phone model once translated "avalanche" as
  /// 「あらわせ」). The search model is multilingual, so the original works
  /// as it is.
  Future<List<RankedHit>> rankAll(
    String query, {
    String? original,
    String? lang,
  }) async {
    final q = await embedder.query(query);
    final o = original == null || original == query
        ? null
        : await embedder.query(original);
    double sim(List<double> v) =>
        o == null ? _dot(q, v) : max(_dot(q, v), _dot(o, v));
    final asked = lang ?? (_japanese.hasMatch(query) ? _mainLang : 'en');
    final own = asked == _mainLang ? null : _textVectors[asked];
    final n = package.passages.length;
    final cos = [
      for (var i = 0; i < n; i++)
        if (asked == _mainLang)
          sim(_vectors[i])
        else
          max(
            sim(_vectors[i]) + crossLanguage,
            own?[i] == null ? double.negativeInfinity : sim(own![i]!),
          ),
    ];
    // Keyword search is for Japanese text only: Latin letters in English
    // questions matched link lists and captions in spike 3.
    final kw = <int, double>{
      if (_japanese.hasMatch(query))
        for (final h in keywords.search(query, limit: n, minScore: 0))
          h.passage.id: h.score,
    };
    final byCos = List<int>.generate(n, (i) => i)
      ..sort((a, b) => cos[b].compareTo(cos[a]));
    final byKw = List<int>.generate(n, (i) => i)
      ..sort(
        (a, b) => (kw[package.passages[b].id] ?? 0).compareTo(
          kw[package.passages[a].id] ?? 0,
        ),
      );
    final rrf = List<double>.filled(n, 0);
    for (var r = 0; r < n; r++) {
      rrf[byCos[r]] += 1 / (60 + r);
      // Keyword rank counts only where there was a keyword match at all.
      if ((kw[package.passages[byKw[r]].id] ?? 0) > 0) {
        rrf[byKw[r]] += 1 / (60 + r);
      }
    }
    final hits = [
      for (var i = 0; i < n; i++)
        RankedHit(
          package.passages[i],
          rrf[i] * localityBoost(package.passages[i].source.region, userRegion),
          cosine: cos[i],
          keyword: kw[package.passages[i].id] ?? 0,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  /// The passages that pass [minCosine], best first, at most [limit]. When
  /// fewer pass, the rest of their sections fill the free places: a source
  /// section is often split into several passages (prevention, then
  /// symptoms, then treatment), and the first may pass alone. The Japanese
  /// carbon monoxide question of the answer eval found only the prevention
  /// passage (0.704); the treatment ones scored 0.689 and 0.695
  /// (lychnion/lychnion#85).
  Future<List<RankedHit>> search(
    String query, {
    int limit = 4,
    String? original,
    String? lang,
  }) async {
    final ranked = await rankAll(query, original: original, lang: lang);
    final hits = ranked
        .where((h) => h.cosine >= minCosine)
        .take(limit)
        .toList();
    if (hits.isEmpty || hits.length >= limit) return hits;
    final index = {
      for (var i = 0; i < package.passages.length; i++)
        package.passages[i].id: i,
    };
    final taken = {for (final h in hits) h.passage.id};
    final section = <int>{};
    for (final h in hits) {
      for (final step in const [-1, 1]) {
        for (
          var i = index[h.passage.id]! + step;
          i >= 0 &&
              i < package.passages.length &&
              _sameSection(package.passages[i], h.passage);
          i += step
        ) {
          section.add(package.passages[i].id);
        }
      }
    }
    section.removeAll(taken);
    // Best first, as ranked.
    return [
      ...hits,
      ...ranked
          .where((h) => section.contains(h.passage.id))
          .take(limit - hits.length),
    ];
  }

  /// One section of a source: consecutive passages under the same heading.
  static bool _sameSection(Passage a, Passage b) =>
      a.source.id == b.source.id &&
      a.heading.isNotEmpty &&
      a.heading == b.heading;

  static double _dot(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < min(a.length, b.length); i++) {
      s += a[i] * b[i];
    }
    return s; // vectors are L2-normalised by the engine
  }
}
