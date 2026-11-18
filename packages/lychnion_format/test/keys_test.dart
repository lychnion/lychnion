import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

/// Small costs, so the tests run fast; files still say what they used.
const _fastKdf = KeyBackupKdf(memory: 64, iterations: 1);
const _pass = 'correct horse battery';

Future<({String seed, String pub, SimpleKeyPair pair})> _key() async {
  final k = await newKeyPair();
  return (seed: k.seed, pub: k.publicKey, pair: await keyPairFromSeed(k.seed));
}

Future<PackageRecord> _record(
  SimpleKeyPair pair, {
  String publisher = 'jp.test',
}) => PackageRecord.sign({
  'format': 1,
  'id': 'jp.test.package',
  'kind': 'package',
  'version': '2026.11.1',
  'publisher': publisher,
  'signed': '2026-11-19',
  'files': [
    {'name': 'jp.test.package.sqlite', 'size': 3, 'sha256': 'a' * 64},
  ],
}, pair);

Future<String> _backup(String seed, {String name = 'jp.test'}) =>
    KeyBackup.create(
      name: name,
      title: 'Test',
      seed: seed,
      passphrase: _pass,
      signed: '2026-11-19',
      kdf: _fastKdf,
    );

Matcher _problem(KeyBackupProblem p) =>
    throwsA(isA<KeyBackupException>().having((e) => e.problem, 'problem', p));

