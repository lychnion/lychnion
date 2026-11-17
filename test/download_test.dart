import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/downloader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves [data] at /file with Range support, /redirect → /file, and can
/// drop the connection after [cutAfter] bytes or ignore Range.
class TestServer {
  TestServer(this.data);
  final List<int> data;
  late HttpServer _server;
  int? cutAfter;
  bool ignoreRange = false;
  final ranges = <String?>[];

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/file');
  Uri get redirectUrl => Uri.parse('http://127.0.0.1:${_server.port}/redirect');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/redirect') {
        res.statusCode = HttpStatus.found;
        res.headers.set(HttpHeaders.locationHeader, '/file');
        await res.close();
        return;
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      var from = 0;
      if (range != null && !ignoreRange) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $from-${data.length - 1}/${data.length}',
        );
      }
      final body = data.sublist(from);
      res.contentLength = body.length;
      final cut = cutAfter;
      if (cut != null && cut < body.length) {
        // Send the headers and part of the body, then drop the socket,
        // like a lost Wi-Fi connection.
        final socket = await res.detachSocket();
        socket.add(body.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      res.add(body);
      await res.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory tmp;
  late TestServer server;
  final data = List<int>.generate(
    300000,
    (i) => Random(1).nextInt(256) ^ i & 0xff,
  );
  final sum = sha256.convert(data).toString();
  FileSpec spec(Uri url, {String? hash}) =>
      FileSpec(url: url, name: 'f.bin', size: data.length, sha256: hash ?? sum);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-dl');
    server = TestServer(data);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  group('Downloader', () {
    test('downloads and verifies', () async {
      final f = await Downloader().fetch(spec(server.url), tmp);
      expect(await f.readAsBytes(), data);
      expect(Downloader.partFile(tmp, 'f.bin').existsSync(), isFalse);
    });

    test('resumes after a dropped connection', () async {
      server.cutAfter = 100000;
      await expectLater(
        Downloader().fetch(spec(server.url), tmp),
        throwsA(anything),
      );
      final have = Downloader.partBytes(tmp, spec(server.url));
      expect(have, greaterThan(0));
      expect(have, lessThan(data.length));

      server.cutAfter = null;
      final phases = <DownloadPhase>{};
      final f = await Downloader().fetch(
        spec(server.url),
        tmp,
        onProgress: (p, _, _) => phases.add(p),
      );
      expect(server.ranges.last, 'bytes=$have-');
      expect(phases, contains(DownloadPhase.checkingPart));
      expect(await f.readAsBytes(), data);
    });

    test('keeps the Range header across a redirect', () async {
      server.cutAfter = 50000;
      await expectLater(
        Downloader().fetch(spec(server.redirectUrl), tmp),
        throwsA(anything),
      );
      server.cutAfter = null;
      await Downloader().fetch(spec(server.redirectUrl), tmp);
      expect(server.ranges.last, startsWith('bytes='));
    });

    test('starts again when the server ignores Range', () async {
      server.cutAfter = 100000;
      await expectLater(
        Downloader().fetch(spec(server.url), tmp),
        throwsA(anything),
      );
      server
        ..cutAfter = null
        ..ignoreRange = true;
      final f = await Downloader().fetch(spec(server.url), tmp);
      expect(await f.readAsBytes(), data);
    });

    test('rejects a wrong checksum and removes the part', () async {
      final bad = spec(server.url, hash: '0' * 64);
      await expectLater(
        Downloader().fetch(bad, tmp),
        throwsA(isA<ChecksumError>()),
      );
      expect(File('${tmp.path}/f.bin').existsSync(), isFalse);
      expect(Downloader.partFile(tmp, 'f.bin').existsSync(), isFalse);
    });

    test('does not resume a part of another version', () async {
      server.cutAfter = 100000;
      await expectLater(
        Downloader().fetch(spec(server.url, hash: 'a' * 64), tmp),
        throwsA(anything),
      );
      expect(Downloader.partBytes(tmp, spec(server.url)), 0);
      server.cutAfter = null;
      final f = await Downloader().fetch(spec(server.url), tmp);
      expect(server.ranges.last, isNull);
      expect(await f.readAsBytes(), data);
    });

    test('stop keeps the part for later', () async {
      final cancel = CancelToken();
      await expectLater(
        Downloader().fetch(
          spec(server.url),
          tmp,
          cancel: cancel,
          onProgress: (p, b, _) {
            if (b > 0) cancel.cancel();
          },
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(Downloader.partFile(tmp, 'f.bin').existsSync(), isTrue);
      expect(File('${tmp.path}/f.bin').existsSync(), isFalse);
    });
  });

  group('Catalog', () {
    test('bundled catalog is complete', () {
      final c = Catalog.parse(
        File('assets/downloads/catalog.json').readAsStringSync(),
      );
      expect(c.items.map((i) => i.kind).toSet(), ItemKind.values.toSet());
      for (final i in c.items) {
        for (final f in i.files) {
          expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
          expect(f.size, greaterThan(0));
        }
      }
      // Models come from Hugging Face; the bundled files match their assets.
      for (final i in c.items.where((i) => i.kind == ItemKind.model)) {
        expect(c.canDownload(i), isTrue);
      }
      final pkg = c.byId('jp.bousai.core')!.files.single;
      final bundled = File('assets/packages/${pkg.name}');
      expect(bundled.lengthSync(), pkg.size);
      expect(sha256.convert(bundled.readAsBytesSync()).toString(), pkg.sha256);
    });

    test('resolves relative URLs against the base', () {
      const json = '''{"format": 1, "items": [{"id": "p", "kind": "package",
        "title": {"ja": "p", "en": "p"}, "version": "1",
        "files": [{"name": "p.sqlite", "size": 1, "sha256": "AB", "url": "p.sqlite"}]}]}''';
      final none = Catalog.parse(json);
      expect(none.canDownload(none.items.single), isFalse);
      final c = Catalog.parse(
        json,
        fetchedFrom: Uri.parse('https://example.org/fk/catalog.json'),
      );
      expect(
        c.urlOf(c.items.single.files.single).toString(),
        'https://example.org/fk/p.sqlite',
      );
      expect(c.items.single.files.single.sha256, 'ab');
      final o = Catalog.parse(json, baseOverride: Uri.parse('http://h:1/x/'));
      expect(
        o.urlOf(o.items.single.files.single).toString(),
        'http://h:1/x/p.sqlite',
      );
    });

    test('formats sizes', () {
      expect(formatBytes(2841481184), '2.8 GB');
      expect(formatBytes(309855456), '310 MB');
      expect(formatBytes(26211536), '26.2 MB');
    });
  });

  group('DownloadStore', () {
    CatalogItem item(
      String id,
      ItemKind kind,
      List<(String, int)> files, {
      String? role,
      String version = '1',
    }) => CatalogItem(
      id: id,
      kind: kind,
      titleJa: id,
      titleEn: id,
      version: version,
      licence: '',
      role: role,
      files: [for (final (n, s) in files) CatalogFile(n, s, 'x', n)],
    );

    Future<void> put(DownloadStore s, ItemKind k, String name, int size) async {
      await s.dirFor(k).create(recursive: true);
      await File(
        '${s.dirFor(k).path}/$name',
      ).writeAsBytes(List.filled(size, 1));
    }

    test('only files with a record count, and only at their size', () async {
      final s = DownloadStore(tmp);
      final map = item('jp.map.x', ItemKind.map, [
        ('x.pmtiles', 10),
        ('x.sites.sqlite', 5),
      ]);
      await put(s, ItemKind.map, 'x.pmtiles', 10);
      await put(s, ItemKind.map, 'x.sites.sqlite', 5);
      expect(s.mapPaths(), isNull);
      expect(s.hasUnverifiedFiles(map), isTrue);

      await s.markInstalled(map);
      expect(s.mapPaths()!.pmtiles, endsWith('/maps/x.pmtiles'));
      expect(s.hasUnverifiedFiles(map), isFalse);

      await put(s, ItemKind.map, 'x.pmtiles', 9); // truncated
      expect(s.mapPaths(), isNull);

      await s.delete(map);
      expect(
        File('${s.dirFor(ItemKind.map).path}/x.sites.sqlite').existsSync(),
        isFalse,
      );
    });

    test('chat model: picked one, else the first installed', () async {
      final s = DownloadStore(tmp);
      final e2b = item('model.e2b', ItemKind.model, [
        ('e2b.gguf', 3),
      ], role: 'chat');
      final e4b = item('model.e4b', ItemKind.model, [
        ('e4b.gguf', 4),
      ], role: 'chat');
      final emb = item('model.emb', ItemKind.model, [
        ('emb.gguf', 2),
      ], role: 'embed');
      expect(s.chatModelPath(), isNull);
      for (final (i, n, sz) in [
        (e2b, 'e2b.gguf', 3),
        (e4b, 'e4b.gguf', 4),
        (emb, 'emb.gguf', 2),
      ]) {
        await put(s, ItemKind.model, n, sz);
        await s.markInstalled(i);
      }
      expect(s.chatModelPath(), endsWith('/models/e2b.gguf'));
      await s.setChatModelId('model.e4b');
      expect(s.chatModelPath(), endsWith('/models/e4b.gguf'));
      expect(s.embedModelPath(), endsWith('/models/emb.gguf'));
      await s.delete(e4b);
      expect(s.chatModelPath(), endsWith('/models/e2b.gguf'));
    });

    test('Wi-Fi only is on by default', () async {
      final s = DownloadStore(tmp);
      expect(s.wifiOnly, isTrue);
      await s.setWifiOnly(false);
      expect(s.wifiOnly, isFalse);
    });
  });
}
