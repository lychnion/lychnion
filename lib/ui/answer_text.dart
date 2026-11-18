import '../knowledge/grounded_answer.dart' show GroundedAnswer;
import '../knowledge/knowledge_package.dart' show Alert;

/// The answer as shown: citation markers removed (sources are listed once,
/// under the answer) and sentences dropped that only repeat a safety line
/// already shown above it. The full text stays in the answer for the
/// citation check and the logs.
String shownAnswer(String text, List<Alert> alerts) {
  final clean = text
      .replaceAll(RegExp('\\s?${GroundedAnswer.citation.pattern}'), '')
      .trim();
  if (alerts.isEmpty) return clean;
  final lines = [
    for (final a in alerts) ...[
      _grams(a.text),
      for (final t in a.translations.values) _grams(t),
    ],
  ];
  final kept = [
    for (final s in _sentences(clean))
      if (!lines.any((l) => _covered(_grams(s), l))) s,
  ];
  return kept.join().trim();
}

/// Sentences with their end mark, so joining them gives the text back.
List<String> _sentences(String text) => [
  for (final m in RegExp(r'[^。！？!?.]+[。！？!?.]*\s*').allMatches(text))
    m.group(0)!,
];

/// Most of the sentence's units appear in the safety line.
bool _covered(Set<String> sentence, Set<String> line) {
  if (sentence.length < 4) return false;
  final shared = sentence.where(line.contains).length;
  return shared / sentence.length >= 0.6;
}

final _japanese = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');

/// Units to compare: pairs of letters for Japanese (no spaces), words of
/// three letters or more for English (letter pairs are too common there).
Set<String> _grams(String s) {
  final lower = s.toLowerCase();
  if (!_japanese.hasMatch(lower)) {
    return {
      for (final m in RegExp(r'[a-z]{3,}').allMatches(lower)) m.group(0)!,
    };
  }
  final t = lower.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
  return {for (var i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)};
}
