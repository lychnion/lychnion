import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Why a catalog could not be fetched: `offline` (no answer in time),
/// `HTTP <status>`, `too large`, or `invalid` (not text).
class CatalogFetchError implements Exception {
  CatalogFetchError(this.code);
  final String code;
  @override
  String toString() => 'CatalogFetchError($code)';
}

/// Catalogs are small (Lychnion's is a few kilobytes): anything larger
/// than this is refused while it arrives, before it fills the memory.
const maxCatalogBytes = 2 << 20;

/// Fetches a catalog's text: an answer other than 200 is refused at once
/// (its body is not read), the body is counted while it arrives and
/// refused above [maxBytes] (also after decompression), and the whole
/// fetch has a time limit.
///
/// With [followRedirects] false (a device on the local network), a
/// redirect is refused like any other answer than 200: that device must
/// not send the phone to a host it picks.
Future<String> fetchCatalogText(
  Uri url, {
  int maxBytes = maxCatalogBytes,
  Duration limit = const Duration(seconds: 45),
  bool followRedirects = true,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 5);
  final sw = Stopwatch()..start();
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 15));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.followRedirects = followRedirects;
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != HttpStatus.ok) {
      throw CatalogFetchError('HTTP ${res.statusCode}');
    }
    if (res.contentLength > maxBytes) throw CatalogFetchError('too large');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw CatalogFetchError('too large');
      }
      if (sw.elapsed > limit) throw CatalogFetchError('offline');
      bytes.add(chunk);
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw CatalogFetchError('invalid');
    }
  } on CatalogFetchError {
    rethrow;
  } on Object {
    throw CatalogFetchError('offline');
  } finally {
    // Also ends an answer whose body was not read.
    client.close(force: true);
  }
}
