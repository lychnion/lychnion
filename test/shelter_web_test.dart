import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/shelter/shelter_web.dart';

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');

  test('an answer for the page: no citation marks, sources once', () {
    final tsunami = pkg.alerts.singleWhere((a) => a.id == 'tsunami-go-high');
    final a = GroundedAnswer('海の近くで強い揺れを感じました。')
      ..alerts = [tsunami]
      ..hits = [Hit(pkg.passages[40], 1), Hit(pkg.passages[41], 1)]
      ..text = '高台へ避難します [1]。津波は何度も来ます [1, 2]。';
    final w = webAnswer(a);
    expect(w['shown'], '高台へ避難します。津波は何度も来ます。');
    expect(w['grounded'], isTrue);
    expect(w['alerts'], [tsunami.text]);
    final ids = (w['sources'] as List).map((s) => (s as Map)['publisher']);
    expect(ids.toSet().length, ids.length);
    expect((w['texts'] as Map)['sources'], '出典');
  });

  test('English questions get the English safety line', () {
    final tsunami = pkg.alerts.singleWhere((a) => a.id == 'tsunami-go-high');
    final a = GroundedAnswer('Strong shaking near the sea?')
      ..alerts = [tsunami]
      ..text = 'No answer in the sources.';
    final w = webAnswer(a);
    expect(w['alerts'], [tsunami.textIn('en')]);
    expect(w['no_source'], isTrue);
    expect((w['texts'] as Map)['sources'], 'Sources');
  });

  test('facts on the page name shelters, not their IDs', () {
    final now = DateTime(2026, 11, 18, 15);
    Fact f(FactKind kind, String subject, String value) => Fact(
      kind: kind,
      subject: subject,
      value: value,
      observedAt: now.subtract(const Duration(minutes: 20)),
      expiresAt: now.add(const Duration(hours: 2)),
      sourceType: SourceType.official,
      sourceName: '西宮市',
    );
    final info = webInfo(
      lang: 'ja',
      name: 'Test',
      now: now,
      placeName: (id) => id == 'E1' ? '市役所' : null,
      facts: [
        f(FactKind.shelterStatus, 'E1', 'full'),
        f(FactKind.roadBlocked, '34.73,135.34', ''),
        f(FactKind.warning, '西宮市', '津波警報'),
      ],
    );
    final facts = (info['facts'] as List).cast<Map>();
    expect(facts[0]['subject'], '市役所');
    expect(facts[0]['avoid'], isTrue);
    expect(facts[1]['subject'], isNull);
    expect(facts[2]['subject'], '西宮市');
    expect(facts[2]['avoid'], isTrue);
  });
}
