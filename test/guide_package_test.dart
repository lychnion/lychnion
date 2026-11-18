// The shared guide check (packages/lychnion_guide, also used by
// lychnion-studio) and the app's own reader must agree: every guide the
// check accepts opens in KnowledgePackage, the bundled guides pass the
// check.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion_guide/lychnion_guide.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('guide'));
  tearDown(() => tmp.delete(recursive: true));

  const source = GuideSource(
    id: 's1',
    title: '防災ガイド',
    publisher: '市',
    url: 'https://example.org',
    licence: 'CC BY 4.0',
    attribution: '市',
  );

  test('a guide the shared check refuses is never written', () {
    expect(
      () => writeGuide(
        File('${tmp.path}/g.sqlite'),
        meta: const {'id': 'jp.g', 'version': '1'},
        sources: const [source],
        passages: const [],
      ),
      throwsA(isA<GuideProblem>()),
    );
    expect(File('${tmp.path}/g.sqlite').existsSync(), isFalse);
  });

  test('what the shared check accepts opens in the app', () {
    final variants = <String, Map<String, String>>{
      'minimal': const {'id': 'jp.g', 'version': '1'},
      'full': const {
        'id': 'jp.g',
        'version': '2026.11.1',
        'title': '市の防災',
        'language': 'ja',
        'name': '{"ja": "市の防災", "en": "City"}',
        'notice': '{"ja": ["緊急時は119番"], "en": ["Call 119"]}',
        'suggestions': '{"ja": [{"icon": "water", "text": "給水所は？"}]}',
        'synonyms': '{"避難所": ["避難場所"]}',
        'gaps': '["地震"]',
        'area': 'JP-28',
      },
    };
    for (final e in variants.entries) {
      final f = writeGuide(
        File('${tmp.path}/${e.key}.sqlite'),
        meta: e.value,
        sources: const [source],
        passages: const [
          GuidePassage(sourceId: 's1', heading: '避難', text: '避難所へ行きます。'),
        ],
        alerts: const [
          GuideAlert(
            id: 'a1',
            sourceId: 's1',
            text: '高台へ',
            matchAll: [
              ['津波'],
            ],
          ),
        ],
      );
      final p = KnowledgePackage.open(f.path);
      expect(p.passages, hasLength(1), reason: e.key);
    }
  });

  test('the bundled guides pass the shared check', () {
    final guides = Directory('assets/packages')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'));
    expect(guides, isNotEmpty);
    for (final f in guides) {
      expect(() => checkGuide(f.path), returnsNormally, reason: f.path);
    }
  });
}
