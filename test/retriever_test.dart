import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/spike/bench_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  final retriever = Retriever(pkg);

  List<String> topSources(String q) => [
    for (final h in retriever.search(q)) h.passage.source.id,
  ];

  test('finds the right source for questions the package covers', () {
    expect(topSources(benchPrompts[0]), contains('kantei-jishin'));
    expect(topSources(benchPrompts[1]).first, 'kantei-tsunami');
    expect(topSources(benchPrompts[2]), contains('kantei-sonae'));
    // The bear source is disabled (OCR mixed its columns).
    expect(topSources(benchPrompts[5]), isNot(contains('env-kuma')));
    expect(topSources(benchPrompts[6]).first, 'kantei-setsugai');
    expect(topSources(benchPrompts[7]), contains('fdma-shiketsu'));
  });

  test('tsunami safety line fires only near the sea', () {
    final tsunami = pkg.alerts.singleWhere((a) => a.id == 'tsunami-go-high');
    expect(tsunami.matches(benchPrompts[1]), isTrue);
    expect(tsunami.matches(benchPrompts[0]), isFalse);
    expect(tsunami.matches('山でクマに出会いました'), isFalse);
  });

  test('bear and lost-in-the-mountains safety lines', () {
    Alert byId(String id) => pkg.alerts.singleWhere((a) => a.id == id);
    final bear = byId('bear-move-slowly'), lost = byId('lost-go-back');
    expect(bear.matches('山でクマに出会ってしまいました。'), isTrue);
    expect(bear.matches('I saw a bear on the trail.'), isTrue);
    expect(bear.matches('クマに会わないために山菜採りで気をつけることは？'), isFalse);
    expect(lost.matches('登山中に道に迷いました。'), isTrue);
    expect(lost.matches('I got lost while hiking.'), isTrue);
    expect(lost.matches('避難所への道に迷いました。'), isFalse);
  });
}
