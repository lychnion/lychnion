import 'dart:async';
import 'dart:math';

import 'package:lychnion_node/lychnion_node.dart';
import 'package:test/test.dart';

void main() {
  test('--every: hours, minutes, seconds; at least a minute', () {
    expect(parseEvery('30m'), const Duration(minutes: 30));
    expect(parseEvery('1h'), const Duration(hours: 1));
    expect(parseEvery('2h30m'), const Duration(hours: 2, minutes: 30));
    expect(parseEvery('90s'), const Duration(seconds: 90));
    for (final bad in ['', '30', '59s', 'm', '1d', '-5m', '30 m']) {
      expect(parseEvery(bad), isNull, reason: bad);
    }
  });

  test('after failures: 1, 2, 4 … minutes, never more than every', () {
    const every = Duration(minutes: 30);
    expect(
      [for (var f = 1; f <= 7; f++) nextWait(every, failures: f).inMinutes],
      [1, 2, 4, 8, 16, 30, 30],
    );
    expect(nextWait(every, failures: 1000), every);
  });

  test('after a run that worked: every, give or take a tenth', () {
    const every = Duration(minutes: 30);
    for (var seed = 0; seed < 50; seed++) {
      final w = nextWait(every, failures: 0, random: Random(seed));
      expect(w.inSeconds, inInclusiveRange(27 * 60, 33 * 60));
    }
  });

  test('runs again and again, sooner after failures, until stopped', () async {
    final results = [false, false, true, false];
    final waits = <int>[];
    final stop = Completer<void>();
    var runs = 0;
    await runEvery(
      () async => results[runs++],
      const Duration(minutes: 30),
      stop: stop.future,
      sleep: (d, _) async {
        waits.add(d.inMinutes);
        if (runs == results.length) stop.complete();
      },
    );
    expect(runs, 4);
    expect(waits.take(2), [1, 2]);
    expect(waits[2], inInclusiveRange(27, 33));
    expect(waits[3], 1);
  });

  test('a run that throws counts as failed and the loop goes on', () async {
    final stop = Completer<void>();
    var runs = 0;
    final waits = <int>[];
    await runEvery(
      () async {
        runs++;
        if (runs == 1) throw StateError('disk');
        return true;
      },
      const Duration(minutes: 30),
      stop: stop.future,
      sleep: (d, _) async {
        waits.add(d.inMinutes);
        if (runs == 2) stop.complete();
      },
    );
    expect(runs, 2);
    expect(waits.first, 1);
  });
}
