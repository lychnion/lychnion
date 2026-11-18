import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/record.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/llm/local_llm.dart';
import 'package:lychnion/shelter/shelter_library.dart';
import 'package:lychnion/shelter/shelter_server.dart';

Future<PackageRecord> _record(
  SimpleKeyPair key,
  String id,
  String version,
  String sha,
) => PackageRecord.sign({
  'format': 1,
  'id': id,
  'kind': 'package',
  'version': version,
  'publisher': 'lychnion',
  'title': {'ja': id, 'en': id},
  'files': [
    {'name': '$id.sqlite', 'size': 3, 'sha256': sha},
  ],
  'signed': '2026-11-18T09:00:00+09:00',
}, key);

/// A shelter library without a download store: one file.
class _OneFile implements ShelterLibrary {
  _OneFile(this.file, this.sha, this.catalogJson);
  final File file;
  final String sha;
  final Map<String, Object?> catalogJson;

  @override
  Map<String, Object?> catalog() => catalogJson;
  @override
  File? blob(String sha256) => sha256 == sha ? file : null;
  @override
  DownloadStore get store => throw UnimplementedError();
  @override
  List<Installed> get items => throw UnimplementedError();
}

void main() {
  late SimpleKeyPair key;
  late TrustedKeys trust;
  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
  });
  final shaA = 'a' * 64, shaB = 'b' * 64;

  Future<Catalog> catalog(List<PackageRecord> rs, Uri from, {Map? urls}) =>
      Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [for (final r in rs) r.json],
          'urls': ?urls,
        }),
        fetchedFrom: from,
        trust: trust,
      );

  group('merging a shelter catalog', () {
    final home = Uri.parse('https://example.org/catalog.json');
    final shelter = Uri.parse('http://192.168.1.20:8642/catalog.json');

    test('same or newer from the shelter wins, with its addresses', () async {
      final mine = await catalog([
        await _record(key, 'jp.x', '2026.11.1', shaA),
      ], home);
      final theirs = await catalog(
        [
          await _record(key, 'jp.x', '2026.11.2', shaB),
          await _record(key, 'jp.y', '1', shaA),
        ],
        shelter,
        urls: {shaB: 'blobs/sha256/$shaB', shaA: 'blobs/sha256/$shaA'},
      );
      final m = mine.mergedWith(theirs);
      final x = m.byId('jp.x')!;
      expect(x.version, '2026.11.2');
      expect(
        m.urlOf(x.files.single).toString(),
        'http://192.168.1.20:8642/blobs/sha256/$shaB',
      );
      expect(m.byId('jp.y'), isNotNull);
      expect(m.refreshUrl, mine.refreshUrl);
    });

    test('an older version on the shelter does not replace mine', () async {
      final mine = await catalog([
        await _record(key, 'jp.x', '2026.11.2', shaA),
      ], home);
      final theirs = await catalog([
        await _record(key, 'jp.x', '2026.11.1', shaB),
      ], shelter);
      expect(mine.mergedWith(theirs).byId('jp.x')!.version, '2026.11.2');
    });

    test(
      'records with a bad signature from the shelter are left out',
      () async {
        final other = await Ed25519().newKeyPair();
        final theirs = await catalog([
          await _record(other, 'jp.evil', '9', shaB),
        ], shelter);
        final m = (await catalog([], home)).mergedWith(theirs);
        expect(m.byId('jp.evil'), isNull);
        expect(m.rejected, isNotEmpty);
      },
    );
  });

  group('shelter server', () {
    late ShelterServer server;
    late Directory tmp;
    late List<int> data;
    late String sha;
    final port = 18000 + Random().nextInt(2000);
    Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lychnion-shelter');
      data = List<int>.generate(5000, (i) => i * 7 & 0xff);
      sha = sha256.convert(data).toString();
      final file = File('${tmp.path}/x.sqlite')..writeAsBytesSync(data);
      server = ShelterServer(
        answerer: GroundedAnswerer(
          LocalLlm(),
          KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite'),
        ),
        name: 'Test shelter',
        modelName: 'none',
        library: _OneFile(file, sha, {
          'format': 2,
          'records': const [],
          'urls': {sha: 'blobs/sha256/$sha'},
        }),
      );
      await server.start(port: port);
    });
    tearDown(() async {
      await server.stop();
      await tmp.delete(recursive: true);
    });

    Future<(int, List<int>, HttpHeaders)> get(
      String path, {
      String? range,
    }) async {
      final c = HttpClient();
      try {
        final req = await c.getUrl(url(path));
        if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
        final res = await req.close();
        final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
        return (res.statusCode, body, res.headers);
      } finally {
        c.close(force: true);
      }
    }

    test('serves its catalog', () async {
      final (status, body, _) = await get('/catalog.json');
      expect(status, 200);
      expect((jsonDecode(utf8.decode(body)) as Map)['format'], 2);
    });

    test('serves a file by its hash, also from an offset', () async {
      final (s1, all, _) = await get('/blobs/sha256/$sha');
      expect(s1, 200);
      expect(all, data);
      final (s2, rest, h) = await get(
        '/blobs/sha256/$sha',
        range: 'bytes=1000-',
      );
      expect(s2, 206);
      expect(rest, data.sublist(1000));
      expect(h.value(HttpHeaders.contentRangeHeader), 'bytes 1000-4999/5000');
    });

    test('serves nothing else', () async {
      expect((await get('/blobs/sha256/${'0' * 64}')).$1, 404);
      expect((await get('/blobs/sha256/../../etc/passwd')).$1, 404);
      expect((await get('/blobs/x.sqlite')).$1, 404);
    });
  });
}
