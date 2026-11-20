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

Future<PackageRecord> cityRecord(
  SimpleKeyPair key, {
  String id = 'jp.x',
  String publisher = city,
  String version = '1',
  String? file,
}) => PackageRecord.sign({
  'format': 1,
  'id': id,
  'kind': 'package',
  'version': version,
  'publisher': publisher,
  'title': {'ja': '市のガイド', 'en': 'City guide'},
  'files': [
    {'name': file ?? '$id.sqlite', 'size': 3, 'sha256': '0' * 64},
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

  group('review fixes', () {
    late SimpleKeyPair lychnionKey;
    late TrustedKeys builtIn;
    setUpAll(() async {
      lychnionKey = await Ed25519().newKeyPair();
      builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(lychnionKey)],
      });
    });

    PublisherList withBuiltIn() =>
        PublisherList(File('${tmp.path}/publishers.json'), builtIn: builtIn);

    Future<void> put(String name) async {
      final f = File('${tmp.path}/packages/$name');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
    }

    test(
      "an added publisher cannot take a built-in publisher's id or files",
      () async {
        final publishers = withBuiltIn();
        await publishers.add(link());
        final s = DownloadStore(tmp, publishers: publishers);
        await put('jp.x.sqlite');
        await s.markInstalled(
          CatalogItem.fromRecord(
            await cityRecord(lychnionKey, publisher: 'lychnion'),
          ),
        );
        final sameId = CatalogItem.fromRecord(
          await cityRecord(key, version: '9'),
        );
        expect(s.isTaken(sameId), isTrue);
        await expectLater(s.markInstalled(sameId), throwsA(isA<TakenItem>()));
        final sameFile = CatalogItem.fromRecord(
          await cityRecord(key, id: 'jp.y', file: 'jp.x.sqlite'),
        );
        expect(s.isTaken(sameFile), isTrue);
        expect(
          s.installed(ItemKind.package, 'jp.x')!.record.publisher,
          'lychnion',
        );
      },
    );

    test('a catalog merge keeps an id with its publisher', () async {
      final publishers = withBuiltIn();
      await publishers.add(link());
      Future<Catalog> cat(PackageRecord r) => Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [r.json],
        }),
        trust: publishers.trust,
        fetchedFrom: Uri.parse('https://example.org/catalog.json'),
      );
      final mine = await cat(
        await cityRecord(lychnionKey, publisher: 'lychnion'),
      );
      final base = await cat(await cityRecord(key, version: '9'));
      final m = mine.mergedWith(base);
      expect(m.byId('jp.x')!.record!.publisher, 'lychnion');
      expect(m.byId('jp.x')!.version, '1');
    });

    test('versions only go up, also after the publisher was removed', () async {
      final publishers = withBuiltIn();
      await publishers.add(link());
      final s = DownloadStore(tmp, publishers: publishers);
      await put('jp.x.sqlite');
      await s.markInstalled(
        CatalogItem.fromRecord(await cityRecord(key, version: '2')),
      );
      await publishers.remove(city);
      await s.reverify();
      await publishers.add(link());
      await expectLater(
        s.markInstalled(
          CatalogItem.fromRecord(await cityRecord(key, version: '1')),
        ),
        throwsA(isA<OlderVersion>()),
      );
    });

    test('titles cannot pass for the app or hide characters', () {
      expect(PublisherLink.cleanTitle('Lychnion'), isNull);
      expect(PublisherLink.cleanTitle(' リクニオン '), isNull);
      expect(PublisherLink.cleanTitle('神戸\u202e市\n'), '神戸市');
      expect(PublisherLink.cleanTitle('x' * 100)!.length, 60);
      final l = PublisherLink.fromUri(
        Uri.parse(
          'lychnion://publisher?name=jp.a&title=Lychnion&key=$publicKey',
        ),
      )!;
      expect(l.title, isNull);
    });

    test(
      'one bad entry keeps the others; an unreadable file is kept aside',
      () async {
        final f = File('${tmp.path}/publishers.json');
        f.writeAsStringSync(
          jsonEncode({
            'publishers': [
              {'name': 42, 'key': publicKey},
              {'name': city, 'key': publicKey},
            ],
          }),
        );
        final l = list();
        await l.load();
        expect(l.added.map((p) => p.name), [city]);

        f.writeAsStringSync('{broken');
        await list().load();
        expect(File('${f.path}.broken').readAsStringSync(), '{broken');
      },
    );

    test('a list that cannot be saved does not trust the publisher', () async {
      // The file's place is taken by a folder: the save fails.
      Directory('${tmp.path}/publishers.json').createSync();
      final l = list();
      await expectLater(l.add(link()), throwsA(isA<FileSystemException>()));
      expect(l.added, isEmpty);
      expect(await l.trust.verify(await cityRecord(key)), isFalse);
    });

    test('the same key with or without padding is the same key', () async {
      final l = list();
      await l.add(link());
      expect(l.problemWith(link(key: '$publicKey=')), PublisherProblem.known);
    });
  });

  group('Copilot review fixes', () {
    late SimpleKeyPair lychnionKey;
    late TrustedKeys builtIn;
    setUpAll(() async {
      lychnionKey = await Ed25519().newKeyPair();
      builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(lychnionKey)],
      });
    });

    Future<DownloadStore> withLychnionX() async {
      final publishers = PublisherList(
        File('${tmp.path}/publishers.json'),
        builtIn: builtIn,
      );
      await publishers.add(link());
      final s = DownloadStore(tmp, publishers: publishers);
      final f = File('${tmp.path}/packages/jp.x.sqlite');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
      await s.markInstalled(
        CatalogItem.fromRecord(
          await cityRecord(lychnionKey, publisher: 'lychnion'),
        ),
      );
      return s;
    }

    test('file names and ids that differ only in case are taken', () async {
      final s = await withLychnionX();
      expect(
        s.isTaken(
          CatalogItem.fromRecord(
            await cityRecord(key, id: 'jp.y', file: 'JP.X.SQLITE'),
          ),
        ),
        isTrue,
      );
      expect(
        s.isTaken(CatalogItem.fromRecord(await cityRecord(key, id: 'JP.X'))),
        isTrue,
      );
      expect(
        s.isTaken(CatalogItem.fromRecord(await cityRecord(key, id: 'jp.z'))),
        isFalse,
      );
    });

    test('files named like the app\'s own records are refused', () async {
      final s = await withLychnionX();
      final r = await cityRecord(key, id: 'jp', file: 'jp.x.installed.json');
      expect(s.isTaken(CatalogItem.fromRecord(r)), isTrue);
      final c = await Catalog.parse(
        jsonEncode({
          'format': 2,
          'records': [r.json],
        }),
        trust: s.trust,
      );
      expect(c.items, isEmpty);
      expect(c.rejected.single, contains('reserved'));
    });

    test('the version on disk counts before downloading', () async {
      final s = await withLychnionX();
      final city = await cityRecord(key, id: 'jp.c', version: '3');
      final f = File('${tmp.path}/packages/jp.c.sqlite');
      await f.writeAsBytes([1, 2, 3]);
      await s.markInstalled(CatalogItem.fromRecord(city));
      await s.publishers.remove('jp.city.test');
      await s.reverify();
      final older = CatalogItem.fromRecord(
        await cityRecord(key, id: 'jp.c', version: '2'),
      );
      expect(s.installedVersion(older), isNull);
      expect(s.recordedVersion(older), '3');
    });

    test("removing a publisher's downloads keeps the others", () async {
      final s = await withLychnionX();
      final f = File('${tmp.path}/packages/jp.c.sqlite');
      await f.writeAsBytes([1, 2, 3]);
      await s.markInstalled(
        CatalogItem.fromRecord(await cityRecord(key, id: 'jp.c')),
      );
      expect(await s.deleteFrom('jp.city.test'), 1);
      expect(f.existsSync(), isFalse);
      expect(s.installed(ItemKind.package, 'jp.c'), isNull);
      expect(s.installed(ItemKind.package, 'jp.x'), isNotNull);
    });

    test('additions at the same time are all kept', () async {
      final l = list();
      final keys = [
        for (var i = 0; i < 3; i++)
          await publicKeyOf(await Ed25519().newKeyPair()),
      ];
      await Future.wait([
        for (var i = 0; i < 3; i++) l.add(link(name: 'jp.p$i', key: keys[i])),
      ]);
      final again = list();
      await again.load();
      expect(again.added.map((p) => p.name), ['jp.p0', 'jp.p1', 'jp.p2']);
    });
  });

  // lychnion/lychnion#68: Lychnion's ids are Lychnion's, from every route.
  group('Lychnion ids', () {
    late SimpleKeyPair lychnionKey;
    late TrustedKeys builtIn;
    setUpAll(() async {
      lychnionKey = await Ed25519().newKeyPair();
      builtIn = TrustedKeys({
        'lychnion': [await publicKeyOf(lychnionKey)],
      });
    });

    Future<DownloadStore> store() async {
      final publishers = PublisherList(
        File('${tmp.path}/publishers.json'),
        builtIn: builtIn,
      );
      await publishers.add(link());
      return DownloadStore(tmp, publishers: publishers);
    }

    Future<void> put(String name) async {
      final f = File('${tmp.path}/packages/$name');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
    }

    test('an added publisher cannot install a Lychnion id, also when '
        'Lychnion has not installed it', () async {
      final s = await store()
        ..reserve(['jp.x']);
      await put('jp.x.sqlite');
      for (final id in ['jp.x', 'JP.X']) {
        final item = CatalogItem.fromRecord(await cityRecord(key, id: id));
        expect(s.isTaken(item), isTrue, reason: id);
        await expectLater(s.markInstalled(item), throwsA(isA<TakenItem>()));
      }
      // Lychnion itself may.
      final own = CatalogItem.fromRecord(
        await cityRecord(lychnionKey, publisher: 'lychnion'),
      );
      expect(s.isTaken(own), isFalse);
      await s.markInstalled(own);
      expect(
        s.installed(ItemKind.package, 'jp.x')!.record.publisher,
        'lychnion',
      );
    });

    test('a copy installed before is not used, and Lychnion replaces it '
        'whatever version it claims', () async {
      final s = await store();
      await put('jp.x.sqlite');
      // Installed by an older build, before ids were reserved.
      await s.markInstalled(
        CatalogItem.fromRecord(await cityRecord(key, version: '99')),
      );
      expect(s.installed(ItemKind.package, 'jp.x'), isNotNull);

      s.reserve(['jp.x']);
      expect(s.installed(ItemKind.package, 'jp.x'), isNull);
      expect(s.allInstalled(ItemKind.package), isEmpty);
      final own = CatalogItem.fromRecord(
        await cityRecord(lychnionKey, publisher: 'lychnion', version: '1'),
      );
      expect(s.isTaken(own), isFalse);
      // Downloads and the USB stick read this too: no "older" refusal.
      expect(s.recordedVersion(own), isNull);
      await s.markInstalled(own);
      final now = s.installed(ItemKind.package, 'jp.x')!;
      expect((now.record.publisher, now.version), ('lychnion', '1'));
    });

    test("Lychnion's ids: the bundled packages and Lychnion's items in the "
        'catalog fetched last', () async {
      final s = await store();
      Map<String, Object?> rec(String id, String publisher) => {
        'id': id,
        'publisher': publisher,
      };
      await s.cachedCatalog.create(recursive: true);
      await s.cachedCatalog.writeAsString(
        jsonEncode({
          'url': 'https://example.org/catalog.json',
          'body': jsonEncode({
            'format': 2,
            'records': [
              rec('jp.new.guide', 'lychnion'),
              rec('jp.city.only', city),
            ],
          }),
        }),
      );
      final ids = await s.lychnionIds();
      expect(ids, containsAll(['jp.bousai.core', 'jp.new.guide']));
      expect(ids, isNot(contains('jp.city.only')));
    });

    test("an added publisher cannot use a Lychnion file name under another "
        'id', () async {
      final s = await store()
        ..reserve(const [], files: ['jp.x.sqlite']);
      final item = CatalogItem.fromRecord(
        await cityRecord(key, id: 'jp.evil', file: 'jp.x.sqlite'),
      );
      expect(s.isTaken(item), isTrue);
    });

    test("an added publisher's item never blocks Lychnion's, by a shared "
        'file name', () async {
      final s = await store();
      await put('jp.x.sqlite');
      // An older build let a city take Lychnion's file name.
      await s.markInstalled(
        CatalogItem.fromRecord(
          await cityRecord(key, id: 'jp.y', file: 'jp.x.sqlite'),
        ),
      );
      s.reserve(['jp.x'], files: ['jp.x.sqlite']);
      final own = CatalogItem.fromRecord(
        await cityRecord(lychnionKey, publisher: 'lychnion'),
      );
      expect(s.isTaken(own), isFalse);
    });

    test(
      "Lychnion's items of a checked catalog are reserved at once",
      () async {
        final s = await store();
        s.reserveFrom([
          CatalogItem.fromRecord(
            await cityRecord(lychnionKey, id: 'jp.new', publisher: 'lychnion'),
          ),
          CatalogItem.fromRecord(await cityRecord(key, id: 'jp.mine')),
        ]);
        expect(s.isReservedFor('jp.new', city), isTrue);
        expect(s.isReservedFor('jp.mine', city), isFalse);
        // Lychnion's file names too.
        final clash = CatalogItem.fromRecord(
          await cityRecord(key, id: 'jp.other', file: 'jp.new.sqlite'),
        );
        expect(s.isTaken(clash), isTrue);
      },
    );

    test(
      "replacing an added publisher's copy removes its other files",
      () async {
        final s = await store();
        await put('jp.x.big.bin');
        await s.markInstalled(
          CatalogItem.fromRecord(await cityRecord(key, file: 'jp.x.big.bin')),
        );
        s.reserve(['jp.x']);
        await put('jp.x.sqlite');
        await s.markInstalled(
          CatalogItem.fromRecord(
            await cityRecord(lychnionKey, publisher: 'lychnion'),
          ),
        );
        expect(File('${tmp.path}/packages/jp.x.big.bin').existsSync(), isFalse);
        expect(File('${tmp.path}/packages/jp.x.sqlite').existsSync(), isTrue);
      },
    );

    test("replacing a copy whose file differs only in case keeps Lychnion's "
        'file', () async {
      final s = await store();
      // On macOS and Windows these are the same file.
      await put('jp.x.SQLITE');
      await s.markInstalled(
        CatalogItem.fromRecord(await cityRecord(key, file: 'jp.x.SQLITE')),
      );
      s.reserve(['jp.x']);
      await put('jp.x.sqlite');
      await s.markInstalled(
        CatalogItem.fromRecord(
          await cityRecord(lychnionKey, publisher: 'lychnion'),
        ),
      );
      expect(File('${tmp.path}/packages/jp.x.sqlite').existsSync(), isTrue);
      expect(s.installed(ItemKind.package, 'jp.x'), isNotNull);
    });

    test(
      "removing a publisher keeps a file Lychnion's item now uses",
      () async {
        final s = await store();
        await put('jp.x.sqlite');
        // An older build let a city item use Lychnion's file name.
        await s.markInstalled(
          CatalogItem.fromRecord(
            await cityRecord(key, id: 'jp.y', file: 'jp.x.sqlite'),
          ),
        );
        s.reserve(['jp.x'], files: ['jp.x.sqlite']);
        await s.markInstalled(
          CatalogItem.fromRecord(
            await cityRecord(lychnionKey, publisher: 'lychnion'),
          ),
        );
        expect(await s.deleteFrom(city), 1);
        expect(File('${tmp.path}/packages/jp.x.sqlite').existsSync(), isTrue);
        expect(s.installed(ItemKind.package, 'jp.x'), isNotNull);
      },
    );

    test(
      'a broken cached catalog still reserves the bundled packages',
      () async {
        final s = await store();
        await s.cachedCatalog.create(recursive: true);
        await s.cachedCatalog.writeAsString('{not json');
        expect(await s.lychnionIds(), contains('jp.bousai.core'));
      },
    );
  });
}
