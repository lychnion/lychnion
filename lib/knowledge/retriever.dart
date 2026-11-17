import 'dart:math';

import 'knowledge_package.dart';

class Hit {
  Hit(this.passage, this.score);
  final Passage passage;
  final double score;
}

/// Keyword search over character bigrams (BM25).
///
/// Japanese has no spaces, so bigrams stand in for words. Good enough for a
/// small package; vector search can be added later for paraphrases.
class Retriever {
  Retriever(this.package) {
    for (final p in package.passages) {
      final grams = _bigrams('${p.heading} ${p.heading} ${p.text}');
      _docs.add(grams);
      for (final g in grams.keys) {
        _df[g] = (_df[g] ?? 0) + 1;
      }
    }
    _avgLen =
        _docs.fold<int>(0, (s, d) => s + d.values.fold(0, (a, b) => a + b)) /
        _docs.length;
  }

  final KnowledgePackage package;

  /// Where the user is (ISO 3166); more local sources get a small nudge.
  String userRegion = 'JP';
  final _docs = <Map<String, int>>[];
  final _df = <String, int>{};
  late final double _avgLen;

  static const _k1 = 1.2, _b = 0.75;

  List<Hit> search(String query, {int limit = 4, double minScore = 8}) {
    final expanded = StringBuffer(query);
    package.synonyms.forEach((word, alts) {
      if (query.contains(word)) expanded.write(' ${alts.join(' ')}');
    });
    final q = _bigrams(expanded.toString()).keys.toSet();
    final n = _docs.length;
    final hits = <Hit>[];
    for (var i = 0; i < n; i++) {
      final doc = _docs[i];
      final len = doc.values.fold(0, (a, b) => a + b);
      var score = 0.0;
      for (final g in q) {
        final tf = doc[g];
        if (tf == null) continue;
        final df = _df[g]!;
        final idf = log(1 + (n - df + 0.5) / (df + 0.5));
        score +=
            idf * tf * (_k1 + 1) / (tf + _k1 * (1 - _b + _b * len / _avgLen));
      }
      if (score < minScore) continue;
      final p = package.passages[i];
      hits.add(Hit(p, score * localityBoost(p.source.region, userRegion)));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  // Kana, kanji and latin letters/digits; punctuation and particles-only grams are dropped.
  static final _word = RegExp(r'[ぁ-ヿ一-鿿ー0-9A-Za-zＡ-Ｚａ-ｚ０-９]+');
  static final _hiraganaOnly = RegExp(r'^[ぁ-ゟ]+$');

  static Map<String, int> _bigrams(String text) {
    final counts = <String, int>{};
    for (final m in _word.allMatches(text)) {
      final run = m.group(0)!;
      for (var i = 0; i + 1 < run.length; i++) {
        final g = run.substring(i, i + 2);
        // です, ます, して ... carry no meaning.
        if (_hiraganaOnly.hasMatch(g)) continue;
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    return counts;
  }
}
