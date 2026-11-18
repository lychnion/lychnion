import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

Map<String, Object?> _unsigned({String version = '2026.11.1'}) => {
  'format': 1,
  'id': 'jp.test.package',
  'kind': 'package',
  'version': version,
  'publisher': 'test',
  'signed': '2026-11-18',
  'title': {'en': 'Test', 'ja': 'テスト'},
  'files': [
    {'name': 'jp.test.package.sqlite', 'size': 3, 'sha256': 'a' * 64},
  ],
};

void main() {
  test('canonical JSON sorts keys and drops spaces', () {
    expect(
      canonicalJson({
        'b': [1, true, null],
        'a': 'x\n"y"',
        'c': 2.0,
      }),
      '{"a":"x\\n\\"y\\"","b":[1,true,null],"c":2}',
    );
  });

  test('versions compare by number, not by text', () {
    expect(compareVersions('2026.11.2', '2026.11.10'), -1);
    expect(compareVersions('2026.11', '2026.11.0'), 0);
    expect(isOlder('2026.10.9', '2026.11.0'), isTrue);
    expect(isOlder('2026.11.0', 'bundled'), isFalse);
    expect(() => compareVersions('v1', '1'), throwsFormatException);
  });

  test('a signed record verifies, a changed one does not', () async {
    final pair = await newKeyPair();
    final key = await keyPairFromSeed(pair.seed);
    final trusted = TrustedKeys({
      'test': [pair.publicKey],
    });
    final record = await PackageRecord.sign(_unsigned(), key);
    expect(await trusted.verify(record), isTrue);
    expect(await trusted.check(record.json), isNotNull);

    final changed = Map.of(record.json)..['version'] = '2026.11.2';
    expect(await trusted.check(changed), isNull);
    expect(await builtInPublishers.check(record.json), isNull);
  });

  test('records with unsafe names are refused', () async {
    final key = await keyPairFromSeed((await newKeyPair()).seed);
    final bad = _unsigned()
      ..['files'] = [
        {'name': '../x', 'size': 3, 'sha256': 'a' * 64},
      ];
    expect(() => PackageRecord.sign(bad, key), throwsFormatException);
  });

  test('plus adds publishers without changing the original', () async {
    final pair = await newKeyPair();
    final key = await keyPairFromSeed(pair.seed);
    final record = await PackageRecord.sign(_unsigned(), key);
    final more = builtInPublishers.plus({
      record.publisher: [pair.publicKey],
    });
    expect(await more.verify(record), isTrue);
    expect(await builtInPublishers.verify(record), isFalse);
    expect(more.publishers, containsAll(['lychnion', record.publisher]));
    expect(builtInPublishers.publishers, ['lychnion']);
    expect(
      () => more.plus({
        'x': ['short'],
      }),
      throwsFormatException,
    );
  });

  test("Lychnion's key is built in", () {
    expect(lychnionPublicKey, hasLength(43));
  });
}
