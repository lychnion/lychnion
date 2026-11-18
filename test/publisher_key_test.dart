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
      // Nothing signed by the revoked key vouches for the new one: the
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
      expect(p.statements, hasLength(KeyStatement.maxReplacesPerPublisher));
      final revoke = await KeyStatement.revoke(
        publisher: _name,
        key: await me.keyPair(),
        signed: nowStamp(),
      );
      expect(await p.learn([revoke]), isTrue);
      expect(p.keyStateOf(_name), PublisherKeyState.revoked);
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
}
