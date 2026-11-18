// Followed catalogs (docs/distribution.md, step 4c).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/catalogs_screen.dart';
import 'package:lychnion/download/followed_catalogs.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-followed');
  });
  tearDown(() => tmp.delete(recursive: true));

  FollowedCatalogs list() => FollowedCatalogs(tmp);
  final kobe = Uri.parse('https://bousai.city.kobe.example/catalog.json');

  group('CatalogLink', () {
    test('goes through a lychnion://catalog link and back', () {
      final l = CatalogLink(kobe, name: '神戸市');
      final back = CatalogLink.fromUri(l.toUri())!;
      expect(back.url, kobe);
      expect(back.name, '神戸市');
    });

    test('only http(s) addresses with a host and no password', () {
      for (final s in [
        'ftp://x.example/c.json',
        'file:///etc/passwd',
        'https://user:pw@x.example/c.json',
        'catalog.json',
        '',
      ]) {
        expect(CatalogLink.normalize(s), isNull, reason: s);
      }
      expect(
        '${CatalogLink.normalize(' https://x.example/c.json#top ')}',
        'https://x.example/c.json',
      );
    });

    test('pasted text: an address or a link', () {
      expect(catalogLinkFrom('$kobe')!.url, kobe);
      expect(
        catalogLinkFrom('${CatalogLink(kobe, name: 'K').toUri()}')!.name,
        'K',
      );
      expect(catalogLinkFrom('lychnion://publisher?name=x&key=y'), isNull);
    });
  });

  group('FollowedCatalogs', () {
    test('is saved, read again, and keeps no duplicates', () async {
      final l = list();
      expect(await l.add(CatalogLink(kobe, name: '神戸市')), isTrue);
      expect(await l.add(CatalogLink(kobe)), isFalse);
      final again = list();
      await again.load();
      expect(again.all.single.url, kobe);
      expect(again.all.single.name, '神戸市');
      await again.remove(kobe);
      final third = list();
      await third.load();
      expect(third.all, isEmpty);
    });

    test(
      'keeps the last copy of a catalog, and forgets it on removal',
      () async {
        final l = list();
        await l.add(CatalogLink(kobe));
        expect(await l.cached(kobe), isNull);
        await l.keep(kobe, '{"format":2}');
        final copy = (await l.cached(kobe))!;
        expect(copy.body, '{"format":2}');
        expect(DateTime.now().difference(copy.fetched).inMinutes, lessThan(1));
        await l.remove(kobe);
        expect(await l.cached(kobe), isNull);
      },
    );

    test(
      'at most ${FollowedCatalogs.max}, and additions at once all kept',
      () async {
        final l = list();
        final results = await Future.wait([
          for (var i = 0; i < FollowedCatalogs.max + 2; i++)
            l.add(CatalogLink(Uri.parse('https://c$i.example/catalog.json'))),
        ]);
        expect(results.where((r) => r), hasLength(FollowedCatalogs.max));
        final again = list();
        await again.load();
        expect(again.all, hasLength(FollowedCatalogs.max));
      },
    );

    test('a broken file means no followed catalogs', () async {
      File('${tmp.path}/catalogs.json').writeAsStringSync('{broken');
      final l = list();
      await l.load();
      expect(l.all, isEmpty);
    });
  });

  group('merging a followed catalog', () {
    late SimpleKeyPair key;
    late TrustedKeys trust;
    setUpAll(() async {
      key = await Ed25519().newKeyPair();
      trust = TrustedKeys({
        'lychnion': [await publicKeyOf(key)],
        'jp.city.kobe': [await publicKeyOf(key)],
      });
    });

    Future<Catalog> cat(
      List<(String id, String version, String publisher, String sha)> recs,
      Uri from,
    ) async => Catalog.parse(
      jsonEncode({
        'format': 2,
        'records': [
          for (final (id, version, publisher, sha) in recs)
            (await PackageRecord.sign({
              'format': 1,
              'id': id,
              'kind': 'package',
              'version': version,
              'publisher': publisher,
              'title': {'en': id},
              'files': [
                {'name': '$id.sqlite', 'size': 1, 'sha256': sha},
              ],
              'signed': '2026-11-18T09:00:00+09:00',
            }, key)).json,
        ],
      }),
      trust: trust,
      fetchedFrom: from,
    );

    final home = Uri.parse('https://lychnion.example/catalog.json');
    final a = 'a' * 64, b = 'b' * 64;

    test("Lychnion's catalog keeps the same version and comes first", () async {
      final mine = await cat([('jp.x', '1', 'lychnion', a)], home);
      final theirs = await cat([
        ('jp.x', '1', 'lychnion', a),
        ('jp.kobe.g', '1', 'jp.city.kobe', b),
      ], kobe);
      final m = mine.mergedWith(theirs, preferOther: false);
      expect(m.urlsOf(m.byId('jp.x')!.files.single).map((u) => '$u'), [
        'https://lychnion.example/jp.x.sqlite',
        'https://bousai.city.kobe.example/jp.x.sqlite',
      ]);
      expect(m.byId('jp.kobe.g'), isNotNull);
    });

    test('a newer version from the followed catalog wins', () async {
      final mine = await cat([('jp.x', '1', 'lychnion', a)], home);
      final theirs = await cat([('jp.x', '2', 'lychnion', b)], kobe);
      final m = mine.mergedWith(theirs, preferOther: false);
      expect(m.byId('jp.x')!.version, '2');
    });

    test('an id stays with its publisher', () async {
      final mine = await cat([('jp.x', '1', 'lychnion', a)], home);
      final theirs = await cat([('jp.x', '9', 'jp.city.kobe', b)], kobe);
      final m = mine.mergedWith(theirs, preferOther: false);
      expect(m.byId('jp.x')!.record!.publisher, 'lychnion');
    });

    test('records of publishers not added are counted, not shown', () async {
      final c = await Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [
            (await PackageRecord.sign({
              'format': 1,
              'id': 'jp.y',
              'kind': 'package',
              'version': '1',
              'publisher': 'jp.city.other',
              'title': {'en': 'y'},
              'files': [
                {'name': 'jp.y.sqlite', 'size': 1, 'sha256': a},
              ],
              'signed': '2026-11-18T09:00:00+09:00',
            }, key)).json,
          ],
        }),
        trust: trust,
      );
      expect(c.items, isEmpty);
      expect(c.rejected, hasLength(1));
    });
  });

  group('fetchCatalogText', () {
    late HttpServer server;
    late void Function(HttpRequest) handle;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => handle(r));
    });
    tearDown(() => server.close(force: true));
    Uri at(String p) => Uri.parse('http://127.0.0.1:${server.port}/$p');
    Matcher code(String c) =>
        throwsA(isA<CatalogFetchError>().having((e) => e.code, 'code', c));

    test('reads a catalog', () async {
      handle = (r) => r.response
        ..write('{"format":2,"records":[]}')
        ..close();
      expect(await fetchCatalogText(at('c.json')), '{"format":2,"records":[]}');
    });

    test('an error answer is refused at once, its body not read', () async {
      handle = (r) {
        r.response
          ..statusCode = 404
          ..bufferOutput = false
          ..write('still going');
        r.response.flush(); // and never closed
      };
      final sw = Stopwatch()..start();
      await expectLater(fetchCatalogText(at('x')), code('HTTP 404'));
      expect(sw.elapsed.inSeconds, lessThan(5));
    });

    test('too large: by its length, and while it arrives', () async {
      handle = (r) => r.response
        ..contentLength = 100
        ..add(List.filled(100, 32))
        ..close();
      await expectLater(
        fetchCatalogText(at('x'), maxBytes: 50),
        code('too large'),
      );
      handle = (r) {
        r.response.bufferOutput = false;
        for (var i = 0; i < 20; i++) {
          r.response.add(List.filled(10, 32));
        }
        r.response.close();
      };
      await expectLater(
        fetchCatalogText(at('x'), maxBytes: 50),
        code('too large'),
      );
    });

    test('not text is invalid', () async {
      handle = (r) => r.response
        ..add([0xff, 0xfe, 0xfd])
        ..close();
      await expectLater(fetchCatalogText(at('x')), code('invalid'));
    });

    test('nobody listening is offline', () async {
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      await expectLater(
        fetchCatalogText(Uri.parse('http://127.0.0.1:$port/c.json')),
        code('offline'),
      );
    });
  });

  test('copies of catalogs no longer followed are removed at load', () async {
    final l = list();
    await l.add(CatalogLink(kobe));
    await l.keep(kobe, '{}');
    final stray = File('${tmp.path}/followed/stray.json')
      ..writeAsStringSync('x');
    final half = File('${l.cacheFile(kobe).path}.tmp')..writeAsStringSync('x');
    await list().load();
    expect(stray.existsSync(), isFalse);
    expect(half.existsSync(), isFalse);
    expect(l.cacheFile(kobe).existsSync(), isTrue);
  });

  test('very long addresses are refused', () {
    expect(CatalogLink.normalize('https://x.example/${'a' * 3000}'), isNull);
  });

  test('copies are written one at a time, only while followed', () async {
    final l = list();
    expect(await l.keep(kobe, 'x'), isFalse);
    await l.add(CatalogLink(kobe));
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) l.keep(kobe, '{"n":$i}'),
    ]);
    expect(results, everyElement(isTrue));
    expect((await l.cached(kobe))!.body, '{"n":4}');
    await l.remove(kobe);
    expect(await l.keep(kobe, 'late'), isFalse);
    expect(l.cacheFile(kobe).existsSync(), isFalse);
  });
}
