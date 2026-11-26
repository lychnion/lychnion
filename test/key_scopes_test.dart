// Key scopes in the app (lychnion/lychnion#125): a package's official
// safety lines count only when its signer may sign safety lines, and
// attestations and statuses need their own scopes.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  // copyBundled reads the app's assets.
  TestWidgetsFlutterBinding.ensureInitialized();
  late SimpleKeyPair root, data, lines;
  late TrustedKeys trust;
  late Directory tmp;

  setUpAll(() async {
    root = await Ed25519().newKeyPair();
    data = await Ed25519().newKeyPair();
    lines = await Ed25519().newKeyPair();
    const t = '2026-11-26T09:00:00+09:00';
    trust =
        TrustedKeys({
          'lychnion': [await publicKeyOf(root)],
        }).withStatements([
          await KeyStatement.grant(
            publisher: 'lychnion',
            granter: root,
            newKey: data,
            scope: [KeyScope.data],
            signed: t,
          ),
          await KeyStatement.grant(
            publisher: 'lychnion',
            granter: root,
            newKey: lines,
            scope: [KeyScope.data, KeyScope.safetyLines],
            signed: t,
          ),
        ]);
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-scopes');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<Installed> install(
    DownloadStore s,
    String id,
    SimpleKeyPair by,
  ) async {
    final bytes = utf8.encode(id);
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
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
      'signed': '2026-11-26T09:00:00+09:00',
    }, by);
    final f = File('${s.dirFor(ItemKind.package).path}/$id.sqlite');
    await f.create(recursive: true);
    await f.writeAsBytes(bytes);
    await s.markInstalled(CatalogItem.fromRecord(r));
    return s.installed(ItemKind.package, id)!;
  }

  test('safety lines count only with the safety-lines scope', () async {
    final s = DownloadStore(Directory('${tmp.path}/s'), trust: trust);
    expect(await s.givesSafetyLines(await install(s, 'jp.root', root)), isTrue);
    expect(
      await s.givesSafetyLines(await install(s, 'jp.lines', lines)),
      isTrue,
    );
    // A data key brings the guide, not its official lines.
    expect(
      await s.givesSafetyLines(await install(s, 'jp.data', data)),
      isFalse,
    );
  });

  test('a successor of the safety-lines key keeps the scope', () async {
    final next = await Ed25519().newKeyPair();
    final s = DownloadStore(
      Directory('${tmp.path}/n'),
      trust: trust.withStatements([
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: lines,
          newKey: next,
          signed: '2026-11-26T10:00:00+09:00',
        ),
      ]),
    );
    expect(await s.givesSafetyLines(await install(s, 'jp.next', next)), isTrue);
  });

  test(
    'a bundled id downloaded with a data key: the bundled file stays',
    () async {
      final s = DownloadStore(Directory('${tmp.path}/b'), trust: trust);
      await install(s, 'jp.bousai.core', data);
      final src = await s.bundledPackageSource(
        'jp.bousai.core',
        'jp.bousai.core.sqlite',
      );
      // Not the download: its official lines would not count, and the
      // bundled ones would be lost.
      expect(src.path, isNot(contains('${tmp.path}/b/downloads')));
      expect(src.notUsed, isTrue);
      expect(await s.bundledDownloadNotUsed('jp.bousai.core'), isTrue);
      // With a key that may sign safety lines, the download is used.
      final t = DownloadStore(Directory('${tmp.path}/c'), trust: trust);
      await install(t, 'jp.bousai.core', lines);
      final used = await t.bundledPackageSource(
        'jp.bousai.core',
        'jp.bousai.core.sqlite',
      );
      expect(used.path, contains('${tmp.path}/c'));
      expect(used.notUsed, isFalse);
      expect(await t.bundledDownloadNotUsed('jp.bousai.core'), isFalse);
    },
  );

  test('a flood of revocations by a data key does not push out the real '
      'one', () async {
    final list = PublisherList(
      File('${tmp.path}/publishers.json'),
      builtIn: TrustedKeys({
        'lychnion': [await publicKeyOf(root)],
      }),
    );
    const t = '2026-11-26T09:00:00+09:00';
    await list.learn([
      await KeyStatement.grant(
        publisher: 'lychnion',
        granter: root,
        newKey: data,
        scope: [KeyScope.data],
        signed: t,
      ),
    ]);
    final flood = <KeyStatement>[];
    for (var i = 0; i < 60; i++) {
      final x = await Ed25519().newKeyPair();
      flood.add(
        await KeyStatement.revoke(
          publisher: 'lychnion',
          revoked: await publicKeyOf(x),
          by: data,
          signed: t,
        ),
      );
    }
    final real = await KeyStatement.revoke(
      publisher: 'lychnion',
      revoked: await publicKeyOf(data),
      by: root,
      signed: t,
    );
    expect(await list.learn([...flood, real]), isTrue);
    expect(list.statements, contains(real));
    expect(list.statements.any(flood.contains), isFalse);
    expect(list.trust.keysOf('lychnion'), {await publicKeyOf(root)});
  });

  test('a granted key fills the list; the root still revokes it', () async {
    final builtIn = TrustedKeys({
      'lychnion': [await publicKeyOf(root)],
    });
    final file = File('${tmp.path}/full.json');
    final list = PublisherList(file, builtIn: builtIn, maxStatements: 10);
    const t = '2026-11-26T09:00:00+09:00';
    final d = await Ed25519().newKeyPair();
    await list.learn([
      await KeyStatement.grant(
        publisher: 'lychnion',
        granter: root,
        newKey: d,
        scope: [KeyScope.data],
        signed: t,
      ),
    ]);
    // A thief's chain of the granted key.
    var prev = d;
    final chain = <KeyStatement>[];
    for (var i = 0; i < 30; i++) {
      final next = await Ed25519().newKeyPair();
      chain.add(
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: prev,
          newKey: next,
          signed: t,
        ),
      );
      prev = next;
    }
    await list.learn(chain);
    // The root's grant has a budget of its own.
    expect(list.statements.length, 11);
    final real = await KeyStatement.revoke(
      publisher: 'lychnion',
      revoked: await publicKeyOf(d),
      by: root,
      signed: t,
    );
    expect(await list.learn([real]), isTrue);
    expect(list.trust.keysOf('lychnion'), {await publicKeyOf(root)});
    // Read back too.
    final again = PublisherList(file, builtIn: builtIn, maxStatements: 10);
    await again.load();
    expect(again.statements, contains(real));
    expect(again.trust.keysOf('lychnion'), {await publicKeyOf(root)});
  });

  test('an added root floods grants; the built-in key\'s revocation and a '
      'theft proof still count', () async {
    final builtIn = TrustedKeys({
      'lychnion': [await publicKeyOf(root)],
    });
    final file = File('${tmp.path}/flood.json');
    final list = PublisherList(file, builtIn: builtIn, maxStatements: 5);
    await list.load();
    const t = '2026-11-26T09:00:00+09:00';
    final a = await Ed25519().newKeyPair();
    await list.add(PublisherLink(name: 'jp.a', key: await publicKeyOf(a)));
    final d = await Ed25519().newKeyPair();
    await list.learn([
      await KeyStatement.grant(
        publisher: 'lychnion',
        granter: root,
        newKey: d,
        scope: [KeyScope.data],
        signed: t,
      ),
    ]);
    for (var round = 0; round < 3; round++) {
      await list.learn([
        for (var i = 0; i < 20; i++)
          await KeyStatement.grant(
            publisher: 'jp.a',
            granter: a,
            newKey: await Ed25519().newKeyPair(),
            scope: [KeyScope.data],
            signed: '$t$round',
          ),
      ]);
    }
    // A granted key is not a replaced one.
    expect(list.keyStateOf('jp.a'), PublisherKeyState.added);
    final theft = [
      for (var i = 0; i < 2; i++)
        await KeyStatement.replace(
          publisher: 'lychnion',
          oldKey: d,
          newKey: await Ed25519().newKeyPair(),
          signed: t,
        ),
    ];
    await list.learn(theft);
    final self = await KeyStatement.revoke(
      publisher: 'lychnion',
      key: root,
      signed: t,
    );
    expect(await list.learn([self]), isTrue);
    final again = PublisherList(file, builtIn: builtIn, maxStatements: 5);
    await again.load();
    expect(again.statements, containsAll([...theft, self]));
    expect(again.trust.keysOf('lychnion'), isEmpty);
  });

  test('other roots fill their budget; the root\'s revocation of a granted '
      'key still counts', () async {
    final builtIn = TrustedKeys({
      'lychnion': [await publicKeyOf(root)],
    });
    final file = File('${tmp.path}/revoke.json');
    final list = PublisherList(file, builtIn: builtIn, maxStatements: 5);
    await list.load();
    const t = '2026-11-26T09:00:00+09:00';
    final d = await Ed25519().newKeyPair();
    await list.learn([
      await KeyStatement.grant(
        publisher: 'lychnion',
        granter: root,
        newKey: d,
        scope: [KeyScope.data],
        signed: t,
      ),
    ]);
    // Two added publishers' roots fill the roots' budget with grants.
    for (final name in ['jp.a', 'jp.b']) {
      final a = await Ed25519().newKeyPair();
      await list.add(PublisherLink(name: name, key: await publicKeyOf(a)));
      await list.learn([
        for (var i = 0; i < 10; i++)
          await KeyStatement.grant(
            publisher: name,
            granter: a,
            newKey: await Ed25519().newKeyPair(),
            scope: [KeyScope.data],
            signed: t,
          ),
      ]);
    }
    // The granted key is stolen: the root revokes it.
    final cut = await KeyStatement.revoke(
      publisher: 'lychnion',
      revoked: await publicKeyOf(d),
      by: root,
      signed: t,
    );
    expect(await list.learn([cut]), isTrue);
    final again = PublisherList(file, builtIn: builtIn, maxStatements: 5);
    await again.load();
    expect(again.statements, contains(cut));
    expect(again.trust.isRevoked('lychnion', await publicKeyOf(d)), isTrue);
  });

  test(
    'added publishers fill at most half of the revocations\' budget',
    () async {
      final builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(root)],
      });
      final file = File('${tmp.path}/half.json');
      // Revocations' budget: 6; added publishers together at most 3.
      final list = PublisherList(file, builtIn: builtIn, maxStatements: 3);
      await list.load();
      const t = '2026-11-26T09:00:00+09:00';
      final d = await Ed25519().newKeyPair();
      await list.learn([
        await KeyStatement.grant(
          publisher: 'lychnion',
          granter: root,
          newKey: d,
          scope: [KeyScope.data],
          signed: t,
        ),
      ]);
      // Seven added publishers' roots each revoke themselves.
      for (var i = 0; i < 7; i++) {
        final a = await Ed25519().newKeyPair();
        await list.add(
          PublisherLink(name: 'jp.p$i', key: await publicKeyOf(a)),
        );
        await list.learn([
          await KeyStatement.revoke(publisher: 'jp.p$i', key: a, signed: t),
        ]);
      }
      final cut = await KeyStatement.revoke(
        publisher: 'lychnion',
        revoked: await publicKeyOf(d),
        by: root,
        signed: t,
      );
      expect(await list.learn([cut]), isTrue);
      final again = PublisherList(file, builtIn: builtIn, maxStatements: 3);
      await again.load();
      expect(again.statements, contains(cut));
      expect(again.trust.isRevoked('lychnion', await publicKeyOf(d)), isTrue);
    },
  );

  test(
    'added publishers\' theft proofs count toward their half, whole',
    () async {
      final builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(root)],
      });
      final file = File('${tmp.path}/proofs.json');
      // Revocations' budget: 6; added publishers together at most 3.
      final list = PublisherList(file, builtIn: builtIn, maxStatements: 3);
      await list.load();
      const t = '2026-11-26T09:00:00+09:00';
      final d = await Ed25519().newKeyPair();
      await list.learn([
        await KeyStatement.grant(
          publisher: 'lychnion',
          granter: root,
          newKey: d,
          scope: [KeyScope.data],
          signed: t,
        ),
      ]);
      // Three added publishers' roots each name two successors: a theft
      // proof of two statements.
      for (var i = 0; i < 3; i++) {
        final a = await Ed25519().newKeyPair();
        await list.add(
          PublisherLink(name: 'jp.t$i', key: await publicKeyOf(a)),
        );
        await list.learn([
          for (var j = 0; j < 2; j++)
            await KeyStatement.replace(
              publisher: 'jp.t$i',
              oldKey: a,
              newKey: await Ed25519().newKeyPair(),
              signed: t,
            ),
        ]);
      }
      // Only the first pair fits the added half; no lone half is kept.
      int of(String name) =>
          list.statements.where((s) => s.publisher == name).length;
      expect([of('jp.t0'), of('jp.t1'), of('jp.t2')], [2, 0, 0]);
      final cut = await KeyStatement.revoke(
        publisher: 'lychnion',
        revoked: await publicKeyOf(d),
        by: root,
        signed: t,
      );
      expect(await list.learn([cut]), isTrue);
      final again = PublisherList(file, builtIn: builtIn, maxStatements: 3);
      await again.load();
      // What the phone took, it reads back.
      expect(again.statements, list.statements);
      expect(again.trust.isRevoked('lychnion', await publicKeyOf(d)), isTrue);
    },
  );

  group('a theft proof is kept whole', () {
    const t = '2026-11-26T09:00:00+09:00';
    Future<KeyStatement> rep(String p, SimpleKeyPair from, SimpleKeyPair to) =>
        KeyStatement.replace(publisher: p, oldKey: from, newKey: to, signed: t);

    test('on a key first trusted in the same batch', () async {
      final file = File('${tmp.path}/fork.json');
      final list = PublisherList(
        file,
        builtIn: TrustedKeys({}),
        maxStatements: 1,
      );
      await list.load();
      final a = await Ed25519().newKeyPair();
      await list.add(PublisherLink(name: 'jp.f', key: await publicKeyOf(a)));
      final k1 = await Ed25519().newKeyPair();
      await list.learn([
        await rep('jp.f', a, k1),
        await rep('jp.f', k1, await Ed25519().newKeyPair()),
        await rep('jp.f', k1, await Ed25519().newKeyPair()),
      ]);
      final k1Key = TrustedKeys.canonicalKey(await publicKeyOf(k1));
      final onK1 = list.statements
          .where((s) => TrustedKeys.canonicalKey(s.oldKey) == k1Key)
          .length;
      expect(onK1, isNot(1));
      final again = PublisherList(
        file,
        builtIn: TrustedKeys({}),
        maxStatements: 1,
      );
      await again.load();
      expect(again.statements, list.statements);
    });

    test('a pair past the added half', () async {
      final file = File('${tmp.path}/three.json');
      // Added publishers together at most 1 in budget 0.
      final list = PublisherList(
        file,
        builtIn: TrustedKeys({}),
        maxStatements: 1,
      );
      await list.load();
      final a = await Ed25519().newKeyPair();
      await list.add(PublisherLink(name: 'jp.g', key: await publicKeyOf(a)));
      await list.learn([
        for (var i = 0; i < 2; i++)
          await rep('jp.g', a, await Ed25519().newKeyPair()),
      ]);
      expect(list.statements, isEmpty);
      final again = PublisherList(
        file,
        builtIn: TrustedKeys({}),
        maxStatements: 1,
      );
      await again.load();
      expect(again.statements, isEmpty);
    });

    test('in budget 0 when the other budgets are full', () async {
      final builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(root)],
      });
      final file = File('${tmp.path}/zero.json');
      final list = PublisherList(file, builtIn: builtIn, maxStatements: 2);
      await list.load();
      final d = [await Ed25519().newKeyPair(), await Ed25519().newKeyPair()];
      // Budget 1: two grants by the root; budget 2: the granted keys'
      // own replacements.
      await list.learn([
        for (final k in d)
          await KeyStatement.grant(
            publisher: 'lychnion',
            granter: root,
            newKey: k,
            scope: [KeyScope.data],
            signed: t,
          ),
      ]);
      await list.learn([
        for (final k in d)
          await rep('lychnion', k, await Ed25519().newKeyPair()),
      ]);
      expect(list.statements, hasLength(4));
      final a = await Ed25519().newKeyPair();
      await list.add(PublisherLink(name: 'jp.z', key: await publicKeyOf(a)));
      final k1 = await Ed25519().newKeyPair();
      await list.learn([
        await rep('jp.z', a, k1),
        await rep('jp.z', k1, await Ed25519().newKeyPair()),
        await rep('jp.z', k1, await Ed25519().newKeyPair()),
      ]);
      final k1Key = TrustedKeys.canonicalKey(await publicKeyOf(k1));
      expect(
        list.statements
            .where((s) => TrustedKeys.canonicalKey(s.oldKey) == k1Key)
            .length,
        2,
      );
      expect(list.trust.keysOf('jp.z'), isNot(contains(k1Key)));
      final again = PublisherList(file, builtIn: builtIn, maxStatements: 2);
      await again.load();
      expect(again.statements, list.statements);
    });
  });
}
