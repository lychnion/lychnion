/// Links that tell a phone which base computer to use.
///
/// The base computer shows `lychnion://base?url=…&name=…&key=…` as a QR
/// code. Scanning it with the phone's camera opens Lychnion, which asks the
/// user before it connects. A typed address (`192.168.1.20`,
/// `http://192.168.1.20:8642`) works too.
///
/// A web page or a message can open the same link, so its key only names
/// the computer to connect to. Its notices count as official only after
/// the user compared the key's code with the base's screen
/// (base_key_code.dart, lychnion/lychnion#63).
library;

import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode;

import '../download/publisher_list.dart' show cleanShownText;
import 'base_discovery.dart' show isPrivateIPv4;
import 'base_server.dart';

class BaseLink {
  const BaseLink(this.url, {this.name, this.key, this.signs = false});

  /// Base URL, e.g. http://192.168.1.20:8642
  final String url;
  final String? name;

  /// The base's public signing key: a computer at this address with
  /// another key is refused. Its signed facts are trusted only after the
  /// user compared the key's code.
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
  /// with [key], whose base is known to sign with [signedKey]. With
  /// [keyTrusted] false the link is still asked about: the user may now
  /// compare the key's code.
  bool changesNothing({
    required String? url,
    required String? key,
    required String? signedKey,
    bool keyTrusted = true,
  }) =>
      this.url == url &&
      (this.key == null ||
          (this.key == key && keyTrusted && (!signs || signedKey == this.key)));

  /// A lychnion:// link, or null if [uri] is something else.
  static BaseLink? fromUri(Uri uri) {
    if (uri.scheme != scheme || (uri.host != host && uri.host != oldHost)) {
      return null;
    }
    final url = normalize(uri.queryParameters['url'] ?? '');
    if (url == null) return null;
    // Shown in dialogs and Settings, and anyone can write a link: no
    // control or direction-changing characters, at most 60 characters.
    final name = cleanShownText(uri.queryParameters['name']);
    final rawKey = uri.queryParameters['key'];
    final key = rawKey == null || rawKey.isEmpty ? null : rawKey;
    return BaseLink(
      url,
      name: name,
      key: key,
      signs: key != null && uri.queryParameters['s'] == '1',
    );
  }

  /// Turns what a user typed into a base URL, or null if it is not one.
  /// Adds http:// and the default port when they are missing. Only hosts
  /// on the local network ([isLocalHost]): a base is a computer at the
  /// same place, and a link from a web page must not send the phone's
  /// questions to a server on the internet (lychnion/lychnion#72).
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
    if (u.userInfo.isNotEmpty || !isLocalHost(u.host)) return null;
    final port = u.hasPort ? u.port : BaseServer.defaultPort;
    if (port < 1 || port > 65535) return null;
    // An IPv6 address keeps its brackets in a URL.
    final host = u.host.contains(':') ? '[${u.host}]' : u.host;
    return '${u.scheme}://$host:$port';
  }

  /// Whether [host] is on the local network: a private IPv4 address (the
  /// ranges discovery lists, isPrivateIPv4), a link-local or private IPv6
  /// address (fe80::/10, fc00::/7), or a `.local` name (mDNS; a DNS server
  /// could still point one elsewhere, see threat-model.md
  /// `device-egress`). Loopback only with [loopback]: in debug builds (a
  /// simulator reaching a base on the same computer) and on desktops, not
  /// on a phone, where it would be another app. Not a public address or
  /// another name, which DNS could point anywhere.
  static bool isLocalHost(String host, {bool? loopback}) {
    final h = host.toLowerCase();
    if (h.endsWith('.local') && h.length > '.local'.length) return true;
    final a = InternetAddress.tryParse(h);
    if (a == null) return false;
    if (a.isLoopback) return loopback ?? _loopbackAllowed;
    if (a.isLinkLocal) return true;
    if (a.type == InternetAddressType.IPv4) return isPrivateIPv4(a);
    return (a.rawAddress[0] & 0xfe) == 0xfc;
  }

  static bool get _loopbackAllowed =>
      kDebugMode ||
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };
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
