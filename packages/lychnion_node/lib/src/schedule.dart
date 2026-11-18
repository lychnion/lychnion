import 'dart:async';
import 'dart:math';

/// `30m`, `1h`, `90s`, `2h30m`: a duration of at least one minute, or
/// null when [text] is not one.
Duration? parseEvery(String text) {
  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(text);
  if (m == null || text.isEmpty) return null;
  final d = Duration(
    hours: int.parse(m[1] ?? '0'),
    minutes: int.parse(m[2] ?? '0'),
    seconds: int.parse(m[3] ?? '0'),
  );
  return d < const Duration(minutes: 1) ? null : d;
}

/// How long to wait after a run (docs/distribution.md, step 5c): [every]
/// after one that worked (give or take a tenth, so many nodes do not all
/// ask at the same second); after [failures] failed runs in a row one
/// minute, then two, four … up to [every], so a short internet window is
/// not missed.
Duration nextWait(Duration every, {required int failures, Random? random}) {
  if (failures > 0) {
    final backoff = const Duration(minutes: 1) * pow(2, min(failures - 1, 20));
    return backoff < every ? backoff : every;
  }
  final r = random ?? Random();
  final spread = every.inMilliseconds ~/ 10;
  return every +
      Duration(milliseconds: spread == 0 ? 0 : r.nextInt(2 * spread) - spread);
}

/// Runs [run] again and again until [stop] completes: [nextWait] between
/// runs. [run] returns true when it worked. [sleep] is for tests.
Future<void> runEvery(
  Future<bool> Function() run,
  Duration every, {
  required Future<void> stop,
  void Function(String line)? log,
  Future<void> Function(Duration d, Future<void> stop)? sleep,
}) async {
  var stopped = false;
  unawaited(stop.then((_) => stopped = true));
  var failures = 0;
  while (!stopped) {
    bool ok;
    try {
      ok = await run();
    } on Object catch (e) {
      log?.call('run failed: ${e.runtimeType}');
      ok = false;
    }
    failures = ok ? 0 : failures + 1;
    if (stopped) break;
    final wait = nextWait(every, failures: failures);
    log?.call(
      'next run in ${wait.inMinutes}m ${wait.inSeconds.remainder(60)}s',
    );
    await (sleep ?? _sleep)(wait, stop);
  }
}

/// Waits [d], or until [stop]; the timer is cancelled then, so nothing
/// keeps the process alive after a stop.
Future<void> _sleep(Duration d, Future<void> stop) {
  final done = Completer<void>();
  final timer = Timer(d, () {
    if (!done.isCompleted) done.complete();
  });
  unawaited(
    stop.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    }),
  );
  return done.future;
}
