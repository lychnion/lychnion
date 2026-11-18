// Finding bases on the local Wi-Fi (docs/distribution.md, step 5e).
//
// A base (the desktop app sharing on the local network) announces itself
// with Bonjour/mDNS as `_lychnion._tcp`, with its name and signing key.
// A phone lists the bases it finds; it connects only after the user picks
// one and answers the same question as for a scanned QR code. Nothing in
// an announcement is trusted: the address is only where to ask, and the
// key works as from a QR code (a computer there with another key is
// refused).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../download/publisher_list.dart' show cleanShownText;
import 'shelter_link.dart';

/// The Bonjour service type of a base.
const baseServiceType = '_lychnion._tcp';

/// At most this many bases are listed (a network could announce many).
const maxFoundBases = 20;

/// What a base announces besides its port: its name and signing key.
Map<String, String> baseAttributes({required String name, String? key}) => {
  'v': '1',
  'name': ?cleanShownText(name),
  if (key != null && isKeyText(key)) 'key': key,
};

/// A signing key as /info and QR codes give it: 32 bytes, base64url
/// without padding.
bool isKeyText(String s) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(s);

/// The Bonjour instance name for [name]: at most 63 bytes (a DNS label).
String instanceName(String name) {
  var s = cleanShownText(name) ?? 'Lychnion';
  while (utf8.encode(s).length > 63) {
    s = String.fromCharCodes(s.runes.take(s.runes.length - 1));
  }
  return s;
}

/// A found base as a link, or null when its announcement is not usable:
/// the first IPv4 address on the local network (bases are reached by
/// IPv4, see ShelterServer.localAddresses), the port, the name and key.
ShelterLink? baseLinkFrom({
  required List<String> addresses,
  required int port,
  required Map<String, String> attributes,
  required String serviceName,
}) {
  if (port <= 0 || port > 65535) return null;
  InternetAddress? v4;
  for (final a in addresses) {
    final ip = InternetAddress.tryParse(a);
    if (ip != null &&
        ip.type == InternetAddressType.IPv4 &&
        !ip.isLoopback &&
        !ip.isLinkLocal &&
        !ip.isMulticast) {
      v4 = ip;
      break;
    }
  }
  if (v4 == null) return null;
  final url = ShelterLink.normalize('${v4.address}:$port');
  if (url == null) return null;
  final key = attributes['key'];
  return ShelterLink(
    url,
    name: cleanShownText(attributes['name']) ?? cleanShownText(serviceName),
    key: key != null && isKeyText(key) ? key : null,
  );
}

/// Announces this computer as a base while it shares.
class BaseAnnouncer {
  BonsoirBroadcast? _broadcast;

  Future<void> start({
    required String name,
    required int port,
    String? key,
  }) async {
    await stop();
    final b = BonsoirBroadcast(
      service: BonsoirService(
        name: instanceName(name),
        type: baseServiceType,
        port: port,
        attributes: baseAttributes(name: name, key: key),
      ),
    );
    await b.initialize();
    await b.start();
    _broadcast = b;
  }

  Future<void> stop() async {
    final b = _broadcast;
    _broadcast = null;
    await b?.stop();
  }
}

/// Lists the bases on the local Wi-Fi while it runs.
class BaseFinder {
  /// The bases found so far, by the order they were found.
  final found = ValueNotifier<List<ShelterLink>>(const []);

  final _byService = <String, ShelterLink>{};
  BonsoirDiscovery? _discovery;
  var _disposed = false;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;

  /// Starts looking. Throws when this platform cannot (then nothing is
  /// listed; a base can still be added by its address or QR code).
  Future<void> start() async {
    final d = BonsoirDiscovery(type: baseServiceType);
    await d.initialize();
    _discovery = d;
    _events = d.eventStream?.listen((e) => _on(d, e));
    await d.start();
  }

  void _on(BonsoirDiscovery d, BonsoirDiscoveryEvent e) {
    switch (e) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        unawaited(
          Future.sync(
            () => d.serviceResolver.resolveService(service),
          ).catchError((Object _) {}),
        );
      case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final link = baseLinkFrom(
          addresses: service.hostAddresses,
          port: service.port,
          attributes: service.attributes,
          serviceName: service.name,
        );
        if (link == null) {
          _byService.remove(service.name);
        } else if (_byService.containsKey(service.name) ||
            _byService.length < maxFoundBases) {
          _byService[service.name] = link;
        }
        _publish();
      case BonsoirDiscoveryServiceLostEvent(:final service):
        _byService.remove(service.name);
        _publish();
      default:
        break;
    }
  }

  void _publish() {
    if (_disposed) return;
    // One entry per address (a base on two interfaces, or announced twice).
    final seen = <String>{};
    found.value = [
      for (final l in _byService.values)
        if (seen.add(l.url)) l,
    ];
  }

  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
    final d = _discovery;
    _discovery = null;
    await d?.stop();
  }

  void dispose() {
    _disposed = true;
    unawaited(stop().catchError((Object _) {}));
    found.dispose();
  }
}
