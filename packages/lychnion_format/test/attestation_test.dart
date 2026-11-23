import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

// lychnion/lychnion#119: attestations signed by Lychnion label official
// publishers; they never change what may be published.

Future<({String pub, SimpleKeyPair pair})> _key() async {
  final k = await newKeyPair();
  return (pub: k.publicKey, pair: await keyPairFromSeed(k.seed));
}

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// [j] signed again with [pair] as it is: a shape rule must refuse it,
/// not the signature.
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
    });
  });

  Future<Attestation> attestation({
    String publisher = 'jp.city.sendai',
    String? key,
    SimpleKeyPair? by,
    String signed = '2026-11-23T14:00:00+09:00',
    bool withdrawn = false,
    String? url = 'https://www.city.sendai.jp/key.html',
  }) => Attestation.sign(
    publisher: publisher,
    key: key ?? city.pub,
    checked: '2026-11-23',
    method: 'official-website',
    signed: signed,
    signer: by ?? lychnion.pair,
    title: const {'ja': '仙台市', 'en': 'Sendai City'},
    url: url,
    withdrawn: withdrawn,
  );

  // Through JSON, as from a catalog.
  Map<String, Object?> wire(Attestation v) =>
      (jsonDecode(jsonEncode(v.json)) as Map).cast<String, Object?>();

  group('check', () {
    test('an attestation signed by Lychnion is valid', () async {
      final v = await Attestation.check(wire(await attestation()), trust);
      expect(v, isNotNull);
      expect(v!.publisher, 'jp.city.sendai');
      expect(v.title['ja'], '仙台市');
      expect(v.withdrawn, isFalse);
    });

    test('an attestation signed by any other key is not', () async {
      final forged = await attestation(by: other.pair);
      expect(await Attestation.check(wire(forged), trust), isNull);
      // Not even by a publisher the device trusts for its own records.
      final withCity = trust.plus({
        'jp.city.sendai': [city.pub],
      });
      final self = await attestation(by: city.pair);
      expect(await Attestation.check(wire(self), withCity), isNull);
    });

    test('a changed field breaks the signature', () async {
      final j = wire(await attestation())..['publisher'] = 'jp.city.kobe';
      expect(await Attestation.check(j, trust), isNull);
    });

    test('follows Lychnion key statements', () async {
      final next = await _key();
      final replace = await KeyStatement.replace(
        publisher: attesterPublisher,
        oldKey: lychnion.pair,
        newKey: next.pair,
        signed: '2026-11-24',
      );
      final byNext = wire(await attestation(by: next.pair));
      expect(await Attestation.check(byNext, trust), isNull);
      expect(
        await Attestation.check(byNext, trust.withStatements([replace])),
        isNotNull,
      );
      // A revoked Lychnion key's attestations lapse.
      final old = wire(await attestation());
      final revoke = await KeyStatement.revoke(
        publisher: attesterPublisher,
        key: lychnion.pair,
        signed: '2026-11-24',
      );
      expect(
        await Attestation.check(old, trust.withStatements([revoke])),
        isNull,
      );
    });

    test('shape rules refuse even a correctly signed attestation', () async {
      final good = wire(await attestation());
      Future<Attestation?> signedAs(
        void Function(Map<String, Object?>) change,
      ) async {
        final j = Map<String, Object?>.of(good);
        change(j);
        return Attestation.check(await _resigned(j, lychnion.pair), trust);
      }

      // The helper itself: unchanged, it passes.
      expect(await signedAs((_) {}), isNotNull);
      final refused = <String, void Function(Map<String, Object?>)>{
        'an unknown field': (j) => j['extra'] = 'x',
        'another format': (j) => j['format'] = 2,
        'a key spelled with padding': (j) => j['key'] = '${j['key']}=',
        'a signer spelled with padding': (j) => j['signer'] = '${j['signer']}=',
        'a day in another form': (j) => j['checked'] = '23 Nov 2026',
        'a day that does not exist': (j) => j['checked'] = '2026-02-31',
        'a method with capitals': (j) => j['method'] = 'Official Website',
        'an http address': (j) => j['url'] = 'http://www.city.sendai.jp/',
        'a user before the host': (j) =>
            j['url'] = 'https://city.sendai.jp@evil.example/',
        'a port': (j) => j['url'] = 'https://www.city.sendai.jp:8443/',
        'a space in the address': (j) =>
            j['url'] = 'https://www.city.sendai.jp/a b',
        'withdrawn: false': (j) => j['withdrawn'] = false,
        "Lychnion's own name": (j) => j['publisher'] = attesterPublisher,
        'a direction mark in the title': (j) =>
            j['title'] = {'ja': '仙台\u202e市'},
        'a word joiner in the title': (j) => j['title'] = {'ja': '仙台\u2060市'},
        'a Hangul filler in the title': (j) => j['title'] = {'ja': '\u3164仙台市'},
        'a long title': (j) => j['title'] = {'ja': 'あ' * 61},
        'a blank title': (j) => j['title'] = {'ja': '  '},
        'a language that is not a code': (j) =>
            j['title'] = {'japanese': '仙台市'},
        'five languages': (j) => j['title'] = {
          for (final l in ['ja', 'en', 'fr', 'de', 'es']) l: '仙台市',
        },
        'a time in words': (j) => j['signed'] = 'yesterday',
        'a time without a zone': (j) => j['signed'] = '2026-11-23T14:00:00',
        'a date without a time': (j) => j['signed'] = '2026-11-23',
        'a time far in the future': (j) => j['signed'] = '9999-12-31T23:59:59Z',
        'a month that does not exist': (j) =>
            j['signed'] = '2026-13-45T00:00:00Z',
      };
      for (final e in refused.entries) {
        expect(await signedAs(e.value), isNull, reason: e.key);
      }
      // Japanese spaces are ordinary text.
      expect(
        await signedAs((j) => j['title'] = {'ja': '仙台市　危機管理局'}),
        isNotNull,
      );
    });

    test('sign refuses what check would refuse', () async {
      expect(
        () => attestation(url: 'http://www.city.sendai.jp/'),
        throwsArgumentError,
      );
      expect(
        () => attestation(signed: '9999-12-31T23:59:59Z'),
        throwsArgumentError,
      );
    });

    test(
      'a checked attestation does not change with the map it came from',
      () async {
        final j = wire(await attestation());
        final v = (await Attestation.check(j, trust))!;
        final id = v.id;
        (j['title']! as Map)['ja'] = '別の市';
        expect(v.id, id);
        expect(v.title['ja'], '仙台市');
      },
    );

    test('checkAll keeps each valid attestation once, at most max', () async {
      final a = await attestation();
      final b = await attestation(publisher: 'jp.city.kobe', key: other.pub);
      final forged = await attestation(by: other.pair);
      final got = await Attestation.checkAll([
        wire(a),
        wire(a),
        'x',
        wire(forged),
        wire(b),
      ], trust);
      expect(got, [a, b]);
      expect(await Attestation.checkAll([wire(a), wire(b)], trust, max: 1), [
        a,
      ]);
      expect(await Attestation.checkAll({'not': 'a list'}, trust), isEmpty);
    });

    test('checkAll stops after maxBadSignatures wrong signatures', () async {
      final good = await attestation();
      // Lychnion's key named, but signatures that do not match: each costs
      // a check. Each one different, so none is skipped as a repeat.
      final flood = [
        for (var i = 0; i < Attestation.maxBadSignatures; i++)
          wire(await attestation(publisher: 'jp.city.c$i'))
            ..['signature'] = _b64(List.filled(64, i)),
      ];
      expect(
        await Attestation.checkAll([...flood, wire(good)], trust),
        isEmpty,
      );
      expect(
        await Attestation.checkAll([...flood.skip(1), wire(good)], trust),
        [good],
      );
      // The same bad entry many times counts once.
      final same = List.filled(100, flood.first);
      expect(await Attestation.checkAll([...same, wire(good)], trust), [good]);
    });
  });

  group('attestationFor', () {
    test('the attested key, another key, and no attestation', () async {
      final v = await attestation();
      expect(
        attestationFor('jp.city.sendai', city.pub, [v], []).status,
        AttestationStatus.attested,
      );
      // The same name with another key: not the attested-for publisher.
      expect(
        attestationFor('jp.city.sendai', other.pub, [v], []).status,
        AttestationStatus.otherKey,
      );
      expect(
        attestationFor('jp.club.hiking', other.pub, [v], []).status,
        AttestationStatus.none,
      );
    });

    test("follows the publisher's own key statements", () async {
      final v = await attestation();
      final next = await _key();
      final replace = await KeyStatement.replace(
        publisher: 'jp.city.sendai',
        oldKey: city.pair,
        newKey: next.pair,
        signed: '2026-11-24',
      );
      // The attested key's successor.
      expect(
        attestationFor('jp.city.sendai', next.pub, [v], [replace]).status,
        AttestationStatus.attested,
      );
      // A key the attested key replaced: Lychnion attested its successor.
      final onNext = await attestation(key: next.pub);
      expect(
        attestationFor('jp.city.sendai', city.pub, [onNext], [replace]).status,
        AttestationStatus.attested,
      );
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: city.pair,
        signed: '2026-11-24',
      );
      expect(
        attestationFor('jp.city.sendai', city.pub, [v], [revoke]).status,
        AttestationStatus.revoked,
      );
    });

    test('the newest attestation for a name decides', () async {
      final first = await attestation();
      final back = await attestation(
        signed: '2026-12-01T09:00:00+09:00',
        withdrawn: true,
      );
      final again = await attestation(signed: '2027-01-10T09:00:00+09:00');
      expect(
        attestationFor('jp.city.sendai', city.pub, [first, back], []).status,
        AttestationStatus.withdrawn,
      );
      // In any order.
      expect(
        attestationFor('jp.city.sendai', city.pub, [back, first], []).status,
        AttestationStatus.withdrawn,
      );
      expect(
        attestationFor('jp.city.sendai', city.pub, [
          again,
          first,
          back,
        ], []).status,
        AttestationStatus.attested,
      );
      // On the same time a withdrawal wins.
      final sameTime = await attestation(withdrawn: true);
      expect(
        attestationFor('jp.city.sendai', city.pub, [
          first,
          sameTime,
        ], []).status,
        AttestationStatus.withdrawn,
      );
      // A time in another zone is the same moment.
      final utc = await attestation(
        signed: '2026-11-23T05:00:00Z',
        withdrawn: true,
      );
      expect(
        attestationFor('jp.city.sendai', city.pub, [utc, first], []).status,
        AttestationStatus.withdrawn,
      );
    });

    test(
      'two attestations at the same time decide the same in any order',
      () async {
        final a = await attestation();
        final b = await attestation(key: other.pub);
        final ab = attestationFor('jp.city.sendai', city.pub, [a, b], []);
        final ba = attestationFor('jp.city.sendai', city.pub, [b, a], []);
        expect(ab.status, ba.status);
        expect(ab.attestation, ba.attestation);
      },
    );
  });

  group('catalog', () {
    test('attestations travel in a catalog and older fields stay', () async {
      final v = await attestation();
      final c = CatalogDocument(records: const [], attestations: [v.json]);
      final back = CatalogDocument.parse(c.encode());
      expect(await Attestation.checkAll(back.attestations, trust), [v]);
      // A catalog without them, or with the wrong type, reads as before.
      expect(
        CatalogDocument.parse('{"format":2,"records":[]}').attestations,
        isEmpty,
      );
      expect(
        CatalogDocument.parse(
          '{"format":2,"records":[],"attestations":"x"}',
        ).attestations,
        isEmpty,
      );
      expect(
        jsonDecode(CatalogDocument(records: const []).encode()),
        isNot(contains('attestations')),
      );
    });

    test('capped keeps what decides: withdrawals, then the newest', () async {
      final many = [
        for (var i = 0; i < 3; i++)
          await attestation(
            publisher: 'jp.city.c$i',
            signed: '2026-11-2${i}T00:00:00Z',
          ),
      ];
      final back = await attestation(
        publisher: 'jp.city.c0',
        signed: '2026-11-25T00:00:00Z',
        withdrawn: true,
      );
      final kept = Attestation.capped([...many, back], 2);
      expect(kept, [many[2], back]);
      // A withdrawal a newer attestation replaced changes nothing: it goes first.
      final oldBack = await attestation(
        publisher: 'jp.city.c1',
        signed: '2026-11-01T00:00:00Z',
        withdrawn: true,
      );
      expect(Attestation.capped([oldBack, many[1], many[2]], 2), [
        many[1],
        many[2],
      ]);
      // byHash: each once.
      final c = CatalogDocument.byHash(
        const [],
        attestations: [...many, many[0]],
      );
      expect(c.attestations, hasLength(3));
    });

    test('fitted leaves attestations out before key statements', () async {
      final keep = await attestation(withdrawn: true);
      final v = await attestation(publisher: 'jp.city.kobe', key: other.pub);
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: city.pair,
        signed: '2026-11-24',
      );
      int size(CatalogDocument c) => utf8.encode(c.encode()).length;
      String filler(int bytes) => 'x' * bytes;
      // Just over the limit with one attestation too many.
      final base = CatalogDocument(records: const [], keys: [revoke.json]);
      final attestationBytes = utf8.encode(jsonEncode(v.json)).length;
      var c = CatalogDocument(
        records: [
          filler(
            CatalogDocument.maxBytes - size(base) - attestationBytes - 200,
          ),
        ],
        keys: [revoke.json],
        attestations: [v.json, keep.json],
      );
      var f = c.fitted();
      expect(f.keys, [revoke.json]);
      expect(f.attestations, [keep.json]);
      expect(CatalogDocument.attestationsLeftOut([v, keep], f), 1);
      expect(size(f), lessThanOrEqualTo(CatalogDocument.maxBytes));
      // So full that key statements must go too: then no attestation is left.
      final bare = CatalogDocument(records: const []);
      c = CatalogDocument(
        records: [filler(CatalogDocument.maxBytes - size(bare) - 20)],
        keys: [revoke.json],
        attestations: [v.json, keep.json],
      );
      f = c.fitted();
      expect(f.attestations, isEmpty);
      expect(f.keys, isEmpty);
      // Records alone too large: no reader would take it.
      expect(
        () => CatalogDocument(
          records: [filler(CatalogDocument.maxBytes)],
          attestations: [v.json],
        ).fitted(),
        throwsA(isA<CatalogTooLarge>()),
      );
    });
  });
}
