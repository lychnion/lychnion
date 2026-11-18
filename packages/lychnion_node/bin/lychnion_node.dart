import 'dart:async';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:lychnion_node/lychnion_node.dart';

const _usage = '''
Lychnion node: serves signed packages and maps to the app and other nodes.

  lychnion_node serve DIR [--port 8642] [--host 0.0.0.0]
                     [--pull URL]... [--every 30m] [--publisher NAME=KEY]...
                     [--kind KIND]...
      Serve DIR (catalog.json and blobs/sha256/) over HTTP. With --pull,
      also pull those catalogs into DIR now and every 30 minutes (or
      --every), in the same process: one container is enough.

  lychnion_node pull --into DIR [--publisher NAME=KEY]... [--kind KIND]...
                     [--every 30m] URL...
      Fetch the catalogs at URL... (or read them from folders, such as a
      USB stick written by the app), keep the records signed by Lychnion
      or by the publishers given, fetch their files by hash into DIR and
      write DIR/catalog.json. Versions only go up. --kind package / map /
      model takes only those (models are gigabytes). With --every it
      keeps going: again after that time, and sooner after a failed run
      (1, 2, 4 … minutes), so short internet windows are not missed.
      Without it, run it from cron.

  lychnion_node check DIR [--publisher NAME=KEY]...
      Check every record's signature and every file's hash in DIR.

KEY is the publisher's public key (base64url), as in its
lychnion://publisher link. Lychnion's key is built in.
''';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    stdout.write(_usage);
    exit(argv.isEmpty ? 64 : 0);
  }
  final args = argv.skip(1).toList();
  try {
    exitCode = switch (argv.first) {
      'serve' => await _serve(args),
      'pull' => await _pull(args),
      'check' => await _check(args),
      _ => _bad('unknown command ${argv.first}'),
    };
  } on _Usage catch (e) {
    exitCode = _bad(e.message);
  } on PullBusy catch (e) {
    // Not an error for cron: the running pull does the work.
    stderr.writeln(e);
    exitCode = 75;
  } on FileSystemException catch (e) {
    stderr.writeln(errorLine(e));
    exitCode = 74;
  } on SocketException catch (e) {
    stderr.writeln(errorLine(e));
    exitCode = 1;
  } on FormatException catch (e) {
    stderr.writeln(errorLine(e));
    exitCode = 1;
  }
  // Signal listeners would keep the process alive; end it here.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}

class _Usage implements Exception {
  _Usage(this.message);
  final String message;
}

int _bad(String message) {
  stderr.writeln('$message\n');
  stderr.write(_usage);
  return 64;
}

/// Takes `--name value` (all of them) out of [args].
List<String> _opts(List<String> args, String name) {
  final out = <String>[];
  for (var i = args.indexOf(name); i >= 0; i = args.indexOf(name)) {
    if (i + 1 >= args.length) throw _Usage('$name needs a value');
    out.add(args[i + 1]);
    args.removeRange(i, i + 2);
  }
  return out;
}

String? _opt(List<String> args, String name) {
  final all = _opts(args, name);
  if (all.length > 1) throw _Usage('$name given twice');
  return all.firstOrNull;
}

TrustedKeys _trust(List<String> args) {
  final more = <String, List<String>>{};
  for (final p in _opts(args, '--publisher')) {
    final i = p.indexOf('=');
    if (i <= 0) throw _Usage('--publisher wants NAME=KEY');
    if (builtInPublishers.publishers.contains(p.substring(0, i))) {
      throw _Usage('${p.substring(0, i)} is built in; its key cannot be added');
    }
    more.putIfAbsent(p.substring(0, i), () => []).add(p.substring(i + 1));
  }
  try {
    return builtInPublishers.plus(more);
  } on FormatException {
    throw _Usage('--publisher: the key must be 32 bytes, base64url');
  }
}

/// The options of a pull (trust and kinds), taken out of [args], and its
/// sources: [urls], or else what is left in [args] after the options.
({List<Uri> sources, TrustedKeys trust, Set<String> kinds}) _pullOptions(
  List<String> args, {
  List<String>? urls,
}) {
  final trust = _trust(args);
  final kinds = _opts(args, '--kind').toSet();
  for (final k in kinds) {
    if (!const {'package', 'map', 'model'}.contains(k)) {
      throw _Usage('--kind is package, map or model');
    }
  }
  final addresses = urls ?? [...args];
  if (urls == null) args.clear();
  final sources = <Uri>[];
  for (final a in addresses) {
    // A folder (a USB stick) or an http(s) address.
    if (Directory(a).existsSync()) {
      sources.add(Directory(a).absolute.uri);
      continue;
    }
    final u = Uri.tryParse(a);
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
      throw _Usage('not an http(s) address or a folder: $a');
    }
    sources.add(u);
  }
  return (sources: sources, trust: trust, kinds: kinds);
}

Duration? _every(List<String> args) {
  final text = _opt(args, '--every');
  if (text == null) return null;
  return parseEvery(text) ??
      (throw _Usage('--every wants a time from 1m to 168h, like 30m or 2h'));
}

/// Completes on Ctrl-C or SIGTERM (docker stop). A second one ends the
/// process at once (130).
Future<void> _stopSignal() {
  final done = Completer<void>();
  for (final s in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    s.watch().listen((_) {
      if (done.isCompleted) exit(130);
      done.complete();
    });
  }
  return done.future;
}