void main() {
  group('key backup', () {
    test('a short passphrase is refused', () async {
      final k = await _key();
      expect(
        () => KeyBackup.create(
          name: 'jp.test',
          seed: k.seed,
          passphrase: 'short',
          signed: '2026-11-19',
          kdf: _fastKdf,
        ),
        throwsArgumentError,
      );
    });

    test('a wrong passphrase does not open it', () async {
      final k = await _key();
      final text = await _backup(k.seed);
      expect(
        () => KeyBackup.open(text, 'wrong horse battery'),
        _problem(KeyBackupProblem.wrongPassphrase),
      );
    });

    test('other files and damaged backups are refused', () async {
      final k = await _key();
      final text = await _backup(k.seed);
      final j = jsonDecode(text) as Map<String, Object?>;

      expect(
        () => KeyBackup.open('not json', _pass),
        _problem(KeyBackupProblem.notABackup),
      );
      expect(
        () => KeyBackup.open('{"format":1,"name":"jp.test"}', _pass),
        _problem(KeyBackupProblem.notABackup),
      );
      expect(
        () => KeyBackup.open(jsonEncode({...j, 'format': 2}), _pass),
        _problem(KeyBackupProblem.newer),
      );
      expect(
        () => KeyBackup.open(text.substring(0, text.length ~/ 2), _pass),
        _problem(KeyBackupProblem.notABackup),
      );
      expect(
        () => KeyBackup.open(jsonEncode({...j}..remove('cipher')), _pass),
        _problem(KeyBackupProblem.damaged),
      );
      // A file asking for absurd costs could stall the app.
      final kdf = {...(j['kdf']! as Map), 'memory': 1 << 30};
      expect(
        () => KeyBackup.open(jsonEncode({...j, 'kdf': kdf}), _pass),
        _problem(KeyBackupProblem.damaged),
      );
    });

    test('changed name, key or data does not open', () async {
      final k = await _key();
      final other = await _key();
      final j = jsonDecode(await _backup(k.seed)) as Map<String, Object?>;
      final cipher = j['cipher']! as Map;
      final data = cipher['data']! as String;
      final flipped = '${data[0] == 'A' ? 'B' : 'A'}${data.substring(1)}';

      for (final changed in [
        {...j, 'name': 'jp.other'},
        {...j, 'public_key': other.pub},
        {
          ...j,
          'cipher': {...cipher, 'data': flipped},
        },
      ]) {
        expect(
          () => KeyBackup.open(jsonEncode(changed), _pass),
          _problem(KeyBackupProblem.wrongPassphrase),
        );
      }
    });

    test('export and import give back the same key', () async {
      final k = await _key();
      final text = await _backup(k.seed);
      expect(text, isNot(contains(k.seed)));
      expect(text, contains('Keep it offline'));
      final r = await KeyBackup.open(text, _pass);
      expect(r.name, 'jp.test');
      expect(r.title, 'Test');
      expect(r.seed, k.seed);
      expect(r.publicKey, k.pub);
    });

    test('the revocation inside opens without the passphrase', () async {
      final k = await _key();
      final text = await _backup(k.seed);
      final s = await KeyBackup.revocationIn(text);
      expect(s.type, KeyStatementType.revoke);
      expect(s.oldKey, k.pub);

      // One taken from another backup does not pass.
      final other = await _key();
      final j = jsonDecode(text) as Map<String, Object?>;
      final foreign = jsonDecode(await _backup(other.seed)) as Map;
      expect(
        () => KeyBackup.revocationIn(
          jsonEncode({...j, 'revocation': foreign['revocation']}),
        ),
        _problem(KeyBackupProblem.damaged),
      );
    });
  });

  group('key statements', () {
    test('changed or half-signed statements are refused', () async {
      final a = await _key(), b = await _key(), c = await _key();
      final s = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: a.pair,
        newKey: b.pair,
        signed: '2026-11-19',
      );
      expect(await KeyStatement.check(s.json), isNotNull);
      for (final bad in <Map<String, Object?>>[
        {...s.json, 'new': c.pub}, // successor swapped
        {...s.json, 'publisher': 'jp.other'},
        {...s.json}..remove('new_signature'),
        {...s.json, 'format': 2},
        {...s.json, 'type': 'revoke'},
        {...s.json, 'new': a.pub},
      ]) {
        expect(await KeyStatement.check(bad), isNull, reason: '$bad');
      }
      expect(await KeyStatement.check('nonsense'), isNull);
      expect(await KeyStatement.check(null), isNull);
    });

    test('an attacker\'s replacement is refused', () async {
      final a = await _key(), thief = await _key(), t2 = await _key();
      final trust = TrustedKeys({
        'jp.test': [a.pub],
      });

      // The thief's own key cannot sign for the old one.
      final fake = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: thief.pair,
        newKey: t2.pair,
        signed: '2026-11-19',
      );
      final forged = {...fake.json, 'old': a.pub};
      expect(await KeyStatement.check(forged), isNull);
      final after = trust.withStatements([fake]);
      expect(after.keysOf('jp.test'), {a.pub});
      expect(await after.verify(await _record(t2.pair)), isFalse);

      // Nor for another publisher it is not trusted for.
      final other = await KeyStatement.replace(
        publisher: 'jp.other',
        oldKey: a.pair,
        newKey: thief.pair,
        signed: '2026-11-19',
      );
      expect(trust.withStatements([other]).keysOf('jp.test'), {a.pub});
    });

    test('a replacement signed by the old key is accepted', () async {
      final a = await _key(), b = await _key(), c = await _key();
      final trust = TrustedKeys({
        'jp.test': [a.pub],
      });
      final ab = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: a.pair,
        newKey: b.pair,
        signed: '2026-11-19',
      );
      final bc = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: b.pair,
        newKey: c.pair,
        signed: '2026-11-20',
      );
      // Order does not matter; chains are followed.
      final after = trust.withStatements([bc, ab]);
      expect(after.keysOf('jp.test'), {a.pub, b.pub, c.pub});
      expect(await after.verify(await _record(c.pair)), isTrue);
      // Records of the replaced key stay valid.
      expect(await after.verify(await _record(a.pair)), isTrue);
      // The same statement again changes nothing.
      expect(identical(after.withStatements([ab]), after), isTrue);
      // plus() keeps the statements.
      expect(after.plus({'jp.x': []}).keysOf('jp.test'), {a.pub, b.pub, c.pub});
    });

    test('a revocation is honoured, also for what came after it', () async {
      final a = await _key(), b = await _key(), c = await _key();
      final trust = TrustedKeys({
        'jp.test': [a.pub],
      });
      final ab = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: a.pair,
        newKey: b.pair,
        signed: '2026-11-19',
      );
      final bc = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: b.pair,
        newKey: c.pair,
        signed: '2026-11-20',
      );
      final revokeB = await KeyStatement.revoke(
        publisher: 'jp.test',
        key: b.pair,
        signed: '2026-11-21',
      );
      final after = trust.withStatements([ab, bc, revokeB]);
      expect(after.keysOf('jp.test'), {a.pub});
      expect(await after.verify(await _record(b.pair)), isFalse);
      // Reached only through the revoked key.
      expect(await after.verify(await _record(c.pair)), isFalse);
      expect(after.isRevoked('jp.test', b.pub), isTrue);

      final revokeA = await KeyStatement.revoke(
        publisher: 'jp.test',
        key: a.pair,
        signed: '2026-11-21',
      );
      final none = after.withStatements([revokeA]);
      expect(none.publishers, isNot(contains('jp.test')));
      expect(none.known, contains('jp.test'));
      expect(await none.verify(await _record(a.pair)), isFalse);
    });

    test('two different successors count as a theft', () async {
      final a = await _key(), b = await _key(), thief = await _key();
      final trust = TrustedKeys({
        'jp.test': [a.pub],
      });
      final owner = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: a.pair,
        newKey: b.pair,
        signed: '2026-11-19',
      );
      final stolen = await KeyStatement.replace(
        publisher: 'jp.test',
        oldKey: a.pair,
        newKey: thief.pair,
        signed: '2026-11-19',
      );
      final after = trust.withStatements([owner, stolen]);
      expect(after.publishers, isEmpty);
      expect(after.revokedIdsOf('jp.test'), {recordKeyIdOf(_bytes(a.pub))});
      expect(await after.verify(await _record(thief.pair)), isFalse);
    });

    test('checkAll skips bad entries and duplicates', () async {
      final a = await _key();
      final r = await KeyStatement.revoke(
        publisher: 'jp.test',
        key: a.pair,
        signed: '2026-11-19',
      );
      final list = await KeyStatement.checkAll([
        r.json,
        'x',
        {'format': 1},
        jsonDecode(jsonEncode(r.json)),
      ]);
      expect(list, [r]);
      expect(await KeyStatement.checkAll('not a list'), isEmpty);
    });

    test(
      'relevantStatements: order does not matter, junk is skipped',
      () async {
        final a = await _key(), b = await _key();
        final trust = TrustedKeys({
          'jp.test': [a.pub],
        });
        final ab = await KeyStatement.replace(
          publisher: 'jp.test',
          oldKey: a.pair,
          newKey: b.pair,
          signed: '2026-11-19',
        );
        final revokeB = await KeyStatement.revoke(
          publisher: 'jp.test',
          key: b.pair,
          signed: '2026-11-20',
        );
        final junk = [
          for (var i = 0; i < 20; i++)
            (await KeyStatement.revoke(
              publisher: 'jp.test',
              key: (await _key()).pair,
              signed: '2026-11-19',
            )).json,
        ];
        // The revocation of B comes first, junk fills the list before both.
        final got = await relevantStatements(trust, [
          ...junk,
          revokeB.json,
          ab.json,
          'x',
        ], max: 5);
        expect(got.toSet(), {ab, revokeB});
        expect(trust.withStatements(got).keysOf('jp.test'), {a.pub});
        // Statements about publishers not given are not looked at.
        final other = await KeyStatement.revoke(
          publisher: 'jp.other',
          key: a.pair,
          signed: '2026-11-19',
        );
        expect(await relevantStatements(trust, [other.json]), isEmpty);
        expect(await relevantStatements(trust, 'nope'), isEmpty);
      },
    );
  });
}

List<int> _bytes(String k) => base64Url.decode(base64Url.normalize(k));
