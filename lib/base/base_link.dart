/// Links that tell a phone which base computer to use.
///
/// The base computer shows `lychnion://base?url=…&name=…&key=…` as a QR
/// code. Scanning it with the phone's camera opens Lychnion, which asks the
/// user before it connects. A typed address (`192.168.1.20`,
/// `http://192.168.1.20:8642`) works too.
library;

import 'base_server.dart';

class BaseLink {
  const BaseLink(this.url, {this.name, this.key, this.signs = false});

  /// Base URL, e.g. http://192.168.1.20:8642
  final String url;
  final String? name;

  /// The base's public signing key: its signed facts are trusted, and a
  /// computer at this address with another key is refused.
  final String? key;

  /// The base signs its answers with [key] (`s=1`, from bases that sign):
  /// the phone refuses unsigned answers from the first one. Old QR codes
  /// do not say so; the phone then learns it from the first signed answer.
  final bool signs;

  static const scheme = 'lychnion';

  /// The link's host.
  static const host = 'base';

  /// The host before the base was called a base: still read.
  static const oldHost = 'shelter';

  Uri toUri() => Uri(
    scheme: scheme,
    host: host,
    queryParameters: {
      'url': url,
      'name': ?name,
      'key': ?key,
      if (signs && key != null) 's': '1',
    },
  );

  /// Whether this link changes nothing for a phone connected to [url]
  /// with [key], whose base is known to sign with [signedKey].
  bool changesNothing({
    required String? url,
    required String? key,
    required String? signedKey,
  }) =>
      this.url == url &&
      (this.key == null ||
          (this.key == key && (!signs || signedKey == this.key)));

  /// A lychnion:// link, or null if [uri] is something else.
  static BaseLink? fromUri(Uri uri) {
    if (uri.scheme != scheme || (uri.host != host && uri.host != oldHost)) {
      return null;
    }
    final url = normalize(uri.queryParameters['url'] ?? '');
    if (url == null) return null;
    final name = uri.queryParameters['name'];
    final rawKey = uri.queryParameters['key'];
    final key = rawKey == null || rawKey.isEmpty ? null : rawKey;
    return BaseLink(
      url,
      name: name == null || name.isEmpty ? null : name,
      key: key,
      signs: key != null && uri.queryParameters['s'] == '1',
    );
  }

  /// Turns what a user typed into a base URL, or null if it is not one.
  /// Adds http:// and the default port when they are missing.
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    if (u.hasQuery || u.hasFragment || (u.path.isNotEmpty && u.path != '/')) {
      return null;
    }
    final port = u.hasPort ? u.port : BaseServer.defaultPort;
    return '${u.scheme}://${u.host}:$port';
  }
}

/// A phone sharing its downloads with phones nearby:
/// `lychnion://share?url=http://<address>:8643`. The receiving phone adds
/// that phone's signed catalog to Downloads; it does not ask it questions.
class ShareLink {
  const ShareLink(this.url);

  /// Base URL, e.g. http://192.168.43.1:8643
  final String url;

  Uri toUri() => Uri(
    scheme: BaseLink.scheme,
    host: 'share',
    queryParameters: {'url': url},
  );

  static ShareLink? fromUri(Uri uri) {
    if (uri.scheme != BaseLink.scheme || uri.host != 'share') return null;
    final url = BaseLink.normalize(uri.queryParameters['url'] ?? '');
    return url == null ? null : ShareLink(url);
  }
}
