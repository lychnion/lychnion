import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/ui/answer_text.dart';

void main() {
  final src = Source('s', 't', 'p', '', 'PDL1.0', '');
  GroundedAnswer answer(String text) => GroundedAnswer('q?')
    ..hits = [
      Hit(Passage(1, src, '', 'a'), 1),
      Hit(Passage(2, src, '', 'b'), 1),
    ]
    ..text = text;

  test('all citation forms count', () {
    for (final t in [
      'A [1]. B [2].',
      'A [1][2].',
      'A [1, 2].',
      'A [1,2].',
      'A [1、2]。',
    ]) {
      expect(answer(t).citedNumbers, {1, 2}, reason: t);
      expect(answer(t).isGrounded, isTrue, reason: t);
    }
    expect(answer('A [1, 2].').citedNumbers, {1, 2});
    expect(answer('A [1, 3].').invalidCitations, {3});
  });

  test('citation marks are removed from the shown text', () {
    expect(
      shownAnswer('Wash it [1, 2]. See a doctor [1].', []),
      'Wash it. See a doctor.',
    );
    expect(shownAnswer('洗います [1、2]。', []), '洗います。');
  });
}
