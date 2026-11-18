import 'dart:convert';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

void main() {
  test('not a catalog, or fields of the wrong type: refused', () {
    for (final bad in [
      'nope',
      '[]',
      '{"format": 1, "records": []}',
      '{"format": 2}',
      '{"format": 2, "records": {}}',
      '{"format": 2, "records": [], "urls": []}',
      '{"format": 2, "records": [], "mirrors": "x"}',
      '{"format": 2, "records": [], "keys": {}}',
      '{"format": 2, "records": [], "base": 3}',
    ]) {
      expect(
        () => CatalogDocument.parse(bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('entries that are not strings are left out', () {
    final c = CatalogDocument.parse(
      jsonEncode({
        'format': 2,
        'records': [1],
        'urls': {'a': 'x', 'b': 2, 'c': ''},
        'mirrors': ['https://m/', 3, ''],
      }),
    );
    expect(c.urls, {'a': 'x'});
    expect(c.mirrors, ['https://m/']);
    expect(c.keys, isEmpty);
    expect(c.records, [1]);
  });

  test('byHash: sorted, files by hash, keys once; round trip', () async {
    final k = await newKeyPair();
    final pair = await keyPairFromSeed(k.seed);
    Future<PackageRecord> rec(String id) => PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': '1',
      'publisher': 'jp.test',
      'signed': '2026-11-19',
      'files': [
        {
          'name': '$id.sqlite',
          'size': 3,
          'sha256': id.codeUnitAt(3).toRadixString(16).padLeft(64, '0'),
        },
      ],
    }, pair);
    final b = await rec('jp.b'), a = await rec('jp.a');
    final s = await KeyStatement.revoke(
      publisher: 'jp.test',
      key: pair,
      signed: '2026-11-19',
    );
    final c = CatalogDocument.byHash([b, a], keys: [s, s]);
    expect([for (final r in c.records) (r! as Map)['id']], ['jp.a', 'jp.b']);
    expect(
      c.urls[a.files.single.sha256],
      'blobs/sha256/${a.files.single.sha256}',
    );
    expect(c.keys, [s.json]);
    final back = CatalogDocument.parse(c.encode());
    expect(back.toJson(), jsonDecode(jsonEncode(c.toJson())));
    expect(await KeysFile.parse(KeysFile.encode([s, s])), [s]);
    expect(await KeysFile.parse('broken'), isEmpty);
  });

  test('too large to encode', () {
    final c = CatalogDocument(records: ['x' * CatalogDocument.maxBytes]);
    expect(c.encode, throwsA(isA<CatalogTooLarge>()));
  });
}
