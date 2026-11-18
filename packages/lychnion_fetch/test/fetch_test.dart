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
      r.response.close();
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
      r.response.close();
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
      r.response.close();
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
}
