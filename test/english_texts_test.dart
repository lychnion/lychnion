import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';

void main() {
  for (final id in ['jp.bousai.core', 'jp.outdoor.hiking']) {
    test('$id: every passage has an English text made at build time', () {
      final pkg = KnowledgePackage.open('assets/packages/$id.sqlite');
      for (final p in pkg.passages) {
        expect(questionLanguage(p.textIn('ja')), 'ja', reason: p.text);
        expect(p.texts['en'], isNotNull, reason: p.text);
        // Mostly English; official Japanese terms stay in brackets.
        expect(
          _latinShare(p.textIn('en')),
          greaterThan(0.8),
          reason: p.textIn('en'),
        );
      }
      expect(pkg.parts.single.notice, isNotEmpty);
    });
  }

  test('the lightning line keeps its strength in English', () {
    final hiking = KnowledgePackage.open(
      'assets/packages/jp.outdoor.hiking.sqlite',
    );
    expect(
      hiking.passages.map((p) => p.textIn('en')).join(),
      contains(
        'If you hear thunder in the distance, you are already in danger.',
      ),
    );
  });

  test('merged packages keep each passage\'s languages', () {
    final both = KnowledgePackage.merge([
      KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite'),
      KnowledgePackage.open('assets/packages/intl.firstaid.basics.sqlite'),
    ]);
    expect(both.passages.every((p) => p.texts.containsKey('en')), isTrue);
  });
}

double _latinShare(String s) {
  final letters = s.runes.where(
    (r) => RegExp(
      r'[A-Za-z\u3040-\u30ff\u4e00-\u9fff]',
    ).hasMatch(String.fromCharCode(r)),
  );
  if (letters.isEmpty) return 1;
  return letters.where((r) => r < 0x80).length / letters.length;
}
