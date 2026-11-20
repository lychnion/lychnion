// A fact dated in the future, or with a far too long lifetime, does not
// win its topic (lychnion/lychnion#70).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20, 6);

  Fact status(
    String value, {
    required DateTime observed,
    required DateTime expires,
    SourceType src = SourceType.citizen,
  }) => Fact(
    kind: FactKind.shelterStatus,
    subject: 'site-1',
    value: value,
    observedAt: observed,
    expiresAt: expires,
    sourceType: src,
  );

  Fact normal(String value, {int minutesAgo = 5}) => status(
    value,
    observed: now.subtract(Duration(minutes: minutesAgo)),
    expires: now.add(const Duration(hours: 3)),
  );

  test('a fact dated 2099 is refused and does not win', () async {
    final s = FactStore(clock: () => now);
    final added = await s.addAll([
      normal('open'),
      status(
        'full',
        observed: DateTime.utc(2099),
        expires: DateTime.utc(2099).add(const Duration(hours: 3)),
      ),
    ]);
    expect(added, 1);
    expect(s.shelterStatus('site-1')!.value, 'open');
  });

  test('a short lifetime does not help a date far ahead', () async {
    final s = FactStore(clock: () => now);
    final added = await s.addAll([
      status(
        'cleared',
        observed: now.add(const Duration(days: 2)),
        expires: now.add(const Duration(days: 2, hours: 1)),
      ),
    ]);
    expect(added, 0);
  });

  test('a lifetime longer than three days is refused', () async {
    final s = FactStore(clock: () => now);
    expect(
      await s.addAll([
        status(
          'full',
          observed: now.subtract(const Duration(minutes: 1)),
          expires: now.add(const Duration(days: 30)),
        ),
      ]),
      0,
    );
    // A day is fine (the app's own form offers up to 24 hours).
    expect(
      await s.addAll([
        status(
          'full',
          observed: now.subtract(const Duration(minutes: 1)),
          expires: now.add(const Duration(days: 1)),
        ),
      ]),
      1,
    );
  });

  group('clock skew', () {
    Fact ahead([int minutes = 5]) => status(
      'full',
      observed: now.add(Duration(minutes: minutes)),
      expires: now.add(const Duration(hours: 3)),
    );

    test('a few minutes ahead is accepted, and wins when nothing else is '
        'there', () async {
      final s = FactStore(clock: () => now);
      expect(await s.addAll([ahead()]), 1);
      expect(s.shelterStatus('site-1')!.value, 'full');
    });

    test('but never over a real report, not even one from a while ago, in '
        'either order', () async {
      for (final order in [true, false]) {
        final s = FactStore(clock: () => now);
        final earlier = normal('open', minutesAgo: 20);
        await s.addAll(order ? [ahead(), earlier] : [earlier, ahead()]);
        expect(s.shelterStatus('site-1')!.value, 'open', reason: '$order');
      }
    });

    test('of two ahead, the one less far ahead wins', () async {
      final s = FactStore(clock: () => now);
      final far = status(
        'closed',
        observed: now.add(const Duration(minutes: 25)),
        expires: now.add(const Duration(hours: 3)),
      );
      await s.addAll([far, ahead(5)]);
      expect(s.shelterStatus('site-1')!.value, 'full');
    });

    test('more than 30 minutes ahead is refused', () async {
      final s = FactStore(clock: () => now);
      expect(await s.addAll([ahead(31)]), 0);
    });
  });

  test('a clock set back hides facts that now look ahead, and shows them '
      'again when it is right; nothing is lost', () async {
    final dir = Directory.systemTemp.createTempSync('facts_clock_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var clock = now;
    final s = FactStore(clock: () => clock);
    await s.load(dir: dir);
    await s.addAll([normal('open', minutesAgo: 1)]);
    // The clock is corrected back by two hours.
    clock = now.subtract(const Duration(hours: 2));
    await s.addAll([
      Fact(
        kind: FactKind.roadBlocked,
        subject: '34.7,135.3',
        value: 'blocked',
        observedAt: clock,
        expiresAt: clock.add(const Duration(hours: 6)),
        sourceType: SourceType.citizen,
      ),
    ]);
    expect(s.shelterStatus('site-1'), isNull);
    // Still on disk after a restart with the wrong clock.
    final again = FactStore(clock: () => clock);
    await again.load(dir: dir);
    expect(again.shelterStatus('site-1'), isNull);
    clock = now;
    expect(again.shelterStatus('site-1')!.value, 'open');
  });

  test('the exact bounds', () {
    bool ok(Duration ahead, Duration life, {Duration? expiresIn}) =>
        FactStore.inTimeBounds(
          status(
            'full',
            observed: now.add(ahead),
            expires: expiresIn != null
                ? now.add(expiresIn)
                : now.add(ahead + life),
          ),
          now,
        );
    const ms = Duration(milliseconds: 1);
    const skew = FactStore.maxSkew, life = FactStore.maxLifetime;
    expect(ok(skew, const Duration(hours: 1)), isTrue);
    expect(ok(skew + ms, const Duration(hours: 1)), isFalse);
    expect(ok(Duration.zero, life), isTrue);
    expect(ok(Duration.zero, life + ms), isFalse);
    // Expiring at most 3 days and 30 minutes from now.
    expect(ok(skew, life), isTrue);
    expect(ok(skew, life + ms), isFalse);
    // A local time and a UTC time of the same moment count the same.
    expect(
      FactStore.inTimeBounds(
        status(
          'full',
          observed: now.toLocal(),
          expires: now.toLocal().add(const Duration(hours: 1)),
        ),
        now,
      ),
      isTrue,
    );
  });

  test('a fact more than a year ahead is dropped from storage', () async {
    final dir = Directory.systemTemp.createTempSync('facts_year_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final far = status(
      'cleared',
      observed: now.add(const Duration(days: 400)),
      expires: now.add(const Duration(days: 400, hours: 1)),
    );
    File('${dir.path}/facts.jsonl').writeAsStringSync(
      '{"format":1}\n${jsonEncode({...far.toJson(), 'v_ok': true})}\n',
    );
    final s = FactStore(clock: () => now);
    await s.load(dir: dir);
    expect(File('${dir.path}/facts.jsonl').readAsLinesSync(), hasLength(1));
  });

  test('ends before it begins: refused', () async {
    final s = FactStore(clock: () => now);
    expect(
      await s.addAll([
        status(
          'full',
          observed: now,
          expires: now.subtract(const Duration(minutes: 1)),
        ),
      ]),
      0,
    );
  });

  test('saved by an older build: a 2099 date and an endless lifetime are '
      'dropped at the next start', () async {
    final dir = Directory.systemTemp.createTempSync('facts_bounds_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final far = status(
      'cleared',
      observed: DateTime.utc(2099),
      expires: DateTime.utc(2099).add(const Duration(hours: 1)),
    );
    final endless = status(
      'full',
      observed: now.subtract(const Duration(hours: 1)),
      expires: now.add(const Duration(days: 30)),
    );
    File('${dir.path}/facts.jsonl').writeAsStringSync(
      '{"format":1}\n'
      '${jsonEncode({...normal('open').toJson(), 'v_ok': true})}\n'
      '${jsonEncode({...far.toJson(), 'v_ok': true})}\n'
      '${jsonEncode({...endless.toJson(), 'v_ok': true})}\n',
    );
    final s = FactStore(clock: () => now);
    await s.load(dir: dir);
    expect([for (final f in s.all) f.value], ['open']);
    expect(s.shelterStatus('site-1')!.value, 'open');
    // Written again with only the normal one (2099 is more than a year
    // ahead; a fact only a little ahead would stay, hidden).
    final lines = File('${dir.path}/facts.jsonl').readAsLinesSync();
    expect(lines, hasLength(2));
    expect(lines.last, contains('"open"'));
  });
}
