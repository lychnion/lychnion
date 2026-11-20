// The base and Share nearby listen only on the local network
// (lychnion/lychnion#64): one socket per Wi-Fi or hotspot address, never
// mobile data or a public address, followed as the network changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_server.dart';
import 'package:lychnion/base/lan_sockets.dart';

/// An interface's address, as BaseServer.localAddresses lists them.
(String, InternetAddress) _addr(String name, List<String> address) =>
    (name, InternetAddress(address.single));

Future<bool> _connects(String address, int port) async {
  try {
    final s = await Socket.connect(
      address,
      port,
      timeout: const Duration(seconds: 1),
    );
    s.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

/// Waits until [test] is true, at most a few seconds.
Future<void> _until(bool Function() test) async {
  for (var i = 0; i < 100 && !test(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('the addresses phones can use', () {
    test('Wi-Fi, hotspot and wired private addresses, Wi-Fi first', () {
      final picked = BaseServer.pickLocalAddresses([
        _addr('lo0', ['127.0.0.1']),
        _addr('utun3', ['10.8.0.2']),
        _addr('tailscale0', ['100.101.1.2']),
        _addr('docker0', ['172.17.0.1']),
        _addr('wlan0', ['192.168.1.20']),
        _addr('rmnet_data0', ['10.120.4.7']),
        _addr('pdp_ip0', ['10.1.2.3']),
        _addr('ap0', ['192.168.43.1']),
        _addr('en1', ['169.254.3.4']),
      ]);
      expect(picked, ['192.168.1.20', '192.168.43.1']);
      // Never loopback, link-local, a VPN or mobile data.
      expect(
        picked,
        isNot(
          anyOf(
            contains('10.8.0.2'),
            contains('127.0.0.1'),
            contains('169.254.3.4'),
            contains('10.120.4.7'),
            contains('10.1.2.3'),
          ),
        ),
      );
    });

    test('unknown names and mobile data under other names are left out', () {
      final picked = BaseServer.pickLocalAddresses([
        _addr('r_rmnet_data0', ['10.20.30.40']),
        _addr('ccemni0', ['10.20.30.41']),
        _addr('sipa_eth0', ['10.20.30.42']),
        _addr('wwan0', ['10.20.30.43']),
        _addr('foo0', ['192.168.5.5']),
        // Carrier-grade NAT, even on a Wi-Fi name.
        _addr('wlan1', ['100.70.1.2']),
        _addr('swlan0', ['192.168.44.1']),
        _addr('rndis0', ['192.168.42.129']),
      ]);
      expect(picked, ['192.168.44.1', '192.168.42.129']);
    });

    test('Windows names: Wi-Fi, Ethernet and the hotspot, not VMs or VPNs', () {
      final picked = BaseServer.pickLocalAddresses([
        _addr('vEthernet (WSL)', ['172.20.48.1']),
        _addr('Ethernet', ['192.168.10.5']),
        _addr('Tailscale', ['100.90.1.1']),
        _addr('VMware Network Adapter VMnet8', ['192.168.200.1']),
        _addr('VirtualBox Host-Only Network', ['192.168.56.1']),
        _addr('Local Area Connection* 10', ['192.168.137.1']),
        _addr('Wi-Fi', ['192.168.1.3']),
      ]);
      // Wi-Fi and the hotspot first: the QR code shows the first one.
      expect(picked, ['192.168.1.3', '192.168.10.5', '192.168.137.1']);
    });

    test('Japanese and Chinese Windows names are known; an unknown name is '
        'reported', () {
      final all = [
        _addr('イーサネット', ['192.168.10.5']),
        _addr('ローカル エリア接続* 10', ['192.168.137.1']),
        _addr('以太网', ['192.168.11.2']),
        _addr('Wi-Fi', ['192.168.1.3']),
        _addr('Something 7', ['192.168.77.7']),
        _addr('vEthernet (WSL)', ['172.20.48.1']),
      ];
      expect(BaseServer.pickLocalAddresses(all), [
        '192.168.1.3',
        '192.168.10.5',
        '192.168.137.1',
        '192.168.11.2',
      ]);
      // Left out, and logged so the name can be added.
      expect(BaseServer.unknownInterfaces(all), ['Something 7']);
    });

    test('a public address is never used', () {
      final picked = BaseServer.pickLocalAddresses([
        _addr('eth0', ['203.0.113.5']),
        _addr('en0', ['192.168.0.9']),
      ]);
      expect(picked, ['192.168.0.9']);
    });
  });

  group('listening', () {
    test('only on the given address, not on others of the machine', () async {
      final s = await LanSockets.bind(0, addresses: () async => ['127.0.0.1']);
      addTearDown(s.close);
      s.listen((c) => c.destroy());
      expect(s.addresses, ['127.0.0.1']);
      expect(await _connects('127.0.0.1', s.port), isTrue);
      // On Linux all of 127/8 reaches this machine: bound to 0.0.0.0 this
      // would connect.
      expect(await _connects('127.0.0.2', s.port), isFalse);
    });

    test('follows the network: binds an address that appears and closes '
        'one that goes', () async {
      var now = <String>[];
      final s = await LanSockets.bind(
        0,
        addresses: () async => now,
        every: const Duration(milliseconds: 30),
      );
      addTearDown(s.close);
      s.listen((c) => c.destroy());
      final changes = <List<String>>[];
      s.onChanged = changes.add;
      expect(s.addresses, isEmpty);

      now = ['127.0.0.1'];
      await _until(() => s.addresses.isNotEmpty);
      expect(changes.last, ['127.0.0.1']);
      expect(await _connects('127.0.0.1', s.port), isTrue);

      now = [];
      await _until(() => changes.last.isEmpty);
      expect(s.addresses, isEmpty);
      expect(await _connects('127.0.0.1', s.port), isFalse);
    });

    test('a taken port is an error when nothing could be bound', () async {
      final taken = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(taken.close);
      await expectLater(
        LanSockets.bind(taken.port, addresses: () async => ['127.0.0.1']),
        throwsA(isA<SocketException>()),
      );
    });

    test('a base started without an address listens where the screen '
        'says, and on loopback for simulators', () async {
      final server = BaseServer(answerer: null, name: '');
      await server.start(port: 0);
      addTearDown(server.stop);
      expect(server.addresses, await BaseServer.localAddresses());
      expect(server.addresses, isNot(contains('127.0.0.1')));
      expect(await _connects('127.0.0.1', server.port), isTrue);
      for (final a in server.addresses) {
        expect(await _connects(a, server.port), isTrue, reason: a);
      }
    });

    test('a base whose port is taken on its local address does not start, '
        'even though loopback is free', () async {
      final local = await BaseServer.localAddresses();
      if (local.isEmpty) {
        markTestSkipped('no local-network address on this machine');
        return;
      }
      // The port taken on every local-network address of this machine.
      final first = await ServerSocket.bind(local.first, 0);
      final taken = [first];
      addTearDown(() async {
        for (final s in taken) {
          await s.close();
        }
      });
      for (final a in local.skip(1)) {
        try {
          taken.add(await ServerSocket.bind(a, first.port));
        } on SocketException {
          markTestSkipped('port ${first.port} not free on $a');
          return;
        }
      }
      final server = BaseServer(answerer: null, name: '');
      addTearDown(() async {
        // Only if it started after all (the test then fails above).
        try {
          await server.stop();
        } on Object {
          // Never started.
        }
      });
      await expectLater(
        server.start(port: first.port),
        throwsA(isA<SocketException>()),
      );
      // Nothing is left listening on loopback.
      expect(await _connects('127.0.0.1', first.port), isFalse);
    });

    test('closing stops listening', () async {
      final s = await LanSockets.bind(0, addresses: () async => ['127.0.0.1']);
      s.listen((c) => c.destroy());
      final port = s.port;
      await s.close();
      expect(await _connects('127.0.0.1', port), isFalse);
      expect(s.addresses, isEmpty);
    });
  });
}
