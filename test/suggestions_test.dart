import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/ui/suggestions.dart';

void main() {
  final infos = [
    for (final id in [
      'jp.bousai.core',
      'jp.outdoor.hiking',
      'intl.firstaid.basics',
    ])
      KnowledgePackage.readInfo('assets/packages/$id.sqlite'),
  ];

  test('takes turns between packages, core first, five at most', () {
    final ja = [for (final (_, q) in suggestionsFor(infos, lang: 'ja')) q];
    expect(ja, [
      '海の近くで強い揺れを感じたら？',
      '山で雷が鳴ってきたら？',
      'けがをして出血しているときは？',
      'マダニに刺されたら？',
      '非常用の水はどれくらい必要？',
    ]);
    expect(suggestionsFor(infos, lang: 'en').first.$2, startsWith('Strong'));
  });

  test('suggestions come from the packages, in any language they have', () {
    expect(suggestionsFor(const [], lang: 'ja'), isEmpty);
    // No Spanish in the packages yet: English is the fallback.
    expect(suggestionsFor(infos, lang: 'es').first.$2, startsWith('Strong'));
    // Names come from the manifests too.
    expect(infos.map((p) => p.nameIn('ja')), ['防災', '登山', '応急手当']);
    expect(infos.map((p) => p.nameIn('en')), [
      'Disasters',
      'Hiking',
      'First aid',
    ]);
  });

  test('every Japanese suggestion finds a passage', () {
    final r = Retriever(
      KnowledgePackage.merge([
        for (final p in infos)
          KnowledgePackage.open('assets/packages/${p.id}.sqlite'),
      ]),
    );
    for (final (_, q) in suggestionsFor(infos, lang: 'ja', max: 99)) {
      expect(r.search(q), isNotEmpty, reason: q);
    }
  });
}
