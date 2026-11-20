import 'dart:convert';
import 'dart:io';

import 'package:lychnion/facts/compact_codec.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/map/evac_sites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/facts/fact_view.dart';
import 'package:flutter/widgets.dart' show Locale;

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

  group('limits', () {
    test('expired facts are not kept', () async {
      final store = FactStore(clock: () => now);
      final added = await store.addAll([
        status('open', SourceType.official, minutesAgo: 200),
      ]);
      expect(added, 0);
      expect(store.all, isEmpty);
    });

    test('over the limit, the oldest that decide nothing go first', () async {
      final store = FactStore(clock: () => now, maxFacts: 3);
      await store.addAll([
        // Oldest, but the most trusted: it decides the topic.
        status('open', SourceType.official, minutesAgo: 100),
        for (final m in [50, 40, 30, 20])
          status('full $m', SourceType.citizen, minutesAgo: m),
      ]);
      expect(store.all.map((f) => f.value), ['open', 'full 30', 'full 20']);
      expect(store.shelterStatus(cityHallTsunami)!.value, 'open');
    });

    test(
      'a flood of unverified facts does not push out verified ones',
      () async {
        final store = FactStore(clock: () => now, maxFacts: 3);
        final official = status('open', SourceType.official, minutesAgo: 100)
          ..verified = true;
        await store.addAll([official], checked: true);
        await store.addAll([
          for (var i = 0; i < 5; i++)
            Fact(
              kind: FactKind.shelterStatus,
              subject: '35.7$i,139.7$i',
              value: 'closed',
              // Newer than the official one (a date in the future is
              // refused before it gets here, #70).
              observedAt: now.subtract(Duration(minutes: i)),
              expiresAt: now.add(const Duration(days: 1)),
              sourceType: SourceType.official,
              sourceName: 'fake',
            )..verified = false,
        ], checked: true);
        expect(store.all, hasLength(3));
        expect(store.all, contains(official));
      },
    );

    test('expired facts are dropped from disk at the next start', () async {
      final dir = Directory.systemTemp.createTempSync('facts_limit_');
      addTearDown(() => dir.deleteSync(recursive: true));
      var clock = now;
      final store = FactStore(clock: () => clock);
      await store.load(dir: dir);
      await store.addAll([
        status('open', SourceType.official, minutesAgo: 10, ttlMinutes: 60),
        status('full', SourceType.citizen, minutesAgo: 5, ttlMinutes: 600),
      ]);
      clock = now.add(const Duration(hours: 2));
      final again = FactStore(clock: () => clock);
      await again.load(dir: dir);
      expect(again.all.map((f) => f.value), ['full']);
      final lines = File('${dir.path}/facts.jsonl').readAsLinesSync();
      // The header and the one fact left.
      expect(lines, hasLength(2));
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
    final ja = lookupAppLocalizations(const Locale('ja'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(factAge(ja, f, now), '2時間前');
    expect(factAge(en, f, now), '2 h ago');
    expect(factSourceLabel(ja, f), '西宮市 · 公式');
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
