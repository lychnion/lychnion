import 'dart:io';
import 'dart:typed_data';

import 'package:lychnion_guide/lychnion_guide.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _source = GuideSource(
  id: 's1',
  title: '防災ガイド',
  publisher: '市',
  url: 'https://example.org',
  licence: 'CC BY 4.0',
  attribution: '市',
);

Map<String, String> _meta({String id = 'jp.test.guide'}) => {
  'id': id,
  'version': '2026.11.1',
  'title': '市の防災',
  'name': '{"ja": "市の防災", "en": "City guide"}',
  'notice': '{"ja": ["緊急時は119番"]}',
};

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('guide'));
  tearDown(() => tmp.delete(recursive: true));

  File write({
    Map<String, String>? meta,
    List<GuidePassage>? passages,
    List<GuideAlert> alerts = const [],
    String name = 'jp.test.guide.sqlite',
  }) => writeGuide(
    File('${tmp.path}/$name'),
    meta: meta ?? _meta(),
    sources: const [_source],
    passages:
        passages ??
        const [GuidePassage(sourceId: 's1', heading: '避難', text: '避難所へ。')],
    alerts: alerts,
  );

  Matcher problem(String part) => throwsA(
    isA<GuideProblem>().having((e) => e.message, 'message', contains(part)),
  );

  group('refused', () {
    test('no file, or not a guide', () {
      expect(() => checkGuide('${tmp.path}/none.sqlite'), problem('no such'));
      final junk = File('${tmp.path}/junk.sqlite')
        ..writeAsStringSync('x' * 200);
      expect(() => checkGuide(junk.path), throwsA(isA<GuideProblem>()));
      final empty = File('${tmp.path}/empty.sqlite');
      sqlite3.open(empty.path)
        ..execute('CREATE TABLE x(a)')
        ..close();
      expect(() => checkGuide(empty.path), problem('meta'));
    });

    test('meta without id or version, or broken JSON', () {
      expect(() => write(meta: {..._meta()}..remove('id')), problem('no id'));
      expect(
        () => write(meta: {..._meta()}..remove('version')),
        problem('no version'),
      );
      expect(
        () => write(meta: {..._meta(), 'name': '{broken'}),
        problem('broken JSON'),
      );
      expect(
        () => write(meta: {..._meta(), 'notice': '{"ja": "not lines"}'}),
        problem('meta notice'),
      );
    });

    test('no passages, or one without its source', () {
      expect(() => write(passages: const []), problem('no passages'));
      expect(
        () => write(
          passages: const [GuidePassage(sourceId: 'x', text: 'a')],
        ),
        throwsA(isA<GuideProblem>()),
      );
    });

    test('an alert without its source', () {
      expect(
        () => write(
          alerts: const [
            GuideAlert(
              id: 'a1',
              sourceId: 'missing',
              text: '高台へ',
              matchAll: [
                ['津波'],
              ],
            ),
          ],
        ),
        throwsA(isA<GuideProblem>()),
      );
    });

    test('a region not like JP or JP-28', () {
      expect(
        () => writeGuide(
          File('${tmp.path}/r.sqlite'),
          meta: _meta(),
          sources: const [
            GuideSource(
              id: 's1',
              title: 't',
              publisher: 'p',
              url: 'u',
              licence: 'l',
              attribution: 'a',
              region: 'jp',
            ),
          ],
          passages: const [GuidePassage(sourceId: 's1', text: 'x')],
        ),
        problem('region'),
      );
    });

    test('vectors that do not match the passages', () {
      final f = write();
      final db = sqlite3.open(f.path)
        ..execute(
          'CREATE TABLE vectors(model TEXT, passage_id INTEGER, vec BLOB)',
        );
      db.execute('INSERT INTO vectors VALUES(?, ?, ?)', ['m', 1, Uint8List(5)]);
      db.close();
      expect(() => checkGuide(f.path), problem('vectors'));
      sqlite3.open(f.path)
        ..execute('DELETE FROM vectors')
        ..execute('INSERT INTO vectors VALUES(?, ?, ?)', ['m', 1, Uint8List(8)])
        ..execute('INSERT INTO vectors VALUES(?, ?, ?)', ['m', 2, Uint8List(8)])
        ..close();
      expect(() => checkGuide(f.path), problem('but 1 passages'));
    });

    test('where it cannot be written', () {
      final notDir = File('${tmp.path}/file')..writeAsStringSync('x');
      expect(
        () => writeGuide(
          File('${notDir.path}/g.sqlite'),
          meta: _meta(),
          sources: const [_source],
          passages: const [GuidePassage(sourceId: 's1', text: 'x')],
        ),
        throwsA(isA<GuideProblem>()),
      );
    });

    test('a refused guide never replaces a good one', () {
      final good = write();
      final before = good.readAsBytesSync();
      expect(() => write(passages: const []), throwsA(isA<GuideProblem>()));
      expect(good.readAsBytesSync(), before);
      expect(File('${good.path}.building').existsSync(), isFalse);
    });
  });

  test('a good guide replaces the one there', () {
    write();
    final f = write(meta: {..._meta(), 'version': '2026.11.2'});
    expect(checkGuide(f.path).version, '2026.11.2');
    expect(tmp.listSync().where((e) => e.path.endsWith('.building')), isEmpty);
  });

  test('written and checked, with an alert', () {
    final f = write(
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
    final s = checkGuide(f.path);
    expect(s.id, 'jp.test.guide');
    expect(s.version, '2026.11.1');
    expect(s.sources, 1);
    expect(s.passages, 1);
  });
}
