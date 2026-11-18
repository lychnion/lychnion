import 'dart:io';
import 'dart:math';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/downloader.dart';
import 'package:lychnion/download/record.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signs a record for [id] with [key] (test publisher `lychnion`).
Future<PackageRecord> signedRecord(
  SimpleKeyPair key,
  String id,
  String kind,
  List<(String, int, String)> files, {
  String version = '1',
  String? role,
}) => PackageRecord.sign({
  'format': 1,
  'id': id,
  'kind': kind,
  'version': version,
  'publisher': 'lychnion',
  'title': {'ja': id, 'en': id},
  'role': ?role,
  'files': [
    for (final (n, size, sha) in files)
      {'name': n, 'size': size, 'sha256': sha},
  ],
  'signed': '2026-11-18T09:00:00+09:00',
}, key);

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
  late SimpleKeyPair key;
  late TrustedKeys trust;
  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
  });
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
    test('bundled catalog is complete and signed', () async {
      final c = await Catalog.parse(
        File('assets/downloads/catalog.json').readAsStringSync(),
      );
      expect(c.rejected, isEmpty);
      expect(c.items.map((i) => i.kind).toSet(), ItemKind.values.toSet());
      for (final i in c.items) {
        expect(i.record, isNotNull);
        for (final f in i.files) {
          expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
          expect(f.size, greaterThan(0));
        }
      }
      // Models come from Hugging Face; the bundled files match their assets.
      for (final i in c.items.where((i) => i.kind == ItemKind.model)) {
        expect(c.canDownload(i), isTrue);
      }
      for (final id in [
        'jp.bousai.core',
        'jp.outdoor.hiking',
        'intl.firstaid.basics',
      ]) {
        final pkg = c.byId(id)!.files.single;
        final bundled = File('assets/packages/${pkg.name}');
        expect(bundled.lengthSync(), pkg.size, reason: id);
        expect(
          sha256.convert(bundled.readAsBytesSync()).toString(),
          pkg.sha256,
          reason: id,
        );
      }
    });

    Future<String> catalogJson(List<Object?> records, {Map? urls}) async =>
        jsonEncode({'format': 2, 'records': records, 'urls': ?urls});

    test(
      'resolves file URLs: listed, else by name next to the catalog',
      () async {
        final r = await signedRecord(key, 'p', 'package', [
          ('p.sqlite', 1, 'ab' * 32),
          ('q.sqlite', 2, 'cd' * 32),
        ]);
        final json = await catalogJson(
          [r.json],
          urls: {'cd' * 32: 'https://cdn.example.org/q'},
        );
        final none = await Catalog.parse(json, trust: trust);
        expect(none.canDownload(none.items.single), isFalse);
        final c = await Catalog.parse(
          json,
          trust: trust,
          fetchedFrom: Uri.parse('https://example.org/fk/catalog.json'),
        );
        final [p, q] = c.items.single.files;
        expect(c.urlOf(p).toString(), 'https://example.org/fk/p.sqlite');
        expect(c.urlOf(q).toString(), 'https://cdn.example.org/q');
        final o = await Catalog.parse(
          json,
          trust: trust,
          baseOverride: Uri.parse('http://h:1/x/'),
        );
        expect(
          o.urlOf(o.items.single.files.first).toString(),
          'http://h:1/x/p.sqlite',
        );
      },
    );

    test('leaves out records with a bad signature or unknown key', () async {
      final good = await signedRecord(key, 'good', 'package', [
        ('g.sqlite', 1, 'ab' * 32),
      ]);
      final changed = Map.of(
        (await signedRecord(key, 'changed', 'package', [
          ('c.sqlite', 1, 'ab' * 32),
        ])).json,
      )..['version'] = '2';
      final other = await signedRecord(
        await Ed25519().newKeyPair(),
        'stranger',
        'package',
        [('s.sqlite', 1, 'ab' * 32)],
      );
      final c = await Catalog.parse(
        await catalogJson([
          good.json,
          changed,
          other.json,
          {'id': 'junk'},
        ]),
        trust: trust,
      );
      expect(c.items.map((i) => i.id), ['good']);
      expect(c.rejected, hasLength(3));
      // The bundled app key does not know the test key.
      expect(
        (await Catalog.parse(await catalogJson([good.json]))).items,
        isEmpty,
      );
    });

    test('refuses the old unsigned format', () async {
      expect(
        Catalog.parse('{"format": 1, "items": []}', trust: trust),
        throwsFormatException,
      );
    });

    test('a file with the wrong hash is not installed', () async {
      final r = await signedRecord(key, 'p', 'package', [
        ('f.bin', data.length, 'ab' * 32),
      ]);
      final c = await Catalog.parse(
        await catalogJson([r.json]),
        trust: trust,
        baseOverride: server.url.resolve('/'),
      );
      final f = c.items.single.files.single;
      await expectLater(
        Downloader().fetch(c.spec(f), tmp),
        throwsA(isA<ChecksumError>()),
      );
      expect(File('${tmp.path}/f.bin').existsSync(), isFalse);
    });

    test('formats sizes', () {
      expect(formatBytes(2841481184), '2.8 GB');
      expect(formatBytes(309855456), '310 MB');
      expect(formatBytes(26211536), '26.2 MB');
    });
  });

  group('DownloadStore', () {
    Future<CatalogItem> item(
      String id,
      ItemKind kind,
      List<(String, int)> files, {
      String? role,
      String version = '1',
      SimpleKeyPair? signer,
    }) async => CatalogItem.fromRecord(
      await signedRecord(
        signer ?? key,
        id,
        kind.name,
        [for (final (n, s) in files) (n, s, '0' * 64)],
        version: version,
        role: role,
      ),
    );

    Future<void> put(DownloadStore s, ItemKind k, String name, int size) async {
      await s.dirFor(k).create(recursive: true);
      await File(
        '${s.dirFor(k).path}/$name',
      ).writeAsBytes(List.filled(size, 1));
    }

    test('only files with a record count, and only at their size', () async {
      final s = DownloadStore(tmp, trust: trust);
      final map = await item('jp.map.x', ItemKind.map, [
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
      final s = DownloadStore(tmp, trust: trust);
      final e2b = await item('model.e2b', ItemKind.model, [
        ('e2b.gguf', 3),
      ], role: 'chat');
      final e4b = await item('model.e4b', ItemKind.model, [
        ('e4b.gguf', 4),
      ], role: 'chat');
      final emb = await item('model.emb', ItemKind.model, [
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

    test('install needs a trusted signature', () async {
      final s = DownloadStore(tmp, trust: trust);
      final stranger = await item('p', ItemKind.package, [
        ('p.sqlite', 3),
      ], signer: await Ed25519().newKeyPair());
      await put(s, ItemKind.package, 'p.sqlite', 3);
      await expectLater(
        s.markInstalled(stranger),
        throwsA(isA<UnsignedItem>()),
      );
      final unsigned = CatalogItem(
        id: 'p',
        kind: ItemKind.package,
        titles: const {'en': 'p'},
        version: '1',
        licence: '',
        files: const [CatalogFile('p.sqlite', 3, 'x', 'p.sqlite')],
      );
      await expectLater(
        s.markInstalled(unsigned),
        throwsA(isA<UnsignedItem>()),
      );
      expect(s.installed(ItemKind.package, 'p'), isNull);
    });

    test('versions only go up', () async {
      final s = DownloadStore(tmp, trust: trust);
      await put(s, ItemKind.package, 'p.sqlite', 3);
      await s.markInstalled(
        await item('p', ItemKind.package, [
          ('p.sqlite', 3),
        ], version: '2026.11.2'),
      );
      final older = await item('p', ItemKind.package, [
        ('p.sqlite', 3),
      ], version: '2026.11.1');
      await expectLater(s.markInstalled(older), throwsA(isA<OlderVersion>()));
      expect(s.installed(ItemKind.package, 'p')!.version, '2026.11.2');
      await s.markInstalled(
        await item('p', ItemKind.package, [
          ('p.sqlite', 3),
        ], version: '2026.11.10'),
      );
      expect(s.installed(ItemKind.package, 'p')!.version, '2026.11.10');
      expect(isOlder('2026.11.9', '2026.11.10'), isTrue);
      expect(isOlder('2026.12', '2026.11.10'), isFalse);
      expect(isOlder('2026.11.0', 'Q4_0'), isFalse); // installed before records
    });

    test('install records are checked again when the app starts', () async {
      final s = DownloadStore(tmp, trust: trust);
      await put(s, ItemKind.package, 'p.sqlite', 3);
      await put(s, ItemKind.package, 'q.sqlite', 3);
      await s.markInstalled(
        await item('p', ItemKind.package, [('p.sqlite', 3)]),
      );
      await s.markInstalled(
        await item('q', ItemKind.package, [('q.sqlite', 3)]),
      );
      // Someone edits one record on disk; another is from before signing.
      final m = File('${s.dirFor(ItemKind.package).path}/p.installed.json');
      await m.writeAsString(m.readAsStringSync().replaceFirst('"1"', '"9"'));
      await File(
        '${s.dirFor(ItemKind.package).path}/old.installed.json',
      ).writeAsString(
        jsonEncode({
          'id': 'old',
          'kind': 'package',
          'version': '1',
          'files': {'q.sqlite': 3},
        }),
      );
      final again = DownloadStore(tmp, trust: trust);
      expect(again.installed(ItemKind.package, 'q'), isNull); // not checked yet
      await again.verifyInstalled();
      expect(again.installed(ItemKind.package, 'p'), isNull);
      expect(again.installed(ItemKind.package, 'old'), isNull);
      expect(again.installed(ItemKind.package, 'q'), isNotNull);
      // An edit after the check, keeping the signature, does not pass.
      final q = File('${s.dirFor(ItemKind.package).path}/q.installed.json');
      await q.writeAsString(q.readAsStringSync().replaceFirst('"1"', '"9"'));
      expect(again.installed(ItemKind.package, 'q'), isNull);
    });

    test('mobile data: Wi-Fi only by default, three choices', () async {
      final s = DownloadStore(tmp, trust: trust);
      expect(s.mobileData, MobileData.never);
      await s.setMobileData(MobileData.ask);
      expect(s.mobileData, MobileData.ask);
      await s.setMobileData(MobileData.always);
      expect(s.mobileData, MobileData.always);
    });

    test('updates: notify by default, three choices', () async {
      final s = DownloadStore(tmp, trust: trust);
      expect(s.updateMode, UpdateMode.notify);
      await s.setUpdateMode(UpdateMode.auto);
      expect(s.updateMode, UpdateMode.auto);
      await s.setUpdateMode(UpdateMode.off);
      expect(s.updateMode, UpdateMode.off);
    });

    test('the old Wi-Fi-only switch is read as before', () async {
      final s = DownloadStore(tmp, trust: trust);
      await File('${tmp.path}/downloads/settings.json')
          .create(recursive: true)
          .then((f) => f.writeAsString('{"wifi_only": false}'));
      expect(s.mobileData, MobileData.always);
    });
  });
}
