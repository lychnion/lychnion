import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

// lychnion/lychnion#119: vouches signed by Lychnion label official
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
      voucherPublisher: [lychnion.pub],
    });
  });

  Future<Vouch> vouch({
    String publisher = 'jp.city.sendai',
    String? key,
    SimpleKeyPair? by,
    String signed = '2026-11-23T14:00:00+09:00',
    bool withdrawn = false,
    String? url = 'https://www.city.sendai.jp/key.html',
  }) => Vouch.sign(
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
  Map<String, Object?> wire(Vouch v) =>
      (jsonDecode(jsonEncode(v.json)) as Map).cast<String, Object?>();

  group('check', () {
    test('a vouch signed by Lychnion is valid', () async {
      final v = await Vouch.check(wire(await vouch()), trust);
      expect(v, isNotNull);
      expect(v!.publisher, 'jp.city.sendai');
      expect(v.title['ja'], '仙台市');
      expect(v.withdrawn, isFalse);
    });

    test('a vouch signed by any other key is not', () async {
      final forged = await vouch(by: other.pair);
      expect(await Vouch.check(wire(forged), trust), isNull);
      // Not even by a publisher the device trusts for its own records.
      final withCity = trust.plus({
        'jp.city.sendai': [city.pub],
      });
      final self = await vouch(by: city.pair);
      expect(await Vouch.check(wire(self), withCity), isNull);
    });

    test('a changed field breaks the signature', () async {
      final j = wire(await vouch())..['publisher'] = 'jp.city.kobe';
      expect(await Vouch.check(j, trust), isNull);
    });

    test('follows Lychnion key statements', () async {
      final next = await _key();
      final replace = await KeyStatement.replace(
        publisher: voucherPublisher,
        oldKey: lychnion.pair,
        newKey: next.pair,
        signed: '2026-11-24',
      );
      final byNext = wire(await vouch(by: next.pair));
      expect(await Vouch.check(byNext, trust), isNull);
      expect(
        await Vouch.check(byNext, trust.withStatements([replace])),
        isNotNull,
      );
      // A revoked Lychnion key's vouches lapse.
      final old = wire(await vouch());
      final revoke = await KeyStatement.revoke(
        publisher: voucherPublisher,
        key: lychnion.pair,
        signed: '2026-11-24',
      );
      expect(await Vouch.check(old, trust.withStatements([revoke])), isNull);
    });

    test('shape rules refuse even a correctly signed vouch', () async {
      final good = wire(await vouch());
      Future<Vouch?> signedAs(
        void Function(Map<String, Object?>) change,
      ) async {
        final j = Map<String, Object?>.of(good);
        change(j);
        return Vouch.check(await _resigned(j, lychnion.pair), trust);
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
        "Lychnion's own name": (j) => j['publisher'] = voucherPublisher,
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
        () => vouch(url: 'http://www.city.sendai.jp/'),
        throwsArgumentError,
      );
      expect(() => vouch(signed: '9999-12-31T23:59:59Z'), throwsArgumentError);
    });

    test('a checked vouch does not change with the map it came from', () async {
      final j = wire(await vouch());
      final v = (await Vouch.check(j, trust))!;
      final id = v.id;
      (j['title']! as Map)['ja'] = '別の市';
      expect(v.id, id);
      expect(v.title['ja'], '仙台市');
    });

    test('checkAll keeps each valid vouch once, at most max', () async {
      final a = await vouch();
      final b = await vouch(publisher: 'jp.city.kobe', key: other.pub);
      final forged = await vouch(by: other.pair);
      final got = await Vouch.checkAll([
        wire(a),
        wire(a),
        'x',
        wire(forged),
        wire(b),
      ], trust);
      expect(got, [a, b]);
      expect(await Vouch.checkAll([wire(a), wire(b)], trust, max: 1), [a]);
      expect(await Vouch.checkAll({'not': 'a list'}, trust), isEmpty);
    });

    test('checkAll stops after maxBadSignatures wrong signatures', () async {
      final good = await vouch();
      // Lychnion's key named, but signatures that do not match: each costs
      // a check. Each one different, so none is skipped as a repeat.
      final flood = [
        for (var i = 0; i < Vouch.maxBadSignatures; i++)
          wire(await vouch(publisher: 'jp.city.c$i'))
            ..['signature'] = _b64(List.filled(64, i)),
      ];
      expect(await Vouch.checkAll([...flood, wire(good)], trust), isEmpty);
      expect(await Vouch.checkAll([...flood.skip(1), wire(good)], trust), [
        good,
      ]);
      // The same bad entry many times counts once.
      final same = List.filled(100, flood.first);
      expect(await Vouch.checkAll([...same, wire(good)], trust), [good]);
    });
  });

  group('vouchFor', () {
    test('the vouched key, another key, and no vouch', () async {
      final v = await vouch();
      expect(
        vouchFor('jp.city.sendai', city.pub, [v], []).status,
        VouchStatus.vouched,
      );
      // The same name with another key: not the vouched-for publisher.
      expect(
        vouchFor('jp.city.sendai', other.pub, [v], []).status,
        VouchStatus.otherKey,
      );
      expect(
        vouchFor('jp.club.hiking', other.pub, [v], []).status,
        VouchStatus.none,
      );
    });

    test("follows the publisher's own key statements", () async {
      final v = await vouch();
      final next = await _key();
      final replace = await KeyStatement.replace(
        publisher: 'jp.city.sendai',
        oldKey: city.pair,
        newKey: next.pair,
        signed: '2026-11-24',
      );
      // The vouched key's successor.
      expect(
        vouchFor('jp.city.sendai', next.pub, [v], [replace]).status,
        VouchStatus.vouched,
      );
      // A key the vouched key replaced: Lychnion vouched for its successor.
      final onNext = await vouch(key: next.pub);
      expect(
        vouchFor('jp.city.sendai', city.pub, [onNext], [replace]).status,
        VouchStatus.vouched,
      );
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: city.pair,
        signed: '2026-11-24',
      );
      expect(
        vouchFor('jp.city.sendai', city.pub, [v], [revoke]).status,
        VouchStatus.revoked,
      );
    });

    test('the newest vouch for a name decides', () async {
      final first = await vouch();
      final back = await vouch(
        signed: '2026-12-01T09:00:00+09:00',
        withdrawn: true,
      );
      final again = await vouch(signed: '2027-01-10T09:00:00+09:00');
      expect(
        vouchFor('jp.city.sendai', city.pub, [first, back], []).status,
        VouchStatus.withdrawn,
      );
      // In any order.
      expect(
        vouchFor('jp.city.sendai', city.pub, [back, first], []).status,
        VouchStatus.withdrawn,
      );
      expect(
        vouchFor('jp.city.sendai', city.pub, [again, first, back], []).status,
        VouchStatus.vouched,
      );
      // On the same time a withdrawal wins.
      final sameTime = await vouch(withdrawn: true);
      expect(
        vouchFor('jp.city.sendai', city.pub, [first, sameTime], []).status,
        VouchStatus.withdrawn,
      );
      // A time in another zone is the same moment.
      final utc = await vouch(signed: '2026-11-23T05:00:00Z', withdrawn: true);
      expect(
        vouchFor('jp.city.sendai', city.pub, [utc, first], []).status,
        VouchStatus.withdrawn,
      );
    });

    test('two vouches at the same time decide the same in any order', () async {
      final a = await vouch();
      final b = await vouch(key: other.pub);
      final ab = vouchFor('jp.city.sendai', city.pub, [a, b], []);
      final ba = vouchFor('jp.city.sendai', city.pub, [b, a], []);
      expect(ab.status, ba.status);
      expect(ab.vouch, ba.vouch);
    });
  });

  group('catalog', () {
    test('vouches travel in a catalog and older fields stay', () async {
      final v = await vouch();
      final c = CatalogDocument(records: const [], vouches: [v.json]);
      final back = CatalogDocument.parse(c.encode());
      expect(await Vouch.checkAll(back.vouches, trust), [v]);
      // A catalog without them, or with the wrong type, reads as before.
      expect(
        CatalogDocument.parse('{"format":2,"records":[]}').vouches,
        isEmpty,
      );
      expect(
        CatalogDocument.parse(
          '{"format":2,"records":[],"vouches":"x"}',
        ).vouches,
        isEmpty,
      );
      expect(
        jsonDecode(CatalogDocument(records: const []).encode()),
        isNot(contains('vouches')),
      );
    });

    test('capped keeps what decides: withdrawals, then the newest', () async {
      final many = [
        for (var i = 0; i < 3; i++)
          await vouch(
            publisher: 'jp.city.c$i',
            signed: '2026-11-2${i}T00:00:00Z',
          ),
      ];
      final back = await vouch(
        publisher: 'jp.city.c0',
        signed: '2026-11-25T00:00:00Z',
        withdrawn: true,
      );
      final kept = Vouch.capped([...many, back], 2);
      expect(kept, [many[2], back]);
      // A withdrawal a newer vouch replaced changes nothing: it goes first.
      final oldBack = await vouch(
        publisher: 'jp.city.c1',
        signed: '2026-11-01T00:00:00Z',
        withdrawn: true,
      );
      expect(Vouch.capped([oldBack, many[1], many[2]], 2), [many[1], many[2]]);
      // byHash: each once.
      final c = CatalogDocument.byHash(const [], vouches: [...many, many[0]]);
      expect(c.vouches, hasLength(3));
    });

    test('fitted leaves vouches out before key statements', () async {
      final keep = await vouch(withdrawn: true);
      final v = await vouch(publisher: 'jp.city.kobe', key: other.pub);
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: city.pair,
        signed: '2026-11-24',
      );
      int size(CatalogDocument c) => utf8.encode(c.encode()).length;
      String filler(int bytes) => 'x' * bytes;
      // Just over the limit with one vouch too many.
      final base = CatalogDocument(records: const [], keys: [revoke.json]);
      final vouchBytes = utf8.encode(jsonEncode(v.json)).length;
      var c = CatalogDocument(
        records: [
          filler(CatalogDocument.maxBytes - size(base) - vouchBytes - 200),
        ],
        keys: [revoke.json],
        vouches: [v.json, keep.json],
      );
      var f = c.fitted();
      expect(f.keys, [revoke.json]);
      expect(f.vouches, [keep.json]);
      expect(CatalogDocument.vouchesLeftOut([v, keep], f), 1);
      expect(size(f), lessThanOrEqualTo(CatalogDocument.maxBytes));
      // So full that key statements must go too: then no vouch is left.
      final bare = CatalogDocument(records: const []);
      c = CatalogDocument(
        records: [filler(CatalogDocument.maxBytes - size(bare) - 20)],
        keys: [revoke.json],
        vouches: [v.json, keep.json],
      );
      f = c.fitted();
      expect(f.vouches, isEmpty);
      expect(f.keys, isEmpty);
      // Records alone too large: no reader would take it.
      expect(
        () => CatalogDocument(
          records: [filler(CatalogDocument.maxBytes)],
          vouches: [v.json],
        ).fitted(),
        throwsA(isA<CatalogTooLarge>()),
      );
    });
  });
}
