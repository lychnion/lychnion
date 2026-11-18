import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_llm.dart';

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  final passage = pkg.passages.first;

  GroundedAnswer answer(String q, String text) => GroundedAnswer(q)
    ..hits = [Hit(passage, 1)]
    ..text = text;

  test('detects answers that admit a gap', () {
    expect(
      answer('クマ', '具体的な対処方法についての記述は資料にありませんが、[2]。').admitsGap,
      isFalse,
      reason: '[2] does not exist, so the answer is not grounded',
    );
    expect(answer('クマ', '具体的な対処方法についての記述は資料にありません [1]。').admitsGap, isTrue);
    expect(
      answer('登山', 'スマホの電波がない場合の具体的な対処法についての記載はありません [1]。').admitsGap,
      isTrue,
    );
    expect(
      answer('bear', 'The sources do not mention what to do [1].').admitsGap,
      isTrue,
    );
    expect(answer('避難所', '具体的なリストは記載されていません [1]。').admitsGap, isTrue);
    expect(answer('地震', '丈夫な机の下などに隠れる [1]。').admitsGap, isFalse);
  });

  test('language of the question', () {
    expect(questionLanguage('津波は一回だけですか？'), 'ja');
    expect(questionLanguage('Is a tsunami only one wave?'), 'en');
  });

  group('GroundedAnswerer when the sources do not answer', () {
    test('nothing found: the model is not asked to guess', () async {
      final llm = FakeLlm();
      final a = GroundedAnswer('ピアノの調律', lang: 'ja');
      await GroundedAnswerer(llm, pkg).answer(a, () {});
      expect(a.hits, isEmpty);
      expect(a.text, AnswerTexts.of('ja').noSource);
      expect(a.isGrounded, isFalse);
      expect(llm.prompts, isEmpty);
    });

    test(
      'related but no answer: shown as no answer, nothing generated',
      () async {
        final llm = FakeLlm(['いいえ']);
        final a = GroundedAnswer('津波は一回だけですか？', lang: 'ja');
        await GroundedAnswerer(llm, pkg, checkRelevance: true).answer(a, () {});
        expect(a.hits, isNotEmpty);
        expect(a.relatedOnly, isTrue);
        expect(a.text, AnswerTexts.of('ja').noSource);
        expect(llm.prompts, hasLength(1), reason: 'only the yes/no check');
      },
    );

    test('the relevance check says yes: the answer is written', () async {
      final llm = FakeLlm(['はい', '津波は何度も来ます [1]。']);
      final a = GroundedAnswer('津波は一回だけですか？', lang: 'ja');
      await GroundedAnswerer(llm, pkg, checkRelevance: true).answer(a, () {});
      expect(a.judgedRelevant, isTrue);
      expect(a.text, '津波は何度も来ます [1]。');
      expect(a.isGrounded, isTrue);
      expect(llm.prompts, hasLength(2));
    });

    test('English without a search model: searched in Japanese', () async {
      final llm = FakeLlm(['津波は一回だけですか？', 'Tsunamis come again [1].']);
      final a = GroundedAnswer('Is a tsunami only one wave?');
      await GroundedAnswerer(llm, pkg).answer(a, () {});
      expect(a.lang, 'en');
      expect(a.searchQuery, '津波は一回だけですか？');
      expect(a.hits, isNotEmpty);
      expect(a.text, 'Tsunamis come again [1].');
    });

    test('an empty translation: the question is searched as it is', () async {
      final llm = FakeLlm(['  ']);
      final a = GroundedAnswer('Is a tsunami only one wave?');
      await GroundedAnswerer(llm, pkg).answer(a, () {});
      expect(a.searchQuery, isNull);
      expect(a.hits, isEmpty);
      expect(a.text, AnswerTexts.of('en').noSource);
      expect(llm.prompts, hasLength(1), reason: 'only the translation');
    });
  });
}
