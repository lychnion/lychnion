// A USB stick between places (docs/distribution.md, step 5d).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/stick.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late Directory tmp, stick;
  late SimpleKeyPair key;
  late TrustedKeys trust;

  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-stick');
    stick = Directory('${tmp.path}/stick')..createSync();
  });
  tearDown(() => tmp.delete(recursive: true));

  DownloadStore store(String name, {TrustedKeys? keys}) =>
      DownloadStore(Directory('${tmp.path}/$name'), trust: keys ?? trust);

  /// Installs [id] at [version] with one file holding [content].
  Future<PackageRecord> install(
    DownloadStore s,
    String id,
    String version,
    String content, {
    String publisher = 'lychnion',
    SimpleKeyPair? by,
  }) async {
    final data = utf8.encode(content);
    final r = await PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': version,
      'publisher': publisher,
      'title': {'en': id},
      'files': [
        {
          'name': '$id.sqlite',
          'size': data.length,
          'sha256': sha256.convert(data).toString(),
        },
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, by ?? key);
    final f = File('${s.dirFor(ItemKind.package).path}/$id.sqlite');
    await f.create(recursive: true);
    await f.writeAsBytes(data);
    await s.markInstalled(CatalogItem.fromRecord(r));
    return r;
  }

  test('copy to a stick, load on another device', () async {
    final here = store('here');
    final a = await install(here, 'jp.a', '1', 'aaa');
    await install(here, 'jp.b', '2', 'bbb');
    final c = await copyToStick(here, stick);
    expect(c.added, 2);
    final folder = stickFolder(stick);
    expect(folder.path, endsWith('/lychnion'));
    expect(
      File('${folder.path}/blobs/sha256/${a.files.single.sha256}')
          .readAsStringSync(),
      'aaa',
    );

    final there = store('there');
    final l = await loadFromStick(there, stick);
    expect(l.added, 2);
    expect(there.installed(ItemKind.package, 'jp.a'), isNotNull);
    expect(
      File(
        there.path(there.installed(ItemKind.package, 'jp.b')!, 'jp.b.sqlite'),
      ).readAsStringSync(),
      'bbb',
    );
    // Again: nothing new.
    final again = await loadFromStick(there, stick);
    expect((again.added, again.notNewer), (0, 2));
  });

  test('versions only go up, both ways', () async {
    final newer = store('newer');
    await install(newer, 'jp.a', '2', 'two');
    await copyToStick(newer, stick);
    final older = store('older');
    final old = await install(older, 'jp.a', '1', 'one');
    // The stick keeps version 2; loading it on the older device updates it.
    final c = await copyToStick(older, stick);
    expect((c.added, c.notNewer), (0, 1));
    expect(
      File('${stickFolder(stick).path}/blobs/sha256/${old.files.single.sha256}')
          .existsSync(),
      isFalse,
    );
    final l = await loadFromStick(older, stick);
    expect(l.added, 1);
    expect(older.installed(ItemKind.package, 'jp.a')!.version, '2');
  });

  test('a changed file is not installed; the old version stays', () async {
    final here = store('here');
    final r = await install(here, 'jp.a', '2', 'good');
    await copyToStick(here, stick);
    File('${stickFolder(stick).path}/blobs/sha256/${r.files.single.sha256}')
        .writeAsStringSync('evil');
    final there = store('there');
    await install(there, 'jp.a', '1', 'old');
    final l = await loadFromStick(there, stick);
    expect(l.added, 0);
    expect(l.failed, ['jp.a 2']);
    final inst = there.installed(ItemKind.package, 'jp.a')!;
    expect(inst.version, '1');
    expect(File(there.path(inst, 'jp.a.sqlite')).readAsStringSync(), 'old');
  });

  test('records of publishers not trusted here are not installed', () async {
    final here = store('here');
    await install(here, 'jp.a', '1', 'aaa');
    await copyToStick(here, stick);
    final stranger = TrustedKeys({
      'lychnion': [await publicKeyOf(await Ed25519().newKeyPair())],
    });
    final l = await loadFromStick(store('there', keys: stranger), stick);
    expect((l.added, l.notTrusted), (0, 1));
  });

  // lychnion/lychnion#67: only Lychnion publishes models.
  group("an added publisher's model on a stick", () {
    late SimpleKeyPair cityKey;
    late TrustedKeys withCity;
    setUpAll(() async {
      cityKey = await Ed25519().newKeyPair();
      withCity = TrustedKeys({
        'lychnion': [await publicKeyOf(key)],
        'jp.city.test': [await publicKeyOf(cityKey)],
      });
    });

    /// A stick holding Lychnion's guide and, as an older build could have
    /// written it, a city's model with its file.
    Future<void> stickWithCityModel() async {
      final here = store('here');
      await install(here, 'jp.a', '1', 'aaa');
      await copyToStick(here, stick);
      final data = utf8.encode('gguf');
      final hash = sha256.convert(data).toString();
      final model = await PackageRecord.sign({
        'format': 1,
        'id': 'jp.city.chat',
        'kind': 'model',
        'version': '1',
        'publisher': 'jp.city.test',
        'role': 'chat',
        'title': {'en': 'Chat'},
        'files': [
          {'name': 'jp.city.chat.gguf', 'size': data.length, 'sha256': hash},
        ],
        'signed': '2026-11-20T09:00:00+09:00',
      }, cityKey);
      final folder = Directory('${stick.path}/lychnion');
      final cat = File('${folder.path}/catalog.json');
      final j = jsonDecode(await cat.readAsString()) as Map<String, dynamic>;
      (j['records'] as List).add(model.json);
      await cat.writeAsString(jsonEncode(j));
      final blob = File('${folder.path}/blobs/sha256/$hash');
      await blob.create(recursive: true);
      await blob.writeAsBytes(data);
    }

    test('is not installed, even from a trusted publisher', () async {
      await stickWithCityModel();
      final there = store('there', keys: withCity);
      final l = await loadFromStick(there, stick);
      expect(l.added, 1);
      expect(l.notTrusted, 1);
      expect(there.allInstalled(ItemKind.model), isEmpty);
      expect(
        File('${there.dirFor(ItemKind.model).path}/jp.city.chat.installed.json')
            .existsSync(),
        isFalse,
      );
    });

    test('is not carried on by the next copy to the stick', () async {
      await stickWithCityModel();
      await copyToStick(store('here', keys: withCity), stick);
      final j = jsonDecode(
        await File('${stick.path}/lychnion/catalog.json').readAsString(),
      ) as Map;
      final ids = [for (final r in j['records'] as List) (r as Map)['id']];
      expect(ids, ['jp.a']);
    });
  });

  test('a stick without a Lychnion folder says so', () async {
    await expectLater(
      loadFromStick(store('there'), stick),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a node folder copied as it is works too', () async {
    final here = store('here');
    await install(here, 'jp.a', '1', 'aaa');
    await copyToStick(here, stick);
    // Move lychnion/* to the top of another stick.
    final flat = Directory('${tmp.path}/flat');
    await Directory('${stick.path}/lychnion').rename(flat.path);
    expect(stickFolder(flat).path, flat.path);
    expect((await loadFromStick(store('there'), flat)).added, 1);
  });

  test('a stick whose catalog cannot be read is not touched', () async {
    final here = store('here');
    await install(here, 'jp.a', '1', 'aaa');
    final folder = Directory('${stick.path}/lychnion');
    final blob = File('${folder.path}/blobs/sha256/${'0' * 64}');
    await blob.create(recursive: true);
    for (final text in ['{"format": 2, "records": [', '{"format": 3}']) {
      File('${folder.path}/catalog.json').writeAsStringSync(text);
      await expectLater(
        copyToStick(here, stick),
        throwsA(isA<UnreadableStick>()),
      );
      await expectLater(
        loadFromStick(store('there'), stick),
        throwsA(isA<UnreadableStick>()),
      );
      expect(File('${folder.path}/catalog.json').readAsStringSync(), text);
      expect(blob.existsSync(), isTrue);
    }
  });

  test('an untrusted record does not keep ours off the stick', () async {
    final other = await Ed25519().newKeyPair();
    final junk = await PackageRecord.sign({
      'format': 1,
      'id': 'jp.a',
      'kind': 'package',
      'version': '999',
      'publisher': 'lychnion',
      'title': {'en': 'junk'},
      'files': [
        {'name': 'jp.a.sqlite', 'size': 1, 'sha256': 'a' * 64},
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, other);
    final folder = Directory('${stick.path}/lychnion')..createSync();
    File('${folder.path}/catalog.json').writeAsStringSync(
      jsonEncode({
        'format': 2,
        'records': [junk.json],
      }),
    );
    final here = store('here');
    await install(here, 'jp.a', '1', 'aaa');
    final c = await copyToStick(here, stick);
    expect(c.added, 1);
    final l = await loadFromStick(store('there'), stick);
    expect(l.added, 1);
  });

  test('a damaged file on the stick is copied again', () async {
    final here = store('here');
    final r = await install(here, 'jp.a', '1', 'aaa');
    // Left by an earlier copy that was cut off: right size, wrong bytes.
    File('${stick.path}/lychnion/blobs/sha256/${r.files.single.sha256}')
      ..createSync(recursive: true)
      ..writeAsStringSync('xyz');
    expect((await copyToStick(here, stick)).added, 1);
    expect((await loadFromStick(store('there'), stick)).added, 1);
  });

  test('picking the lychnion folder itself works', () async {
    final picked = Directory('${stick.path}/lychnion')..createSync();
    expect(stickFolder(picked).path, picked.path);
  });

  test('a file missing on the stick is copied again', () async {
    final here = store('here');
    final r = await install(here, 'jp.a', '1', 'aaa');
    await copyToStick(here, stick);
    final blob = File(
      '${stickFolder(stick).path}/blobs/sha256/${r.files.single.sha256}',
    )..deleteSync();
    final c = await copyToStick(here, stick);
    expect((c.added, c.notNewer), (0, 1));
    expect(c.failed, isEmpty);
    expect(blob.readAsStringSync(), 'aaa');
  });

  test(
    'a newer version on the stick with a missing file is reported',
    () async {
      final newer = store('newer');
      final r = await install(newer, 'jp.a', '2', 'two');
      await copyToStick(newer, stick);
      File('${stickFolder(stick).path}/blobs/sha256/${r.files.single.sha256}')
          .deleteSync();
      final older = store('older');
      await install(older, 'jp.a', '1', 'one');
      final c = await copyToStick(older, stick);
      expect(c.notNewer, 1);
      expect(c.failed, ['jp.a 2']);
    },
  );

  test('a file damaged here is not copied to the stick', () async {
    final here = store('here');
    final r = await install(here, 'jp.a', '1', 'aaa');
    File(here.path(here.installed(ItemKind.package, 'jp.a')!, 'jp.a.sqlite'))
        .writeAsStringSync('bbb'); // same size
    final c = await copyToStick(here, stick);
    expect(c.added, 0);
    expect(c.failed, ['jp.a 1']);
    expect(
      File('${stickFolder(stick).path}/blobs/sha256/${r.files.single.sha256}')
          .existsSync(),
      isFalse,
    );
  });

  test('a linked folder on the stick is refused', () async {
    final elsewhere = Directory('${tmp.path}/elsewhere')..createSync();
    final keep = File('${elsewhere.path}/${'0' * 64}')..writeAsStringSync('x');
    Directory('${stick.path}/lychnion/blobs').createSync(recursive: true);
    Link('${stick.path}/lychnion/blobs/sha256').createSync(elsewhere.path);
    final here = store('here');
    await install(here, 'jp.a', '1', 'aaa');
    await expectLater(
      copyToStick(here, stick),
      throwsA(isA<UnreadableStick>()),
    );
    expect(keep.existsSync(), isTrue);
  });

  test("another trusted publisher's item of the same id stays", () async {
    final city = await Ed25519().newKeyPair();
    final both = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
      'city': [await publicKeyOf(city)],
    });
    final a = store('a', keys: both);
    final theirs = await install(
      a,
      'jp.a',
      '2',
      'city',
      publisher: 'city',
      by: city,
    );
    await copyToStick(a, stick);
    final b = store('b', keys: both);
    await install(b, 'jp.a', '1', 'ours');
    final c = await copyToStick(b, stick);
    expect(c.added, 0);
    expect(c.clashed, ['jp.a (city)']);
    expect(
      File(
        '${stickFolder(stick).path}/blobs/sha256/${theirs.files.single.sha256}',
      ).existsSync(),
      isTrue,
    );
  });

  test('files a node set aside (.kept.json) stay', () async {
    final here = store('here');
    final r = await install(here, 'jp.a', '1', 'aaa');
    // A node folder that set jp.a aside (its publisher was not given).
    final node = Directory('${tmp.path}/node')..createSync();
    final blob = File('${node.path}/blobs/sha256/${r.files.single.sha256}')
      ..createSync(recursive: true)
      ..writeAsStringSync('aaa');
    File('${node.path}/catalog.json')
        .writeAsStringSync(jsonEncode({'format': 2, 'records': <Object?>[]}));
    File('${node.path}/.kept.json').writeAsStringSync(jsonEncode([r.json]));
    await copyToStick(store('empty'), node);
    expect(blob.existsSync(), isTrue);
    // Unreadable: nothing is removed.
    File('${node.path}/.kept.json').writeAsStringSync('[');
    final other = File('${node.path}/blobs/sha256/${'1' * 64}')
      ..writeAsStringSync('x');
    await copyToStick(store('empty2'), node);
    expect(other.existsSync(), isTrue);
  });

  test('file names that differ only in case are not installed', () async {
    final data = utf8.encode('aaa');
    final f = {'size': data.length, 'sha256': sha256.convert(data).toString()};
    final r = await PackageRecord.sign({
      'format': 1,
      'id': 'jp.a',
      'kind': 'package',
      'version': '1',
      'publisher': 'lychnion',
      'title': {'en': 'a'},
      'files': [
        {'name': 'jp.a.sqlite', ...f},
        {'name': 'JP.A.sqlite', ...f},
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, key);
    final folder = Directory('${stick.path}/lychnion');
    File('${folder.path}/blobs/sha256/${f['sha256']}')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data);
    File('${folder.path}/catalog.json').writeAsStringSync(
      jsonEncode({
        'format': 2,
        'records': [r.json],
      }),
    );
    final l = await loadFromStick(store('there'), stick);
    expect(l.added, 0);
    expect(l.failed, ['jp.a 1']);
  });
}