/// One pull with its report. True when nothing failed (another pull
/// running counts as done: that one does the work).
Future<bool> _pullOnce(
  ({List<Uri> sources, TrustedKeys trust, Set<String> kinds}) o,
  NodeFolder folder,
) async {
  final PullResult r;
  try {
    r = await pull(
      o.sources,
      folder,
      o.trust,
      kinds: o.kinds,
      log: stdout.writeln,
    );
  } on PullBusy catch (e) {
    stdout.writeln('$e');
    return true;
  }
  for (final c in r.changed) {
    stdout.writeln('new: $c');
  }
  for (final t in r.taken) {
    stdout.writeln('not taken (another publisher has this id here): $t');
  }
  for (final f in r.failed) {
    stderr.writeln('failed: $f');
  }
  if (r.keptUntrusted > 0) {
    stdout.writeln(
      '${r.keptUntrusted} records here are from publishers not given now: '
      'left out of the catalog, their files kept',
    );
  }
  stdout.writeln(
    '${DateTime.now().toUtc().toIso8601String()} '
    '${r.changed.length} new, ${r.notTrusted} not trusted, '
    '${r.pruned} old files removed, ${r.failed.length} failed',
  );
  return r.failed.isEmpty;
}

Directory _dir(List<String> args) {
  if (args.length != 1) throw _Usage('give one folder');
  return Directory(args.single);
}

Future<int> _serve(List<String> args) async {
  final port = int.tryParse(
    _opt(args, '--port') ?? '${NodeServer.defaultPort}',
  );
  if (port == null || port < 0 || port > 65535) {
    throw _Usage('--port wants a number from 0 to 65535');
  }
  final host = _opt(args, '--host');
  InternetAddress? address;
  if (host != null) {
    address = InternetAddress.tryParse(host);
    if (address == null) {
      final found = await InternetAddress.lookup(host);
      if (found.isEmpty) throw _Usage('--host: $host not found');
      address = found.first;
    }
  }
  final pulls = _opts(args, '--pull');
  if (pulls.isEmpty) {
    for (final o in ['--every', '--publisher', '--kind']) {
      if (args.contains(o)) throw _Usage('serve: $o needs --pull');
    }
  }
  final every = _every(args) ?? const Duration(minutes: 30);
  final options = pulls.isEmpty ? null : _pullOptions(args, urls: pulls);
  final folder = NodeFolder(_dir(args));
  if (options == null && !await folder.catalogFile.exists()) {
    stderr.writeln('${folder.catalogFile.path} is missing (run pull first)');
    return 1;
  }
  final server = NodeServer(
    folder,
    port: port,
    address: address,
    log: (l) =>
        stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $l'),
  );
  await server.start();
  stdout.writeln('Serving ${folder.dir.path} on port ${server.boundPort}');
  final stop = _stopSignal();
  // Pulls run next to the server; until the first one is done, the
  // server answers 404 for a catalog it does not have yet.
  final pulling = options == null
      ? Future<void>.value()
      : runEvery(
          () => _pullOnce(options, folder),
          every,
          stop: stop,
          log: stdout.writeln,
        );
  await stop;
  await server.stop();
  // A pull in the middle of a download is not waited for: the part file
  // resumes next time, and the lock ends with the process.
  unawaited(pulling);
  return 0;
}

Future<int> _pull(List<String> args) async {
  final into = _opt(args, '--into');
  if (into == null) throw _Usage('pull needs --into DIR');
  final every = _every(args);
  final all = _pullOptions(args);
  if (all.sources.isEmpty) {
    throw _Usage('pull needs at least one catalog URL');
  }
  final folder = NodeFolder(Directory(into));
  if (every == null) {
    // One run; another pull running is exit 75 (main), as before.
    final r = await pull(
      all.sources,
      folder,
      all.trust,
      kinds: all.kinds,
      log: stdout.writeln,
    );
    for (final c in r.changed) {
      stdout.writeln('new: $c');
    }
    for (final t in r.taken) {
      stdout.writeln('not taken (another publisher has this id here): $t');
    }
    for (final f in r.failed) {
      stderr.writeln('failed: $f');
    }
    if (r.keptUntrusted > 0) {
      stdout.writeln(
        '${r.keptUntrusted} records here are from publishers not given '
        'now: left out of the catalog, their files kept',
      );
    }
    stdout.writeln(
      '${r.changed.length} new, ${r.notTrusted} not trusted, '
      '${r.pruned} old files removed, ${r.failed.length} failed',
    );
    return r.failed.isEmpty ? 0 : 1;
  }
  final stop = _stopSignal();
  // A stop does not wait for a pull in the middle of a download: the part
  // file resumes next time, and the lock ends with the process.
  await Future.any([
    runEvery(
      () => _pullOnce(all, folder),
      every,
      stop: stop,
      log: stdout.writeln,
    ),
    stop,
  ]);
  return 0;
}

Future<int> _check(List<String> args) async {
  final trust = _trust(args);
  final problems = await checkFolder(NodeFolder(_dir(args)), trust);
  for (final p in problems) {
    stdout.writeln(p);
  }
  stdout.writeln(problems.isEmpty ? 'ok' : '${problems.length} problems');
  return problems.isEmpty ? 0 : 1;
}
