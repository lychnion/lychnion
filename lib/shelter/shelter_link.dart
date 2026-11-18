/// Links that tell a phone which shelter computer to use.
///
/// The shelter computer shows `lychnion://shelter?url=…&name=…` as a QR
/// code. Scanning it with the phone's camera opens Lychnion, which asks the
/// user before it connects. A typed address (`192.168.1.20`,
/// `http://192.168.1.20:8642`) works too.
library;

import 'shelter_server.dart';

class ShelterLink {
  const ShelterLink(this.url, {this.name, this.key});

  /// Base URL, e.g. http://192.168.1.20:8642
  final String url;
  final String? name;

  /// The shelter's public signing key: its signed facts are trusted, and a
  /// computer at this address with another key is refused.
  final String? key;

  static const scheme = 'lychnion';

  /// QR codes printed before the rename still open the app.
  static const oldScheme = 'fieldkit';

  Uri toUri() => Uri(
    scheme: scheme,
    host: 'shelter',
    queryParameters: {'url': url, 'name': ?name, 'key': ?key},
  );

  /// A lychnion:// (or old fieldkit://) link, or null if [uri] is
  /// something else.
  static ShelterLink? fromUri(Uri uri) {
    if ((uri.scheme != scheme && uri.scheme != oldScheme) ||
        uri.host != 'shelter') {
      return null;
    }
    final url = normalize(uri.queryParameters['url'] ?? '');
    if (url == null) return null;
    final name = uri.queryParameters['name'];
    final key = uri.queryParameters['key'];
    return ShelterLink(
      url,
      name: name == null || name.isEmpty ? null : name,
      key: key == null || key.isEmpty ? null : key,
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
    final port = u.hasPort ? u.port : ShelterServer.defaultPort;
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
    scheme: ShelterLink.scheme,
    host: 'share',
    queryParameters: {'url': url},
  );

  static ShareLink? fromUri(Uri uri) {
    if (uri.scheme != ShelterLink.scheme || uri.host != 'share') return null;
    final url = ShelterLink.normalize(uri.queryParameters['url'] ?? '');
    return url == null ? null : ShareLink(url);
  }
}
