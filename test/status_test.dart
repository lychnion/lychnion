// Publishers' statuses on a device: kept, checked again, carried, and their
// key statements and withdrawals taken in (lychnion/lychnion#117, part 2).
// Never a block: they only let the app say that something newer exists.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_library.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/status_list.dart';
import 'package:lychnion/download/stick.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late SimpleKeyPair lychnion, club, other;
  late String clubKey;
  late TrustedKeys trust;
  late Directory tmp;

  setUpAll(() async {
    lychnion = await Ed25519().newKeyPair();
    club = await Ed25519().newKeyPair();
    other = await Ed25519().newKeyPair();
    clubKey = await publicKeyOf(club);
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(lychnion)],
      'org.club': [clubKey],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-status');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<PublisherStatus> status({
    String publisher = 'lychnion',
    SimpleKeyPair? by,
    String signed = '2026-11-24T09:00:00+09:00',
    Map<String, String> items = const {'jp.a': '2026.11.10'},
    Iterable<KeyStatement> keys = const [],
    Iterable<Attestation> attestations = const [],
  }) => PublisherStatus.sign(
    publisher: publisher,
    signed: signed,
    items: items,
    signer: by ?? lychnion,
    keys: keys,
    attestations: attestations,
  );

  Future<Attestation> withdrawal(String publisher) => Attestation.sign(
    publisher: publisher,
    key: clubKey,
    checked: '2026-11-23',
    method: 'official-website',
    signed: '2026-11-24T08:00:00+09:00',
    signer: lychnion,
    withdrawn: true,
  );

  final now = DateTime.parse('2026-11-24T12:00:00+09:00');
  StatusList list({DateTime? at}) =>
      StatusList(File('${tmp.path}/status.json'), now: () => at ?? now);

  group('StatusList', () {
    test('keeps the newest of each publisher; load checks again', () async {
      final l = list();
      final old = await status(signed: '2026-11-01T00:00:00Z');
      final s = await status();
      final c = await status(publisher: 'org.club', by: club);
      expect(await l.learn([old, c], () => trust), isTrue);
      expect(await l.learn([s], () => trust), isTrue);
      expect(await l.learn([old], () => trust), isFalse, reason: 'older');
      expect(l.statusFor('lychnion', trust), s);
      expect(l.statusFor('org.club', trust), c);
      final again = list();
      await again.load(trust);
      expect(again.all.toSet(), {s, c});
      // Read with keys that no longer trust the club: not used.
      final fewer = TrustedKeys({
        'lychnion': [await publicKeyOf(lychnion)],
      });
      final third = list();
      await third.load(fewer);
      expect(third.all, [s]);
    });

    test('a status from more than a day ahead never decides', () async {
      final l = list();
      final s = await status();
      await l.learn([s], () => trust);
      final ahead = await status(signed: '2026-11-30T00:00:00+09:00');
      expect(await l.learn([ahead], () => trust), isFalse);
      expect(l.statusFor('lychnion', trust), s);
      // Within a day: fine (clocks differ).
      final soon = await status(signed: '2026-11-25T09:00:00+09:00');
      expect(await l.learn([soon], () => trust), isTrue);
    });

    test(
      'a signer not trusted is not kept; recheck drops a revoked one',
      () async {
        final l = list();
        expect(await l.learn([await status(by: other)], () => trust), isFalse);
        final c = await status(publisher: 'org.club', by: club);
        await l.learn([c], () => trust);
        var told = 0;
        l.addListener(() => told++);
        l.recheck(
          TrustedKeys({
            'lychnion': [await publicKeyOf(lychnion)],
          }),
        );
        expect(l.all, isEmpty);
        expect(told, 1);
      },
    );

    test('after a revocation, an earlier replacement is kept', () async {
      final next = await Ed25519().newKeyPair();
      final l = list();
      // The thief's status, signed later with the old key.
      final thief = await status(signed: '2026-11-24T11:00:00+09:00');
      await l.learn([thief], () => trust);
      final revoked = TrustedKeys({
        'lychnion': [await publicKeyOf(next)],
        'org.club': [clubKey],
      });
      final real = await status(by: next, signed: '2026-11-24T10:00:00+09:00');
      expect(await l.learn([real], () => revoked), isTrue);
      expect(l.statusFor('lychnion', revoked), real);
    });

    test('a far-future status in the file never decides', () async {
      final s = await status();
      final ahead = await status(signed: '2027-01-01T00:00:00+09:00');
      File('${tmp.path}/status.json').writeAsStringSync(
        jsonEncode({
          'format': 1,
          'status': [ahead.json, s.json],
        }),
      );
      final l = list();
      await l.load(trust);
      expect(l.statusFor('lychnion', trust), s);
    });

    test('known: only when what it carried is still here', () async {
      final l = list();
      final revoke = await KeyStatement.revoke(
        publisher: 'org.club',
        key: club,
        signed: '2026-11-24T08:00:00+09:00',
      );
      final c = await status(
        publisher: 'org.club',
        by: club,
        items: const {},
        keys: [revoke],
      );
      await l.learn([c], () => trust);
      expect(l.knownIds(statements: {}, attestations: {}), isEmpty);
      expect(l.knownIds(statements: {revoke.id}, attestations: {}), {c.id});
    });

    test('newer version, last news, and the 30-day hint', () async {
      final l = list();
      expect(l.isQuiet(trust), isFalse, reason: 'no status yet');
      expect(l.lastNews(trust), isNull);
      await l.learn([await status()], () => trust);
      expect(
        l.newerVersion('lychnion', 'jp.a', '2026.11.2', trust),
        '2026.11.10',
      );
      expect(l.newerVersion('lychnion', 'jp.a', '2026.11.10', trust), isNull);
      expect(l.newerVersion('org.club', 'jp.a', '1', trust), isNull);
      expect(l.isQuiet(trust), isFalse);
      final later = list(at: now.add(const Duration(days: 31)));
      await later.load(trust);
      expect(later.isQuiet(trust), isTrue);
    });
  });

  group('Catalog.parse', () {
    test(
      'keeps statuses; their revocations and withdrawals count at once',
      () async {
        final data = utf8.encode('x');
        final record = await PackageRecord.sign({
          'format': 1,
          'id': 'org.club.guide',
          'kind': 'package',
          'version': '1',
          'publisher': 'org.club',
          'title': {'en': 'Guide'},
          'files': [
            {
              'name': 'g.sqlite',
              'size': data.length,
              'sha256': sha256.convert(data).toString(),
            },
          ],
          'signed': '2026-11-18T09:00:00+09:00',
        }, club);
        // The club's key was stolen: its own status says so. A carrier that
        // passes on the status cannot leave the revocation out.
        final revoke = await KeyStatement.revoke(
          publisher: 'org.club',
          key: club,
          signed: '2026-11-24T08:00:00+09:00',
        );
        final clubStatus = await status(
          publisher: 'org.club',
          by: club,
          items: const {},
          keys: [revoke],
        );
        final gone = await withdrawal('org.club');
        final lychnionStatus = await status(attestations: [gone]);
        final text = jsonEncode({
          'format': 2,
          'records': [record.json],
          'status': [clubStatus.json, lychnionStatus.json],
        });
        final c = await Catalog.parse(text, trust: trust);
        expect(c.status.toSet(), {clubStatus, lychnionStatus});
        expect(c.statements, [revoke]);
        expect(c.items, isEmpty, reason: 'its key is revoked');
        expect(c.attestations, [gone]);
        // Known ones are not checked again.
        final known = await Catalog.parse(
          text,
          trust: trust,
          knownStatus: {lychnionStatus.id},
        );
        expect(known.status, [clubStatus]);
      },
    );
  });

  DownloadStore store(String name) =>
      DownloadStore(Directory('${tmp.path}/$name'), trust: trust);

  Future<void> install(DownloadStore s, String id) async {
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
  }

  test('a stick carries statuses and the withdrawals inside', () async {
    final here = store('here');
    await install(here, 'jp.a');
    final gone = await withdrawal('org.club');
    final s = await status(attestations: [gone]);
    await here.learnStatus([s]);
    final stick = Directory('${tmp.path}/stick')..createSync();
    final c = await copyToStick(here, stick);
    expect(c.statusLeftOut, 0);

    final there = store('there');
    final r = await loadFromStick(there, stick);
    expect(r.statusNotSaved, isFalse);
    expect(there.status.statusFor('lychnion', trust), s);
    // The withdrawal came with the status, though the stick's own
    // attestations list was empty.
    expect(there.attestations.attestations, [gone]);
  });

  test(
    'a far-future status on a stick does not push the real one out',
    () async {
      final here = store('here');
      await install(here, 'jp.a');
      final stick = Directory('${tmp.path}/stick')..createSync();
      final ahead = await status(signed: '2027-06-01T00:00:00+09:00');
      // An older stick that carried a stolen key's status dated far ahead.
      File('${stick.path}/catalog.json').writeAsStringSync(
        jsonEncode({
          'format': 2,
          'records': <Object>[],
          'status': [ahead.json],
        }),
      );
      final s = await status();
      await here.learnStatus([s]);
      await copyToStick(here, stick);
      final written = jsonDecode(
        File('${stick.path}/catalog.json').readAsStringSync(),
      ) as Map;
      expect(written['status'], [s.json]);
    },
  );

  test('the base passes statuses on; its catalog follows changes', () async {
    final s = store('base');
    await install(s, 'jp.a');
    final lib = BaseLibrary(s);
    final first = lib.catalog();
    expect(first.containsKey('status'), isFalse);
    final st = await status();
    await s.learnStatus([st]);
    final next = lib.catalog();
    expect(next['status'], [st.json]);
    expect(lib.statusLeftOut, 0);
    final c = await Catalog.parse(jsonEncode(next), trust: trust);
    expect(c.status, [st]);
  });
}
