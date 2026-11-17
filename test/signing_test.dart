import 'dart:convert';

import 'package:lychnion/facts/compact_codec.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/map/evac_sites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 14, 20);
  final sites = EvacSites.open('assets/maps/jp.map.nishinomiya.sites.sqlite');
  final site = sites.siteIds[10];

  Fact status(String value, SourceType src, int minutesAgo) => Fact(
    kind: FactKind.shelterStatus,
    subject: site,
    value: value,
    observedAt: now.subtract(Duration(minutes: minutesAgo)),
    expiresAt: now.add(const Duration(hours: 3)),
    sourceType: src,
    sourceName: src == SourceType.official ? '西宮市' : '',
  );

  late FactSigner city;
  late FactSigner stranger;
  late TrustList trust;

  setUp(() async {
    city = await FactSigner.generate();
    stranger = await FactSigner.generate();
    trust = TrustList();
    await trust.add(city.publicKeyText, '西宮市');
  });

  test(
    'only a valid signature from a trusted key counts as official',
    () async {
      final ok = await city.sign(status('full', SourceType.official, 10));
      expect(await trust.verify(ok), isTrue);

      final unknown = await stranger.sign(
        status('full', SourceType.official, 10),
      );
      expect(await trust.verify(unknown), isFalse);

      final unsigned = status('full', SourceType.official, 10);
      expect(await trust.verify(unsigned), isFalse);

      // Changing a signed fact breaks the signature.
      final j = ok.toJson()..['value'] = 'open';
      expect(await trust.verify(Fact.fromJson(j)), isFalse);
    },
  );

  test('an unsigned "official" fact cannot overrule a signed one', () async {
    final store = FactStore(clock: () => now, trust: trust);
    await store.addAll([
      await city.sign(status('full', SourceType.official, 30)),
      // Newer, claims to be official, but nobody trusted signed it.
      status('open', SourceType.official, 5),
    ]);
    final f = store.shelterStatus(site)!;
    expect(f.value, 'full');
    expect(f.verified, isTrue);
  });

  test('an unsigned "official" fact is shown as unconfirmed', () async {
    final store = FactStore(clock: () => now, trust: trust);
    await store.addAll([status('open', SourceType.official, 5)]);
    final f = store.shelterStatus(site)!;
    expect(f.unconfirmed, isTrue);
    expect(f.sourceLabel(en: false), contains('署名なし'));
  });

  test('facts entered on this device are signed', () async {
    final store = FactStore(clock: () => now, trust: trust)..signer = city;
    await store.addOwn([status('crowded', SourceType.official, 1)]);
    final f = store.shelterStatus(site)!;
    expect(f.sig, isNotNull);
    expect(f.verified, isTrue);
  });

  test('signed radio messages: size, check, tampering', () async {
    final codec = CompactCodec(sites.siteIds);
    final facts = [
      for (var i = 0; i < 12; i++)
        Fact(
          kind: FactKind.shelterStatus,
          subject: sites.siteIds[i * 50],
          value: 'crowded',
          observedAt: now,
          expiresAt: now.add(const Duration(hours: 3)),
          sourceType: SourceType.official,
        ),
    ];
    final msgs = await city.packSigned(codec, facts);
    final perMsg = [for (final m in msgs) trust.unpackSigned(codec, m)];
    final counts = [for (final p in perMsg) (await p).length];
    // ignore: avoid_print
    print(
      '12 signed updates -> ${msgs.length} messages, '
      '${[for (final m in msgs) utf8.encode(m).length]} bytes, $counts facts',
    );
    for (final m in msgs) {
      expect(utf8.encode(m).length, lessThanOrEqualTo(200));
    }
    expect(counts.reduce((a, b) => a + b), 12);
    final first = await trust.unpackSigned(codec, msgs.first);
    expect(first.every((f) => f.verified && f.sourceName == '西宮市'), isTrue);

    final tampered = msgs.first.replaceFirst('|c|', '|o|');
    final bad = await trust.unpackSigned(codec, tampered);
    expect(bad.any((f) => f.verified), isFalse);
  });
}
