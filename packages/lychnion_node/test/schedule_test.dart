import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:lychnion_node/lychnion_node.dart';
import 'package:test/test.dart';

void main() {
  test('--every: hours, minutes, seconds; at least a minute', () {
    expect(parseEvery('30m'), const Duration(minutes: 30));
    expect(parseEvery('1h'), const Duration(hours: 1));
    expect(parseEvery('2h30m'), const Duration(hours: 2, minutes: 30));
    expect(parseEvery('90s'), const Duration(seconds: 90));
    for (final bad in [
      '',
      '30',
      '59s',
      'm',
      '1d',
      '-5m',
      '30 m',
      '169h',
      '99999h',
      '99999999999999999999h',
    ]) {
      expect(parseEvery(bad), isNull, reason: bad);
    }
    expect(parseEvery('168h'), maxEvery);
  });

  test('after failures: 1, 2, 4 … minutes, never more than every, '
      'give or take a tenth', () {
    const every = Duration(minutes: 30);
    final want = [1, 2, 4, 8, 16, 30, 30];
    for (var f = 1; f <= 7; f++) {
      final w = nextWait(every, failures: f, random: Random(f));
      final base = want[f - 1] * 60;
      expect(
        w.inSeconds,
        inInclusiveRange(base * 0.9 - 1, base * 1.1),
        reason: 'failure $f',
      );
    }
    final long = nextWait(every, failures: 1000, random: Random(1));
    expect(long.inSeconds, inInclusiveRange(27 * 60, 33 * 60));
  });

  test('the longest --every does not overflow the spread', () {
    expect(nextWait(maxEvery, failures: 0) > Duration.zero, isTrue);
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
      sleep: (d) async {
        waits.add(d.inSeconds);
        if (runs == results.length) stop.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );
    expect(runs, 4);
    expect(waits[0], inInclusiveRange(54, 66));
    expect(waits[1], inInclusiveRange(108, 132));
    expect(waits[2], inInclusiveRange(27 * 60, 33 * 60));
    expect(waits[3], inInclusiveRange(54, 66));
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
      sleep: (d) async {
        waits.add(d.inSeconds);
        if (runs == 2) stop.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );
    expect(runs, 2);
    expect(waits.first, inInclusiveRange(54, 66));
  });

  test('a stop ends the real wait at once', () async {
    final stop = Completer<void>();
    var runs = 0;
    final sw = Stopwatch()..start();
    final loop = runEvery(
      () async {
        runs++;
        return true;
      },
      const Duration(hours: 1),
      stop: stop.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    stop.complete();
    await loop;
    expect(runs, 1);
    expect(sw.elapsed.inSeconds, lessThan(2));
  });

  test('error lines say what and where', () {
    expect(
      errorLine(const FileSystemException('x', '/data', OSError('full', 28))),
      '/data: full',
    );
    expect(errorLine(const FormatException('bad')), 'bad');
    expect(errorLine(StateError('?')), 'StateError');
  });
}
