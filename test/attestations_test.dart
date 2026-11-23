// Lychnion's attestations on a device: kept, checked again, carried
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
import 'package:lychnion/download/attestation_list.dart';
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
    tmp = await Directory.systemTemp.createTemp('lychnion-attestations');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<Attestation> attestation(
    String publisher, {
    SimpleKeyPair? by,
    String signed = '2026-11-23T10:00:00+09:00',
    bool withdrawn = false,
  }) async => Attestation.sign(
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

  File file() => File('${tmp.path}/attestations.json');

  group('AttestationList', () {
    test('learn saves; load reads back and checks again', () async {
      final a = await attestation('jp.city.a');
      final list = AttestationList(file());
      expect(await list.learn([a], () => trust), isTrue);
      expect(await list.learn([a], () => trust), isFalse, reason: 'known');
      expect(list.attestations, [a]);
      expect(list.ids, {a.id});

      // A forged copy in the file is left out when read.
      final j = jsonDecode(file().readAsStringSync()) as Map;
      final forged = Map<String, Object?>.of(a.json)
        ..['publisher'] = 'jp.city.b';
      j['attestations'] = [...j['attestations'] as List, forged];
      file().writeAsStringSync(jsonEncode(j));
      final again = AttestationList(file());
      await again.load(trust);
      expect(again.attestations, [a]);

      // Read with keys that no longer trust that signer: nothing.
      final none = AttestationList(file());
      await none.load(
        TrustedKeys({
          'lychnion': [await publicKeyOf(other)],
        }),
      );
      expect(none.attestations, isEmpty);
    });

    test('a signer not trusted here for Lychnion is not kept', () async {
      final list = AttestationList(file());
      final byOther = await attestation('jp.city.a', by: other);
      expect(await list.learn([byOther], () => trust), isFalse);
      expect(list.attestations, isEmpty);
      expect(file().existsSync(), isFalse);
    });

    test('recheck leaves out attestations of a revoked Lychnion key', () async {
      final list = AttestationList(file());
      final a = await attestation('jp.city.a');
      await list.learn([a], () => trust);
      var told = 0;
      list.addListener(() => told++);
      list.recheck(trust);
      expect(told, 0);
      list.recheck(
        TrustedKeys({
          'lychnion': [await publicKeyOf(other)],
        }),
      );
      expect(list.attestations, isEmpty);
      expect(told, 1);
    });

    test('status by attestationFor', () async {
      final list = AttestationList(file());
      await list.learn([await attestation('jp.city.a')], () => trust);
      expect(
        list
            .statusOf('jp.city.a', await publicKeyOf(city), const [], trust)
            .status,
        AttestationStatus.attested,
      );
      expect(
        list
            .statusOf('jp.city.a', await publicKeyOf(other), const [], trust)
            .status,
        AttestationStatus.otherKey,
      );
      expect(
        list
            .statusOf('jp.city.b', await publicKeyOf(city), const [], trust)
            .status,
        AttestationStatus.none,
      );
    });

    test('at most max; what decides kept first', () async {
      final list = AttestationList(file(), max: 2);
      final old = await attestation(
        'jp.city.a',
        signed: '2026-11-01T00:00:00Z',
      );
      final gone = await attestation(
        'jp.city.a',
        signed: '2026-11-02T00:00:00Z',
        withdrawn: true,
      );
      final b = await attestation('jp.city.b');
      expect(await list.learn([old, gone, b], () => trust), isTrue);
      expect(list.attestations.toSet(), {gone, b});
      // Only a replaced one more: nothing changes.
      expect(await list.learn([old], () => trust), isFalse);
    });

    test(
      'a revocation during the save: the attestation stays out of use',
      () async {
        final list = AttestationList(file());
        final revoked = TrustedKeys({
          'lychnion': [await publicKeyOf(other)],
        });
        var asked = 0;
        // Trusted when learned, revoked by the time the save is done.
        final changed = await list.learn([
          await attestation('jp.city.a'),
        ], () => asked++ == 0 ? trust : revoked);
        expect(changed, isTrue);
        expect(list.attestations, isEmpty);
        expect(list.attestationsFor(trust), isEmpty);
      },
    );

    test('attestationsFor leaves out a lapsed signer before recheck', () async {
      final list = AttestationList(file());
      final a = await attestation('jp.city.a');
      await list.learn([a], () => trust);
      final revoked = TrustedKeys({
        'lychnion': [await publicKeyOf(other)],
      });
      expect(list.attestationsFor(trust), [a]);
      expect(list.attestationsFor(revoked), isEmpty);
      expect(
        list
            .statusOf('jp.city.a', await publicKeyOf(city), const [], revoked)
            .status,
        AttestationStatus.none,
      );
    });

    test('a failed save changes nothing', () async {
      // A folder where the file should be: the rename fails.
      Directory(file().path).createSync();
      final list = AttestationList(file());
      await expectLater(
        list.learn([await attestation('jp.city.a')], () => trust),
        throwsA(isA<FileSystemException>()),
      );
      expect(list.attestations, isEmpty);
      expect(list.ids, isEmpty);
    });

    test('one over the cap is not kept, and not checked again', () async {
      final list = AttestationList(file(), max: 1);
      final newer = await attestation(
        'jp.city.a',
        signed: '2026-11-23T00:00:00Z',
      );
      final older = await attestation(
        'jp.city.b',
        signed: '2026-11-01T00:00:00Z',
      );
      expect(await list.learn([newer], () => trust), isTrue);
      expect(await list.learn([older], () => trust), isFalse);
      expect(list.attestations, [newer]);
      expect(list.ids, {newer.id, older.id});
      final c = await Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': <Object>[],
          'attestations': [older.json],
        }),
        trust: trust,
        knownAttestations: list.ids,
      );
      expect(c.attestations, isEmpty);
    });

    test('a newer file is set aside, not read', () async {
      file().writeAsStringSync(
        jsonEncode({'format': 99, 'attestations': <Object?>[]}),
      );
      final list = AttestationList(file());
      await list.load(trust);
      expect(list.attestations, isEmpty);
    });
  });

  group('Catalog.parse', () {
    test('keeps attestations signed for Lychnion, skips known ones', () async {
      final a = await attestation('jp.city.a');
      final b = await attestation('jp.city.b');
      final byOther = await attestation('jp.city.c', by: other);
      final text = jsonEncode({
        'format': 2,
        'records': <Object>[],
        'attestations': [a.json, b.json, byOther.json, 'nonsense'],
      });
      final c = await Catalog.parse(text, trust: trust);
      expect(c.attestations, [a, b]);
      final known = await Catalog.parse(
        text,
        trust: trust,
        knownAttestations: {a.id},
      );
      expect(known.attestations, [b]);
    });

    test(
      'a successor of Lychnion\'s key in the same catalog may attest',
      () async {
        final s = await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: lychnion,
          newKey: other,
          signed: '2026-11-20T00:00:00Z',
        );
        final v = await attestation('jp.city.a', by: other);
        final c = await Catalog.parse(
          jsonEncode({
            'format': 2,
            'records': <Object>[],
            'keys': [s.json],
            'attestations': [v.json],
          }),
          trust: trust,
        );
        expect(c.attestations, [v]);
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

  test('a stick carries attestations; another device keeps them', () async {
    final here = store('here');
    await install(here, 'jp.a');
    final a = await attestation('jp.city.a');
    await here.learnAttestations([a]);
    final stick = Directory('${tmp.path}/stick')..createSync();
    await copyToStick(here, stick);

    // A second device adds its own; the stick's stay.
    final second = store('second');
    final b = await attestation('jp.city.b');
    await second.learnAttestations([b]);
    final c2 = await copyToStick(second, stick);
    expect(c2.attestationsLeftOut, 0);

    final there = store('there');
    final r = await loadFromStick(there, stick);
    expect(r.attestationsNotSaved, isFalse);
    expect(there.attestations.attestations.toSet(), {a, b});
  });

  test(
    'the base passes attestations on; its catalog follows changes',
    () async {
      final s = store('base');
      await install(s, 'jp.a');
      final lib = BaseLibrary(s);
      final first = lib.catalog();
      expect(first.containsKey('attestations'), isFalse);
      expect(identical(lib.catalog(), first), isTrue, reason: 'cached');
      final a = await attestation('jp.city.a');
      await s.learnAttestations([a]);
      final next = lib.catalog();
      expect(next['attestations'], [a.json]);
      expect(lib.attestationsLeftOut, 0);
      // A phone reading it keeps the attestation.
      final c = await Catalog.parse(jsonEncode(next), trust: trust);
      expect(c.attestations, [a]);
    },
  );
}
