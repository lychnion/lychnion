// Lychnion's vouches on a device: kept, checked again, carried
// (lychnion/lychnion#119, part 2). Labels only: nothing here changes
// which keys are trusted.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_library.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/stick.dart';
import 'package:lychnion/download/vouch_list.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late SimpleKeyPair lychnion, other, city;
  late TrustedKeys trust;
  late Directory tmp;

  setUpAll(() async {
    lychnion = await Ed25519().newKeyPair();
    other = await Ed25519().newKeyPair();
    city = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(lychnion)],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-vouches');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<Vouch> vouch(
    String publisher, {
    SimpleKeyPair? by,
    String signed = '2026-11-23T10:00:00+09:00',
    bool withdrawn = false,
  }) async => Vouch.sign(
    publisher: publisher,
    key: await publicKeyOf(city),
    title: {'en': publisher},
    checked: '2026-11-23',
    method: 'official-website',
    url: 'https://example.jp/',
    signed: signed,
    signer: by ?? lychnion,
    withdrawn: withdrawn,
  );

  File file() => File('${tmp.path}/vouches.json');

  group('VouchList', () {
    test('learn saves; load reads back and checks again', () async {
      final a = await vouch('jp.city.a');
      final list = VouchList(file());
      expect(await list.learn([a], trust), isTrue);
      expect(await list.learn([a], trust), isFalse, reason: 'known');
      expect(list.vouches, [a]);
      expect(list.ids, {a.id});

      // A forged copy in the file is left out when read.
      final j = jsonDecode(file().readAsStringSync()) as Map;
      final forged = Map<String, Object?>.of(a.json)
        ..['publisher'] = 'jp.city.b';
      j['vouches'] = [...j['vouches'] as List, forged];
      file().writeAsStringSync(jsonEncode(j));
      final again = VouchList(file());
      await again.load(trust);
      expect(again.vouches, [a]);

      // Read with keys that no longer trust that signer: nothing.
      final none = VouchList(file());
      await none.load(
        TrustedKeys({
          'lychnion': [await publicKeyOf(other)],
        }),
      );
      expect(none.vouches, isEmpty);
    });

    test('a signer not trusted here for Lychnion is not kept', () async {
      final list = VouchList(file());
      final byOther = await vouch('jp.city.a', by: other);
      expect(await list.learn([byOther], trust), isFalse);
      expect(list.vouches, isEmpty);
      expect(file().existsSync(), isFalse);
    });

    test('recheck leaves out vouches of a revoked Lychnion key', () async {
      final list = VouchList(file());
      final a = await vouch('jp.city.a');
      await list.learn([a], trust);
      var told = 0;
      list.addListener(() => told++);
      list.recheck(trust);
      expect(told, 0);
      list.recheck(
        TrustedKeys({
          'lychnion': [await publicKeyOf(other)],
        }),
      );
      expect(list.vouches, isEmpty);
      expect(told, 1);
    });

    test('status by vouchFor', () async {
      final list = VouchList(file());
      await list.learn([await vouch('jp.city.a')], trust);
      expect(
        list.statusOf('jp.city.a', await publicKeyOf(city), const []).status,
        VouchStatus.vouched,
      );
      expect(
        list.statusOf('jp.city.a', await publicKeyOf(other), const []).status,
        VouchStatus.otherKey,
      );
      expect(
        list.statusOf('jp.city.b', await publicKeyOf(city), const []).status,
        VouchStatus.none,
      );
    });

    test('at most max; what decides kept first', () async {
      final list = VouchList(file(), max: 2);
      final old = await vouch('jp.city.a', signed: '2026-11-01T00:00:00Z');
      final gone = await vouch(
        'jp.city.a',
        signed: '2026-11-02T00:00:00Z',
        withdrawn: true,
      );
      final b = await vouch('jp.city.b');
      expect(await list.learn([old, gone, b], trust), isTrue);
      expect(list.vouches.toSet(), {gone, b});
      // Only a replaced one more: nothing changes.
      expect(await list.learn([old], trust), isFalse);
    });

    test('a newer file is set aside, not read', () async {
      file().writeAsStringSync(jsonEncode({'format': 99, 'vouches': []}));
      final list = VouchList(file());
      await list.load(trust);
      expect(list.vouches, isEmpty);
    });
  });

  group('Catalog.parse', () {
    test('keeps vouches signed for Lychnion, skips known ones', () async {
      final a = await vouch('jp.city.a');
      final b = await vouch('jp.city.b');
      final byOther = await vouch('jp.city.c', by: other);
      final text = jsonEncode({
        'format': 2,
        'records': <Object>[],
        'vouches': [a.json, b.json, byOther.json, 'nonsense'],
      });
      final c = await Catalog.parse(text, trust: trust);
      expect(c.vouches, [a, b]);
      final known = await Catalog.parse(
        text,
        trust: trust,
        knownVouches: {a.id},
      );
      expect(known.vouches, [b]);
    });

    test(
      'a successor of Lychnion\'s key in the same catalog may vouch',
      () async {
        final s = await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: lychnion,
          newKey: other,
          signed: '2026-11-20T00:00:00Z',
        );
        final v = await vouch('jp.city.a', by: other);
        final c = await Catalog.parse(
          jsonEncode({
            'format': 2,
            'records': <Object>[],
            'keys': [s.json],
            'vouches': [v.json],
          }),
          trust: trust,
        );
        expect(c.vouches, [v]);
      },
    );
  });

  DownloadStore store(String name) =>
      DownloadStore(Directory('${tmp.path}/$name'), trust: trust);

  Future<PackageRecord> install(DownloadStore s, String id) async {
    final data = utf8.encode(id);
    final r = await PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': '1',
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
    }, lychnion);
    final f = File('${s.dirFor(ItemKind.package).path}/$id.sqlite');
    await f.create(recursive: true);
    await f.writeAsBytes(data);
    await s.markInstalled(CatalogItem.fromRecord(r));
    return r;
  }

  test('a stick carries vouches; another device keeps them', () async {
    final here = store('here');
    await install(here, 'jp.a');
    final a = await vouch('jp.city.a');
    await here.learnVouches([a]);
    final stick = Directory('${tmp.path}/stick')..createSync();
    await copyToStick(here, stick);

    // A second device adds its own; the stick's stay.
    final second = store('second');
    final b = await vouch('jp.city.b');
    await second.learnVouches([b]);
    final c2 = await copyToStick(second, stick);
    expect(c2.vouchesLeftOut, 0);

    final there = store('there');
    final r = await loadFromStick(there, stick);
    expect(r.vouchesNotSaved, isFalse);
    expect(there.vouches.vouches.toSet(), {a, b});
  });

  test('the base passes vouches on; its catalog follows changes', () async {
    final s = store('base');
    await install(s, 'jp.a');
    final lib = BaseLibrary(s);
    final first = lib.catalog();
    expect(first.containsKey('vouches'), isFalse);
    expect(identical(lib.catalog(), first), isTrue, reason: 'cached');
    final a = await vouch('jp.city.a');
    await s.learnVouches([a]);
    final next = lib.catalog();
    expect(next['vouches'], [a.json]);
    expect(lib.vouchesLeftOut, 0);
    // A phone reading it keeps the vouch.
    final c = await Catalog.parse(jsonEncode(next), trust: trust);
    expect(c.vouches, [a]);
  });
}
