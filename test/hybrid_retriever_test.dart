import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/hybrid_retriever.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/llm/local_embedder.dart';

/// Returns a fixed query vector for every question.
class _FakeEmbedder implements LocalEmbedder {
  _FakeEmbedder(this.queryVector);
  final List<double> queryVector;

  @override
  String modelName = 'fake.gguf';

  @override
  Future<List<double>> query(String text) async => queryVector;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A unit vector with [c] as its similarity to (1, 0).
List<double> _at(double c) => [c, sqrt(1 - c * c)];

void main() {
  // lychnion/lychnion#85: English questions are compared with the English
  // text where the package has one.
  group('English text', () {
    final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
    final water = pkg.passages.indexWhere(
      (p) => p.source.id == 'kantei-sonae' && p.heading == '備蓄しておきたいもの',
    );

    HybridRetriever retriever({required bool english}) {
      final r = HybridRetriever(pkg, _FakeEmbedder([1, 0]), minCosine: 0.70);
      r.useVectors(
        [
          for (var i = 0; i < pkg.passages.length; i++)
            i == water ? _at(0.674) : _at(0),
        ],
        {
          if (english)
            'en': [
              for (var i = 0; i < pkg.passages.length; i++)
                i == water ? _at(0.724) : null,
            ],
        },
      );
      return r;
    }

    test('an English question finds the passage by its English text', () async {
      expect(pkg.passages[water].texts.containsKey('en'), isTrue);
      final hits = await retriever(english: true)
          .search('How much water for three days?', lang: 'en');
      expect([for (final h in hits) h.passage.id], [pkg.passages[water].id]);
      expect(hits.single.cosine, closeTo(0.724, 0.001));
    });

    test('across languages it needs 0.68, as before', () async {
      final hits = await retriever(english: false)
          .search('How much water for three days?', lang: 'en');
      expect(hits, isEmpty); // 0.674 + 0.02 < 0.70
    });

    test('a Japanese question reads only the Japanese text', () async {
      final hits = await retriever(english: true)
          .search('飲み水は3日分でどれくらい？', lang: 'ja');
      expect(hits, isEmpty);
    });

    test(
      'across languages 0.68 still passes, and counts when better',
      () async {
        final r = HybridRetriever(pkg, _FakeEmbedder([1, 0]), minCosine: 0.70)
          ..useVectors(
            [
              for (var i = 0; i < pkg.passages.length; i++)
                i == water ? _at(0.682) : _at(0),
            ],
            {
              'en': [
                for (var i = 0; i < pkg.passages.length; i++)
                  i == water ? _at(0.60) : null,
              ],
            },
          );
        final hits = await r.search('How much water?', lang: 'en');
        expect([for (final h in hits) h.passage.id], [pkg.passages[water].id]);
        expect(hits.single.cosine, closeTo(0.702, 0.001));
      },
    );
  });

  // The vectors come from the package (lychnion-data/tool/add_vectors.py):
  // `<model>` for the main texts, `<model>@en` for the English texts.
  group('shipped vectors', () {
    List<List<double>> all(KnowledgePackage p, List<double> v) => [
      for (final _ in p.passages) v,
    ];

    test('index() uses the English vectors a package ships', () async {
      final pkg = KnowledgePackage.open(
        'assets/packages/jp.bousai.core.sqlite',
      );
      final water = pkg.passages.indexWhere(
        (p) => p.source.id == 'kantei-sonae' && p.heading == '備蓄しておきたいもの',
      );
      pkg.vectors['fake.gguf'] = [
        for (var i = 0; i < pkg.passages.length; i++)
          i == water ? _at(0.674) : _at(0),
      ];
      pkg.vectors['fake.gguf@en'] = [
        for (var i = 0; i < pkg.passages.length; i++)
          i == water ? _at(0.724) : _at(0),
      ];
      final r = HybridRetriever(pkg, _FakeEmbedder([1, 0]), minCosine: 0.70);
      await r.index();
      final hits = await r.search('How much water?', lang: 'en');
      expect([for (final h in hits) h.passage.id], [pkg.passages[water].id]);
    });

    test('a merged package keeps them where one package has them', () async {
      final core = KnowledgePackage.open(
        'assets/packages/jp.bousai.core.sqlite',
      );
      final hiking = KnowledgePackage.open(
        'assets/packages/jp.outdoor.hiking.sqlite',
      );
      core.vectors['fake.gguf'] = all(core, _at(0));
      core.vectors['fake.gguf@en'] = all(core, _at(0));
      core.vectors['fake.gguf@en']![0] = _at(0.724);
      hiking.vectors['fake.gguf'] = all(hiking, _at(0));
      // Only the main vector, close to the question across languages.
      hiking.vectors['fake.gguf']![0] = _at(0.682);
      hiking.vectors.remove('fake.gguf@en');
      final merged = KnowledgePackage.merge([core, hiking]);
      final n = merged.passages.length;
      expect(merged.vectors['fake.gguf@en'], hasLength(n));
      expect(merged.vectors['fake.gguf@en']![core.passages.length], isEmpty);
      final r = HybridRetriever(merged, _FakeEmbedder([1, 0]), minCosine: 0.70);
      await r.index();
      final hits = await r.search('Water and hiking?', lang: 'en');
      expect(
        [for (final h in hits) h.passage.id],
        containsAll([
          merged.passages[0].id,
          merged.passages[core.passages.length].id,
        ]),
      );
    });
  });

  // lychnion/lychnion#85: a passing passage brings the rest of its section.
  group('section fill', () {
    final pkg = KnowledgePackage.open(
      'assets/packages/intl.firstaid.basics.sqlite',
    );
    final co = [
      for (var i = 0; i < pkg.passages.length; i++)
        if (pkg.passages[i].heading == '一酸化炭素中毒') i,
    ];
    final first = co.first;
    test('the test section is one run of passages', () {
      expect(co, [for (var i = 0; i < co.length; i++) first + i]);
    });

    HybridRetriever retriever(double best) {
      final r = HybridRetriever(pkg, _FakeEmbedder([1, 0]), minCosine: 0.70);
      r.useVectors([
        for (var i = 0; i < pkg.passages.length; i++)
          i == first + 1
              ? _at(best)
              : co.contains(i)
              ? _at(0.69 - 0.001 * i)
              // The passage before the section scores higher than the
              // section's own passages, but is not part of it.
              : i == first - 1
              ? _at(0.695)
              : _at(0),
      ]);
      return r;
    }

    test('fills free places with the same section only', () async {
      expect(co.length, greaterThanOrEqualTo(3));
      expect(pkg.passages[first - 1].heading, isNot('一酸化炭素中毒'));
      final hits = await retriever(0.704).search('テントで頭痛と吐き気', lang: 'ja');
      expect(hits.first.passage.id, pkg.passages[first + 1].id);
      expect(hits.length, min(4, co.length));
      for (final h in hits) {
        expect(h.passage.heading, '一酸化炭素中毒');
      }
    });

    test('keeps the limit', () async {
      final hits = await retriever(0.704)
          .search('テントで頭痛と吐き気', lang: 'ja', limit: 2);
      expect(hits.length, 2);
    });

    test('adds nothing when no passage passes', () async {
      final hits = await retriever(0.69).search('テントで頭痛と吐き気', lang: 'ja');
      expect(hits, isEmpty);
    });
  });
}
