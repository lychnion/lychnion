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
import 'package:lychnion_format/lychnion_format.dart';

void main() {
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
    expect(s.givesSafetyLines(await install(s, 'jp.root', root)), isTrue);
    expect(s.givesSafetyLines(await install(s, 'jp.lines', lines)), isTrue);
    // A data key brings the guide, not its official lines.
    expect(s.givesSafetyLines(await install(s, 'jp.data', data)), isFalse);
  });

  test(
    'a bundled id downloaded with a data key: its lines do not count',
    () async {
      final s = DownloadStore(Directory('${tmp.path}/b'), trust: trust);
      await install(s, 'jp.bousai.core', data);
      final src = await s.bundledPackageSource(
        'jp.bousai.core',
        'jp.bousai.core.sqlite',
      );
      expect(src.shadowed, isNull, reason: "Lychnion's own download is used");
      expect(src.safetyLines, isFalse);
    },
  );
}
