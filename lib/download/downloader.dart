import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One file to fetch: where from, where to, and what it must be.
class FileSpec {
  const FileSpec({
    required this.url,
    required this.name,
    required this.size,
    required this.sha256,
    this.fallbacks = const [],
  });

  final Uri url;

  /// Other places with the same file (mirrors), tried in order when [url]
  /// is unreachable, answers with an error, or sends a wrong file.
  final List<Uri> fallbacks;

  List<Uri> get urls => [url, ...fallbacks];

  /// File name in the target folder.
  final String name;
  final int size;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;
}

class ChecksumError implements Exception {
  ChecksumError(this.name, this.expected, this.actual);
  final String name, expected, actual;
  @override
  String toString() => 'Checksum mismatch for $name';
}

/// Lets the UI stop a download. The part file stays for resuming.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }

  void _onCancel(void Function() l) => _listeners.add(l);
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download stopped';
}

/// Another app instance is downloading the same file.
class DownloadBusy implements Exception {
  @override
  String toString() => 'Already downloading in another window';
}

/// Phases reported to [Downloader.onProgress].
enum DownloadPhase { checkingPart, downloading, verifying }

/// Downloads one file with resume (HTTP Range) and SHA-256 check.
///
/// Writes to `<name>.part` next to the target, with `<name>.part.json`
/// remembering which file (sha256) the part belongs to. Only a file whose
/// size and hash match is renamed to its final name, so loaders never see
/// a partial or wrong file.
///
/// A file can have several addresses ([FileSpec.fallbacks]). When one fails
/// (unreachable, an HTTP error, the connection drops) the download goes on
/// from the next one where it stopped: the part belongs to the hash, not
/// to a server. When the finished file has the wrong hash, it starts again
/// from the next address not used yet.
///
/// Use one instance per download: stopping closes its HTTP client.
class Downloader {
  Downloader({
    HttpClient? client,
    this.idleTimeout = const Duration(seconds: 30),
    this.onSourceFailed,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration idleTimeout;

  /// Called when an address fails and the next one is tried (for logs).
  final void Function(Uri url, Object error)? onSourceFailed;

  /// Errors after which another address may work.
  static bool _sourceError(Object e) =>
      e is SocketException ||
      e is HttpException ||
      e is TimeoutException ||
      e is TlsException;

  static File partFile(Directory dir, String name) =>
      File('${dir.path}/$name.part');
  static File _partMeta(Directory dir, String name) =>
      File('${dir.path}/$name.part.json');

  /// Bytes already downloaded for [spec], or 0.
  static int partBytes(Directory dir, FileSpec spec) {
    final part = partFile(dir, spec.name);
    final meta = _partMeta(dir, spec.name);
    if (!part.existsSync() || !meta.existsSync()) return 0;
    try {
      final m = jsonDecode(meta.readAsStringSync()) as Map;
      if (m['sha256'] != spec.sha256) return 0;
    } catch (_) {
      return 0;
    }
    return part.lengthSync();
  }

  static Future<void> deletePart(Directory dir, String name) async {
    for (final f in [partFile(dir, name), _partMeta(dir, name)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Fetches [spec] into [dir]. Returns the final file.
  Future<File> fetch(
    FileSpec spec,
    Directory dir, {
    void Function(DownloadPhase phase, int bytes, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    await dir.create(recursive: true);
    final target = File('${dir.path}/${spec.name}');
    final part = partFile(dir, spec.name);
    final meta = _partMeta(dir, spec.name);

    // A part of another version (or without meta) cannot be resumed.
    var have = partBytes(dir, spec);
    if (have == 0 || have > spec.size) {
      await deletePart(dir, spec.name);
      have = 0;
    }
    await meta.writeAsString(
      jsonEncode({'url': spec.url.toString(), 'sha256': spec.sha256}),
    );

    // One writer per part file, also across app instances (desktop).
    final raf = await part.open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      throw DownloadBusy();
    }
    final urls = spec.urls;
    var next = 0; // first address not used yet
    // After a wrong file: the addresses still to try, each alone and from
    // byte 0, so bytes of one source never mix with another's.
    List<int>? alone;
    String? wrong; // hash of a wrong file, after every address was tried
    try {
      final p = _Part(have, _Sha256Sink());
      // A part from an earlier run: its source is unknown.
      if (have > 0) p.writers.add(-1);
      Future<void> restart() async {
        p
          ..have = 0
          ..digest = _Sha256Sink()
          ..writers.clear();
        await raf.truncate(0);
        await raf.setPosition(0);
      }

      // Hash what is already there, so the final check covers the whole
      // file.
      if (have > 0) {
        var done = 0;
        await for (final chunk in part.openRead(0, have)) {
          if (cancel?.isCancelled ?? false) throw DownloadCancelled();
          p.digest.add(chunk);
          done += chunk.length;
          onProgress?.call(DownloadPhase.checkingPart, done, have);
        }
      }
      while (true) {
        while (p.have < spec.size) {
          final i = alone?.first ?? next;
          try {
            await _receive(spec, urls[i], i, raf, p, onProgress, cancel);
          } catch (e) {
            if (cancel?.isCancelled ?? false) throw DownloadCancelled();
            if (!_sourceError(e)) rethrow;
            if (alone == null) {
              if (next + 1 >= urls.length) rethrow;
              next++;
            } else {
              if (alone.length == 1) rethrow;
              alone.removeAt(0);
              await restart();
            }
            onSourceFailed?.call(urls[i], e);
          }
        }
        onProgress?.call(DownloadPhase.verifying, spec.size, spec.size);
        final actual = p.digest.close();
        if (actual == spec.sha256) break;
        final error = ChecksumError(spec.name, spec.sha256, actual);
        if (alone == null) {
          // One known source wrote it all: that one is wrong. Otherwise
          // any of them may be, so every address gets a turn of its own.
          final bad = p.writers.length == 1 && p.writers.first >= 0
              ? p.writers.first
              : null;
          if (bad != null) onSourceFailed?.call(urls[bad], error);
          alone = [
            for (var i = 0; i < urls.length; i++)
              if (i != bad) i,
          ];
        } else {
          final i = alone.removeAt(0);
          onSourceFailed?.call(urls[i], error);
        }
        if (alone.isEmpty) {
          wrong = actual;
          break;
        }
        await restart();
      }
    } finally {
      await raf.unlock();
      await raf.close();
    }
    if (wrong != null) {
      await deletePart(dir, spec.name);
      throw ChecksumError(spec.name, spec.sha256, wrong);
    }
    try {
      await part.rename(target.path); // replaces the old file (POSIX)
    } on FileSystemException {
      // Windows does not replace on rename.
      if (!await target.exists()) rethrow;
      await target.delete();
      await part.rename(target.path);
    }
    await meta.delete();
    return target;
  }

  /// Appends the rest of the file from [url] to [raf], keeping [p] (bytes
  /// written and their hash) up to date even when it fails half-way, so
  /// the next address can go on from there.
  Future<void> _receive(
    FileSpec spec,
    Uri url,
    int source,
    RandomAccessFile raf,
    _Part p,
    void Function(DownloadPhase phase, int bytes, int total)? onProgress,
    CancelToken? cancel,
  ) async {
    final response = await _open(url, p.have, cancel);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await _discard(response);
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    // Nothing is written unless the answer is the expected part of a file
    // of the expected size (not a captive portal's page, not another file).
    final problem = _mismatch(response, p.have, spec.size);
    if (problem != null) {
      await _discard(response);
      throw HttpException(problem, uri: url);
    }
    if (p.have > 0 && response.statusCode == HttpStatus.ok) {
      // Server ignored the range: start again.
      p
        ..have = 0
        ..digest = _Sha256Sink()
        ..writers.clear();
      await raf.truncate(0);
      await raf.setPosition(0);
    }
    cancel?._onCancel(() {
      // Closing the connection ends the stream with an error below.
      _client.close(force: true);
    });
    try {
      await for (final chunk in response.timeout(idleTimeout)) {
        if (cancel?.isCancelled ?? false) throw DownloadCancelled();
        if (p.have + chunk.length > spec.size) {
          throw HttpException('More data than expected', uri: url);
        }
        await raf.writeFrom(chunk);
        p.writers.add(source);
        p.digest.add(chunk);
        p.have += chunk.length;
        onProgress?.call(DownloadPhase.downloading, p.have, spec.size);
      }
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      rethrow;
    } finally {
      await raf.flush();
    }
    if (cancel?.isCancelled ?? false) throw DownloadCancelled();
    if (p.have < spec.size) {
      throw HttpException(
        'Connection ended at ${p.have} of ${spec.size} bytes',
        uri: url,
      );
    }
  }

  /// Drops an answer whose body is not wanted, without reading it (a body
  /// that never ends must not hold up the next address).
  static Future<void> _discard(HttpClientResponse res) async {
    try {
      (await res.detachSocket()).destroy();
    } on Object {
      // Already closed.
    }
  }

  /// Why [res] cannot be the rest of a file of [size] bytes from byte
  /// [from], or null when it can.
  static String? _mismatch(HttpClientResponse res, int from, int size) {
    if (res.statusCode == HttpStatus.ok) {
      final n = res.contentLength;
      return n == -1 || n == size ? null : 'Wrong size: $n, expected $size';
    }
    final range = res.headers.value(HttpHeaders.contentRangeHeader);
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range ?? '');
    // tryParse: a number too large for an int is a mismatch, not a crash.
    if (m == null ||
        int.tryParse(m[1]!) != from ||
        int.tryParse(m[2]!) != size - 1 ||
        int.tryParse(m[3]!) != size) {
      return 'Wrong range: $range, expected bytes $from-${size - 1}/$size';
    }
    return null;
  }

  /// GET with an optional Range header. Follows redirects by hand so the
  /// Range header survives the hop to a CDN (Hugging Face does this).
  Future<HttpClientResponse> _open(
    Uri url,
    int from,
    CancelToken? cancel,
  ) async {
    var uri = url;
    for (var hop = 0; hop < 10; hop++) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      if (!uri.isScheme('http') && !uri.isScheme('https')) {
        throw HttpException('Not an http(s) address', uri: uri);
      }
      final HttpClientRequest req;
      try {
        req = await _client.getUrl(uri).timeout(idleTimeout);
      } on ArgumentError catch (e) {
        throw HttpException('$e', uri: uri);
      }
      req.followRedirects = false;
      // Byte ranges only make sense on the file as stored.
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final res = await req.close().timeout(idleTimeout);
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await _discard(res);
        if (loc == null) {
          throw HttpException('Redirect without target', uri: uri);
        }
        final next = Uri.tryParse(loc);
        if (next == null) throw HttpException('Bad redirect', uri: uri);
        uri = uri.resolveUri(next);
        continue;
      }
      return res;
    }
    throw HttpException('Too many redirects', uri: url);
  }

  void close() => _client.close(force: true);
}

/// [url] for logs: no user name or password, no query or fragment (signed
/// links carry their tokens there).
String redactedUrl(Uri url) => Uri(
  scheme: url.scheme,
  host: url.host,
  port: url.hasPort ? url.port : null,
  path: url.path,
).toString();

/// A download error for logs, without the address it came from.
String sourceErrorText(Object e) => switch (e) {
  HttpException(:final message) => message,
  SocketException(:final message, :final osError) =>
    osError == null ? message : '$message (${osError.message})',
  ChecksumError() => 'Checksum mismatch',
  TimeoutException() => 'Timed out',
  TlsException(:final message) => 'TLS: $message',
  _ => e.runtimeType.toString(),
};

/// Hashes a file on disk (to adopt files copied by cable).
Future<String> sha256OfFile(
  File file, {
  void Function(int bytes)? onProgress,
  CancelToken? cancel,
}) async {
  final d = _Sha256Sink();
  var n = 0;
  await for (final chunk in file.openRead()) {
    if (cancel?.isCancelled ?? false) throw DownloadCancelled();
    d.add(chunk);
    n += chunk.length;
    onProgress?.call(n);
  }
  return d.close();
}

/// The part file so far: bytes written and their running hash.
class _Part {
  _Part(this.have, this.digest);
  int have;
  _Sha256Sink digest;

  /// Addresses (by position) whose bytes are in the part; -1: from an
  /// earlier run.
  final writers = <int>{};
}

class _Sha256Sink {
  _Sha256Sink() {
    _input = sha256.startChunkedConversion(_out);
  }
  final _out = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> chunk) => _input.add(chunk);
  String close() {
    _input.close();
    return _out.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
