import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

// lychnion/lychnion#125: key scopes, grants, revocation by the root, and a
// list of signatures on records. Built-in keys keep every scope.

Future<({String pub, SimpleKeyPair pair})> _key() async {
  final k = await newKeyPair();
  return (pub: k.publicKey, pair: await keyPairFromSeed(k.seed));
}

const _t = '2026-11-26T09:00:00+09:00';

Map<String, Object?> _unsigned(String kind, {String id = 'jp.a'}) => {
  'format': 1,
  'id': id,
  'kind': kind,
  'version': '1',
  'publisher': 'lychnion',
  'title': {'en': id},
  'files': [
    {'name': '$id.bin', 'size': 1, 'sha256': 'a' * 64},
  ],
  'signed': _t,
};

void main() {
  late ({String pub, SimpleKeyPair pair}) root, data, data2, att, other;
  late TrustedKeys base;

  setUp(() async {
    root = await _key();
    data = await _key();
    data2 = await _key();
    att = await _key();
    other = await _key();
    base = TrustedKeys({
      'lychnion': [root.pub],
    });
  });

  Future<KeyStatement> grant(
    ({String pub, SimpleKeyPair pair}) k,
    List<String> scope, {
    SimpleKeyPair? by,
  }) => KeyStatement.grant(
    publisher: 'lychnion',
    granter: by ?? root.pair,
    newKey: k.pair,
    scope: scope,
    signed: _t,
  );

  group('scopes', () {
    test('built-in keys hold every scope', () {
      for (final s in KeyScope.all) {
        expect(base.keysFor('lychnion', s), {root.pub});
      }
    });

    test('a granted data key signs data, not models', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, data.pub});
      expect(t.keysFor('lychnion', KeyScope.data), {root.pub, data.pub});
      expect(t.keysFor('lychnion', KeyScope.models), {root.pub});
      final pkg = await PackageRecord.sign(_unsigned('package'), data.pair);
      final model = await PackageRecord.sign(_unsigned('model'), data.pair);
      expect(await t.verify(pkg), isTrue);
      expect(await t.verify(model), isFalse, reason: 'out of scope');
      expect(
        await t.verify(await PackageRecord.sign(_unsigned('model'), root.pair)),
        isTrue,
      );
    });

    test(
      'a successor by replace holds the scopes of the key it replaces',
      () async {
        final t = base.withStatements([
          await grant(data, [KeyScope.data]),
          await KeyStatement.replace(
            publisher: 'lychnion',
            oldKey: data.pair,
            newKey: data2.pair,
            signed: _t,
          ),
        ]);
        expect(t.keysFor('lychnion', KeyScope.data), contains(data2.pub));
        expect(
          t.keysFor('lychnion', KeyScope.models),
          isNot(contains(data2.pub)),
        );
        expect(t.keysFor('lychnion', KeyScope.keys), {root.pub});
      },
    );

    test('only a key holding keys may grant', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(other, [KeyScope.models], by: data.pair),
      ]);
      expect(t.keysOf('lychnion'), isNot(contains(other.pub)));
    });

    test('grants add up', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(data, [KeyScope.attestations]),
      ]);
      expect(
        t.scopesOfKeyId(
          'lychnion',
          recordKeyIdOf(base64Url.decode(base64Url.normalize(data.pub))),
        ),
        {KeyScope.data, KeyScope.attestations},
      );
    });
  });

  group('revocations', () {
    test('the root revokes a delegate it does not hold', () async {
      final g = await grant(data, [KeyScope.data]);
      final cut = await KeyStatement.revoke(
        publisher: 'lychnion',
        revoked: data.pub,
        by: root.pair,
        signed: _t,
      );
      expect(cut.by, root.pub);
      final t = base.withStatements([g, cut]);
      expect(t.keysOf('lychnion'), {root.pub});
      expect(t.isRevoked('lychnion', data.pub), isTrue);
    });

    test('a revocation by a key without keys is ignored', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(data2, [KeyScope.data]),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: data2.pub,
          by: data.pair,
          signed: _t,
        ),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, data.pub, data2.pub});
    });

    test('revoking the granter drops the keys it granted', () async {
      final next = await _key();
      final t =
          TrustedKeys({
            'lychnion': [root.pub, next.pub],
          }).withStatements([
            await grant(data, [KeyScope.data]),
            await KeyStatement.revoke(
              publisher: 'lychnion',
              key: root.pair,
              signed: _t,
            ),
          ]);
      expect(t.keysOf('lychnion'), {next.pub});
    });

    test('a delegate cannot revoke the root; the root revokes it', () async {
      final k2 = await _key();
      final t = base.withStatements([
        await grant(k2, [KeyScope.keys]),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: k2.pub,
          by: root.pair,
          signed: _t,
        ),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: root.pub,
          by: k2.pair,
          signed: _t,
        ),
      ]);
      expect(t.keysOf('lychnion'), {root.pub});
      // Alone, the delegate's revocation of the root is ignored too.
      final alone = base.withStatements([
        await grant(k2, [KeyScope.keys]),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: root.pub,
          by: k2.pair,
          signed: _t,
        ),
      ]);
      expect(alone.keysOf('lychnion'), {root.pub, k2.pub});
    });

    test('a delegate cannot revoke a sibling', () async {
      final g = await _key();
      final t = base.withStatements([
        await grant(g, [KeyScope.keys]),
        await grant(data, [KeyScope.data]),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: data.pub,
          by: g.pair,
          signed: _t,
        ),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, g.pub, data.pub});
    });

    test(
      'the root revokes a keys delegate; its revocations stop counting',
      () async {
        final g = await _key();
        final h = await _key();
        final t = base.withStatements([
          await grant(g, [KeyScope.keys]),
          await grant(data, [KeyScope.data]),
          await grant(h, [KeyScope.data], by: g.pair),
          // Made by g beforehand: against its own delegate, and a sibling.
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: h.pub,
            by: g.pair,
            signed: _t,
          ),
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: data.pub,
            by: g.pair,
            signed: _t,
          ),
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: g.pub,
            by: root.pair,
            signed: _t,
          ),
        ]);
        // g is out, h with it (reached only through g); data stays.
        expect(t.keysOf('lychnion'), {root.pub, data.pub});
      },
    );

    test('a delegate revokes its own delegate', () async {
      final g = await _key();
      final h = await _key();
      final t = base.withStatements([
        await grant(g, [KeyScope.keys]),
        await grant(h, [KeyScope.data], by: g.pair),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: h.pub,
          by: g.pair,
          signed: _t,
        ),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, g.pub});
    });

    test(
      'delegates revoking each other in a loop: both, fail closed',
      () async {
        final a = await _key();
        final b = await _key();
        final t = base.withStatements([
          await grant(a, [KeyScope.keys]),
          await grant(b, [KeyScope.keys], by: a.pair),
          await grant(a, [KeyScope.keys], by: b.pair),
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: b.pub,
            by: a.pair,
            signed: _t,
          ),
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: a.pub,
            by: b.pair,
            signed: _t,
          ),
        ]);
        expect(t.keysOf('lychnion'), {root.pub});
      },
    );

    test(
      'theft still shows with grants: two successors revoke a key',
      () async {
        final t = base.withStatements([
          await grant(data, [KeyScope.data]),
          await KeyStatement.replace(
            publisher: 'lychnion',
            oldKey: data.pair,
            newKey: data2.pair,
            signed: _t,
          ),
          await KeyStatement.replace(
            publisher: 'lychnion',
            oldKey: data.pair,
            newKey: other.pair,
            signed: _t,
          ),
        ]);
        expect(t.keysOf('lychnion'), {root.pub});
      },
    );

    test('flood from a key without keys: the real revocation counts', () async {
      final g = await grant(data, [KeyScope.data]);
      final known = base.withStatements([g]);
      final flood = <Object?>[];
      for (var i = 0; i < 60; i++) {
        final x = await _key();
        flood.add(
          jsonDecode(
            jsonEncode((await grant(x, [KeyScope.models], by: data.pair)).json),
          ),
        );
        flood.add(
          jsonDecode(
            jsonEncode(
              (await KeyStatement.revoke(
                publisher: 'lychnion',
                revoked: x.pub,
                by: data.pair,
                signed: _t,
              )).json,
            ),
          ),
        );
      }
      final real = await KeyStatement.revoke(
        publisher: 'lychnion',
        revoked: data.pub,
        by: root.pair,
        signed: _t,
      );
      final got = await relevantStatements(known, [
        ...flood,
        jsonDecode(jsonEncode(real.json)),
      ], max: 10);
      expect(got, [real]);
      expect(known.withStatements(got).keysOf('lychnion'), {root.pub});
    });

    test('a self-revocation counts past max', () async {
      final g = await grant(data, [KeyScope.data]);
      final known = base.withStatements([g]);
      final grants = [
        for (var i = 0; i < 5; i++)
          jsonDecode(
            jsonEncode((await grant(await _key(), [KeyScope.data])).json),
          ),
      ];
      final self = await KeyStatement.revoke(
        publisher: 'lychnion',
        key: data.pair,
        signed: _t,
      );
      final got = await relevantStatements(known, [
        ...grants,
        jsonDecode(jsonEncode(self.json)),
      ], max: 2);
      expect(got, contains(self));
      expect(got.length, 3);
    });

    test(
      'relevantStatements takes grants and revocations by the root',
      () async {
        final g = await grant(data, [KeyScope.data]);
        final cut = await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: data.pub,
          by: root.pair,
          signed: _t,
        );
        // As raw JSON from a catalog, in any order.
        final got = await relevantStatements(base, [
          jsonDecode(jsonEncode(cut.json)),
          jsonDecode(jsonEncode(g.json)),
        ]);
        expect(got.toSet(), {g, cut});
        expect(KeyStatement.keepOrder([g.json, cut.json]), [1, 0]);
      },
    );
  });

  group('carried', () {
    test(
      'keepOrder and capped: revocations, then grants, then the rest',
      () async {
        final g = await grant(data, [KeyScope.data]);
        final byRoot = await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: data2.pub,
          by: root.pair,
          signed: _t,
        );
        final r = await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: data.pair,
          newKey: other.pair,
          signed: _t,
        );
        expect(KeyStatement.keepOrder([r.json, g.json, byRoot.json]), [
          2,
          1,
          0,
        ]);
        expect(KeyStatement.capped([r, g, byRoot], 2), [g, byRoot]);
      },
    );

    test('a catalog carries a grant; a reader takes it', () async {
      final g = await grant(data, [KeyScope.data]);
      final doc = CatalogDocument.byHash(const [], keys: [g]);
      final back = CatalogDocument.parse(doc.encode());
      final got = await relevantStatements(base, back.keys);
      expect(got, [g]);
      expect(
        base.withStatements(got).keysFor('lychnion', KeyScope.data),
        contains(data.pub),
      );
    });

    test('more than maxSignatures entries: not a record', () async {
      final r = await PackageRecord.sign(_unsigned('package'), root.pair);
      final j = {
        ...r.json,
        'signatures': [
          for (var i = 0; i <= PackageRecord.maxSignatures; i++)
            {'key': 'AAAAAAAA', 'signature': 'x'},
        ],
      };
      expect(() => PackageRecord.fromJson(j), throwsFormatException);
      expect(await base.check(j), isNull);
    });
  });

  group('shape', () {
    test('grant scope sorted, known, once; revoke by itself refused', () async {
      final g = await grant(data, [KeyScope.models, KeyScope.data]);
      expect(g.scope, [KeyScope.data, KeyScope.models], reason: 'sorted');
      Future<Object?> again(Map<String, Object?> change) =>
          KeyStatement.check({...g.json, ...change});
      expect(await again({'scope': <String>[]}), isNull);
      expect(
        await again({
          'scope': ['models', 'data'],
        }),
        isNull,
      );
      expect(
        await again({
          'scope': ['data', 'data'],
        }),
        isNull,
      );
      expect(
        await again({
          'scope': ['everything'],
        }),
        isNull,
      );
      expect(await again({'by': root.pub}), isNull);
      await expectLater(
        KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: root.pub,
          by: root.pair,
          signed: _t,
        ),
        throwsArgumentError,
      );
      final r = await KeyStatement.replace(
        publisher: 'lychnion',
        oldKey: root.pair,
        newKey: data.pair,
        signed: _t,
      );
      expect(
        await KeyStatement.check({
          ...r.json,
          'scope': ['data'],
        }),
        isNull,
      );
    });
  });

  group('signature list', () {
    test('older readers: the single signature covers the list too', () async {
      final r = await PackageRecord.sign(
        _unsigned('package'),
        root.pair,
        more: [data.pair],
      );
      expect(r.signatures, hasLength(1));
      // What an older app checks: `signature` over the record without it.
      final ok = await Ed25519().verify(
        utf8.encode(canonicalJson(Map.of(r.json)..remove('signature'))),
        signature: Signature(
          base64Url.decode(base64Url.normalize(r.signature)),
          publicKey: SimplePublicKey(
            base64Url.decode(base64Url.normalize(root.pub)),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(ok, isTrue);
      expect(await base.verify(r), isTrue);
    });

    test('distinct keys counted once; out-of-scope ones not at all', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(att, [KeyScope.attestations]),
      ]);
      final two = await PackageRecord.sign(
        _unsigned('package'),
        root.pair,
        more: [data.pair],
      );
      expect(await t.verify(two, need: 2), isTrue);
      // The same key twice: one.
      final same = await PackageRecord.sign(
        _unsigned('package'),
        root.pair,
        more: [root.pair],
      );
      expect(await t.verify(same, need: 2), isFalse);
      // A key without data: does not count.
      final outside = await PackageRecord.sign(
        _unsigned('package'),
        root.pair,
        more: [att.pair],
      );
      expect(await t.verify(outside, need: 2), isFalse);
      // A changed list entry fails the single signature (it covers the
      // list), so the record is refused.
      final j = Map<String, Object?>.of(two.json);
      j['signatures'] = [
        {'key': 'AAAAAAAA', 'signature': 'x'},
      ];
      expect(await t.check(j), isNull);
    });

    test('a list entry can carry a record whose key is out of scope', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
      ]);
      // A model signed by the data key, with the root in the list.
      final r = await PackageRecord.sign(
        _unsigned('model'),
        data.pair,
        more: [root.pair],
      );
      expect(await t.verify(r), isTrue);
    });
  });

  group('attestations and statuses need their scope', () {
    test('attestation', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(att, [KeyScope.attestations]),
      ]);
      Future<Attestation> sign(SimpleKeyPair by) => Attestation.sign(
        publisher: 'jp.city.a',
        key: other.pub,
        checked: '2026-11-26',
        method: 'official-website',
        signed: _t,
        signer: by,
      );
      expect(await Attestation.check((await sign(data.pair)).json, t), isNull);
      expect(
        await Attestation.check((await sign(att.pair)).json, t),
        isNotNull,
      );
    });

    test('status', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(att, [KeyScope.attestations]),
      ]);
      Future<PublisherStatus> sign(SimpleKeyPair by) => PublisherStatus.sign(
        publisher: 'lychnion',
        signed: _t,
        items: const {'jp.a': '1'},
        signer: by,
      );
      expect(
        await PublisherStatus.check((await sign(att.pair)).json, t),
        isNull,
      );
      expect(
        await PublisherStatus.check((await sign(data.pair)).json, t),
        isNotNull,
      );
    });
  });
}
