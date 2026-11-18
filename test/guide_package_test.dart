// The shared guide check (packages/lychnion_guide, also used by
// lychnion-studio) and the app's own reader must agree: every guide the
// check accepts opens in KnowledgePackage, the bundled guides pass the
// check.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion_guide/lychnion_guide.dart';
import 'package:sqlite3/sqlite3.dart';

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

  File base(String name) => writeGuide(
    File('${tmp.path}/$name.sqlite'),
    meta: const {'id': 'jp.g', 'version': '1', 'language': 'ja'},
    sources: const [source],
    passages: const [
      GuidePassage(sourceId: 's1', heading: 'Evacuation', text: 'Go.'),
      GuidePassage(sourceId: 's1', text: 'Water.'),
    ],
    alerts: const [
      GuideAlert(
        id: 'a1',
        sourceId: 's1',
        text: '高台へ',
        matchAll: [
          ['津波'],
        ],
        textEn: 'Go to high ground',
        matchAllEn: [
          ['tsunami'],
        ],
      ),
    ],
  );

  /// The optional parts the data tools add: translations, originals of a
  /// translated source, and search vectors.
  void addExtras(File f) {
    sqlite3.open(f.path)
      ..execute('''
        CREATE TABLE passage_texts(passage_id INTEGER, lang TEXT,
                                   heading TEXT, text TEXT);
        INSERT INTO passage_texts VALUES(1, 'en', 'Evacuation', 'Go.');
        UPDATE passages SET original = '避難', original_heading = '避難'
          WHERE id = 1;
        CREATE TABLE vectors(model TEXT, passage_id INTEGER, vec BLOB);
      ''')
      ..execute('INSERT INTO vectors VALUES(?, ?, ?)', ['m', 1, Uint8List(8)])
      ..execute('INSERT INTO vectors VALUES(?, ?, ?)', ['m', 2, Uint8List(8)])
      ..close();
  }

  test('both accept translations, originals and vectors', () {
    final f = base('extras');
    addExtras(f);
    expect(checkGuide(f.path).passages, 2);
    final p = KnowledgePackage.open(f.path);
    expect(p.passages.first.textIn('en'), 'Go.');
    expect(p.vectors['m'], hasLength(2));
    expect(p.alerts.single.textIn('en'), 'Go to high ground');
  });

  test('both refuse what the app cannot read', () {
    final cases = <String, String>{
      // A blob: a number would be stored as text in a TEXT column.
      'lang not text': "UPDATE passage_texts SET lang = x'00'",
      'match_all not a list': "UPDATE alerts SET match_all = '{\"a\": 1}'",
      'alert without its source': "UPDATE alerts SET source_id = 'gone'",
    };
    for (final e in cases.entries) {
      final f = base(e.key.replaceAll(' ', '_'));
      addExtras(f);
      sqlite3.open(f.path)
        ..execute(e.value)
        ..close();
      expect(
        () => checkGuide(f.path),
        throwsA(isA<GuideProblem>()),
        reason: e.key,
      );
      expect(
        () => KnowledgePackage.open(f.path),
        throwsA(anything),
        reason: e.key,
      );
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
