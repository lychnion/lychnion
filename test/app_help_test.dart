import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/app_help.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';

import 'support/fake_llm.dart';

void main() {
  // Built by tool/build_help.py from help/.
  final help = KnowledgePackage.open('assets/help/app.help.sqlite');
  final safety = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');

  test('the help package has every topic in Japanese and English', () {
    expect(help.id, 'app.help');
    expect(help.sources, hasLength(9));
    expect(help.passages.length, greaterThan(30));
    for (final p in help.passages) {
      expect(p.textIn('en'), isNot(p.textIn('ja')), reason: p.heading);
      expect(p.source.publisher, 'Lychnion');
    }
  });

  test('questions about the app, and not about hazards', () {
    for (final q in [
      '近くの人に共有するには？',
      'ベースにつなぐには？',
      'ダウンロードが止まった',
      '質問の履歴はどこ？',
      'How do I share maps with another phone?',
      'Does the app send my position anywhere?',
      'How do I add a publisher?',
    ]) {
      expect(isAppQuestion(q), isTrue, reason: q);
    }
    for (final q in [
      '海の近くで強い揺れを感じたら？',
      'けがをして出血しているときは？',
      '非常用の水はどれくらい必要？',
      'How do I stop bleeding?',
      'What vegetables keep without a fridge?',
      'Should I share food and water with my neighbours?',
      'Is it safe to stay on the table during an earthquake?',
    ]) {
      expect(isAppQuestion(q), isFalse, reason: q);
    }
  });

  test('an app question is answered from the help only', () async {
    final llm = FakeLlm();
    final answerer = GroundedAnswerer(llm, safety, help: help);
    final a = GroundedAnswer('近くの人に共有するには？', lang: 'ja');
    await answerer.answer(a, () {});
    expect(a.hits, isNotEmpty);
    expect(
      a.hits.every((h) => h.passage.source.publisher == 'Lychnion'),
      isTrue,
    );
    expect(a.alerts, isEmpty);
    expect(llm.prompt, contains('近くの人に共有'));
  });

  // lychnion/lychnion#77: an app word in a hazard question does not skip
  // the safety line.
  test('a hazard question with an app word keeps its safety line', () async {
    for (final q in [
      // Each also finds help passages, so before #77 the help answered.
      '地震で津波が来たら、近くの人に共有するには？',
      '海岸で地震、ベースにつなぐには？',
      'ベースキャンプが海の近くで、強い揺れを感じたら？',
      // On purpose: an app question that also names a hazard gets the
      // safety line and the guides, not the help.
      '地震と津波のガイドをダウンロードするには？',
      'Strong shaking at the coast: how do I share offline?',
    ]) {
      expect(isAppQuestion(q), isTrue, reason: q);
      final llm = FakeLlm();
      final answerer = GroundedAnswerer(llm, safety, help: help);
      final a = GroundedAnswer(q, lang: q.contains('shaking') ? 'en' : 'ja');
      await answerer.answer(a, () {});
      expect(a.alerts, isNotEmpty, reason: q);
      expect(
        a.hits.any((h) => h.passage.source.publisher == 'Lychnion'),
        isFalse,
        reason: q,
      );
    }
  });

  test('a safety question never sees help passages', () async {
    final llm = FakeLlm();
    final answerer = GroundedAnswerer(llm, safety, help: help);
    final a = GroundedAnswer('海の近くで強い揺れを感じたら？', lang: 'ja');
    await answerer.answer(a, () {});
    expect(a.hits, isNotEmpty);
    expect(
      a.hits.any((h) => h.passage.source.publisher == 'Lychnion'),
      isFalse,
    );
  });
}
