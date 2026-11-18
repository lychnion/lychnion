import 'dart:async';
import 'dart:io';

import 'package:lychnion_format/lychnion_format.dart';
import 'package:lychnion_node/lychnion_node.dart';

const _usage = '''
Lychnion node: serves signed packages and maps to the app and other nodes.

  lychnion_node serve DIR [--port 8642] [--host 0.0.0.0]
      Serve DIR (catalog.json and blobs/sha256/) over HTTP.

  lychnion_node pull --into DIR [--publisher NAME=KEY]... [--kind KIND]... URL...
      Fetch the catalogs at URL..., keep the records signed by Lychnion
      or by the publishers given, fetch their files by hash into DIR and
      write DIR/catalog.json. Versions only go up. --kind package / map /
      model takes only those (models are gigabytes). Run it from cron to
      keep the node current.

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
    stderr.writeln('${e.path ?? ''}: ${e.osError?.message ?? e.message}');
    exitCode = 74;
  } on SocketException catch (e) {
    stderr.writeln('network: ${e.osError?.message ?? e.message}');
    exitCode = 1;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
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
  final folder = NodeFolder(_dir(args));
  if (!await folder.catalogFile.exists()) {
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
  final done = Completer<void>();
  for (final s in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    s.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
  }
  await done.future;
  await server.stop();
  return 0;
}

Future<int> _pull(List<String> args) async {
  final into = _opt(args, '--into');
  if (into == null) throw _Usage('pull needs --into DIR');
  final trust = _trust(args);
  final kinds = _opts(args, '--kind').toSet();
  for (final k in kinds) {
    if (!const {'package', 'map', 'model'}.contains(k)) {
      throw _Usage('--kind is package, map or model');
    }
  }
  if (args.isEmpty) throw _Usage('pull needs at least one catalog URL');
  final sources = <Uri>[];
  for (final a in args) {
    final u = Uri.tryParse(a);
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
      throw _Usage('not an http(s) address: $a');
    }
    sources.add(u);
  }
  final r = await pull(
    sources,
    NodeFolder(Directory(into)),
    trust,
    kinds: kinds,
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
      '${r.keptUntrusted} records here are from publishers not given now: '
      'left out of the catalog, their files kept',
    );
  }
  stdout.writeln(
    '${r.changed.length} new, ${r.notTrusted} not trusted, '
    '${r.pruned} old files removed, ${r.failed.length} failed',
  );
  return r.failed.isEmpty ? 0 : 1;
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
