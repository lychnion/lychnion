import 'dart:convert';
import 'dart:math';

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

  test("a publisher's key cannot sign for another publisher", () async {
    final lychnion = await newKeyPair();
    final city = await newKeyPair();
    final cityKey = await keyPairFromSeed(city.seed);
    final trusted = TrustedKeys({
      'lychnion': [lychnion.publicKey],
      'jp.city.test': [city.publicKey],
    });
    // Signed by the city, but says it is from Lychnion.
    final posing = await PackageRecord.sign(
      _unsigned()..['publisher'] = 'lychnion',
      cityKey,
    );
    expect(posing.publisher, 'lychnion');
    expect(await trusted.verify(posing), isFalse);
    expect(await trusted.check(posing.json), isNull);
    // The same record under the city's own name is fine.
    final own = await PackageRecord.sign(
      _unsigned()..['publisher'] = 'jp.city.test',
      cityKey,
    );
    expect(await trusted.verify(own), isTrue);
    // A publisher nobody added.
    final unknown = await PackageRecord.sign(
      _unsigned()..['publisher'] = 'jp.city.other',
      cityKey,
    );
    expect(await trusted.verify(unknown), isFalse);
  });

  test('records with unsafe names are refused', () async {
    final key = await keyPairFromSeed((await newKeyPair()).seed);
    final bad = _unsigned()
      ..['files'] = [
        {'name': '../x', 'size': 3, 'sha256': 'a' * 64},
      ];
    expect(() => PackageRecord.sign(bad, key), throwsFormatException);
  });

  // lychnion/lychnion#76: a name must be the same file on Windows too.
  test('names Windows would change or open as a device are refused', () async {
    final key = await keyPairFromSeed((await newKeyPair()).seed);
    Map<String, Object?> withFile(String name) => _unsigned()
      ..['files'] = [
        {'name': name, 'size': 3, 'sha256': 'a' * 64},
      ];
    for (final name in [
      'x.sqlite.',
      'x..',
      'NUL',
      'nul.sqlite',
      'CON',
      'con.txt',
      'prn',
      'Aux.db',
      'COM1',
      'com9.sqlite',
      'LPT1',
      'com0',
      '${'a' * 127}.',
      'lpt0.x',
    ]) {
      await expectLater(
        PackageRecord.sign(withFile(name), key),
        throwsFormatException,
        reason: name,
      );
      await expectLater(
        PackageRecord.sign(_unsigned()..['id'] = name, key),
        throwsFormatException,
        reason: 'id $name',
      );
    }
    for (final name in [
      'x.sqlite',
      'nullable.sqlite',
      'console',
      'com10.x',
      'lpt',
      'auxx',
      'jp.con.sqlite',
      'x.nul',
    ]) {
      expect(
        (await PackageRecord.sign(withFile(name), key)).files.single.name,
        name,
      );
    }
    // Two files that are one on macOS and Windows, also with one hash.
    await expectLater(
      PackageRecord.sign(
        _unsigned()
          ..['files'] = [
            {'name': 'x.sqlite', 'size': 3, 'sha256': 'a' * 64},
            {'name': 'X.sqlite', 'size': 3, 'sha256': 'a' * 64},
          ],
        key,
      ),
      throwsFormatException,
    );
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

  test('area: codes of the right form, empty when absent', () async {
    final key = await keyPairFromSeed((await newKeyPair()).seed);
    final none = await PackageRecord.sign(_unsigned(), key);
    expect(none.area, isEmpty);
    final some = await PackageRecord.sign(
      _unsigned()..['area'] = ['JP-27', 'JP-28', 'jp', 7, 'JP-'],
      key,
    );
    expect(some.area, ['JP-27', 'JP-28']);
  });

  test("Lychnion's key is built in", () {
    expect(lychnionPublicKey, hasLength(43));
  });

  group('random input', () {
    // A record from a base or mirror can be anything: check() gives a
    // record only when the signed content is unchanged, and never throws.
    late TrustedKeys trusted;
    late Map<String, Object?> signed;
    setUpAll(() async {
      final pair = await newKeyPair();
      trusted = TrustedKeys({
        'test': [pair.publicKey],
      });
      signed = (await PackageRecord.sign(
        _unsigned(),
        await keyPairFromSeed(pair.seed),
      )).json;
    });

    Map<String, Object?> copy() =>
        (jsonDecode(jsonEncode(signed)) as Map).cast();

    test('changed values are refused, never an error', () async {
      final rnd = Random(11);
      final odd = <Object?>[
        null,
        0,
        -1,
        1e308,
        '',
        'x',
        true,
        <Object?>[],
        <String, Object?>{},
        '../etc/passwd',
        'b' * 64,
        '2026.11.2',
        'lychnion',
      ];
      void mutate(Object? o) {
        if (o is Map && o.isNotEmpty) {
          final k = o.keys.elementAt(rnd.nextInt(o.length));
          switch (rnd.nextInt(3)) {
            case 0:
              o[k] = odd[rnd.nextInt(odd.length)];
            case 1:
              o.remove(k);
            default:
              mutate(o[k]);
          }
        } else if (o is List && o.isNotEmpty) {
          final i = rnd.nextInt(o.length);
          if (rnd.nextBool()) {
            o[i] = odd[rnd.nextInt(odd.length)];
          } else {
            mutate(o[i]);
          }
        }
      }

      // What the signature covers: everything but the key and signature.
      String content(Map<String, Object?> j) => canonicalJson(
        Map.of(j)
          ..remove('key')
          ..remove('signature'),
      );
      final original = content(signed);
      for (var i = 0; i < 400; i++) {
        final j = copy();
        mutate(j);
        final r = await trusted.check(j);
        if (r != null) {
          // Accepted only when nothing that is signed changed.
          expect(content(j), original, reason: '$j');
        }
      }
    });

    test('random values and cut-off JSON are refused', () async {
      final rnd = Random(5);
      final text = jsonEncode(signed);
      for (var i = 0; i < 200; i++) {
        final cut = text.substring(0, rnd.nextInt(text.length));
        Object? j;
        try {
          j = jsonDecode(cut);
        } on FormatException {
          j = cut;
        }
        expect(await trusted.check(j), isNull);
      }
      for (final j in [null, 1, 'x', <Object?>[], <String, Object?>{}]) {
        expect(await trusted.check(j), isNull);
      }
    });
  });
}
