// Files by hash, several mirrors (docs/distribution.md, step 3).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/downloader.dart';
import 'package:lychnion/download/record.dart';

import 'download_test.dart' show TestServer, signedRecord;

/// Answers every request with [status] and no body.
Future<HttpServer> statusServer(int status) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    req.response.statusCode = status;
    await req.response.close();
  });
  return s;
}

/// An address where nothing listens (connection refused).
Future<Uri> deadUrl() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close(force: true);
  return Uri.parse('http://127.0.0.1:$port/file');
}

void main() {
  late Directory tmp;
  late SimpleKeyPair key;
  late TrustedKeys trust;
  final data = List<int>.generate(
    300000,
    (i) => Random(2).nextInt(256) ^ i & 0xff,
  );
  final sum = sha256.convert(data).toString();
  final servers = <TestServer>[];

  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-mirrors');
  });
  tearDown(() async {
    for (final s in servers) {
      await s.stop();
    }
    servers.clear();
    await tmp.delete(recursive: true);
  });

  Future<TestServer> serve(List<int> body) async {
    final s = TestServer(body);
    await s.start();
    servers.add(s);
    return s;
  }

  FileSpec spec(List<Uri> urls) => FileSpec(
    url: urls.first,
    fallbacks: urls.skip(1).toList(),
    name: 'f.bin',
    size: data.length,
    sha256: sum,
  );

  group('Downloader with several addresses', () {
    test('skips an unreachable address and an HTTP error', () async {
      final missing = await statusServer(404);
      addTearDown(() => missing.close(force: true));
      final good = await serve(data);
      final failed = <Uri>[];
      final f = await Downloader(onSourceFailed: (u, _) => failed.add(u)).fetch(
        spec([
          await deadUrl(),
          Uri.parse('http://127.0.0.1:${missing.port}/file'),
          good.url,
        ]),
        tmp,
      );
      expect(f.readAsBytesSync(), data);
      expect(failed, hasLength(2));
    });

    test('goes on from the next address where the first stopped', () async {
      final flaky = await serve(data)
        ..cutAfter = 100000;
      final good = await serve(data);
      final f = await Downloader().fetch(spec([flaky.url, good.url]), tmp);
      expect(f.readAsBytesSync(), data);
      expect(good.ranges.single, startsWith('bytes='));
      expect(good.ranges.single, isNot('bytes=0-'));
    });

    test('a wrong file from one address: the next one is tried', () async {
      final wrong = await serve(List<int>.filled(data.length, 7));
      final good = await serve(data);
      final failed = <Object>[];
      final f = await Downloader(
        onSourceFailed: (_, e) => failed.add(e),
      ).fetch(spec([wrong.url, good.url]), tmp);
      expect(f.readAsBytesSync(), data);
      expect(failed.single, isA<ChecksumError>());
      expect(good.ranges.single, isNull, reason: 'fetched from the start');
    });

    test('when every address fails, the last error stays and the part '
        'is kept for later', () async {
      final flaky = await serve(data)
        ..cutAfter = 50000;
      await expectLater(
        Downloader().fetch(spec([flaky.url, await deadUrl()]), tmp),
        throwsA(isA<SocketException>()),
      );
      expect(Downloader.partBytes(tmp, spec([flaky.url])), 50000);
    });

    test('a wrong file everywhere is a checksum error', () async {
      final a = await serve(List<int>.filled(data.length, 1));
      final b = await serve(List<int>.filled(data.length, 2));
      await expectLater(
        Downloader().fetch(spec([a.url, b.url]), tmp),
        throwsA(isA<ChecksumError>()),
      );
      expect(Downloader.partFile(tmp, 'f.bin').existsSync(), isFalse);
    });
  });

  group('Downloader: bytes of a wrong source never mix in', () {
    test('a short page instead of the file (captive portal) is not '
        'written', () async {
      final portal = await serve(utf8.encode('<html>Log in first</html>'));
      final good = await serve(data);
      final f = await Downloader().fetch(spec([portal.url, good.url]), tmp);
      expect(f.readAsBytesSync(), data);
      expect(good.ranges.single, isNull, reason: 'nothing kept from portal');
    });

    test('a range that is not the one asked for is not written', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-${data.length - 1}/${data.length}',
          )
          ..add(data);
        await req.response.close();
      });
      final flaky = await serve(data)
        ..cutAfter = 1000
        ..cuts = 1;
      final good = await serve(data);
      final f = await Downloader().fetch(
        spec([
          flaky.url,
          Uri.parse('http://127.0.0.1:${server.port}/file'),
          good.url,
        ]),
        tmp,
      );
      expect(f.readAsBytesSync(), data);
      expect(good.ranges.single, 'bytes=1000-');
    });

    test('a right file cut short, then a wrong one: the right one alone '
        'is tried again', () async {
      final cut = await serve(data)
        ..cutAfter = 100000
        ..cuts = 1;
      final wrong = await serve(List<int>.filled(data.length, 3));
      final failed = <Uri>[];
      final f = await Downloader(
        onSourceFailed: (u, _) => failed.add(u),
      ).fetch(spec([cut.url, wrong.url]), tmp);
      expect(f.readAsBytesSync(), data);
      expect(cut.ranges, [null, null], reason: 'second time from byte 0');
    });

    test('an address that is not http(s) is skipped', () async {
      final good = await serve(data);
      final f = await Downloader().fetch(
        spec([Uri.parse('ftp://example.org/f'), good.url]),
        tmp,
      );
      expect(f.readAsBytesSync(), data);
    });
  });

  group('Downloader: errors and logs', () {
    test('an error answer whose body never ends does not hold up the next '
        'address', () async {
      final hang = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => hang.close(force: true));
      hang.listen((req) {
        req.response
          ..statusCode = 500
          ..bufferOutput = false
          ..write('still going');
        req.response.flush(); // and never closed
      });
      final good = await serve(data);
      final f = await Downloader().fetch(
        spec([Uri.parse('http://127.0.0.1:${hang.port}/file'), good.url]),
        tmp,
      );
      expect(f.readAsBytesSync(), data);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('logs show no credentials or tokens', () {
      final u = Uri.parse(
        'https://user:secret@cdn.example.org:8443/f.bin?sig=abc#x',
      );
      expect(redactedUrl(u), 'https://cdn.example.org:8443/f.bin');
      expect(
        sourceErrorText(HttpException('HTTP 403', uri: u)),
        isNot(contains('secret')),
      );
      expect(sourceErrorText(HttpException('HTTP 403', uri: u)), 'HTTP 403');
    });
  });

  group('Catalog mirrors', () {
    final shaP = 'ab' * 32, shaQ = 'cd' * 32;

    Future<Catalog> catalog({
      Object? mirrors,
      Map<String, String>? urls,
      Uri? from,
      String version = '1',
      String? sha,
    }) async {
      final r = await signedRecord(key, 'p', 'package', [
        ('p.sqlite', 1, sha ?? shaP),
      ], version: version);
      return Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [r.json],
          'urls': ?urls,
          'mirrors': ?mirrors,
        }),
        trust: trust,
        fetchedFrom: from,
      );
    }

    test('every file is also looked for on each mirror, by hash', () async {
      final c = await catalog(
        from: Uri.parse('https://example.org/data/catalog.json'),
        mirrors: [
          'https://m1.example.org/lychnion',
          'https://m2.example.org/',
          'local/',
          'ftp://bad.example.org/',
          42,
          'https://m2.example.org/',
        ],
      );
      final f = c.items.single.files.single;
      expect(c.urlsOf(f).map((u) => '$u'), [
        'https://example.org/data/p.sqlite',
        'https://m1.example.org/lychnion/blobs/sha256/$shaP',
        'https://m2.example.org/blobs/sha256/$shaP',
        'https://example.org/data/local/blobs/sha256/$shaP',
      ]);
      final s = c.spec(f);
      expect('${s.url}', 'https://example.org/data/p.sqlite');
      expect(s.fallbacks, hasLength(3));
    });

    test('mirrors: no query, at most ten, own addresses web only', () async {
      final c = await catalog(
        urls: {shaP: 'file:///etc/passwd'},
        mirrors: [
          'https://q.example.org/x?token=1#top',
          for (var i = 0; i < 20; i++) 'https://m$i.example.org/',
        ],
      );
      expect(c.mirrors, hasLength(Catalog.maxMirrors));
      expect('${c.mirrors.first}', 'https://q.example.org/x/');
      expect(
        '${c.urlOf(c.items.single.files.single)}',
        'https://q.example.org/x/blobs/sha256/$shaP',
      );
    });

    test('mirrors alone make a file downloadable', () async {
      final none = await catalog();
      expect(none.canDownload(none.items.single), isFalse);
      final c = await catalog(mirrors: ['https://m.example.org/']);
      final f = c.items.single.files.single;
      expect(c.canDownload(c.items.single), isTrue);
      expect('${c.urlOf(f)}', 'https://m.example.org/blobs/sha256/$shaP');
    });

    test('a catalog without mirrors reads as before', () async {
      final c = await catalog(
        urls: {shaP: 'https://cdn.example.org/p'},
        from: Uri.parse('https://example.org/catalog.json'),
      );
      expect(c.mirrors, isEmpty);
      expect(c.urlsOf(c.items.single.files.single).map((u) => '$u'), [
        'https://cdn.example.org/p',
      ]);
    });

    test('a broken urls entry does not break the catalog', () async {
      final r = await signedRecord(key, 'p', 'package', [
        ('p.sqlite', 1, shaP),
      ]);
      final c = await Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [r.json],
          'urls': {
            shaP: ['https://a/', 'https://b/'],
          },
        }),
        trust: trust,
        fetchedFrom: Uri.parse('https://example.org/catalog.json'),
      );
      expect('${c.urlOf(c.items.single.files.single)}', endsWith('p.sqlite'));
    });

    group('merging a shelter catalog', () {
      final home = Uri.parse('https://example.org/catalog.json');
      final shelter = Uri.parse('http://192.168.1.20:8642/catalog.json');

      test(
        'the same file keeps its internet address after the shelter\'s',
        () async {
          final mine = await catalog(
            from: home,
            mirrors: ['https://m.example.org/'],
          );
          final theirs = await catalog(
            from: shelter,
            urls: {shaP: 'blobs/sha256/$shaP'},
          );
          final m = mine.mergedWith(theirs);
          expect(m.urlsOf(m.items.single.files.single).map((u) => '$u'), [
            'http://192.168.1.20:8642/blobs/sha256/$shaP',
            'https://example.org/p.sqlite',
            'https://m.example.org/blobs/sha256/$shaP',
          ]);
          expect(m.mirrors, mine.mirrors);
        },
      );

      test('a newer version only on the shelter: the shelter, then the '
          'mirrors', () async {
        final mine = await catalog(
          from: home,
          mirrors: ['https://m.example.org/'],
        );
        final theirs = await catalog(
          from: shelter,
          version: '2',
          sha: shaQ,
          urls: {shaQ: 'blobs/sha256/$shaQ'},
          mirrors: ['http://192.168.1.21:8642/'],
        );
        final m = mine.mergedWith(theirs);
        final i = m.items.single;
        expect(i.version, '2');
        expect(m.urlsOf(i.files.single).map((u) => '$u'), [
          'http://192.168.1.20:8642/blobs/sha256/$shaQ',
          'https://m.example.org/blobs/sha256/$shaQ',
          'http://192.168.1.21:8642/blobs/sha256/$shaQ',
        ]);
      });

      test('merged mirrors stay within the limit', () async {
        final mine = await catalog(
          from: home,
          mirrors: [for (var i = 0; i < 10; i++) 'https://a$i.example.org/'],
        );
        final theirs = await catalog(
          from: shelter,
          mirrors: [for (var i = 0; i < 10; i++) 'http://b$i.example.org/'],
        );
        expect(mine.mergedWith(theirs).mirrors, hasLength(Catalog.maxMirrors));
      });

      test('merging twice adds no address twice', () async {
        final mine = await catalog(from: home);
        final theirs = await catalog(
          from: shelter,
          urls: {shaP: 'blobs/sha256/$shaP'},
        );
        final once = mine.mergedWith(theirs);
        final twice = once.mergedWith(theirs);
        expect(
          twice.urlsOf(twice.items.single.files.single),
          once.urlsOf(once.items.single.files.single),
        );
      });
    });
  });

  test('a mirror serves the file by hash, end to end', () async {
    // A static node: just files under blobs/sha256/.
    final node = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => node.close(force: true));
    node.listen((req) async {
      if (req.uri.path == '/node/blobs/sha256/$sum') {
        req.response.add(data);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final r = await signedRecord(key, 'p', 'package', [
      ('p.sqlite', data.length, sum),
    ]);
    final c = await Catalog.parse(
      jsonEncode({
        'format': 2,
        'records': [r.json],
        'mirrors': ['http://127.0.0.1:${node.port}/node'],
      }),
      trust: trust,
      // Its own address is gone (the catalog came from a stick).
      fetchedFrom: await deadUrl(),
    );
    final f = await Downloader().fetch(
      c.spec(c.items.single.files.single),
      tmp,
    );
    expect(f.path, endsWith('p.sqlite'));
    expect(sha256.convert(f.readAsBytesSync()).toString(), sum);
  });
}
