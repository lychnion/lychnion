import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lychnion_fetch/lychnion_fetch.dart';
import 'package:test/test.dart';

// The app's tests (test/download_test.dart, test/mirrors_test.dart,
// test/followed_test.dart) cover this package in depth; these keep it
// checked on its own, without Flutter.
void main() {
  late HttpServer server;
  late void Function(HttpRequest) handle;
  late Directory tmp;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => handle(r));
    tmp = await Directory.systemTemp.createTemp('lychnion-fetch');
  });
  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });
  Uri at(String p) => Uri.parse('http://127.0.0.1:${server.port}/$p');

  test('fetchCatalogText: reads text, refuses errors and size', () async {
    handle = (r) {
      if (r.uri.path == '/big') {
        r.response.add(List.filled(100, 32));
      } else if (r.uri.path == '/missing') {
        r.response.statusCode = 404;
      } else {
        r.response.write('{"format":2}');
      }
      unawaited(r.response.close());
    };
    expect(await fetchCatalogText(at('c.json')), '{"format":2}');
    await expectLater(
      fetchCatalogText(at('missing')),
      throwsA(isA<CatalogFetchError>().having((e) => e.code, 'c', 'HTTP 404')),
    );
    await expectLater(
      fetchCatalogText(at('big'), maxBytes: 10),
      throwsA(isA<CatalogFetchError>().having((e) => e.code, 'c', 'too large')),
    );
  });

  test('Downloader: falls back to the next address, checks the hash', () async {
    final data = List<int>.generate(5000, (i) => i % 251);
    final sum = sha256.convert(data).toString();
    handle = (r) {
      if (r.uri.path == '/good') {
        r.response.add(data);
      } else {
        r.response.statusCode = 503;
      }
      unawaited(r.response.close());
    };
    final f = await Downloader().fetch(
      FileSpec(
        url: at('down'),
        fallbacks: [at('good')],
        name: 'f.bin',
        size: data.length,
        sha256: sum,
      ),
      tmp,
    );
    expect(f.readAsBytesSync(), data);
  });

  test('Downloader: an address not allowed, also after a redirect, is '
      'skipped', () async {
    final data = List<int>.generate(100, (i) => i);
    final sum = sha256.convert(data).toString();
    handle = (r) {
      if (r.uri.path == '/hop') {
        r.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, '/secret');
      } else if (r.uri.path == '/good') {
        r.response.add(data);
      } else {
        // /secret must never be asked for.
        r.response.statusCode = 500;
      }
      unawaited(r.response.close());
    };
    final asked = <String>[];
    final f =
        await Downloader(
          allowAddress: (u) async {
            asked.add(u.path);
            return u.path != '/secret';
          },
        ).fetch(
          FileSpec(
            url: at('hop'),
            fallbacks: [at('good')],
            name: 'f.bin',
            size: data.length,
            sha256: sum,
          ),
          tmp,
        );
    expect(f.readAsBytesSync(), data);
    expect(asked, ['/hop', '/secret', '/good']);
  });

  test('fetchCatalogText: no redirects for a local device', () async {
    handle = (r) {
      if (r.uri.path == '/hop') {
        r.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, '/c.json');
      } else {
        r.response.write('{"format":2}');
      }
      unawaited(r.response.close());
    };
    expect(await fetchCatalogText(at('hop')), '{"format":2}');
    await expectLater(
      fetchCatalogText(at('hop'), followRedirects: false),
      throwsA(isA<CatalogFetchError>().having((e) => e.code, 'c', 'HTTP 302')),
    );
  });

  // lychnion/lychnion#74: a node checks every redirect of a catalog, as
  // it does for files.
  test('fetchCatalogText: each redirect is checked', () async {
    var hops = 0;
    handle = (r) {
      if (r.uri.path.startsWith('/hop')) {
        hops++;
        r.response
          ..statusCode = 302
          ..headers.set(
            HttpHeaders.locationHeader,
            r.uri.path == '/hop1' ? '/hop2' : '/c.json',
          );
      } else {
        r.response.write('{"format":2}');
      }
      unawaited(r.response.close());
    };
    final asked = <String>[];
    expect(
      await fetchCatalogText(
        at('hop1'),
        allowAddress: (u) async {
          asked.add(u.path);
          return true;
        },
      ),
      '{"format":2}',
    );
    expect(asked, ['/hop2', '/c.json']);
    expect(hops, 2);
    await expectLater(
      fetchCatalogText(at('hop1'), allowAddress: (u) async => false),
      throwsA(
        isA<CatalogFetchError>().having(
          (e) => e.code,
          'c',
          'redirect not allowed',
        ),
      ),
    );
  });

  test('fetchCatalogText: a redirect loop ends', () async {
    var hops = 0;
    handle = (r) {
      hops++;
      r.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, '/again');
      unawaited(r.response.close());
    };
    await expectLater(
      fetchCatalogText(at('again'), allowAddress: (u) async => true),
      throwsA(isA<CatalogFetchError>().having((e) => e.code, 'c', 'HTTP 302')),
    );
    expect(hops, 6);
  });

  test('fetchCatalogText: a redirect to another scheme is refused', () async {
    handle = (r) {
      r.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, 'file:///etc/passwd');
      unawaited(r.response.close());
    };
    await expectLater(
      fetchCatalogText(at('x'), allowAddress: (u) async => true),
      throwsA(
        isA<CatalogFetchError>().having(
          (e) => e.code,
          'c',
          'redirect not allowed',
        ),
      ),
    );
  });

  test(
    'fetchCatalogText: no redirects stays no redirects with a check',
    () async {
      handle = (r) {
        r.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, '/c.json');
        unawaited(r.response.close());
      };
      await expectLater(
        fetchCatalogText(
          at('x'),
          followRedirects: false,
          allowAddress: (u) async => true,
        ),
        throwsA(
          isA<CatalogFetchError>().having((e) => e.code, 'c', 'HTTP 302'),
        ),
      );
    },
  );

  test('Downloader: a local device may redirect only to itself', () async {
    final data = List<int>.generate(100, (i) => i);
    final sum = sha256.convert(data).toString();
    final hosts = <String>[];
    handle = (r) {
      hosts.add('${r.headers.host} ${r.uri.path}');
      if (r.uri.path == '/away') {
        // Another host name for the same machine: another origin.
        r.response
          ..statusCode = 302
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://localhost:${server.port}/good',
          );
      } else if (r.uri.path == '/same') {
        r.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, '/good');
      } else {
        r.response.add(data);
      }
      unawaited(r.response.close());
    };
    final f = await Downloader().fetch(
      FileSpec(
        url: at('away'),
        fallbacks: [at('same')],
        name: 'f.bin',
        size: data.length,
        sha256: sum,
      ),
      tmp,
    );
    expect(f.readAsBytesSync(), data);
    expect(hosts, ['127.0.0.1 /away', '127.0.0.1 /same', '127.0.0.1 /good']);
  });

  test('isLocalNetworkHost', () {
    for (final h in [
      '192.168.1.20',
      '10.0.0.1',
      '172.16.0.5',
      '172.31.255.1',
      '127.0.0.1',
      '169.254.1.1',
      'fd12::1',
      'fe80::1',
      '::1',
      'base.local',
      'localhost',
      // lychnion/lychnion#73: the hotspot range discovery accepts, and
      // plain names on the local network.
      '100.64.0.1',
      '100.127.255.254',
      'mybase',
      // The root dot, and IPv4 written as IPv6.
      'mybase.',
      'base.local.',
      '::ffff:10.0.0.1',
      '::ffff:127.0.0.1',
    ]) {
      expect(isLocalNetworkHost(h), isTrue, reason: h);
    }
    for (final h in [
      '8.8.8.8',
      '172.32.0.1',
      '100.63.255.255',
      '100.128.0.1',
      'example.org',
      'base.lan.example',
      '2001:db8::1',
      '::ffff:8.8.8.8',
      'example.org.',
      '',
    ]) {
      expect(isLocalNetworkHost(h), isFalse, reason: h);
    }
  });

  test('isPrivateIPv4Address: the ranges, IPv4 only', () {
    bool p(String a) => isPrivateIPv4Address(InternetAddress(a));
    expect(
      [
        '10.1.2.3',
        '172.16.0.1',
        '172.31.0.1',
        '192.168.0.1',
        '100.64.0.1',
      ].every(p),
      isTrue,
    );
    expect(
      ['11.0.0.1', '172.15.0.1', '172.32.0.1', '100.63.0.1', 'fd00::1'].any(p),
      isFalse,
    );
  });
}
