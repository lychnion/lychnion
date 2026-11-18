import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';

void main() {
  final infos = [
    for (final id in [
      'jp.bousai.core',
      'jp.outdoor.hiking',
      'intl.firstaid.basics',
    ])
      KnowledgePackage.readInfo('assets/packages/$id.sqlite'),
  ];

  test('suggestions come from the packages, in any language they have', () {
    expect(infos.first.suggestionsIn('ja').first.text, '海の近くで強い揺れを感じたら？');
    expect(infos.first.suggestionsIn('en').first.text, startsWith('Strong'));
    // No Spanish in the packages yet: English is the fallback.
    expect(infos.first.suggestionsIn('es').first.text, startsWith('Strong'));
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
    final all = [
      for (final p in infos)
        for (final s in p.suggestionsIn('ja')) s.text,
    ];
    expect(all, isNotEmpty);
    for (final q in all) {
      expect(r.search(q), isNotEmpty, reason: q);
    }
  });
}
