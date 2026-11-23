import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/base/base_web.dart';

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

  // lychnion/lychnion#116: the page is not signed, so it shows no facts
  // and says that it is not checked.
  test('the page data has no facts and says the page is not checked', () {
    for (final lang in ['ja', 'en']) {
      final info = webInfo(lang: lang, name: 'Test');
      expect(info.containsKey('facts'), isFalse);
      final texts = info['texts'] as Map;
      expect(texts.containsKey('factsTitle'), isFalse);
      expect(texts['pageUnchecked'], isNotEmpty);
    }
    expect(
      (webInfo(lang: 'en', name: 'Test')['texts'] as Map)['pageUnchecked'],
      contains('not checked'),
    );
  });

  test('the page shows the notice and no facts box', () {
    final page = File('assets/web/base.html').readAsStringSync();
    expect(page, contains('T.pageUnchecked'));
    expect(page, isNot(contains('d.facts')));
  });
}
