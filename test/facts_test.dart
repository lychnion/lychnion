import 'dart:convert';

import 'package:fieldkit/facts/compact_codec.dart';
import 'package:fieldkit/facts/fact.dart';
import 'package:fieldkit/facts/fact_store.dart';
import 'package:fieldkit/map/evac_sites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 14, 20);
  final sites = EvacSites.open('assets/maps/jp.map.nishinomiya.sites.sqlite');
  final cityHallTsunami = sites.sites
      .firstWhere(
        (s) =>
            s.emergency &&
            s.name == '市役所' &&
            s.hazards.contains(Hazard.tsunami),
      )
      .uid;

  Fact status(
    String value,
    SourceType src, {
    required int minutesAgo,
    int ttlMinutes = 120,
  }) => Fact(
    kind: FactKind.shelterStatus,
    subject: cityHallTsunami,
    value: value,
    observedAt: now.subtract(Duration(minutes: minutesAgo)),
    expiresAt: now.subtract(Duration(minutes: minutesAgo - ttlMinutes)),
    sourceType: src,
    sourceName: src == SourceType.official ? '西宮市' : '',
  );

  group('conflicts', () {
    test('the most trusted source wins, then the newest', () async {
      final store = FactStore(clock: () => now);
      await store.addAll([
        status('open', SourceType.official, minutesAgo: 90),
        status(
          'full',
          SourceType.citizen,
          minutesAgo: 5,
        ), // newer but less trusted
        status(
          'crowded',
          SourceType.official,
          minutesAgo: 30,
        ), // newest official
      ]);
      expect(store.shelterStatus(cityHallTsunami)!.value, 'crowded');
    });

    test('expired facts never win, even when trusted', () async {
      final store = FactStore(clock: () => now);
      await store.addAll([
        status('open', SourceType.official, minutesAgo: 200, ttlMinutes: 120),
        status('full', SourceType.citizen, minutesAgo: 10),
      ]);
      final f = store.shelterStatus(cityHallTsunami)!;
      expect(f.value, 'full');
      expect(f.unconfirmed, isTrue);
    });

    test('the same fact twice is stored once', () async {
      final store = FactStore(clock: () => now);
      final f = status('full', SourceType.official, minutesAgo: 10);
      expect(await store.addAll([f]), 1);
      expect(await store.addAll([f]), 0);
    });
  });

  group('clearing', () {
    Fact road(String value, SourceType src, int minutesAgo) => Fact(
      kind: FactKind.roadBlocked,
      subject: '34.7349,135.3420',
      value: value,
      observedAt: now.subtract(Duration(minutes: minutesAgo)),
      expiresAt: now.add(const Duration(hours: 3)),
      sourceType: src,
    );

    test('a newer "cleared" fact hides the topic', () async {
      final store = FactStore(clock: () => now);
      await store.addAll([
        road('blocked', SourceType.official, 60),
        road(Fact.cleared, SourceType.official, 5),
      ]);
      expect(store.currentOf({FactKind.roadBlocked}), isEmpty);
      // Still shared, so other devices apply the same rule.
      expect(store.all, hasLength(2));
    });

    test('a resident cannot clear an official fact', () async {
      final store = FactStore(clock: () => now);
      await store.addAll([
        road('blocked', SourceType.official, 60),
        road(Fact.cleared, SourceType.citizen, 5),
      ]);
      expect(store.currentOf({FactKind.roadBlocked}).single.value, 'blocked');
    });
  });

  test('age and source labels', () {
    final f = status('full', SourceType.official, minutesAgo: 120);
    expect(f.age(now, en: false), '2時間前');
    expect(f.age(now, en: true), '2 h ago');
    expect(f.sourceLabel(en: false), '西宮市 · 公式');
    expect(f.shelterStatus!.avoid, isTrue);
  });

  group('compact radio format', () {
    final codec = CompactCodec(sites.siteIds);

    test('a shelter update fits in about 20 bytes and decodes the same', () {
      final f = status('full', SourceType.official, minutesAgo: 0);
      final s = codec.encode(f);
      // ignore: avoid_print
      print('compact: "$s" (${s.length} bytes)');
      expect(s.length, lessThanOrEqualTo(20));
      final back = codec.decode(s);
      expect(back.subject, f.subject);
      expect(back.value, 'full');
      expect(back.sourceType, SourceType.official);
      expect(back.observedAt, f.observedAt);
      expect(back.expiresAt, f.expiresAt);
    });

    test('many updates fit in one 200-byte message', () {
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
      final msgs = codec.pack(facts);
      // ignore: avoid_print
      print(
        '${facts.length} updates -> ${msgs.length} message(s): ${msgs.map((m) => m.length).toList()} bytes',
      );
      expect(msgs.first.length, lessThanOrEqualTo(200));
      expect([for (final m in msgs) ...codec.unpack(m)].length, facts.length);
    });

    test('Japanese text counts as UTF-8 bytes', () {
      final facts = [
        for (var i = 0; i < 12; i++)
          Fact(
            kind: FactKind.warning,
            subject: '西宮市',
            value: '津波警報$i',
            observedAt: now,
            expiresAt: now.add(const Duration(hours: 3)),
            sourceType: SourceType.official,
          ),
      ];
      for (final m in codec.pack(facts)) {
        expect(utf8.encode(m).length, lessThanOrEqualTo(200));
      }
    });

    test('points, not sites, are kept as lat,lon', () {
      final f = Fact(
        kind: FactKind.roadBlocked,
        subject: '34.7401,135.3355',
        value: 'blocked',
        observedAt: now,
        expiresAt: now.add(const Duration(hours: 6)),
        sourceType: SourceType.citizen,
      );
      expect(codec.decode(codec.encode(f)).subject, '34.7401,135.3355');
    });
  });
}
