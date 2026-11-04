/// Links that tell a phone which shelter computer to use.
///
/// The shelter computer shows `fieldkit://shelter?url=…&name=…` as a QR
/// code. Scanning it with the phone's camera opens fieldkit, which asks the
/// user before it connects. A typed address (`192.168.1.20`,
/// `http://192.168.1.20:8642`) works too.
library;

import 'shelter_server.dart';

class ShelterLink {
  const ShelterLink(this.url, {this.name});

  /// Base URL, e.g. http://192.168.1.20:8642
  final String url;
  final String? name;

  static const scheme = 'fieldkit';

  Uri toUri() => Uri(
    scheme: scheme,
    host: 'shelter',
    queryParameters: {'url': url, 'name': ?name},
  );

  /// A fieldkit:// link, or null if [uri] is something else.
  static ShelterLink? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != 'shelter') return null;
    final url = normalize(uri.queryParameters['url'] ?? '');
    if (url == null) return null;
    final name = uri.queryParameters['name'];
    return ShelterLink(url, name: name == null || name.isEmpty ? null : name);
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
