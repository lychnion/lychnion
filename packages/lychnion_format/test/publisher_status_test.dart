import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

// lychnion/lychnion#117: a publisher's signed status says what is newest
// from it, so a phone can tell when a carrier held something back. It never
// stops anything from working.

Future<({String pub, SimpleKeyPair pair})> _key() async {
  final k = await newKeyPair();
  return (pub: k.publicKey, pair: await keyPairFromSeed(k.seed));
}

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// [j] signed again with [pair] as it is: a shape rule must refuse it, not
/// the signature.
Future<Map<String, Object?>> _resigned(
  Map<String, Object?> j,
  SimpleKeyPair pair,
) async {
  final out = Map<String, Object?>.of(j)..remove('signature');
  final sig = await Ed25519().sign(
    utf8.encode(canonicalJson(out)),
    keyPair: pair,
  );
  return out..['signature'] = _b64(sig.bytes);
}

void main() {
  late ({String pub, SimpleKeyPair pair}) lychnion, city, other;
  late TrustedKeys trust;

  setUp(() async {
    lychnion = await _key();
    city = await _key();
    other = await _key();
    trust = TrustedKeys({
      attesterPublisher: [lychnion.pub],
      'jp.city.sendai': [city.pub],
    });
  });

  Future<PublisherStatus> status({
    String publisher = attesterPublisher,
    SimpleKeyPair? by,
    String signed = '2026-11-24T09:00:00+09:00',
    Map<String, String> items = const {'jp.bousai.core': '2026.11.10'},
    Iterable<KeyStatement> keys = const [],
    Iterable<Attestation> attestations = const [],
  }) => PublisherStatus.sign(
    publisher: publisher,
    signed: signed,
    items: items,
    signer: by ?? lychnion.pair,
    keys: keys,
    attestations: attestations,
  );

  group('check', () {
    test('a status signed by a key trusted for its publisher', () async {
      final s = await status();
      final back = await PublisherStatus.check(
        jsonDecode(jsonEncode(s.json)),
        trust,
      );
      expect(back, s);
      expect(back!.items, {'jp.bousai.core': '2026.11.10'});
      expect(back.publisher, attesterPublisher);
      final c = await status(publisher: 'jp.city.sendai', by: city.pair);
      expect(await PublisherStatus.check(c.json, trust), c);
    });

    test('another key, or another publisher\'s key, does not count', () async {
      expect(
        await PublisherStatus.check((await status(by: other.pair)).json, trust),
        isNull,
      );
      // The city's key may not sign Lychnion's status, nor the other way.
      expect(
        await PublisherStatus.check((await status(by: city.pair)).json, trust),
        isNull,
      );
      expect(
        await PublisherStatus.check(
          (await status(publisher: 'jp.city.sendai')).json,
          trust,
        ),
        isNull,
      );
    });

    test('a changed status fails its signature', () async {
      final j = Map<String, Object?>.of((await status()).json);
      j['items'] = {'jp.bousai.core': '2026.11.1'};
      expect(await PublisherStatus.check(j, trust), isNull);
    });

    test('a successor key may sign, with the statement inside', () async {
      final next = await _key();
      final s = await KeyStatement.replace(
        publisher: attesterPublisher,
        oldKey: lychnion.pair,
        newKey: next.pair,
        signed: '2026-11-24T08:00:00+09:00',
      );
      final st = await status(by: next.pair, keys: [s]);
      expect(await PublisherStatus.check(st.json, trust), st);
      expect(st.keys, hasLength(1));
      // Without the statement, the new key is not known.
      expect(
        await PublisherStatus.check((await status(by: next.pair)).json, trust),
        isNull,
      );
    });

    test('shape rules', () async {
      Future<Object?> bad(void Function(Map<String, Object?>) change) async {
        final j = Map<String, Object?>.of((await status()).json);
        change(j);
        return PublisherStatus.check(await _resigned(j, lychnion.pair), trust);
      }

      expect(await bad((j) => j['format'] = 2), isNull);
      expect(await bad((j) => j['extra'] = 1), isNull);
      expect(await bad((j) => j['signed'] = '2026-11-24'), isNull);
      expect(await bad((j) => j['signed'] = '2999-01-01T00:00:00Z'), isNull);
      expect(await bad((j) => j['items'] = ['x']), isNull);
      expect(await bad((j) => j['items'] = {'id with space': '1'}), isNull);
      expect(await bad((j) => j['items'] = {'x': 1}), isNull);
      expect(await bad((j) => j['keys'] = ['not a map']), isNull);
      // Only withdrawals, and only in Lychnion's status.
      expect(
        await bad(
          (j) => j['attestations'] = [
            {'withdrawn': false},
          ],
        ),
        isNull,
      );
      final city0 =
          Map<String, Object?>.of(
              (await status(publisher: 'jp.city.sendai', by: city.pair)).json,
            )
            ..['attestations'] = [
              {'withdrawn': true},
            ];
      expect(
        await PublisherStatus.check(await _resigned(city0, city.pair), trust),
        isNull,
      );
      // Too many items.
      expect(
        await bad(
          (j) => j['items'] = {
            for (var i = 0; i <= PublisherStatus.maxItems; i++) 'i$i': '1',
          },
        ),
        isNull,
      );
    });

    test('carries withdrawals; sign refuses a positive attestation', () async {
      final gone = await Attestation.sign(
        publisher: 'jp.city.sendai',
        key: city.pub,
        checked: '2026-11-23',
        method: 'official-website',
        signed: '2026-11-24T08:00:00+09:00',
        signer: lychnion.pair,
        withdrawn: true,
      );
      final st = await status(attestations: [gone]);
      final back = await PublisherStatus.check(st.json, trust);
      expect(await Attestation.checkAll(back!.attestations, trust), [gone]);
      final kept = await Attestation.sign(
        publisher: 'jp.city.sendai',
        key: city.pub,
        checked: '2026-11-23',
        method: 'official-website',
        signed: '2026-11-24T08:00:00+09:00',
        signer: lychnion.pair,
      );
      await expectLater(status(attestations: [kept]), throwsArgumentError);
    });

    test(
      'inline statements: only relevant ones, only for its signer',
      () async {
        final thief = await _key();
        final thief2 = await _key();
        // A statement made by an untrusted key, naming the signer as new:
        // not taken.
        final own = await KeyStatement.replace(
          publisher: attesterPublisher,
          oldKey: thief.pair,
          newKey: thief2.pair,
          signed: '2026-11-24T08:00:00+09:00',
        );
        expect(
          await PublisherStatus.check(
            (await status(by: thief2.pair, keys: [own])).json,
            trust,
          ),
          isNull,
        );
        // Another publisher's statements in the status: refused by shape.
        final cityNext = await _key();
        final cityS = await KeyStatement.replace(
          publisher: 'jp.city.sendai',
          oldKey: city.pair,
          newKey: cityNext.pair,
          signed: '2026-11-24T08:00:00+09:00',
        );
        await expectLater(status(keys: [cityS]), throwsArgumentError);
      },
    );

    test('items: ids and versions as records have them', () async {
      for (final items in [
        {'a': 'latest!'},
        {'a': 'v1'},
        {'../x': '1'},
        {'x.': '1'},
      ]) {
        await expectLater(
          status(items: items),
          throwsArgumentError,
          reason: '$items',
        );
      }
      // A version here that is not a number never throws.
      expect((await status()).hasNewer('jp.bousai.core', 'dev'), isFalse);
    });

    test('a caller cannot change a status afterwards', () async {
      final items = {'a': '1'};
      final s = await status(items: items);
      items['a'] = '2';
      expect(s.items['a'], '1');
      expect(
        () => (s.json['items']! as Map)['a'] = '3',
        throwsUnsupportedError,
      );
      final next = await _key();
      final st = await status(
        by: next.pair,
        keys: [
          await KeyStatement.replace(
            publisher: attesterPublisher,
            oldKey: lychnion.pair,
            newKey: next.pair,
            signed: '2026-11-24T08:00:00+09:00',
          ),
        ],
      );
      final id = st.id;
      expect(
        () => (st.keys.first! as Map)['signed'] = 'x',
        throwsUnsupportedError,
      );
      expect(st.id, id);
    });
  });

  group('newest and hasNewer', () {
    test('the newest of each publisher decides', () async {
      final old = await status(signed: '2026-11-01T00:00:00Z');
      final now = await status(signed: '2026-11-24T00:00:00Z');
      final c = await status(publisher: 'jp.city.sendai', by: city.pair);
      expect(PublisherStatus.newest([now, c, old]), [now, c]);
      expect(now.decidesOver(old), isTrue);
      expect(old.decidesOver(now), isFalse);
      // The same time: the same one on every device, whatever the order.
      final a = await status(items: const {'x': '1'});
      final b = await status(items: const {'x': '2'});
      expect(a.decidesOver(b), isNot(b.decidesOver(a)));
      expect(PublisherStatus.newest([a, b]), PublisherStatus.newest([b, a]));
    });

    test('a newer version than the one here', () async {
      final s = await status();
      expect(s.hasNewer('jp.bousai.core', '2026.11.2'), isTrue);
      expect(s.hasNewer('jp.bousai.core', '2026.11.10'), isFalse);
      expect(s.hasNewer('jp.bousai.core', '2026.12.1'), isFalse);
      expect(s.hasNewer('jp.other', '1'), isFalse);
    });
  });

  test(
    'checkAll: each once, bad ones left out, stops after bad signatures',
    () async {
      final s = await status();
      final forged = Map<String, Object?>.of(s.json)
        ..['items'] = {'jp.bousai.core': '1'};
      expect(
        await PublisherStatus.checkAll([s.json, s.json, forged, 'x'], trust),
        [s],
      );
      // Distinct forgeries (each costs a check), then a valid one: not read.
      final distinct = [
        for (var i = 0; i < PublisherStatus.maxBadSignatures; i++)
          Map<String, Object?>.of(forged)..['items'] = {'jp.bousai.core': '$i'},
      ];
      expect(
        await PublisherStatus.checkAll([...distinct, s.json], trust),
        isEmpty,
      );
    },
  );

  group('catalog', () {
    test(
      'status travels in a catalog and is kept last when too large',
      () async {
        final st = await status();
        final doc = CatalogDocument.byHash(
          const [],
          status: [
            await status(signed: '2026-11-01T00:00:00Z'),
            st,
          ],
        );
        expect(doc.status, [st.json]);
        final back = CatalogDocument.parse(doc.encode());
        expect(await PublisherStatus.checkAll(back.status, trust), [st]);
        // Older readers' catalogs without it parse as before.
        expect(
          CatalogDocument.parse('{"format": 2, "records": []}').status,
          isEmpty,
        );
        // Over 2 MB: attestations go, then key statements; status stays.
        final big = CatalogDocument(
          records: const [],
          attestations: [
            for (var i = 0; i < 4000; i++) {'pad': 'x' * 600, 'i': i},
          ],
          status: [st.json],
        );
        final fitted = big.fitted();
        expect(fitted.status, [st.json]);
        expect(fitted.attestations.length, lessThan(4000));
      },
    );

    test('byHash: at most 100, Lychnion\'s kept, the same text', () async {
      final others = [
        for (var i = 0; i < PublisherStatus.maxPerSource; i++)
          await status(publisher: 'org.p$i', by: city.pair),
      ];
      // The city's key signs them all here; byHash does not check.
      final mine = await status();
      final doc = CatalogDocument.byHash(const [], status: [...others, mine]);
      expect(doc.status, hasLength(PublisherStatus.maxPerSource));
      expect(doc.status, contains(mine.json));
      expect(CatalogDocument.statusLeftOut([...others, mine], doc), 1);
      final again = CatalogDocument.byHash(
        const [],
        status: [mine, ...others.reversed],
      );
      expect(again.encode(), doc.encode());
    });

    test('fitted trims statuses last, Lychnion\'s first kept', () async {
      final padded = [
        for (var i = 0; i < 6; i++)
          await status(
            publisher: 'org.p$i',
            by: city.pair,
            items: {for (var k = 0; k < 1000; k++) 'item$k': '2026.11.$k'},
          ),
      ];
      final mine = await status();
      final pad = 'x' * 320000;
      final big = CatalogDocument(
        records: [
          {'pad': pad},
          {'pad': pad},
          {'pad': pad},
          {'pad': pad},
          {'pad': pad},
          {'pad': pad},
        ],
        status: [for (final p in padded) p.json, mine.json],
      );
      final fitted = big.fitted();
      expect(fitted.status.length, lessThan(7));
      expect(fitted.status, contains(mine.json));
    });

    test('keepOrder: the same tie rule as decidesOver', () async {
      final a = await status(items: const {'x': '1'});
      final b = await status(items: const {'x': '2'});
      final winner = a.decidesOver(b) ? a : b;
      expect(
        PublisherStatus.keepOrder([a.json, b.json]).first,
        winner == a ? 0 : 1,
      );
      expect(
        PublisherStatus.keepOrder([b.json, a.json]).first,
        winner == b ? 0 : 1,
      );
    });

    test('keepOrder: Lychnion\'s newest first', () async {
      final c = await status(publisher: 'jp.city.sendai', by: city.pair);
      final old = await status(signed: '2026-11-01T00:00:00Z');
      final now = await status();
      final order = PublisherStatus.keepOrder([c.json, old.json, now.json, 1]);
      expect(order, [2, 0, 1, 3]);
    });
  });
}
