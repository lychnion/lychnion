// Publishers the user adds (docs/distribution.md, step 4).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion_format/lychnion_format.dart';

const city = 'jp.city.test';

Future<PackageRecord> cityRecord(SimpleKeyPair key, {String id = 'jp.x'}) =>
    PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'package',
      'version': '1',
      'publisher': city,
      'title': {'ja': '市のガイド', 'en': 'City guide'},
      'files': [
        {'name': '$id.sqlite', 'size': 3, 'sha256': '0' * 64},
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, key);

void main() {
  late Directory tmp;
  late SimpleKeyPair key;
  late String publicKey;

  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    publicKey = await publicKeyOf(key);
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-publishers');
  });
  tearDown(() => tmp.delete(recursive: true));

  PublisherList list() => PublisherList(File('${tmp.path}/publishers.json'));
  PublisherLink link({String name = city, String? key, String? title}) =>
      PublisherLink(name: name, key: key ?? publicKey, title: title);

  group('PublisherLink', () {
    test('goes through a lychnion://publisher URI and back', () {
      final l = link(title: '神戸市');
      final back = PublisherLink.fromUri(Uri.parse('${l.toUri()}'))!;
      expect(back.name, city);
      expect(back.key, publicKey);
      expect(back.title, '神戸市');
      expect(back.keyId, hasLength(8));
    });

    test('other links are not publisher links', () {
      for (final s in [
        'lychnion://shelter?url=http://1.2.3.4:8642',
        'https://publisher?name=a&key=b',
        'lychnion://publisher?name=a',
        'lychnion://publisher?key=b',
      ]) {
        expect(PublisherLink.fromUri(Uri.parse(s)), isNull, reason: s);
      }
    });
  });

  group('PublisherList', () {
    test(
      'refuses bad names and keys, the built-in name, and a second key',
      () async {
        final l = list();
        expect(
          l.problemWith(link(name: 'Kobe City')),
          PublisherProblem.badName,
        );
        expect(l.problemWith(link(name: '.x')), PublisherProblem.badName);
        expect(l.problemWith(link(key: 'abc')), PublisherProblem.badKey);
        expect(l.problemWith(link(name: 'lychnion')), PublisherProblem.builtIn);
        expect(l.problemWith(link()), isNull);
        await l.add(link());
        expect(l.problemWith(link()), PublisherProblem.known);
        final other = await publicKeyOf(await Ed25519().newKeyPair());
        expect(l.problemWith(link(key: other)), PublisherProblem.otherKey);
        expect(() => l.add(link(key: other)), throwsArgumentError);
      },
    );

    test(
      'trusts records of added publishers, and stops after removal',
      () async {
        final l = list();
        final r = await cityRecord(key);
        expect(await l.trust.verify(r), isFalse);
        await l.add(link());
        expect(await l.trust.verify(r), isTrue);
        await l.remove(city);
        expect(await l.trust.verify(r), isFalse);
      },
    );

    test(
      'is saved and read again; hand-edited bad entries are skipped',
      () async {
        await list().add(link(title: '神戸市'));
        final again = list();
        await again.load();
        expect(again.added.single.title, '神戸市');
        expect(again.added.single.keyId, hasLength(8));

        final f = File('${tmp.path}/publishers.json');
        final j = jsonDecode(f.readAsStringSync()) as Map;
        (j['publishers'] as List).add({'name': 'lychnion', 'key': publicKey});
        f.writeAsStringSync(jsonEncode(j));
        final third = list();
        await third.load();
        expect(third.added.map((p) => p.name), [city]);

        f.writeAsStringSync('{broken');
        final fourth = list();
        await fourth.load();
        expect(fourth.added, isEmpty);
      },
    );
  });

  group('DownloadStore with added publishers', () {
    Future<void> put(String name) async {
      final f = File('${tmp.path}/packages/$name');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
    }

    test('installs a city package only once the city is added, and stops '
        'using it after removal', () async {
      final publishers = list();
      final s = DownloadStore(tmp, publishers: publishers);
      final item = CatalogItem.fromRecord(await cityRecord(key));
      await put('jp.x.sqlite');
      await expectLater(s.markInstalled(item), throwsA(isA<UnsignedItem>()));

      await publishers.add(link());
      await s.markInstalled(item);
      expect(s.installed(ItemKind.package, 'jp.x'), isNotNull);

      await publishers.remove(city);
      await s.reverify();
      expect(s.installed(ItemKind.package, 'jp.x'), isNull);
    });

    test(
      'a catalog read with the store trust shows the city records',
      () async {
        final publishers = list();
        final s = DownloadStore(tmp, publishers: publishers);
        final json = jsonEncode({
          'format': 2,
          'records': [(await cityRecord(key)).json],
        });
        expect((await Catalog.parse(json, trust: s.trust)).items, isEmpty);
        await publishers.add(link());
        expect(
          (await Catalog.parse(json, trust: s.trust)).items.single.id,
          'jp.x',
        );
      },
    );
  });
}
