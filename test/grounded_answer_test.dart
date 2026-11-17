import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
