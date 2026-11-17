import 'retriever.dart';

/// Animals whose advice must never be swapped: tick advice is wrong for a
/// snake bite, bear advice wrong for a boar. Found in the test questions:
/// "How do I treat a snake bite?" got the 林野庁 tick page (it shares 咬 with
/// ダニ刺咬) and the model rewrote it as snake advice.
// Hiragana only where it cannot hide in ordinary words (いまだに, くまなく).
const _animals = <String, (List<String> ja, List<String> en)>{
  'snake': (
    ['ヘビ', '蛇', 'へび', 'マムシ', 'まむし', 'ハブ', 'ヤマカガシ'],
    ['snake', 'viper', 'adder'],
  ),
  'tick': (['ダニ'], ['tick']),
  'bee': (['ハチ', '蜂'], ['bee', 'wasp', 'hornet']),
  'bear': (['クマ', '熊'], ['bear']),
  'boar': (['イノシシ', '猪'], ['boar']),
  'jellyfish': (['クラゲ', 'くらげ'], ['jellyfish']),
};

bool _mentions(String text, (List<String>, List<String>) terms) {
  final lower = text.toLowerCase();
  return terms.$1.any(text.contains) ||
      terms.$2.any(
        (w) => RegExp('\\b${RegExp.escape(w)}s?\\b').hasMatch(lower),
      );
}

/// The animals a text talks about.
Set<String> animalsIn(String text) => {
  for (final e in _animals.entries)
    if (_mentions(text, e.value)) e.key,
};

/// Keeps only passages about an animal the question names. A question
/// about no animal keeps every passage. When none is left, the app answers
/// "no answer in the sources" instead of letting the model borrow advice
/// for another animal.
List<H> sameAnimal<H extends Hit>(List<String> questionTexts, List<H> hits) {
  final asked = {for (final q in questionTexts) ...animalsIn(q)};
  if (asked.isEmpty) return hits;
  return [
    for (final h in hits)
      if (animalsIn(
        '${h.passage.source.title} ${h.passage.heading} ${h.passage.text}',
      ).intersection(asked).isNotEmpty)
        h,
  ];
}
