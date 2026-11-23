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

  /// Served instead of [catalog] when set (text jsonEncode cannot make).
  String? rawCatalog;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/catalog.json');
  String get base => 'http://127.0.0.1:${server.port}/';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final p = req.uri.path;
      hits[p] = (hits[p] ?? 0) + 1;
      if (p == '/catalog.json') {
        req.response.write(rawCatalog ?? jsonEncode(catalog));
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
    String kind = 'package',
  }) async {
    final data = utf8.encode(content);
    final name = kind == 'model' ? '$id.gguf' : '$id.sqlite';
    final r = await PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': kind,
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

  void publish(
    List<PackageRecord> records, {
    Map<String, String>? urls,
    List<String>? mirrors,
  }) => src.catalog = {
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

    test('key statements count for records and are passed on', () async {
      final next = await Ed25519().newKeyPair();
      final ab = await KeyStatement.replace(
        publisher: 'jp.city.test',
        oldKey: city,
        newKey: next,
        signed: '2026-11-19',
      );
      // Junk about a key of its own is not kept.
      final junk = await KeyStatement.revoke(
        publisher: 'jp.city.test',
        key: stranger,
        signed: '2026-11-19',
      );
      final a = await offer('jp.a', '1', 'aaa', key: next);
      publish([a]);
      src.catalog['keys'] = [junk.json, ab.json];
      final r = await go();
      expect(r.changed, ['jp.a 1']);
      final j = jsonDecode(folder.catalogFile.readAsStringSync()) as Map;
      expect(j['keys'], [ab.json]);
      expect(await checkFolder(folder, trust), isEmpty);
      // Served again: still trusted from the folder's own statements.
      expect((await folder.records(trust)).single.id, 'jp.a');

      // A revocation of the new key, learned later, drops the record.
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.test',
        key: next,
        signed: '2026-11-20',
      );
      src.catalog['keys'] = [revoke.json];
      await go();
      expect(await folder.allRecords(), isEmpty);
      expect((await folder.keptRecords()).single.id, 'jp.a');
      expect(folder.blob(a.files.single.sha256)!.existsSync(), isTrue);
    });

    test('a key revoked mid-pull: the version before stays', () async {
      final next = await Ed25519().newKeyPair();
      final ab = await KeyStatement.replace(
        publisher: 'jp.city.test',
        oldKey: city,
        newKey: next,
        signed: '2026-11-19',
      );
      final v1 = await offer('jp.a', '1', 'one');
      publish([v1]);
      await go();
      final v2 = await offer('jp.a', '2', 'two', key: next);
      final revoke = await KeyStatement.revoke(
        publisher: 'jp.city.test',
        key: next,
        signed: '2026-11-20',
      );
      publish([v2]);
      src.catalog['keys'] = [ab.json, revoke.json];
      await go();
      expect((await folder.allRecords()).single.version, '1');
    });

    test('a catalog over 2 MB: reported, nothing pruned', () async {
      final a = await offer('jp.a', '1', 'aaa');
      publish([a]);
      await go();
      // Two catalogs under the fetch limit, together over it.
      Future<PackageRecord> large(String id, String content) async {
        final r = await offer(id, '1', content);
        return PackageRecord.sign(
          {
            ...r.json,
            'title': {'en': 'x' * (1200 * 1024)},
          }..remove('signature'),
          city,
        );
      }

      final b = await large('jp.b', 'bbb');
      publish([a, b]);
      final other = Source();
      await other.start();
      try {
        final c = await large('jp.c', 'ccc');
        other.files['jp.c.sqlite'] = src.files.remove('jp.c.sqlite')!;
        other.catalog = {
          'format': 2,
          'records': [c.json],
        };
        final r = await pull([src.url, other.url], folder, trust);
        expect(r.failed.any((f) => f.startsWith('catalog.json')), isTrue);
        expect((await folder.allRecords()).single.id, 'jp.a');
        expect(folder.blob(a.files.single.sha256)!.existsSync(), isTrue);
      } finally {
        await other.server.close(force: true);
      }
    });

    // lychnion/lychnion#67: only Lychnion publishes models.
    test("an added publisher's model is not passed on", () async {
      publish([
        await offer('jp.city.model', '1', 'gguf', kind: 'model'),
        await offer('jp.a', '1', 'aaa'),
      ]);
      final r = await go();
      expect(r.notTrusted, 1);
      expect([for (final x in await folder.allRecords()) x.id], ['jp.a']);
      expect(src.hits['/jp.city.model.gguf'], isNull);
    });

    test("an added publisher's model an older node listed is dropped, its "
        'file too', () async {
      // As an older node wrote it: the city's model listed, its file here.
      final model = await offer('jp.city.model', '1', 'gguf', kind: 'model');
      final hash = model.files.single.sha256;
      await folder.writeCatalog([model]);
      final f = File('${folder.blobs.path}/$hash');
      await f.create(recursive: true);
      await f.writeAsBytes(utf8.encode('gguf'));
      publish([await offer('jp.a', '1', 'aaa')]);
      await go();
      expect([for (final x in await folder.allRecords()) x.id], ['jp.a']);
      expect(folder.blob(hash)!.existsSync(), isFalse);
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

    test('a catalog with fields of the wrong type fails alone', () async {
      final good = Source();
      await good.start();
      addTearDown(() => good.server.close(force: true));
      final a = await offer('jp.a', '1', 'aaa', path: '');
      good.files['jp.a.sqlite'] = utf8.encode('aaa');
      good.catalog = {
        'format': 2,
        'records': [a.json],
      };
      src.catalog = {'format': 2, 'records': [], 'urls': []};
      final r = await pull([src.url, good.url], folder, trust);
      expect(r.failed.single, contains('invalid'));
      expect(r.changed, ['jp.a 1']);
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

  group('review fixes', () {
    // lychnion/lychnion#75: a record no version of which is complete is
    // not listed, but its version still blocks older ones.
    test('an incomplete record keeps its version', () async {
      publish([await offer('jp.a', '1', 'one')]);
      await go();
      final v2 = await offer('jp.a', '2', 'two');
      publish([v2]);
      await go();
      expect((await folder.allRecords()).single.version, '2');

      // v2's file deleted by hand, and v3's fetch fails.
      folder.blob(v2.files.single.sha256)!.deleteSync();
      publish([await offer('jp.a', '3', 'three', path: '')]);
      final r = await go();
      expect(await folder.allRecords(), isEmpty);
      expect((await folder.keptRecords()).single.version, '2');
      expect(
        r.failed,
        contains(startsWith('jp.a 2: files missing, not listed')),
      );

      // An older version, signed and complete, is still refused.
      publish([await offer('jp.a', '1', 'one')]);
      expect((await go()).changed, isEmpty);
      expect(await folder.allRecords(), isEmpty);
      expect((await folder.keptRecords()).single.version, '2');

      // v2 offered again: fetched and listed, no longer set aside.
      publish([await offer('jp.a', '2', 'two')]);
      await go();
      expect((await folder.allRecords()).single.version, '2');
      expect(await folder.keptRecords(), isEmpty);
      expect(await checkFolder(folder, trust), isEmpty);
    });

    test('an incomplete record still holds its id', () async {
      final v1 = await offer('jp.a', '1', 'one');
      publish([v1]);
      await go();
      folder.blob(v1.files.single.sha256)!.deleteSync();
      src.files.clear();
      await go();
      expect((await folder.keptRecords()).single.publisher, 'jp.city.test');
      // Another publisher's record for that id is not taken.
      publish([
        await offer('jp.a', '2', 'club', key: club, publisher: 'jp.club.test'),
      ]);
      final r = await go();
      expect(r.taken, ['jp.a']);
      expect(r.keptUntrusted, 0);
      expect((await folder.keptRecords()).single.publisher, 'jp.city.test');
    });

    test('an incomplete record keeps the files that are here', () async {
      // A record of two files.
      final x = utf8.encode('xxx'), y = utf8.encode('yyy');
      String hash(List<int> d) => sha256.convert(d).toString();
      final r = await PackageRecord.sign({
        'format': 1,
        'id': 'jp.a',
        'kind': 'package',
        'version': '1',
        'publisher': 'jp.city.test',
        'title': {'en': 'jp.a'},
        'files': [
          {'name': 'x.sqlite', 'size': x.length, 'sha256': hash(x)},
          {'name': 'y.sqlite', 'size': y.length, 'sha256': hash(y)},
        ],
        'signed': '2026-11-18T09:00:00+09:00',
      }, city);
      src.files['x.sqlite'] = x;
      src.files['y.sqlite'] = y;
      publish([r]);
      await go();
      // One file deleted by hand, and the source is gone: the record is
      // set aside, the other file stays for the next try.
      folder.blob(hash(x))!.deleteSync();
      src.files.clear();
      await go();
      expect(await folder.allRecords(), isEmpty);
      expect(folder.blob(hash(y))!.existsSync(), isTrue);
      // Back: only the missing file is fetched.
      src.files['x.sqlite'] = x;
      src.files['y.sqlite'] = y;
      src.hits.clear();
      await go();
      expect((await folder.allRecords()).single.version, '1');
      expect(src.hits['/y.sqlite'], isNull);
      expect(src.hits['/x.sqlite'], 1);
    });

    // lychnion/lychnion#78: a deeply nested `keys` entry is skipped; the
    // catalog's records are still pulled.
    test('a deeply nested key statement does not stop the pull', () async {
      final a = await offer('jp.a', '1', 'aaa');
      const depth = 200000;
      final deep = '${'[' * depth}0${']' * depth}';
      final records = jsonEncode([a.json]);
      src.rawCatalog =
          '{"format":2,"records":$records,"keys":[$deep,{"publisher":'
          '"jp.city.test","x":$deep}]}';
      final r = await go();
      expect(r.changed, ['jp.a 1']);
      expect(r.failed, isEmpty);
    });

    test('a second pull on the same folder at the same time stops', () async {
      publish([await offer('jp.a', '1', 'aaa')]);
      await go();
      // Another process holds the lock (file locks are per process).
      final script = File('${tmp.path}/hold.dart')
        ..writeAsStringSync(
          "import 'dart:io';\n"
          'Future<void> main(List<String> a) async {\n'
          '  final f = await File(a[0]).open(mode: FileMode.write);\n'
          '  await f.lock(FileLock.exclusive);\n'
          "  stdout.writeln('locked');\n"
          '  await Future<void>.delayed(const Duration(seconds: 20));\n'
          '}\n',
        );
      final p = await Process.start(Platform.resolvedExecutable, [
        script.path,
        '${folder.dir.path}/.pull.lock',
      ]);
      addTearDown(p.kill);
      await p.stdout.first;
      await expectLater(go(), throwsA(isA<PullBusy>()));
    });

    test('Lychnion keeps its own ids', () async {
      final lychnionKey = await Ed25519().newKeyPair();
      final t = builtInPublishers.plus({
        'lychnion': [await publicKeyOf(lychnionKey)],
        'jp.city.test': [await publicKeyOf(city)],
      });
      publish([await offer('jp.a', '5', 'city')]);
      await pull([src.url], folder, t);
      publish([
        await offer(
          'jp.a',
          '1',
          'ours',
          key: lychnionKey,
          publisher: 'lychnion',
        ),
      ]);
      final r = await pull([src.url], folder, t);
      expect(r.changed, ['jp.a 1']);
      expect((await folder.records(t)).single.publisher, 'lychnion');
    });

    test('a publisher left out: its record goes, its files stay', () async {
      final c = await offer(
        'jp.c',
        '1',
        'club',
        key: club,
        publisher: 'jp.club.test',
      );
      publish([c]);
      await go();
      final onlyCity = builtInPublishers.plus({
        'jp.city.test': [await publicKeyOf(city)],
      });
      final r = await pull([src.url], folder, onlyCity);
      expect(r.keptUntrusted, 1);
      expect(r.pruned, 0);
      expect(await folder.records(onlyCity), isEmpty);
      expect(folder.blob(c.files.single.sha256)!.existsSync(), isTrue);
      // Also on the next run, and the next: set aside, not forgotten.
      for (var i = 0; i < 2; i++) {
        final again = await pull([src.url], folder, onlyCity);
        expect(again.keptUntrusted, 1);
        expect(again.pruned, 0);
        expect(folder.blob(c.files.single.sha256)!.existsSync(), isTrue);
      }
      // With the key again, it is listed again.
      await go();
      expect((await folder.records(trust)).single.id, 'jp.c');
    });

    test('private and public hosts', () async {
      for (final h in [
        '127.0.0.1',
        '10.1.2.3',
        '192.168.1.20',
        '169.254.169.254',
        '::1',
        'fd00::1',
      ]) {
        expect(await isPrivateHost(h), isTrue, reason: h);
      }
      for (final h in ['::ffff:127.0.0.1', '::ffff:169.254.169.254']) {
        expect(await isPrivateHost(h), isTrue, reason: h);
      }
      for (final h in ['8.8.8.8', '2001:4860:4860::8888']) {
        expect(await isPrivateHost(h), isFalse, reason: h);
      }
    });
  });

  group('pull from a folder (a USB stick)', () {
    test('reads the catalog and files there, checks every hash', () async {
      // Fill one node folder over HTTP, then pull another from it.
      final a = await offer('jp.a', '1', 'aaa');
      publish([a]);
      await go();
      final stick = Directory('${tmp.path}/stick/lychnion');
      stick.parent.createSync();
      await folder.dir.rename(stick.path);
      final other = NodeFolder(Directory('${tmp.path}/other'));
      final r = await pull([Directory('${tmp.path}/stick').uri], other, trust);
      expect(r.changed, ['jp.a 1']);
      expect(await checkFolder(other, trust), isEmpty);

      // A changed file on the stick is refused.
      final b = await offer('jp.b', '1', 'bbb');
      await NodeFolder(stick).writeCatalog([a, b]);
      File('${stick.path}/blobs/sha256/${b.files.single.sha256}')
        ..createSync(recursive: true)
        ..writeAsStringSync('bad');
      final r2 = await pull([stick.uri], other, trust);
      expect(r2.failed.single, startsWith('jp.b 1'));
      expect((await other.records(trust)).map((x) => x.id), ['jp.a']);
    });

    test('a folder without a catalog fails alone', () async {
      final empty = Directory('${tmp.path}/empty')..createSync();
      final r = await pull([empty.uri], folder, trust);
      expect(r.failed.single, contains('no catalog.json'));
    });
  });

  group('attestations (lychnion/lychnion#119)', () {
    test(
      'kept and passed on; a signer not trusted for Lychnion is not',
      () async {
        final lychnion = await Ed25519().newKeyPair();
        final t = trust.plus({
          'lychnion': [await publicKeyOf(lychnion)],
        });
        Future<Attestation> attestation(String name, SimpleKeyPair by) async =>
            Attestation.sign(
              publisher: name,
              key: await publicKeyOf(city),
              checked: '2026-11-23',
              method: 'official-website',
              signed: '2026-11-23T10:00:00+09:00',
              signer: by,
            );
        final a = await attestation('jp.city.a', lychnion);
        final forged = await attestation('jp.city.b', stranger);
        src.catalog = {
          'format': 2,
          'records': <Object>[],
          'attestations': [a.json, forged.json],
        };
        final r = await pull([src.url], folder, t);
        expect(r.failed, isEmpty);
        expect(r.attestationsLeftOut, 0);
        expect(await folder.attestations(t), [a]);
        // The source drops it; the node keeps passing it on.
        src.catalog = {'format': 2, 'records': <Object>[]};
        await pull([src.url], folder, t);
        final served = jsonDecode(folder.catalogFile.readAsStringSync()) as Map;
        expect(served['attestations'], [a.json]);
        // Without Lychnion's key (here: another one), none are counted.
        final other = trust.plus({
          'lychnion': [await publicKeyOf(stranger)],
        });
        expect(await folder.attestations(other), isEmpty);
      },
    );

    test(
      'a later source revoking Lychnion\'s key: its attestations lapse',
      () async {
        final lychnion = await Ed25519().newKeyPair();
        final t = trust.plus({
          'lychnion': [await publicKeyOf(lychnion)],
        });
        final a = await Attestation.sign(
          publisher: 'jp.city.a',
          key: await publicKeyOf(city),
          checked: '2026-11-23',
          method: 'official-website',
          signed: '2026-11-23T10:00:00+09:00',
          signer: lychnion,
        );
        src.catalog = {
          'format': 2,
          'records': <Object>[],
          'attestations': [a.json],
        };
        final revoke = await KeyStatement.revoke(
          publisher: 'lychnion',
          key: lychnion,
          signed: '2026-11-23T11:00:00+09:00',
        );
        final stick = Directory('${tmp.path}/stick/lychnion')
          ..createSync(recursive: true);
        File('${stick.path}/catalog.json').writeAsStringSync(
          jsonEncode({
            'format': 2,
            'records': <Object>[],
            'keys': [revoke.json],
          }),
        );
        await pull([src.url, Directory('${tmp.path}/stick').uri], folder, t);
        final served = jsonDecode(folder.catalogFile.readAsStringSync()) as Map;
        expect(served['attestations'], isNull);
        expect(served['keys'], [revoke.json]);
      },
    );
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
      // Ranges this server does not use: the whole file.
      for (final r in ['bytes=0-1,5-6', 'bytes=5-2', 'items=0-1']) {
        final (st, body, _) = await call('/blobs/sha256/$sha', range: r);
        expect((st, body.length), (200, 10), reason: r);
      }
      expect((await call('/blobs/sha256/$sha', range: 'bytes=20-')).$1, 416);
    });
  });

  test('more requests than allowed get 503', () async {
    publish([await offer('jp.a', '1', 'aaa')]);
    await go();
    final busy = NodeServer(
      folder,
      port: 0,
      address: InternetAddress.loopbackIPv4,
      maxConnections: 0,
    );
    await busy.start();
    addTearDown(busy.stop);
    final c = HttpClient();
    addTearDown(() => c.close(force: true));
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:${busy.boundPort}/catalog.json'),
    )).close();
    expect(res.statusCode, 503);
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

  // lychnion/lychnion#78: a nested record id is not printed.
  test('check reports a record with a nested id', () async {
    await go();
    const depth = 200000;
    final deep = '${'[' * depth}0${']' * depth}';
    folder.catalogFile.writeAsStringSync(
      '{"format":2,"records":[{"id":$deep}],"keys":[$deep]}',
    );
    expect(await checkFolder(folder, trust), [
      '?: not signed by a trusted publisher',
    ]);
  });
}
