import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:lychnion_format/lychnion_format.dart';
import 'package:test/test.dart';

// lychnion/lychnion#119: vouches signed by Lychnion label official
// publishers; they never change what may be published.

Future<({String pub, SimpleKeyPair pair})> _key() async {
  final k = await newKeyPair();
  return (pub: k.publicKey, pair: await keyPairFromSeed(k.seed));
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
  Object? wire(Vouch v) => jsonDecode(jsonEncode(v.json));

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
      final j = (wire(await vouch()) as Map)..['publisher'] = 'jp.city.kobe';
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

    test('refuses shapes that could grow or be spelled many ways', () async {
      Future<Object?> bad(void Function(Map<String, Object?>) change) async {
        final j = Map<String, Object?>.of((wire(await vouch()) as Map).cast());
        change(j);
        return Vouch.check(j, trust);
      }

      expect(await bad((j) => j['extra'] = 'x'), isNull);
      expect(await bad((j) => j['format'] = 2), isNull);
      expect(await bad((j) => j['key'] = '${j['key']}='), isNull);
      expect(await bad((j) => j['checked'] = '23 Nov 2026'), isNull);
      expect(await bad((j) => j['method'] = 'Official Website'), isNull);
      expect(await bad((j) => j['url'] = 'http://example.org/'), isNull);
      expect(await bad((j) => j['withdrawn'] = false), isNull);
      expect(await bad((j) => j['publisher'] = voucherPublisher), isNull);
      expect(await bad((j) => j['title'] = {'ja': '仙台\u202e市'}), isNull);
      expect(await bad((j) => j['title'] = {'ja': 'あ' * 61}), isNull);
      expect(await bad((j) => j['title'] = {'japanese': '仙台市'}), isNull);
      expect(await bad((j) => j['signed'] = 'yesterday'), isNull);
    });

    test('sign refuses what check would refuse', () async {
      expect(
        () => Vouch.sign(
          publisher: 'jp.city.sendai',
          key: city.pub,
          checked: '2026-11-23',
          method: 'official-website',
          signed: '2026-11-23T14:00:00+09:00',
          signer: lychnion.pair,
          url: 'http://www.city.sendai.jp/',
        ),
        throwsArgumentError,
      );
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
      expect(
        vouchFor('jp.city.sendai', next.pub, [v], [replace]).status,
        VouchStatus.vouched,
      );
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: city.pair,
        signed: '2026-11-24',
      );
      expect(
        vouchFor('jp.city.sendai', city.pub, [v], [revoke]).status,
        isNot(VouchStatus.vouched),
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

    test('byHash keeps at most maxPerSource, withdrawals first', () async {
      final many = [
        for (var i = 0; i < 3; i++)
          await vouch(
            publisher: 'jp.city.c$i',
            signed: '2026-11-2${i}T00:00:00Z',
          ),
      ];
      final back = await vouch(
        publisher: 'jp.city.c0',
        signed: '2026-11-19T00:00:00Z',
        withdrawn: true,
      );
      final kept = Vouch.capped([...many, back], 2);
      expect(kept, hasLength(2));
      expect(kept, contains(back));
      // Then the newest.
      expect(kept, contains(many[2]));
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
      // Filler records, so the catalog is just over the limit with one
      // vouch too many.
      final base = CatalogDocument(records: const [], keys: [revoke.json]);
      final room = CatalogDocument.maxBytes - utf8.encode(base.encode()).length;
      final vouchBytes = utf8.encode(jsonEncode(v.json)).length;
      final filler = 'x' * (room - vouchBytes - 200);
      final c = CatalogDocument(
        records: [filler],
        keys: [revoke.json],
        vouches: [v.json, keep.json],
      );
      final f = c.fitted();
      expect(f.keys, [revoke.json]);
      expect(f.vouches, [keep.json]);
      expect(CatalogDocument.vouchesLeftOut([v, keep], f), 1);
      expect(
        utf8.encode(f.encode()).length,
        lessThanOrEqualTo(CatalogDocument.maxBytes),
      );
    });
  });
}
