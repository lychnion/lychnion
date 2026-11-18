import 'dart:async';
import 'dart:io';
import 'dart:math';

/// The longest `--every` (a node that asks less often is not current).
const maxEvery = Duration(days: 7);

/// `30m`, `1h`, `90s`, `2h30m`: a duration from one minute to
/// [maxEvery], or null when [text] is not one.
Duration? parseEvery(String text) {
  final m = RegExp(
    r'^(?:(\d{1,4})h)?(?:(\d{1,6})m)?(?:(\d{1,7})s)?$',
  ).firstMatch(text);
  if (m == null || text.isEmpty) return null;
  final d = Duration(
    hours: int.parse(m[1] ?? '0'),
    minutes: int.parse(m[2] ?? '0'),
    seconds: int.parse(m[3] ?? '0'),
  );
  return d < const Duration(minutes: 1) || d > maxEvery ? null : d;
}

/// How long to wait after a run (docs/distribution.md, step 5c): [every]
/// after one that worked; after [failures] failed runs in a row one
/// minute, then two, four … up to [every], so a short internet window is
/// not missed. Give or take a tenth either way, so many nodes do not all
/// ask at the same second (also after an outage).
Duration nextWait(Duration every, {required int failures, Random? random}) {
  var base = every;
  if (failures > 0) {
    final backoff = const Duration(minutes: 1) * pow(2, min(failures - 1, 20));
    if (backoff < every) base = backoff;
  }
  final spread = min(base.inMilliseconds ~/ 10, 1 << 30);
  if (spread == 0) return base;
  final r = random ?? Random();
  return base + Duration(milliseconds: r.nextInt(2 * spread) - spread);
}

/// A failure as one line for the log: what and where, no stack trace.
String errorLine(Object e) => switch (e) {
  FileSystemException(:final path, :final osError, :final message) =>
    '${path ?? ''}: ${osError?.message ?? message}',
  SocketException(:final osError, :final message) =>
    'network: ${osError?.message ?? message}',
  TlsException(:final message) => 'TLS: $message',
  FormatException(:final message) => message,
  _ => e.runtimeType.toString(),
};

/// Runs [run] again and again until [stop] completes: [nextWait] between
/// runs. [run] returns true when it worked. [sleep] is for tests.
Future<void> runEvery(
  Future<bool> Function() run,
  Duration every, {
  required Future<void> stop,
  void Function(String line)? log,
  Future<void> Function(Duration d)? sleep,
}) async {
  var stopped = false;
  // One listener for the whole loop: it ends the wait going on.
  Timer? timer;
  Completer<void>? waiting;
  unawaited(
    stop.then((_) {
      stopped = true;
      timer?.cancel();
      if (waiting case final w? when !w.isCompleted) w.complete();
    }),
  );
  Future<void> wait(Duration d) {
    final w = waiting = Completer<void>();
    timer = Timer(d, () {
      if (!w.isCompleted) w.complete();
    });
    return w.future;
  }

  var failures = 0;
  while (!stopped) {
    bool ok;
    try {
      ok = await run();
    } on Object catch (e) {
      log?.call('run failed: ${errorLine(e)}');
      ok = false;
    }
    failures = ok ? 0 : failures + 1;
    if (stopped) break;
    final d = nextWait(every, failures: failures);
    log?.call('next run in ${d.inMinutes}m ${d.inSeconds.remainder(60)}s');
    await (sleep ?? wait)(d);
  }
}
