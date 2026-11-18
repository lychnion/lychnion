import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:lychnion_node/lychnion_node.dart';
import 'package:test/test.dart';

/// A publisher's web server: a catalog and files, each counted.
class Source {
  late HttpServer server;
  final files = <String, List<int>>{};
  final hits = <String, int>{};
  Map<String, Object?> catalog = {'format': 2, 'records': []};

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/catalog.json');
  String get base => 'http://127.0.0.1:${server.port}/';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final p = req.uri.path;
      hits[p] = (hits[p] ?? 0) + 1;
      if (p == '/catalog.json') {
        req.response.write(jsonEncode(catalog));
      } else if (files[p.substring(1)] case final data?) {
        req.response.add(data);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  }
}

void main() {
  late SimpleKeyPair city, club, stranger;
  late TrustedKeys trust;
  late Directory tmp;
  late NodeFolder folder;
  late Source src;

  setUpAll(() async {
    city = await Ed25519().newKeyPair();
    club = await Ed25519().newKeyPair();
    stranger = await Ed25519().newKeyPair();
    trust = builtInPublishers.plus({
      'jp.city.test': [await publicKeyOf(city)],
      'jp.club.test': [await publicKeyOf(club)],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-node');
    folder = NodeFolder(Directory('${tmp.path}/node'));
    src = Source();
    await src.start();
  });
  tearDown(() async {
    await src.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  /// Signs a record of [id] whose one file has [content], and puts the
  /// file on the source at [path] (default: its name).
  Future<PackageRecord> offer(
    String id,
    String version,
    String content, {
    SimpleKeyPair? key,
    String publisher = 'jp.city.test',
    String? path,
  }) async {
    final data = utf8.encode(content);
    final name = '$id.sqlite';
    final r = await PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': version,
      'publisher': publisher,
      'title': {'en': id},
      'files': [
        {
          'name': name,
          'size': data.length,
          'sha256': sha256.convert(data).toString(),
        },
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, key ?? city);
    if (path != '') src.files[path ?? name] = data;
    return r;
  }

  void publish(List<PackageRecord> records, {Map? urls, List? mirrors}) =>
      src.catalog = {
        'format': 2,
        'records': [for (final r in records) r.json],
        'urls': ?urls,
        'mirrors': ?mirrors,
      };

  Future<PullResult> go() => pull([src.url], folder, trust);

  group('pull', () {
    test('keeps trusted records and their files, by hash', () async {
      final a = await offer('jp.a', '1', 'aaa');
      final s = await offer('jp.s', '1', 'sss', key: stranger);
      publish([a, s]);
      final r = await go();
      expect(r.changed, ['jp.a 1']);
      expect(r.notTrusted, 1);
      expect(r.failed, isEmpty);
      final sha = a.files.single.sha256;
      expect(folder.blob(sha)!.readAsStringSync(), 'aaa');
      final j = jsonDecode(folder.catalogFile.readAsStringSync()) as Map;
      expect((j['records'] as List).single, a.json);
      expect(j['urls'], {sha: 'blobs/sha256/$sha'});
      expect(await checkFolder(folder, trust), isEmpty);
    });

    test('again: nothing fetched twice', () async {
      publish([await offer('jp.a', '1', 'aaa')]);
      await go();
      final r = await go();
      expect(r.changed, isEmpty);
      expect(src.hits['/jp.a.sqlite'], 1);
    });

    test('a newer version replaces the old one, whose file goes', () async {
      final v1 = await offer('jp.a', '1', 'one');
      publish([v1]);
      await go();
      final v2 = await offer('jp.a', '2', 'two');
      publish([v2]);
      final r = await go();
      expect(r.changed, ['jp.a 2']);
      expect(r.pruned, 1);
      expect(folder.blob(v1.files.single.sha256)!.existsSync(), isFalse);
      // An older one later is ignored: versions only go up.
      publish([v1]);
      expect((await go()).changed, isEmpty);
      expect((await folder.records(trust)).single.version, '2');
    });

    test('an id stays with the publisher that has it here', () async {
      publish([await offer('jp.a', '1', 'city')]);
      await go();
      publish([
        await offer('jp.a', '9', 'club', key: club, publisher: 'jp.club.test'),
      ]);
      final r = await go();
      expect(r.taken, ['jp.a']);
      expect((await folder.records(trust)).single.publisher, 'jp.city.test');
    });

    test('files come from mirrors when their own address fails', () async {
      final a = await offer('jp.a', '1', 'aaa', path: '');
      final sha = a.files.single.sha256;
      src.files['m/blobs/sha256/$sha'] = utf8.encode('aaa');
      publish([a], mirrors: ['${src.base}m/']);
      final r = await go();
      expect(r.changed, ['jp.a 1']);
      expect(src.hits['/jp.a.sqlite'], 1, reason: 'tried first, 404');
    });

    test('a record whose files cannot be fetched is not listed; the old '
        'version stays', () async {
      publish([await offer('jp.a', '1', 'one')]);
      await go();
      publish([await offer('jp.a', '2', 'two', path: '')]);
      final r = await go();
      expect(r.failed.single, startsWith('jp.a 2'));
      expect((await folder.records(trust)).single.version, '1');
    });

    test('--kind takes only those kinds', () async {
      publish([await offer('jp.a', '1', 'aaa')]);
      final r = await pull([src.url], folder, trust, kinds: {'map'});
      expect(r.changed, isEmpty);
      expect(await folder.records(trust), isEmpty);
    });

    test('a catalog that cannot be read changes nothing', () async {
      publish([await offer('jp.a', '1', 'aaa')]);
      await go();
      src.catalog = {'format': 1};
      final r = await go();
      expect(r.failed.single, contains('invalid'));
      expect((await folder.records(trust)).single.id, 'jp.a');
    });
  });

  group('serve', () {
    late NodeServer server;
    late HttpClient client;
    late String sha;
    setUp(() async {
      final a = await offer('jp.a', '1', '0123456789');
      sha = a.files.single.sha256;
      publish([a]);
      await go();
      server = NodeServer(
        folder,
        port: 0,
        address: InternetAddress.loopbackIPv4,
      );
      await server.start();
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<(int, String, HttpHeaders)> call(
      String path, {
      String method = 'GET',
      String? range,
    }) async {
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.boundPort}$path'),
      );
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (res.statusCode, body, res.headers);
    }

    test('the catalog and files by hash, also from an offset', () async {
      final (s1, cat, _) = await call('/catalog.json');
      expect(s1, 200);
      expect((jsonDecode(cat) as Map)['format'], 2);
      final (s2, all, _) = await call('/blobs/sha256/$sha');
      expect((s2, all), (200, '0123456789'));
      final (s3, part, h) = await call('/blobs/sha256/$sha', range: 'bytes=4-');
      expect((s3, part), (206, '456789'));
      expect(h.value(HttpHeaders.contentRangeHeader), 'bytes 4-9/10');
      final (s4, tail, _) = await call('/blobs/sha256/$sha', range: 'bytes=-3');
      expect((s4, tail), (206, '789'));
      final (s5, head, h5) = await call('/blobs/sha256/$sha', method: 'HEAD');
      expect((s5, head), (200, ''));
      expect(h5.contentLength, 10);
    });

    test('nothing else', () async {
      for (final p in [
        '/blobs/sha256/${'0' * 64}',
        // '..' is removed by the client; encoded it reaches the server.
        '/blobs/sha256/%2e%2e%2f%2e%2e%2fcatalog.json',
        '/blobs/sha256/$sha.part',
        '/catalog.json.tmp',
        '/node/catalog.json',
      ]) {
        expect((await call(p)).$1, 404, reason: p);
      }
      expect((await call('/catalog.json', method: 'POST')).$1, 405);
      expect((await call('/blobs/sha256/$sha', range: 'bytes=20-')).$1, 416);
    });
  });

  test('check finds a file that does not match', () async {
    final a = await offer('jp.a', '1', 'aaa');
    publish([a]);
    await go();
    folder.blob(a.files.single.sha256)!.writeAsStringSync('bbb');
    expect(await checkFolder(folder, trust), [
      'jp.a 1: jp.a.sqlite does not match',
    ]);
    // Without the city's key its record is not trusted.
    expect(await checkFolder(folder, builtInPublishers), [
      'jp.a: not signed by a trusted publisher',
    ]);
  });
}
