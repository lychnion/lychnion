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
///
/// [allowAddress] is asked before each redirect is followed (at most 5):
/// a node pulling an internet catalog refuses one that leads to its own
/// network (lychnion/lychnion#74), as it does for file addresses.
Future<String> fetchCatalogText(
  Uri url, {
  int maxBytes = maxCatalogBytes,
  Duration limit = const Duration(seconds: 45),
  bool followRedirects = true,
  Future<bool> Function(Uri to)? allowAddress,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 5);
  final sw = Stopwatch()..start();
  try {
    var uri = url;
    late HttpClientResponse res;
    for (var hop = 0; ; hop++) {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // With a check, redirects are followed here, one at a time.
      req.followRedirects = followRedirects && allowAddress == null;
      res = await req.close().timeout(const Duration(seconds: 15));
      if (!followRedirects || allowAddress == null || !res.isRedirect) break;
      final loc = res.headers.value(HttpHeaders.locationHeader);
      // The redirect's own body is not read: a host trickling one must not
      // hold the fetch, and all hops share the one time limit.
      await res
          .drain<void>()
          .timeout(const Duration(seconds: 5))
          .catchError((Object _) {});
      if (sw.elapsed > limit) throw CatalogFetchError('offline');
      final next = loc == null ? null : Uri.tryParse(loc);
      if (next == null || hop >= 5) {
        throw CatalogFetchError('HTTP ${res.statusCode}');
      }
      uri = uri.resolveUri(next);
      if ((!uri.isScheme('http') && !uri.isScheme('https')) ||
          !await allowAddress(uri)) {
        throw CatalogFetchError('redirect not allowed');
      }
    }
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
