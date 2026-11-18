import 'dart:async';
import 'dart:io';

import 'node_folder.dart';

/// Serves a node folder over plain HTTP, to the app and to other nodes:
///
/// - `GET /catalog.json`
/// - `GET /blobs/sha256/<sha256>`, resumable (Range)
/// - `GET /`: one line saying what this is
///
/// HEAD works for all of them; nothing else is served (no listing, no
/// other paths). The files need no trust: phones check every record's
/// signature and every file's hash.
class NodeServer {
  NodeServer(this.folder, {this.port = defaultPort, this.address, this.log});

  /// Same port as a base (the shelter computer), so a phone that knows
  /// a node's address finds it the same way.
  static const defaultPort = 8642;

  final NodeFolder folder;
  final int port;

  /// Default: every IPv4 address of this machine.
  final InternetAddress? address;

  /// One line per request (method, path, status, bytes).
  final void Function(String line)? log;

  HttpServer? _server;

  /// The port actually bound (useful with port 0 in tests).
  int get boundPort => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((req) => unawaited(_handle(req)));
  }

  Future<void> stop() async => _server?.close(force: true);

  static final _blob = RegExp(r'^/blobs/sha256/([0-9a-f]{64})$');

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    var status = 200, bytes = 0;
    try {
      res.headers.set('Access-Control-Allow-Origin', '*');
      if (req.method != 'GET' && req.method != 'HEAD') {
        status = HttpStatus.methodNotAllowed;
        res
          ..statusCode = status
          ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }
      final path = req.uri.path;
      File? file;
      if (path == '/catalog.json') {
        file = folder.catalogFile;
        res.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      } else if (_blob.firstMatch(path) case final m?) {
        file = folder.blob(m[1]!);
        res.headers
          ..contentType = ContentType.binary
          // A file never changes: its name is its hash.
          ..set(HttpHeaders.cacheControlHeader, 'public, max-age=31536000');
      } else if (path == '/') {
        res.headers.contentType = ContentType.text;
        const text = 'Lychnion node. Catalog: /catalog.json\n';
        bytes = text.length;
        if (req.method == 'GET') res.write(text);
        return;
      }
      if (file == null || !await file.exists()) {
        status = HttpStatus.notFound;
        res.statusCode = status;
        return;
      }
      final length = await file.length();
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      var start = 0, end = length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final r = _parseRange(range, length);
        if (r == null) {
          status = HttpStatus.requestedRangeNotSatisfiable;
          res
            ..statusCode = status
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
          return;
        }
        (start, end) = r;
        status = HttpStatus.partialContent;
        res
          ..statusCode = status
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$length',
          );
      }
      bytes = end - start + 1;
      res.contentLength = bytes;
      if (req.method == 'GET' && bytes > 0) {
        await res.addStream(file.openRead(start, end + 1));
      }
    } on Object catch (e) {
      status = HttpStatus.internalServerError;
      try {
        res.statusCode = status;
      } on Object {
        // Headers already sent: the connection just ends.
      }
      log?.call('error ${req.uri.path}: ${e.runtimeType}');
    } finally {
      try {
        await res.close();
      } on Object {
        // The other side went away.
      }
      log?.call('${req.method} ${req.uri.path} $status $bytes');
    }
  }

  /// `bytes=a-`, `bytes=a-b` or `bytes=-n` of a file of [length] bytes, as
  /// (first, last) byte; null when it cannot be served.
  static (int, int)? _parseRange(String header, int length) {
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null || length == 0) return null;
    final a = m[1]!, b = m[2]!;
    if (a.isEmpty && b.isEmpty) return null;
    if (a.isEmpty) {
      final n = int.tryParse(b);
      if (n == null || n == 0) return null;
      return (n >= length ? 0 : length - n, length - 1);
    }
    final start = int.tryParse(a);
    if (start == null || start >= length) return null;
    var end = b.isEmpty ? length - 1 : int.tryParse(b);
    if (end == null || end < start) return null;
    if (end >= length) end = length - 1;
    return (start, end);
  }
}
