import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/ui/answer_text.dart';

void main() {
  final src = Source('kantei-tsunami', '津波', '首相官邸', '', 'PDL1.0', '');
  final tsunami = Alert(
    'tsunami-go-high',
    src,
    '強い揺れや弱くても長い揺れを感じたら、また地震を体で感じなくても、「津波警報」等を見聞きしたら、'
        'いち早く海岸から離れ、可能な限り高い場所へ避難してください。'
        '震源が陸地に近いと津波警報・注意報が津波の襲来に間に合わないことがあります。',
    const [],
    'If you feel strong shaking, or weak but long shaking, or if you hear a '
        'tsunami warning even without feeling an earthquake, leave the coast at '
        'once and evacuate to the highest place you can. If the epicentre is '
        'close to land, tsunami warnings may come too late.',
    const [],
  );

  test('citation markers are removed', () {
    expect(shownAnswer('高い場所へ [1]。水を持つ [2][3]。', []), '高い場所へ。水を持つ。');
  });

  test('a sentence that repeats the safety line is dropped (English)', () {
    const answer =
        'If you feel strong shaking or a long tremor, or if you hear a tsunami '
        'warning, evacuate from the coast as quickly as possible and move to the '
        'highest possible place [1]. If you are near the coast due to swimming, '
        'evacuation is also necessary even with a tsunami advisory; start moving '
        'away from the sea immediately [1].';
    final shown = shownAnswer(answer, [tsunami]);
    expect(shown, isNot(contains('strong shaking')));
    expect(shown, startsWith('If you are near the coast due to swimming'));
  });

  test('a sentence that repeats the safety line is dropped (Japanese)', () {
    const answer =
        '強い揺れや長い揺れを感じたら、いち早く海岸から離れ、できるだけ高い場所へ避難してください [1]。'
        '海水浴中は、津波注意報でも避難が必要です [1]。';
    expect(shownAnswer(answer, [tsunami]), '海水浴中は、津波注意報でも避難が必要です。');
  });

  test('new information is kept', () {
    const answer = '避難するときは、近くの高台や津波避難タワーを目指します [2]。';
    expect(shownAnswer(answer, [tsunami]), '避難するときは、近くの高台や津波避難タワーを目指します。');
  });

  test('an answer that only repeats the safety line shows nothing extra', () {
    const answer = '強い揺れや弱くても長い揺れを感じたら、いち早く海岸から離れ、可能な限り高い場所へ避難してください [1]。';
    expect(shownAnswer(answer, [tsunami]), isEmpty);
  });
}
