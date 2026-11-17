import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/knowledge/subjects.dart';

void main() {
  final r = Retriever(
    KnowledgePackage.merge([
      KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite'),
      KnowledgePackage.open('assets/packages/jp.outdoor.hiking.sqlite'),
    ]),
  );
  List<String> kept(String q, [String? ja]) => [
    for (final h in sameAnimal([q, ?ja], r.search(ja ?? q, minScore: 0)))
      h.passage.source.id,
  ];

  test('animals are recognised, also in English', () {
    expect(animalsIn('ヘビにかまれたら？'), {'snake'});
    expect(animalsIn('How do I treat a snake bite?'), {'snake'});
    expect(animalsIn('マダニに刺されたら？'), {'tick'});
    expect(animalsIn('A wasp stung me'), {'bee'});
    expect(animalsIn('いまだに余震がある。くまなく探した。'), isEmpty);
    expect(animalsIn('津波が来たら？'), isEmpty);
  });

  test('a snake bite gets no tick advice', () {
    // The search finds the tick page (咬 in ダニ刺咬) ...
    expect(r.search('ヘビにかまれたらどうする？', minScore: 0), isNotEmpty);
    // ... but nothing about snakes is left, so the answer is "no source".
    expect(kept('ヘビにかまれたらどうする？'), isEmpty);
    expect(kept('How do I treat a snake bite?', 'ヘビにかまれた場合の治療法は？'), isEmpty);
  });

  test('passages about the asked animal stay', () {
    expect(kept('マダニに刺されたら？'), isNotEmpty);
    expect(
      kept('マダニに刺されたら？'),
      everyElement(isIn(['mhlw-sfts-qa', 'rinya-dani'])),
    );
    expect(kept('山でクマに出会ったら？'), contains('gov-online-kuma'));
    expect(kept('スズメバチに刺されないためには？'), contains('rinya-hachi'));
  });

  test('questions about no animal keep everything', () {
    final all = r.search('津波が来たらどこへ逃げる？');
    expect(sameAnimal(['津波が来たらどこへ逃げる？'], all), all);
  });
}
