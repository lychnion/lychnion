import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';

void main() {
  final core = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');

  test('one package merges to itself', () {
    expect(KnowledgePackage.merge([core]), same(core));
    expect(core.parts.single.id, 'jp.bousai.core');
  });

  test('merged packages are searched together with unique passage ids', () {
    final both = KnowledgePackage.merge([core, core]);
    expect(both.passages.length, core.passages.length * 2);
    expect(both.passages.map((p) => p.id).toSet().length, both.passages.length);
    expect(both.alerts.length, core.alerts.length * 2);
    expect(
      [for (final p in both.parts) p.id],
      ['jp.bousai.core', 'jp.bousai.core'],
    );
    expect(both.id, 'jp.bousai.core+jp.bousai.core');
    // Synonyms are merged without repeats.
    expect(both.synonyms['クマ'], core.synonyms['クマ']);
    // Shipped vectors stay usable: one per passage, in passage order.
    for (final e in core.vectors.entries) {
      expect(both.vectors[e.key]!.length, both.passages.length);
    }
    final hits = Retriever(both).search('津波が来たらどこへ逃げる？');
    expect(hits, isNotEmpty);
  });

  group('hiking with the core package', () {
    final hiking = KnowledgePackage.open(
      'assets/packages/jp.outdoor.hiking.sqlite',
    );
    final both = KnowledgePackage.merge([core, hiking]);
    final r = Retriever(both);
    List<String> top(String q) => [
      for (final h in r.search(q)) h.passage.source.id,
    ];
    List<String> alerts(String q) => [
      for (final a in both.alerts)
        if (a.matches(q)) a.id,
    ];

    test('finds the hiking sources', () {
      expect(top('山で道に迷ったかもしれない。どうすればいい？'), contains('npa-sounan-gaikyou-r07'));
      expect(top('登山届は出したほうがいい？'), contains('npa-sounan-gaikyou-r07'));
      expect(top('山で雷が鳴ってきたらどうする？').first, startsWith('jma-'));
      expect(
        top('マダニに刺されたらどうすればいい？'),
        anyOf(contains('mhlw-sfts-qa'), contains('rinya-dani')),
      );
      expect(top('スズメバチに刺されないためには？'), contains('rinya-hachi'));
      expect(top('噴火速報が出たらどうする？').first, 'jma-funka-sokuho');
      expect(top('熱中症を防ぐには？'), contains('wbgt-heatillness'));
    });

    test('core questions still find the core sources', () {
      expect(top('津波が来たらどこへ逃げる？').first, 'kantei-tsunami');
      expect(top('けがをして出血しているときは？'), contains('fdma-shiketsu'));
    });

    test('hiking safety lines fire on the right questions', () {
      expect(alerts('山で道に迷った'), contains('lost-go-back'));
      expect(
        alerts('I think I am lost on the trail'),
        contains('lost-go-back'),
      );
      expect(
        alerts('雷が鳴ってきた'),
        containsAll(['thunder-already-danger', 'storm-shelter-now']),
      );
      expect(
        alerts('Thunder in the distance, what now?'),
        contains('thunder-already-danger'),
      );
      expect(alerts('非常用の水はどれくらい必要？'), isEmpty);
      expect(alerts('道に迷ったら交番へ'), isNot(contains('lost-go-back')));
    });
  });

  test('vectors are dropped when one package lacks them', () {
    if (core.vectors.isEmpty) return;
    final bare = KnowledgePackage.merge([core, _withoutVectors(core)]);
    expect(bare.vectors, isEmpty);
  });
}

/// A merged copy of the package with its shipped vectors removed.
KnowledgePackage _withoutVectors(KnowledgePackage p) {
  final copy = KnowledgePackage.merge([p, p]);
  copy.vectors.clear();
  return copy;
}
