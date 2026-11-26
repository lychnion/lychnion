// Backing up, replacing and revoking a publisher key (issue 41;
// docs/distribution.md, "Backing up and replacing the key").
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_library.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/download/stick.dart';
import 'package:lychnion/publish/local_publisher.dart';
import 'package:lychnion/publish/publish.dart';
import 'package:lychnion_format/lychnion_format.dart';

import 'publish_test.dart' show packageFile;

const _pass = 'correct horse battery';
const _fast = KeyBackupKdf(memory: 64, iterations: 1);
const _name = 'jp.city.kobe';

Future<LocalPublisher> _restore(Directory d, String text, String pass) async =>
    LocalPublisher.restore(d, await KeyBackup.open(text, pass));

void main() {
  late Directory tmp, pubDir;
  late DownloadStore desk;
  late LocalPublisher me;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-key');
    pubDir = Directory('${tmp.path}/publisher');
    desk = DownloadStore(
      Directory('${tmp.path}/desk'),
      publishers: PublisherList(File('${tmp.path}/desk/publishers.json')),
    );
    me = await LocalPublisher.create(pubDir, name: _name, title: '神戸市');
  });
  tearDown(() => tmp.delete(recursive: true));

  /// A phone that added [link].
  Future<PublisherList> phone(String name, PublisherLink link) async {
    final l = PublisherList(File('${tmp.path}/$name/publishers.json'));
    await l.load();
    await l.add(link);
    return l;
  }

  Future<PackageRecord> publishOne(String version) => publish(
    requestFromPackage(packageFile(tmp, 'jp.city.kobe.guide', version))!,
    publisher: me,
    store: desk,
    publisherDir: pubDir,
  );

  group('backup', () {
    test('restore refuses when a key is here; nothing is changed', () async {
      final text = await me.backup(_pass, kdf: _fast);
      final before = LocalPublisher.fileIn(pubDir).readAsStringSync();
      expect(() => _restore(pubDir, text, _pass), throwsArgumentError);
      expect(LocalPublisher.fileIn(pubDir).readAsStringSync(), before);
    });

    test('a wrong passphrase or a damaged file writes no key', () async {
      final text = await me.backup(_pass, kdf: _fast);
      final d = Directory('${tmp.path}/new');
      await expectLater(
        _restore(d, text, 'wrong horse battery'),
        throwsA(isA<KeyBackupException>()),
      );
      await expectLater(
        _restore(d, text.replaceAll('"seed"', '"x"').substring(9), _pass),
        throwsA(isA<KeyBackupException>()),
      );
      expect(LocalPublisher.existsIn(d), isFalse);
    });

    test('export and import give the same publisher', () async {
      final text = await me.backup(_pass, kdf: _fast);
      final d = Directory('${tmp.path}/new');
      final back = await _restore(d, text, _pass);
      expect(back.name, _name);
      expect(back.title, '神戸市');
      expect(back.publicKey, me.publicKey);
      expect((await LocalPublisher.load(d))!.publicKey, me.publicKey);
    });
  });

  group('replace', () {
    test('an attacker\'s replacement is refused on the phone', () async {
      final p = await phone('phone', me.link);
      final thief = await Ed25519().newKeyPair();
      final t2 = await Ed25519().newKeyPair();
      final fake = await KeyStatement.replace(
        publisher: _name,
        oldKey: thief,
        newKey: t2,
        signed: nowStamp(),
      );
      // Claiming the city's key as the old one breaks the signature.
      expect(
        await KeyStatement.check({...fake.json, 'old': me.publicKey}),
        isNull,
      );
      expect(await p.learn([fake]), isFalse);
      expect(p.trust.keysOf(_name), {me.publicKey});
      expect(p.keyStateOf(_name), PublisherKeyState.added);
    });

    test('a replacement signed by the old key is accepted', () async {
      final old = await publishOne('2026.11.1');
      final p = await phone('phone', me.link);

      final next = await me.replaceKey(pubDir);
      expect(next.publicKey, isNot(me.publicKey));
      expect(next.statements.single.type, KeyStatementType.replace);
      // Saved with the key; keys.json (for the catalog) comes with
      // adoptNewKey, which can run again.
      expect((await LocalPublisher.load(pubDir))!.statements, next.statements);
      expect(await adoptNewKey(desk, pubDir, next), ['jp.city.kobe.guide']);
      expect(await adoptNewKey(desk, pubDir, next), isEmpty);
      final keys = jsonDecode(
        LocalPublisher.keysFileIn(pubDir).readAsStringSync(),
      ) as Map;
      expect(keys['keys'], [next.statements.single.json]);
      expect(
        LocalPublisher.keysFileIn(pubDir).readAsStringSync(),
        isNot(contains('seed')),
      );

      // This computer re-signed and keeps its item in use.
      final now = desk.installed(ItemKind.package, 'jp.city.kobe.guide')!;
      expect(now.record.keyId, next.keyId);
      expect(now.record.files.single.sha256, old.files.single.sha256);

      // The phone learns it and accepts records of the new key; the old
      // record stays valid.
      expect(await p.learn(next.statements), isTrue);
      expect(await p.trust.verify(now.record), isTrue);
      expect(await p.trust.verify(old), isTrue);
      expect(p.keyStateOf(_name), PublisherKeyState.replaced);
      expect(p.problemWith(next.link), PublisherProblem.known);

      // Kept across a restart.
      final again = PublisherList(p.file);
      await again.load();
      expect(await again.trust.verify(now.record), isTrue);
    });

    test('replacing a key changed meanwhile is refused', () async {
      final stale = me;
      await me.replaceKey(pubDir);
      expect(() => stale.replaceKey(pubDir), throwsArgumentError);
    });
  });

  group('revoke', () {
    test('a revocation is honoured; the new link replaces it', () async {
      final old = await publishOne('2026.11.1');
      final p = await phone('phone', me.link);

      final next = await me.revokeAndRenew(pubDir);
      expect(next.statements.single.type, KeyStatementType.revoke);
      expect(await p.learn(next.statements), isTrue);
      expect(await p.trust.verify(old), isFalse);
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
      // Still listed, shown as revoked.
      expect(p.added.single.name, _name);
      // The old link stays refused, also after removing the publisher.
      await p.remove(_name);
      expect(p.problemWith(me.link), PublisherProblem.revoked);
      final again = PublisherList(p.file);
      await again.load();
      expect(again.problemWith(me.link), PublisherProblem.revoked);
      // Nothing signed by the revoked key speaks for the new one: the
      // new link is added by the user.
      expect(again.trust.publishers, isNot(contains(_name)));
      expect(again.problemWith(next.link), isNull);
      await again.add(next.link);

      // This computer re-signs with the new key; the phone accepts it.
      await adoptNewKey(desk, pubDir, next);
      final now = desk.installed(ItemKind.package, 'jp.city.kobe.guide')!;
      expect(now.record.keyId, next.keyId);
      expect(await again.trust.verify(now.record), isTrue);
    });

    test('a phone that still has the publisher re-adds its new link', () async {
      final p = await phone('phone', me.link);
      final next = await me.revokeAndRenew(pubDir);
      await p.learn(next.statements);
      expect(p.problemWith(next.link), isNull);
      await p.add(next.link);
      expect(p.keyStateOf(_name), PublisherKeyState.added);
      expect(p.trust.keysOf(_name), {next.publicKey});
    });

    test('the revocation in a backup works without the passphrase', () async {
      final text = await me.backup(_pass, kdf: _fast);
      final p = await phone('phone', me.link);
      final s = await KeyBackup.revocationIn(text);
      expect(await p.learn([s]), isTrue);
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
    });

    test('two successors of one key count as a theft', () async {
      final p = await phone('phone', me.link);
      final thief = await Ed25519().newKeyPair();
      final stolen = await KeyStatement.replace(
        publisher: _name,
        oldKey: await me.keyPair(),
        newKey: thief,
        signed: nowStamp(),
      );
      final next = await me.replaceKey(pubDir);
      await p.learn([stolen, ...next.statements]);
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
    });
  });

  group('phones learn', () {
    test('only about publishers they know', () async {
      final p = await phone('phone', me.link);
      final other = await Ed25519().newKeyPair();
      final s = await KeyStatement.revoke(
        publisher: 'jp.city.other',
        key: other,
        signed: nowStamp(),
      );
      expect(await p.learn([s]), isFalse);
      expect(p.statements, isEmpty);
    });

    test('statements about keys of their own cannot fill the list', () async {
      final p = await phone('phone', me.link);
      final junk = [
        for (var i = 0; i < 5; i++)
          await KeyStatement.revoke(
            publisher: _name,
            key: await Ed25519().newKeyPair(),
            signed: nowStamp(),
          ),
      ];
      expect(await p.learn(junk), isFalse);
      expect(p.statements, isEmpty);
      // The thief of the key names two successors: the second one and
      // anything after it are no longer kept.
      final thief = [
        for (var i = 0; i < 5; i++)
          await KeyStatement.replace(
            publisher: _name,
            oldKey: await me.keyPair(),
            newKey: await Ed25519().newKeyPair(),
            signed: nowStamp(),
          ),
      ];
      expect(await p.learn(thief), isTrue);
      expect(p.statements, hasLength(2));
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
    });

    test('a thief\'s long chain cannot keep out the revocation', () async {
      final p = await phone('phone', me.link);
      var prev = await me.keyPair();
      final chain = <KeyStatement>[];
      for (var i = 0; i < KeyStatement.maxReplacesPerPublisher + 5; i++) {
        final next = await Ed25519().newKeyPair();
        chain.add(
          await KeyStatement.replace(
            publisher: _name,
            oldKey: prev,
            newKey: next,
            signed: nowStamp(),
          ),
        );
        prev = next;
      }
      await p.learn(chain);
      // The root's rotations are not capped (lychnion/lychnion#125): only
      // its holder makes them, and its revocation still counts.
      expect(p.statements, hasLength(chain.length));
      final revoke = await KeyStatement.revoke(
        publisher: _name,
        key: await me.keyPair(),
        signed: nowStamp(),
      );
      expect(await p.learn([revoke]), isTrue);
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
    });

    // lychnion/lychnion#59: what learn keeps past the limit, load reads
    // back.
    test('a revocation past the limit is read back', () async {
      final file = File('${tmp.path}/small/publishers.json');
      final p = PublisherList(file, maxStatements: 2);
      await p.load();
      await p.add(me.link);
      final k = [
        await me.keyPair(),
        for (var i = 0; i < 3; i++) await Ed25519().newKeyPair(),
      ];
      Future<KeyStatement> link(int i) => KeyStatement.replace(
        publisher: _name,
        oldKey: k[i],
        newKey: k[i + 1],
        signed: nowStamp(),
      );
      await p.learn([await link(0), await link(1), await link(2)]);
      // Made by the added key and its successors: kept past the limit too,
      // never crowded out (lychnion/lychnion#125).
      expect(p.statements, hasLength(3));
      final revoke = await KeyStatement.revoke(
        publisher: _name,
        key: k[2],
        signed: nowStamp(),
      );
      expect(await p.learn([revoke]), isTrue);
      expect(p.statements, hasLength(4));
      final again = PublisherList(file, maxStatements: 2);
      await again.load();
      expect(again.statements, contains(revoke));
      expect(
        again.trust.keysOf(_name),
        isNot(contains(TrustedKeys.canonicalKey(await publicKeyOf(k[2])))),
      );
    });

    // lychnion/lychnion#59: both halves of a theft proof in one batch are
    // kept, also when the list is full.
    test('a theft proof in one batch is kept when the list is full', () async {
      final file = File('${tmp.path}/full/publishers.json');
      final p = PublisherList(file, maxStatements: 2);
      await p.load();
      await p.add(me.link);
      final k1 = await Ed25519().newKeyPair();
      await p.learn([
        await KeyStatement.replace(
          publisher: _name,
          oldKey: await me.keyPair(),
          newKey: k1,
          signed: nowStamp(),
        ),
      ]);
      expect(p.statements, hasLength(1));
      final k1Key = TrustedKeys.canonicalKey(await publicKeyOf(k1));
      expect(p.trust.keysOf(_name), contains(k1Key));
      // The thief and the owner of k1 each name a successor.
      final two = [
        for (var i = 0; i < 2; i++)
          await KeyStatement.replace(
            publisher: _name,
            oldKey: k1,
            newKey: await Ed25519().newKeyPair(),
            signed: nowStamp(),
          ),
      ];
      expect(await p.learn(two), isTrue);
      expect(p.statements, hasLength(3));
      expect(p.trust.keysOf(_name), isNot(contains(k1Key)));
    });

    // lychnion/lychnion#59: a thief's own new keys cannot each add a
    // theft proof past the limit; only keys trusted before the batch.
    test('in-batch theft proofs count only for keys trusted before', () async {
      final file = File('${tmp.path}/thief/publishers.json');
      final p = PublisherList(file, maxStatements: 2);
      await p.load();
      await p.add(me.link);
      final k = await Ed25519().newKeyPair();
      await p.learn([
        await KeyStatement.replace(
          publisher: _name,
          oldKey: await me.keyPair(),
          newKey: k,
          signed: nowStamp(),
        ),
      ]);
      final a1 = await Ed25519().newKeyPair(),
          b1 = await Ed25519().newKeyPair();
      Future<KeyStatement> rep(SimpleKeyPair from, SimpleKeyPair to) =>
          KeyStatement.replace(
            publisher: _name,
            oldKey: from,
            newKey: to,
            signed: nowStamp(),
          );
      final batch = [
        await rep(k, a1),
        await rep(a1, await Ed25519().newKeyPair()),
        await rep(a1, await Ed25519().newKeyPair()),
        await rep(k, b1),
      ];
      await p.learn(batch);
      // The pair on k only; a1's pair is past the limit.
      expect(p.statements, hasLength(3));
      expect(p.statements, containsAll([batch[0], batch[3]]));
    });

    // lychnion/lychnion#59: a revocation stored with its signature spelled
    // another way (before the one-spelling rule) is still read back.
    test('a stored revocation spelled another way is read back', () async {
      final file = File('${tmp.path}/old/publishers.json');
      final p = PublisherList(file);
      await p.load();
      await p.add(me.link);
      final revoke = await KeyStatement.revoke(
        publisher: _name,
        key: await me.keyPair(),
        signed: nowStamp(),
      );
      await p.learn([revoke]);
      final j = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final st = (j['statements']! as List).single as Map<String, Object?>;
      st['signature'] = base64Url.encode(
        base64Url.decode(base64Url.normalize(st['signature']! as String)),
      );
      expect(st['signature'], endsWith('=='));
      file.writeAsStringSync(jsonEncode(j));
      final again = PublisherList(file);
      await again.load();
      expect(again.statements, [revoke]);
      expect(again.keyStateOf(_name), PublisherKeyState.revoked);
    });

    // lychnion/lychnion#59: phones take at most 50 replacements of one
    // publisher; past that only revoke-and-renew works.
    test('no replacement past the limit', () async {
      var p = me;
      for (var i = 0; i < KeyStatement.maxReplacesPerPublisher; i++) {
        expect(p.replacementsLeft, KeyStatement.maxReplacesPerPublisher - i);
        p = await p.replaceKey(pubDir);
      }
      expect(p.replacementsLeft, 0);
      expect(() => p.replaceKey(pubDir), throwsStateError);
      final renewed = await p.revokeAndRenew(pubDir);
      expect(renewed.replacementsLeft, 0);
    });

    test('a revocation listed before its replacement is kept', () async {
      final p = await phone('phone', me.link);
      final next = await me.replaceKey(pubDir);
      final revokeB = await KeyStatement.revoke(
        publisher: _name,
        key: await next.keyPair(),
        signed: nowStamp(),
      );
      await p.learn([revokeB, ...next.statements]);
      expect(p.statements, hasLength(2));
      expect(p.trust.keysOf(_name), {me.publicKey});
      // Also after a restart.
      final again = PublisherList(p.file);
      await again.load();
      expect(again.trust.keysOf(_name), {me.publicKey});
    });

    test('from a catalog: new-key records count at once', () async {
      final next = await me.replaceKey(pubDir);
      final r = await PackageRecord.sign({
        'format': 1,
        'id': 'jp.city.kobe.guide',
        'kind': 'package',
        'version': '2026.11.2',
        'publisher': _name,
        'files': [
          {'name': 'jp.city.kobe.guide.sqlite', 'size': 3, 'sha256': 'a' * 64},
        ],
        'signed': nowStamp(),
      }, await next.keyPair());
      final p = await phone('phone', me.link);
      final json = jsonEncode({
        'format': 2,
        'records': [r.json],
        'keys': [for (final s in next.statements) s.json],
      });
      final c = await Catalog.parse(json, trust: p.trust);
      expect(c.items.single.id, 'jp.city.kobe.guide');
      expect(c.statements, next.statements);
      // Without the statement: not trusted (as in older apps).
      final without = jsonEncode({
        'format': 2,
        'records': [r.json],
      });
      expect((await Catalog.parse(without, trust: p.trust)).items, isEmpty);
    });

    test('from a base, which serves them in its catalog', () async {
      await publishOne('2026.11.1');
      final next = await me.replaceKey(pubDir);
      await adoptNewKey(desk, pubDir, next);
      final cat = BaseLibrary(desk).catalog();
      expect(cat['keys'], [next.statements.single.json]);
      final p = await phone('phone', me.link);
      final c = await Catalog.parse(
        jsonEncode(cat),
        fetchedFrom: Uri.parse('http://192.168.1.2:8080/catalog.json'),
        trust: p.trust,
        ownFilesOnly: true,
      );
      expect(c.items.single.record!.keyId, next.keyId);
    });

    test('a base serves a revocation too', () async {
      await publishOne('2026.11.1');
      final next = await me.revokeAndRenew(pubDir);
      await adoptNewKey(desk, pubDir, next);
      final cat = BaseLibrary(desk).catalog();
      expect(cat['keys'], [next.statements.single.json]);
      final p = await phone('phone', me.link);
      await Catalog.parse(
        jsonEncode(cat),
        fetchedFrom: Uri.parse('http://192.168.1.2:8080/catalog.json'),
        trust: p.trust,
        ownFilesOnly: true,
      ).then((c) => p.learn(c.statements));
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
    });

    test('from a stick, which carries them on', () async {
      final data = utf8.encode('aaa');
      final here = DownloadStore(
        Directory('${tmp.path}/here'),
        publishers: PublisherList(File('${tmp.path}/here/publishers.json')),
      );
      await here.publishers.add(me.link);
      final next = await me.replaceKey(pubDir);
      await here.publishers.learn(next.statements);
      final r = await PackageRecord.sign({
        'format': 1,
        'id': 'jp.city.kobe.guide',
        'kind': 'package',
        'version': '1',
        'publisher': _name,
        'files': [
          {
            'name': 'jp.city.kobe.guide.sqlite',
            'size': data.length,
            'sha256': sha256.convert(data).toString(),
          },
        ],
        'signed': nowStamp(),
      }, await next.keyPair());
      final f = File(
        '${here.dirFor(ItemKind.package).path}/jp.city.kobe.guide.sqlite',
      );
      await f.create(recursive: true);
      await f.writeAsBytes(data);
      await here.markInstalled(CatalogItem.fromRecord(r));

      final stick = Directory('${tmp.path}/stick')..createSync();
      expect((await copyToStick(here, stick)).added, 1);
      final cat = jsonDecode(
        File('${stickFolder(stick).path}/catalog.json').readAsStringSync(),
      ) as Map;
      expect(cat['keys'], [next.statements.single.json]);

      final there = DownloadStore(
        Directory('${tmp.path}/there'),
        publishers: PublisherList(File('${tmp.path}/there/publishers.json')),
      );
      await there.publishers.add(me.link);
      final l = await loadFromStick(there, stick);
      expect(l.keysChanged, isTrue);
      expect(l.added, 1);
      expect(
        there.installed(ItemKind.package, 'jp.city.kobe.guide'),
        isNotNull,
      );
    });
  });

  // lychnion/lychnion#59: a full list must not make this computer forget
  // that its old key was replaced.
  group('own statements, full list', () {
    /// A store whose list keeps [max] statements (4 times that in all).
    Future<DownloadStore> smallDesk(int max) async {
      final list = PublisherList(
        File('${tmp.path}/small/publishers.json'),
        maxStatements: max,
      );
      await list.load();
      return DownloadStore(Directory('${tmp.path}/small'), publishers: list);
    }

    /// [n] replacements of other publishers, kept as the user's own would
    /// be (any): they fill the list.
    Future<void> fill(PublisherList l, int n) async {
      for (var i = 0; i < n; i++) {
        await l.learn([
          await KeyStatement.replace(
            publisher: 'jp.other.p$i',
            oldKey: await Ed25519().newKeyPair(),
            newKey: await Ed25519().newKeyPair(),
            signed: nowStamp(),
          ),
        ], any: true);
      }
    }

    Future<PublisherList> reload() async {
      final l = PublisherList(
        File('${tmp.path}/small/publishers.json'),
        maxStatements: 2,
      );
      await l.load();
      return l;
    }

    for (final published in [false, true]) {
      test('a replacement is kept and read back '
          '(${published ? 'after' : 'before'} the first publish)', () async {
        final s = await smallDesk(2);
        if (published) await s.publishers.add(me.link);
        await fill(s.publishers, 2);
        final next = await me.replaceKey(pubDir);
        await adoptNewKey(s, pubDir, next);
        final replace = next.statements.single;
        expect(s.publishers.statements, contains(replace));
        expect(s.publishers.trust.keysOf(_name), contains(next.publicKey));

        final again = await reload();
        expect(again.statements, contains(replace));
        expect(again.trust.keysOf(_name), contains(next.publicKey));
        // The others past the limit are not kept on reading back.
        expect(again.statements, hasLength(3));
      });
    }

    test('when even the hard limit is full, the key change says so', () async {
      final s = await smallDesk(1);
      await fill(s.publishers, 4);
      expect(s.publishers.statements, hasLength(4));
      final next = await me.replaceKey(pubDir);
      await expectLater(
        adoptNewKey(s, pubDir, next),
        throwsA(isA<PublishError>().having((e) => e.code, 'code', 'key')),
      );
      // Said after the rest was done: the new key is trusted here.
      expect(s.publishers.trust.keysOf(_name), contains(next.publicKey));
    });
  });
}
