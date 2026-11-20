// A node pulling from the internet sends no requests to its own network
// (lychnion/lychnion#74): every address that is not plain public unicast
// counts as not public.
import 'dart:io';

import 'package:lychnion_node/lychnion_node.dart';
import 'package:test/test.dart';

void main() {
  bool nonPublic(String a) => isNonPublicAddress(InternetAddress(a));

  test('local, private, special and multicast addresses are not public', () {
    for (final a in [
      // As before.
      '127.0.0.1', '10.1.2.3', '172.16.0.1', '192.168.1.1', '100.64.0.1',
      '169.254.1.1', '0.0.0.0', '::1', 'fe80::1', 'fd12::1',
      '::ffff:127.0.0.1', '::ffff:10.0.0.1',
      // New (#74).
      '::', // on Linux a connect to it reaches this machine
      '192.0.0.8', '198.18.0.1', '198.19.255.255', // special ranges
      '224.0.0.1', '239.255.255.250', '240.0.0.1', '255.255.255.255',
      'ff02::1', 'ff0e::1', // multicast
      '64:ff9b::7f00:1', '64:ff9b::a00:1', // NAT64 to 127.0.0.1, 10.0.0.1
      '64:ff9b:1::1', // NAT64 local use
      '2002:7f00:1::1', '2002:c0a8:101::1', // 6to4 to 127.0.0.1, 192.168.1.1
      '::7f00:1', // old IPv4-compatible form of 127.0.0.1
      '::ffff:0:7f00:1', '::ffff:0:a00:1', // translated 127.0.0.1, 10.0.0.1
      '2001::1', '2001:0:4136:e378::1', // Teredo
      'fe90::1', 'febf::1', // link-local, beyond what Dart's isLinkLocal sees
      'fec0::1', 'feff::1', // old site-local
    ]) {
      expect(nonPublic(a), isTrue, reason: a);
    }
  });

  test('public addresses stay public', () {
    for (final a in [
      '8.8.8.8',
      '1.1.1.1',
      '192.0.1.1',
      '198.20.0.1',
      '223.255.255.255',
      '2001:4860:4860::8888',
      '64:ff9b::808:808', // NAT64 to 8.8.8.8
      '2002:808:808::1', // 6to4 to 8.8.8.8
      '::ffff:8.8.8.8',
      '::ffff:0:808:808', // translated 8.8.8.8
      '2001:db9::1', '2001:1::1', // next to Teredo
    ]) {
      expect(nonPublic(a), isFalse, reason: a);
    }
  });
}
