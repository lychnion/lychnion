import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
class HybridRetriever {
  HybridRetriever(this.package, this.embedder, {this.minCosine = 0.0})
    : keywords = Retriever(package);

  final KnowledgePackage package;
  final LocalEmbedder embedder;
  final Retriever keywords;
  double minCosine;

  /// Where the user is (ISO 3166); more local sources get a small nudge.
  String userRegion = 'JP';
  late List<List<double>> _vectors;

  /// Uses the vectors shipped in the package if they match the embedding
  /// model; otherwise embeds all passages once and caches them on disk.
  Future<void> index() async {
    final shipped = package.vectors[embedder.modelName];
    if (shipped != null && shipped.length == package.passages.length) {
      _vectors = shipped;
      return;
    }
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/packages',
    );
    await dir.create(recursive: true);
    final cache = File(
      '${dir.path}/${package.id}-${package.version}-${embedder.modelName}.vectors.json',
    );
    if (await cache.exists()) {
      final data = jsonDecode(await cache.readAsString()) as List;
      if (data.length == package.passages.length) {
        _vectors = [for (final v in data) List<double>.from(v as List)];
        return;
      }
    }
    _vectors = await embedder.documents([
      for (final p in package.passages) _docText(p),
    ]);
    await cache.writeAsString(jsonEncode(_vectors));
  }

  static String _docText(Passage p) =>
      [p.source.title, if (p.heading.isNotEmpty) p.heading, p.text].join('\n');

  /// All passages ranked, before the cut-off (used by the eval logs).
  ///
  /// [original] is the question as asked when [query] is a translation of
  /// it: each passage then keeps the better of both similarities, so a bad
  /// translation cannot hide the right passages (the phone model once
  /// translated "avalanche" as 「あらわせ」). The search model is
  /// multilingual, so the original works as it is.
  Future<List<RankedHit>> rankAll(String query, {String? original}) async {
    final q = await embedder.query(query);
    final o = original == null || original == query
        ? null
        : await embedder.query(original);
    final n = package.passages.length;
    final cos = [
      for (final v in _vectors)
        o == null ? _dot(q, v) : max(_dot(q, v), _dot(o, v)),
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

  Future<List<RankedHit>> search(
    String query, {
    int limit = 4,
    String? original,
  }) async {
    // Across languages (an English question, Japanese passages) the same
    // match scores about 0.02 lower: "What should I pack for a day hike?"
    // 0.69 in English, 0.71 as its Japanese translation (test questions,
    // 2026-11-18).
    final cut = _japanese.hasMatch(query) ? minCosine : minCosine - 0.02;
    return (await rankAll(
      query,
      original: original,
    )).where((h) => h.cosine >= cut).take(limit).toList();
  }

  static double _dot(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < min(a.length, b.length); i++) {
      s += a[i] * b[i];
    }
    return s; // vectors are L2-normalised by the engine
  }
}
