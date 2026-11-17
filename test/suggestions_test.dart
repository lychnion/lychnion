import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/ui/suggestions.dart';

void main() {
  const both = ['jp.bousai.core', 'jp.outdoor.hiking'];

  test('takes turns between packages, core first, five at most', () {
    final ja = [for (final (_, q) in suggestionsFor(both, en: false)) q];
    expect(ja, [
      '海の近くで強い揺れを感じたら？',
      '山で雷が鳴ってきたら？',
      'けがをして出血しているときは？',
      'マダニに刺されたら？',
      '非常用の水はどれくらい必要？',
    ]);
    expect(suggestionsFor(both, en: true).first.$2, startsWith('Strong'));
  });

  test('core questions when no known package is loaded', () {
    expect(suggestionsFor(const [], en: false).length, 4);
    expect(suggestionsFor(const ['x.unknown'], en: false).length, 4);
  });

  test('every Japanese suggestion finds a passage', () {
    final r = Retriever(
      KnowledgePackage.merge([
        KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite'),
        KnowledgePackage.open('assets/packages/jp.outdoor.hiking.sqlite'),
      ]),
    );
    for (final (_, q) in suggestionsFor(both, en: false, max: 99)) {
      expect(r.search(q), isNotEmpty, reason: q);
    }
  });
}
