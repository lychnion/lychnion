// Finding bases on the local Wi-Fi (docs/distribution.md, step 5e).
//
// A base (the desktop app sharing on the local network) announces itself
// with Bonjour/mDNS as `_lychnion._tcp`, with its name and signing key.
// A phone lists the bases it finds; it connects only after the user picks
// one and answers the same question as for a scanned QR code. Nothing in
// an announcement is trusted: the address is only where to ask (a private
// address), and the announced key is not kept. A base found here gives
// answers and downloads (checked by signature anyway); its facts are
// trusted only after its QR code is scanned.
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

final _keyText = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// A signing key as /info and QR codes give it: 32 bytes, base64url
/// without padding.
bool isKeyText(String s) => _keyText.hasMatch(s);

/// The Bonjour instance name for [name]: at most 63 bytes (a DNS label).
String instanceName(String name) {
  var s = cleanShownText(name) ?? 'Lychnion';
  while (utf8.encode(s).length > 63) {
    s = String.fromCharCodes(s.runes.take(s.runes.length - 1));
  }
  return s;
}

/// Whether [a] is a private IPv4 address, as on a local Wi-Fi or a phone's
/// hotspot: 10/8, 172.16/12, 192.168/16 and 100.64/10 (some hotspots).
bool isPrivateIPv4(InternetAddress a) {
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
}

/// A found base as a link, or null when its announcement is not usable:
/// the first private IPv4 address (bases are reached by IPv4 on the local
/// network, see ShelterServer.localAddresses), the port and the name. The
/// announced key is not used: nothing here was checked in person.
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
    if (ip != null && isPrivateIPv4(ip)) {
      v4 = ip;
      break;
    }
  }
  if (v4 == null) return null;
  final url = ShelterLink.normalize('${v4.address}:$port');
  if (url == null) return null;
  return ShelterLink(
    url,
    name: cleanShownText(attributes['name']) ?? cleanShownText(serviceName),
  );
}

/// Announces this computer as a base while it shares. Calls run one after
/// the other, so a quick restart never leaves two announcements.
class BaseAnnouncer {
  BonsoirBroadcast? _broadcast;
  Future<void> _last = Future.value();
  var _disposed = false;

  Future<void> _serial(Future<void> Function() f) {
    final run = _last.then((_) => f());
    _last = run.catchError((Object _) {});
    return run;
  }

  Future<void> start({required String name, required int port, String? key}) =>
      _serial(() async {
        await _stopNow();
        if (_disposed) return;
        final b = BonsoirBroadcast(
          service: BonsoirService(
            name: instanceName(name),
            type: baseServiceType,
            port: port,
            attributes: baseAttributes(name: name, key: key),
          ),
        );
        try {
          await b.initialize();
          await b.start();
        } on Object {
          await Future.sync(b.stop).catchError((Object _) {});
          rethrow;
        }
        _broadcast = b;
      });

  Future<void> stop() => _serial(_stopNow);

  /// Stops, and no later start announces again.
  Future<void> dispose() {
    _disposed = true;
    return stop();
  }

  Future<void> _stopNow() async {
    final b = _broadcast;
    _broadcast = null;
    await b?.stop();
  }
}

/// Lists the bases on the local Wi-Fi while it runs.
class BaseFinder {
  /// The bases found so far, by the order they were found.
  final found = ValueNotifier<List<ShelterLink>>(const []);

  /// By service name (unique on a network: mDNS renames a second one), so
  /// a base that moves to a new address is listed once, at the new one.
  final _entries = <String, ShelterLink>{};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  var _started = false;
  var _disposed = false;

  /// Starts looking. Throws when this platform cannot (then nothing is
  /// listed; a base can still be added by its address or QR code).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final d = BonsoirDiscovery(type: baseServiceType);
    await d.initialize();
    if (_disposed) {
      await Future.sync(d.stop).catchError((Object _) {});
      return;
    }
    _discovery = d;
    _events = d.eventStream?.listen((e) => _on(d, e));
    await d.start();
  }

  void _on(BonsoirDiscovery d, BonsoirDiscoveryEvent e) {
    if (_disposed) return;
    switch (e) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        unawaited(
          Future.sync(
            () => d.serviceResolver.resolveService(service),
          ).catchError((Object e) => debugPrint('base not resolved: $e')),
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
          _entries.remove(service.name);
        } else if (_entries.containsKey(service.name) ||
            _entries.length < maxFoundBases) {
          _entries[service.name] = link;
        }
        _publish();
      case BonsoirDiscoveryServiceLostEvent(:final service):
        _entries.remove(service.name);
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
      for (final l in _entries.values)
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
