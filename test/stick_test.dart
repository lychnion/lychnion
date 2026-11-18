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
    String content,
  ) async {
    final data = utf8.encode(content);
    final r = await PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': version,
      'publisher': 'lychnion',
      'title': {'en': id},
      'files': [
        {
          'name': '$id.sqlite',
          'size': data.length,
          'sha256': sha256.convert(data).toString(),
        },
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, key);
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
      File(
        '${folder.path}/blobs/sha256/${a.files.single.sha256}',
      ).readAsStringSync(),
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
      File(
        '${stickFolder(stick).path}/blobs/sha256/${old.files.single.sha256}',
      ).existsSync(),
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
    File(
      '${stickFolder(stick).path}/blobs/sha256/${r.files.single.sha256}',
    ).writeAsStringSync('evil');
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
}
