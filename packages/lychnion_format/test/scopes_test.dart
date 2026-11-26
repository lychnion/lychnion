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
    Object? raw(KeyStatement s) => jsonDecode(jsonEncode(s.json));
    Future<KeyStatement> revokeBy(
      ({String pub, SimpleKeyPair pair}) target,
      SimpleKeyPair by,
    ) => KeyStatement.revoke(
      publisher: 'lychnion',
      revoked: target.pub,
      by: by,
      signed: _t,
    );

    test('the root revokes a granted key it does not hold', () async {
      final g = await grant(data, [KeyScope.data]);
      final cut = await revokeBy(data, root.pair);
      expect(cut.by, root.pub);
      final t = base.withStatements([g, cut]);
      expect(t.keysOf('lychnion'), {root.pub});
      expect(t.isRevoked('lychnion', data.pub), isTrue);
    });

    test('a grant of keys is refused', () async {
      expect(() => grant(data, [KeyScope.keys]), throwsA(isA<ArgumentError>()));
      expect(
        () => grant(data, [KeyScope.data, KeyScope.keys]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a granted key grants and revokes nothing', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(data2, [KeyScope.data]),
        await revokeBy(data2, data.pair),
        await grant(other, [KeyScope.models], by: data.pair),
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: root.pub,
          by: data.pair,
          signed: _t,
        ),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, data.pub, data2.pub});
    });

    test('revoking the root drops the keys it granted', () async {
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

    test(
      'after a rotation the new root grants again; the old one cannot',
      () async {
        final r2 = await _key();
        final rotate = await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: root.pair,
          newKey: r2.pair,
          signed: _t,
        );
        final before = base.withStatements([
          await grant(data, [KeyScope.data]),
          rotate,
        ]);
        // The old root's grant lapsed.
        expect(before.keysOf('lychnion'), {root.pub, r2.pub});
        expect(before.currentRootsOf('lychnion'), {r2.pub});
        expect(before.rootChainOf('lychnion'), {root.pub, r2.pub});
        final again = before.withStatements([
          await grant(data, [KeyScope.data], by: r2.pair),
          await grant(data2, [KeyScope.data], by: root.pair),
        ]);
        expect(again.keysOf('lychnion'), {root.pub, r2.pub, data.pub});
        // Only the new root revokes it.
        expect(
          again
              .withStatements([await revokeBy(data, root.pair)])
              .keysOf('lychnion'),
          contains(data.pub),
        );
        expect(
          again
              .withStatements([await revokeBy(data, r2.pair)])
              .keysOf('lychnion'),
          {root.pub, r2.pub},
        );
      },
    );

    test('two roots: each revokes a key the other granted', () async {
      final b = await _key();
      final two = TrustedKeys({
        'lychnion': [root.pub, b.pub],
      });
      final t = two.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(data2, [KeyScope.data], by: b.pair),
        await grant(other, [KeyScope.data]),
        await grant(other, [KeyScope.data], by: b.pair),
        await revokeBy(data2, root.pair),
        await revokeBy(data, b.pair),
        await revokeBy(other, b.pair),
      ]);
      expect(t.keysOf('lychnion'), {root.pub, b.pub});
      // A root is never revoked by another.
      final r = two.withStatements([
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: b.pub,
          by: root.pair,
          signed: _t,
        ),
      ]);
      expect(r.keysOf('lychnion'), {root.pub, b.pub});
    });

    test('a granted key and its successor are revoked together', () async {
      final t = base.withStatements([
        await grant(data, [KeyScope.data]),
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: data.pair,
          newKey: data2.pair,
          signed: _t,
        ),
        await revokeBy(data, root.pair),
      ]);
      expect(t.keysOf('lychnion'), {root.pub});
    });

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

    test('flood from a granted key: the real revocation counts', () async {
      final known = base.withStatements([
        await grant(data, [KeyScope.data]),
      ]);
      final flood = <Object?>[];
      for (var i = 0; i < 60; i++) {
        final x = await _key();
        flood.add(raw(await grant(x, [KeyScope.models], by: data.pair)));
        flood.add(raw(await revokeBy(x, data.pair)));
      }
      final real = await revokeBy(data, root.pair);
      final got = await relevantStatements(known, [
        ...flood,
        raw(real),
      ], max: 10);
      expect(got, [real]);
      expect(known.withStatements(got).keysOf('lychnion'), {root.pub});
    });

    test('grants and revocations by a granted key or an old root are not '
        'verified', () async {
      final r2 = await _key();
      final known = base.withStatements([
        await grant(data, [KeyScope.data]),
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: root.pair,
          newKey: r2.pair,
          signed: _t,
        ),
        await grant(data, [KeyScope.data], by: r2.pair),
      ]);
      final forged = base64Url.encode(List.filled(64, 7)).replaceAll('=', '');
      // Well formed, badly signed: more than the bad-signature budget.
      final junk = [
        for (var i = 0; i < 40; i++) ...[
          for (final maker in [data.pub, root.pub])
            {
              'format': 1,
              'type': 'grant',
              'publisher': 'lychnion',
              'old': maker,
              'new': (await _key()).pub,
              'scope': ['data'],
              'signed': '$_t$i',
              'signature': forged,
              'new_signature': forged,
            },
          {
            'format': 1,
            'type': 'revoke',
            'publisher': 'lychnion',
            'old': data.pub,
            'by': root.pub,
            'signed': '$_t$i',
            'signature': forged,
          },
        ],
      ];
      // A real statement after them, checked like the rest of the list.
      final step = await KeyStatement.replace(
        publisher: 'lychnion',
        oldKey: data.pair,
        newKey: data2.pair,
        signed: _t,
      );
      final got = await relevantStatements(known, [...junk, raw(step)]);
      expect(got, [step], reason: 'no signature budget was spent');
    });

    test('a self-revocation counts past max', () async {
      final known = base.withStatements([
        await grant(data, [KeyScope.data]),
        await grant(data2, [KeyScope.data]),
      ]);
      // A granted key's chain: counted against max.
      var prev = data;
      final chain = <Object?>[];
      for (var i = 0; i < 5; i++) {
        final next = await _key();
        chain.add(
          raw(
            await KeyStatement.replace(
              publisher: 'lychnion',
              oldKey: prev.pair,
              newKey: next.pair,
              signed: _t,
            ),
          ),
        );
        prev = next;
      }
      final self = await KeyStatement.revoke(
        publisher: 'lychnion',
        key: data2.pair,
        signed: _t,
      );
      final got = await relevantStatements(known, [
        ...chain,
        raw(self),
      ], max: 2);
      expect(got.first, self);
      expect(got.length, 3);
    });

    test(
      'a granted key\'s chain does not block the root\'s rotation',
      () async {
        var prev = data;
        final chain = <KeyStatement>[];
        for (var i = 0; i < KeyStatement.maxReplacesPerPublisher; i++) {
          final next = await _key();
          chain.add(
            await KeyStatement.replace(
              publisher: 'lychnion',
              oldKey: prev.pair,
              newKey: next.pair,
              signed: _t,
            ),
          );
          prev = next;
        }
        final known = base.withStatements([
          await grant(data, [KeyScope.data]),
          ...chain,
        ]);
        final r2 = await _key();
        final rotate = await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: root.pair,
          newKey: r2.pair,
          signed: _t,
        );
        expect(await relevantStatements(known, [raw(rotate)]), [rotate]);
      },
    );

    test(
      'relevantStatements takes grants and revocations by the root',
      () async {
        final g = await grant(data, [KeyScope.data]);
        final cut = await revokeBy(data, root.pair);
        // As raw JSON from a catalog, in any order.
        final got = await relevantStatements(base, [raw(cut), raw(g)]);
        expect(got.toSet(), {g, cut});
        expect(KeyStatement.keepOrder([g.json, cut.json]), [1, 0]);
      },
    );

    test('a new root\'s grant waits for the rotation in the list', () async {
      final r2 = await _key();
      final g = await grant(data, [KeyScope.data], by: r2.pair);
      final rotate = await KeyStatement.replace(
        publisher: 'lychnion',
        oldKey: root.pair,
        newKey: r2.pair,
        signed: _t,
      );
      final got = await relevantStatements(base, [raw(g), raw(rotate)]);
      expect(got, [rotate, g]);
    });

    test('1000 junk statements cost little', () async {
      final known = base.withStatements([
        await grant(data, [KeyScope.data]),
      ]);
      final x = await _key();
      final one = raw(await grant(x, [KeyScope.data], by: data.pair));
      final strangers = await _key();
      final theirs = raw(
        await KeyStatement.revoke(
          publisher: 'lychnion',
          key: strangers.pair,
          signed: _t,
        ),
      );
      final junk = [
        for (var i = 0; i < 1000; i++)
          {...(i.isEven ? one : theirs)! as Map, 'signed': '$_t$i'},
      ];
      final sw = Stopwatch()..start();
      final got = await relevantStatements(known, junk);
      sw.stop();
      expect(got, isEmpty);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a key whose id clashes with a trusted one is not trusted', () async {
      final x = await _key();
      final y = await _key();
      // Ids made to clash: real ones need about 2^48 tries.
      String fakeId(String k) => k == root.pub || k == x.pub
          ? 'R'
          : (k == y.pub || k == data.pub ? 'Y' : k);
      final statements = [
        await grant(x, [KeyScope.data]),
        await grant(y, [KeyScope.data]),
        await grant(data, [KeyScope.data]),
        await grant(data2, [KeyScope.data]),
      ];
      final r = resolveKeys(
        'lychnion',
        [root.pub],
        statements,
        keyIdOf: fakeId,
      );
      // x would share the root's id, y and data each other's.
      expect(r.keys, {root.pub, data2.pub});
      // Once y is revoked, data no longer clashes with a trusted key.
      final after = resolveKeys(
        'lychnion',
        [root.pub],
        [...statements, await revokeBy(y, root.pair)],
        keyIdOf: fakeId,
      );
      expect(after.keys, {root.pub, data.pub, data2.pub});
    });
  });

  group('root caps', () {
    test('root grants are capped per publisher, and cheap', () async {
      final grants = [
        for (var i = 0; i < KeyStatement.maxRootGrantsPerPublisher + 20; i++)
          jsonDecode(
            jsonEncode((await grant(await _key(), [KeyScope.data])).json),
          ),
      ];
      final sw = Stopwatch()..start();
      final got = await relevantStatements(base, grants);
      sw.stop();
      expect(got, hasLength(KeyStatement.maxRootGrantsPerPublisher));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      // Counting those already known.
      final more = await relevantStatements(base.withStatements(got), [
        jsonDecode(
          jsonEncode((await grant(await _key(), [KeyScope.data])).json),
        ),
      ]);
      expect(more, isEmpty);
    });

    test('a root that granted the most keys can still revoke one', () async {
      final keys = [
        for (var i = 0; i < KeyStatement.maxRootGrantsPerPublisher; i++)
          await _key(),
      ];
      final grants = [
        for (final k in keys) await grant(k, [KeyScope.data]),
      ];
      final known = base.withStatements(grants);
      expect(known.keysOf('lychnion'), hasLength(keys.length + 1));
      // Grants and revocations are capped apart.
      final cut = await KeyStatement.revoke(
        publisher: 'lychnion',
        revoked: keys.first.pub,
        by: root.pair,
        signed: _t,
      );
      final got = await relevantStatements(known, [
        jsonDecode(jsonEncode(cut.json)),
      ]);
      expect(got, hasLength(1));
      expect(
        known.withStatements(got).isRevoked('lychnion', keys.first.pub),
        isTrue,
      );
    });

    test('an old root\'s grants don\'t use up the new root\'s cap', () async {
      final keys = [
        for (var i = 0; i < KeyStatement.maxRootGrantsPerPublisher; i++)
          await _key(),
      ];
      final k2 = await _key();
      final rotate = await KeyStatement.replace(
        publisher: 'lychnion',
        oldKey: root.pair,
        newKey: k2.pair,
        signed: _t,
      );
      final known = base.withStatements([
        for (final k in keys) await grant(k, [KeyScope.data]),
        rotate,
      ]);
      // The new root grants the everyday key again.
      final again = await grant(keys.first, [KeyScope.data], by: k2.pair);
      final got = await relevantStatements(known, [
        jsonDecode(jsonEncode(again.json)),
      ]);
      expect(got, hasLength(1));
    });

    test('the root\'s revocations are capped per publisher', () async {
      final keys = [
        for (var i = 0; i <= KeyStatement.maxRootRevokesByPerPublisher; i++)
          await _key(),
      ];
      final known = base.withStatements([
        for (final k in keys) await grant(k, [KeyScope.data]),
      ]);
      final cuts = [
        for (final k in keys)
          jsonDecode(
            jsonEncode(
              (await KeyStatement.revoke(
                publisher: 'lychnion',
                revoked: k.pub,
                by: root.pair,
                signed: _t,
              )).json,
            ),
          ),
      ];
      final got = await relevantStatements(known, cuts);
      expect(got, hasLength(KeyStatement.maxRootRevokesByPerPublisher));
    });

    test('a granted key clashing with a rotated root loses', () async {
      final k2 = await _key();
      final g2 = await _key();
      String fakeId(String k) => k == k2.pub || k == g2.pub ? 'K' : k;
      final statements = [
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: root.pair,
          newKey: k2.pair,
          signed: _t,
        ),
        await grant(data, [KeyScope.data], by: k2.pair),
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: data.pair,
          newKey: g2.pair,
          signed: _t,
        ),
      ];
      final r = resolveKeys(
        'lychnion',
        [root.pub],
        statements,
        keyIdOf: fakeId,
      );
      expect(r.keys, {root.pub, k2.pub, data.pub});
      expect(r.currentRoots, {k2.pub});
    });
  });

  group('kept first', () {
    test('the root\'s rotation survives a flood in catalogs', () async {
      final known = base.withStatements([
        await grant(data, [KeyScope.data]),
      ]);
      final junk = [
        for (var i = 0; i < KeyStatement.maxPerSource; i++)
          await KeyStatement.revoke(
            publisher: 'lychnion',
            revoked: data2.pub,
            by: data.pair,
            signed: '$_t$i',
          ),
      ];
      final r2 = await _key();
      final rotate = await KeyStatement.replace(
        publisher: 'lychnion',
        oldKey: root.pair,
        newKey: r2.pair,
        signed: _t,
      );
      final doc = CatalogDocument.byHash(
        const [],
        trust: known,
        keys: [...junk, rotate],
      );
      expect(doc.keys, contains(rotate.json));
      expect(doc.keys.length, KeyStatement.maxPerSource);
      // Without the keys, revocations by another key come first.
      expect(
        CatalogDocument.byHash(const [], keys: [...junk, rotate]).keys,
        isNot(contains(rotate.json)),
      );
      // Also once the rotation is known: a replacement within the root
      // chain.
      final later = known.withStatements([rotate]);
      final order = KeyStatement.keepOrder([
        for (final s in [...junk, rotate]) s.json,
      ], trust: later);
      expect(order.first, junk.length);
      // fitted: only a few fit next to a large record.
      final tight = CatalogDocument(
        records: ['x' * (CatalogDocument.maxBytes - 1500)],
        keys: [
          for (final s in [...junk.take(5), rotate]) s.json,
        ],
      );
      expect(tight.fitted(trust: known).keys, contains(rotate.json));
      expect(tight.fitted().keys, isNot(contains(rotate.json)));
    });
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
