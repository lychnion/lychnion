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
  });

  final Uri url;

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
/// Use one instance per download: stopping closes its HTTP client.
class Downloader {
  Downloader({
    HttpClient? client,
    this.idleTimeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration idleTimeout;

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
    var digest = _Sha256Sink();
    try {
      // Hash what is already there, so the final check covers the whole file.
      if (have > 0) {
        var done = 0;
        await for (final chunk in part.openRead(0, have)) {
          if (cancel?.isCancelled ?? false) throw DownloadCancelled();
          digest.add(chunk);
          done += chunk.length;
          onProgress?.call(DownloadPhase.checkingPart, done, have);
        }
      }
      if (have < spec.size) {
        digest = await _receive(spec, raf, have, digest, onProgress, cancel);
      }
    } finally {
      await raf.unlock();
      await raf.close();
    }

    onProgress?.call(DownloadPhase.verifying, spec.size, spec.size);
    final actual = digest.close();
    if (actual != spec.sha256) {
      await deletePart(dir, spec.name);
      throw ChecksumError(spec.name, spec.sha256, actual);
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

  /// Appends the rest of the file to [raf]. Returns the digest of the
  /// whole file (a new one if the server sent everything again).
  Future<_Sha256Sink> _receive(
    FileSpec spec,
    RandomAccessFile raf,
    int have,
    _Sha256Sink digest,
    void Function(DownloadPhase phase, int bytes, int total)? onProgress,
    CancelToken? cancel,
  ) async {
    final response = await _open(spec.url, have, cancel);
    if (have > 0 && response.statusCode == HttpStatus.ok) {
      // Server ignored the range: start again.
      have = 0;
      digest = _Sha256Sink();
      await raf.truncate(0);
      await raf.setPosition(0);
    } else if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: spec.url);
    }
    var bytes = have;
    cancel?._onCancel(() {
      // Closing the connection ends the stream with an error below.
      _client.close(force: true);
    });
    try {
      await for (final chunk in response.timeout(idleTimeout)) {
        if (cancel?.isCancelled ?? false) throw DownloadCancelled();
        await raf.writeFrom(chunk);
        digest.add(chunk);
        bytes += chunk.length;
        if (bytes > spec.size) {
          throw HttpException('More data than expected', uri: spec.url);
        }
        onProgress?.call(DownloadPhase.downloading, bytes, spec.size);
      }
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      rethrow;
    } finally {
      await raf.flush();
    }
    if (cancel?.isCancelled ?? false) throw DownloadCancelled();
    if (bytes < spec.size) {
      throw HttpException(
        'Connection ended at $bytes of ${spec.size} bytes',
        uri: spec.url,
      );
    }
    return digest;
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
      final req = await _client.getUrl(uri).timeout(idleTimeout);
      req.followRedirects = false;
      // Byte ranges only make sense on the file as stored.
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final res = await req.close().timeout(idleTimeout);
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null) {
          throw HttpException('Redirect without target', uri: uri);
        }
        uri = uri.resolve(loc);
        continue;
      }
      return res;
    }
    throw HttpException('Too many redirects', uri: url);
  }

  void close() => _client.close(force: true);
}

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
