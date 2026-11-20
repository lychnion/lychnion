// Only Lychnion publishes models (lychnion/lychnion#67): an added
// publisher's model is refused in catalogs, on sticks and from bases, is
// never installed, and one installed by an older build is never loaded.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion_format/lychnion_format.dart';

const city = 'jp.city.test';

Future<PackageRecord> _record(
  SimpleKeyPair key, {
  required String publisher,
  String id = 'jp.city.chat',
  String kind = 'model',
}) => PackageRecord.sign({
  'format': 1,
  'id': id,
  'kind': kind,
  'version': '1',
  'publisher': publisher,
  'role': 'chat',
  'title': {'en': 'Chat'},
  'files': [
    {
      'name': kind == 'model' ? '$id.gguf' : '$id.sqlite',
      'size': 3,
      'sha256': '0' * 64,
    },
  ],
  'signed': '2026-11-20T09:00:00+09:00',
}, key);

void main() {
  late Directory tmp;
  late SimpleKeyPair cityKey, lychnionKey;
  late TrustedKeys builtIn;

  setUpAll(() async {
    cityKey = await Ed25519().newKeyPair();
    lychnionKey = await Ed25519().newKeyPair();
    builtIn = TrustedKeys({
      'lychnion': [await publicKeyOf(lychnionKey)],
    });
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-models');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<PublisherList> publishers() async {
    final p = PublisherList(
      File('${tmp.path}/publishers.json'),
      builtIn: builtIn,
    );
    await p.add(PublisherLink(name: city, key: await publicKeyOf(cityKey)));
    return p;
  }

  Future<void> put(String kind, String name) async {
    final f = File('${tmp.path}/${kind}s/$name');
    await f.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]);
  }

  test('the rule: models from built-in publishers only', () {
    expect(mayPublishKind('lychnion', 'model'), isTrue);
    expect(mayPublishKind(city, 'model'), isFalse);
    expect(mayPublishKind(city, 'package'), isTrue);
    expect(mayPublishKind(city, 'map'), isTrue);
  });

  test(
    "a catalog leaves out an added publisher's model, keeps its guide",
    () async {
      final p = await publishers();
      final c = await Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [
            (await _record(cityKey, publisher: city)).json,
            (await _record(
              cityKey,
              publisher: city,
              id: 'jp.g',
              kind: 'package',
            )).json,
            (await _record(
              lychnionKey,
              publisher: 'lychnion',
              id: 'model.own',
            )).json,
          ],
        }),
        trust: p.trust,
        fetchedFrom: Uri.parse('https://example.org/catalog.json'),
      );
      expect([for (final i in c.items) i.id]..sort(), ['jp.g', 'model.own']);
      // Said why, for the log.
      expect(c.rejected, ['jp.city.chat: model from $city']);
    },
  );

  test("an added publisher's model is never installed", () async {
    final s = DownloadStore(tmp, publishers: await publishers());
    await put('model', 'jp.city.chat.gguf');
    final item = CatalogItem.fromRecord(
      await _record(cityKey, publisher: city),
    );
    expect(s.isTaken(item), isTrue);
    await expectLater(s.markInstalled(item), throwsA(isA<TakenItem>()));
    expect(s.allInstalled(ItemKind.model), isEmpty);
  });

  test('one installed by an older build is never loaded or picked', () async {
    final s = DownloadStore(tmp, publishers: await publishers());
    await put('model', 'jp.city.chat.gguf');
    // What an older build wrote: a verified marker for the city's model.
    final r = await _record(cityKey, publisher: city);
    await File('${tmp.path}/models/jp.city.chat.installed.json')
        .writeAsString(jsonEncode({'format': 1, 'record': r.json}));
    await s.verifyInstalled();
    expect(s.installed(ItemKind.model, 'jp.city.chat'), isNull);
    expect(s.allInstalled(ItemKind.model), isEmpty);
    expect(s.chatModelPath(), isNull);
  });
}
