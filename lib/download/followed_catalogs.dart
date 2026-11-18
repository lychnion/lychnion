import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'publisher_list.dart' show cleanShownText;

// Catalogs the user follows (docs/distribution.md, step 4c): a city's or a
// club's catalog on its web server, next to Lychnion's. Following a catalog
// trusts nobody: only records of Lychnion and of publishers the user added
// show up (publisher links, step 4a).

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
Future<String> fetchCatalogText(
  Uri url, {
  int maxBytes = maxCatalogBytes,
  Duration limit = const Duration(seconds: 45),
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 5);
  final sw = Stopwatch()..start();
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 15));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
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

/// `lychnion://catalog?url=…&name=…`, shown as a QR code or link by
/// whoever runs the catalog.
class CatalogLink {
  const CatalogLink(this.url, {this.name});

  final Uri url;

  /// Shown next to the address; not checked.
  final String? name;

  static const scheme = 'lychnion';

  Uri toUri() => Uri(
    scheme: scheme,
    host: 'catalog',
    queryParameters: {'url': '$url', 'name': ?name},
  );

  static CatalogLink? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != 'catalog') return null;
    final url = normalize(uri.queryParameters['url'] ?? '');
    if (url == null) return null;
    final name = _cleanName(uri.queryParameters['name']);
    return CatalogLink(url, name: name);
  }

  /// A catalog address from a link or from what the user pasted: http(s)
  /// with a host, no user name or password. Null otherwise.
  static Uri? normalize(String input) {
    if (input.length > 2048) return null;
    final u = Uri.tryParse(input.trim());
    if (u == null || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
    if (!u.isScheme('http') && !u.isScheme('https')) return null;
    return u.removeFragment();
  }

  static String? _cleanName(String? t) => cleanShownText(t);
}

class FollowedCatalog {
  const FollowedCatalog(this.url, {this.name, required this.added});
  final Uri url;
  final String? name;
  final DateTime added;

  Map<String, Object?> toJson() => {
    'url': '$url',
    'name': ?name,
    'added': added.toUtc().toIso8601String(),
  };
}

/// What a followed catalog gave the last time it was read.
class CatalogStatus {
  const CatalogStatus({
    this.shown = 0,
    this.notShown = 0,
    this.fetched,
    this.error,
  });

  /// Records shown in Downloads.
  final int shown;

  /// Records left out: their publisher is not added, or a bad signature.
  final int notShown;

  /// When the copy in use was fetched (null: never).
  final DateTime? fetched;

  /// Short code of the last failed fetch (`offline`, `HTTP 404`, …), or
  /// null when the last fetch worked.
  final String? error;
}

/// The followed catalogs, saved in `catalogs.json`, with the last copy of
/// each in `followed/`, so they work offline.
class FollowedCatalogs extends ChangeNotifier {
  FollowedCatalogs(this.dir);

  /// The downloads folder.
  final Directory dir;

  /// More would only slow every refresh.
  static const max = 20;

  File get _file => File('${dir.path}/catalogs.json');
  Directory get _cache => Directory('${dir.path}/followed');

  final _list = <FollowedCatalog>[];
  final status = <Uri, CatalogStatus>{};

  List<FollowedCatalog> get all => List.unmodifiable(_list);

  bool follows(Uri url) => _list.any((c) => c.url == url);

  Future<void> load() async {
    _list.clear();
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      for (final e in (j['catalogs'] as List?) ?? const []) {
        try {
          final m = e as Map;
          final url = CatalogLink.normalize(m['url'] as String);
          if (url == null || follows(url) || _list.length >= max) continue;
          _list.add(
            FollowedCatalog(
              url,
              name: CatalogLink._cleanName(m['name'] as String?),
              added:
                  DateTime.tryParse(m['added'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
        } on Object {
          continue;
        }
      }
    } on Object {
      // No file yet, or a broken one: no followed catalogs.
    }
    // Copies of catalogs no longer followed (a crash between steps) and
    // half-written copies are removed.
    try {
      final keep = {for (final c in _list) cacheFile(c.url).path};
      for (final f in _cache.listSync().whereType<File>()) {
        if (!keep.contains(f.path)) f.deleteSync();
      }
    } on Object {
      // No folder yet.
    }
    notifyListeners();
  }

  /// One change at a time: each saves the list as the one before left it.
  Future<void> _last = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _last.then((_) => f());
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Follows [link] (after the user agreed). False when it is followed
  /// already or the list is full. Throws when it cannot be saved.
  Future<bool> add(CatalogLink link) => _serial(() async {
    if (follows(link.url) || _list.length >= max) return false;
    final next = [
      ..._list,
      FollowedCatalog(link.url, name: link.name, added: DateTime.now()),
    ];
    await _save(next);
    _list
      ..clear()
      ..addAll(next);
    notifyListeners();
    return true;
  });

  /// Stops following [url] and forgets its copy. What was installed from
  /// it stays (it is signed by a trusted publisher).
  Future<void> remove(Uri url) => _serial(() async {
    if (!follows(url)) return;
    final next = [
      for (final c in _list)
        if (c.url != url) c,
    ];
    await _save(next);
    _list
      ..clear()
      ..addAll(next);
    status.remove(url);
    try {
      await cacheFile(url).delete();
    } on FileSystemException {
      // No copy yet.
    }
    notifyListeners();
  });

  Future<void> _save(List<FollowedCatalog> list) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'catalogs': [for (final c in list) c.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  File cacheFile(Uri url) => File(
    '${_cache.path}/${sha256.convert(utf8.encode('$url')).toString().substring(0, 24)}.json',
  );

  /// The last copy of [url]'s catalog, if any.
  Future<({String body, DateTime fetched})?> cached(Uri url) async {
    try {
      final j = jsonDecode(await cacheFile(url).readAsString()) as Map;
      return (
        body: j['body'] as String,
        fetched: DateTime.parse(j['fetched'] as String),
      );
    } on Object {
      return null;
    }
  }

  Future<void> keep(Uri url, String body) async {
    await _cache.create(recursive: true);
    final f = cacheFile(url);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'url': '$url',
        'fetched': DateTime.now().toUtc().toIso8601String(),
        'body': body,
      }),
      flush: true,
    );
    await tmp.rename(f.path);
  }

  void setStatus(Uri url, CatalogStatus s) {
    status[url] = s;
    notifyListeners();
  }
}
