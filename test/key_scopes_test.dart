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
    expect(list.statements.length, 10);
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
}
