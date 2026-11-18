// Publishing on this computer (docs/distribution.md, step 4b).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/publish/local_publisher.dart';
import 'package:lychnion/publish/publish.dart';
import 'package:lychnion/shelter/shelter_library.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:sqlite3/sqlite3.dart';

/// A minimal package file: a meta table as build_package.py writes it.
File packageFile(Directory dir, String id, String version) {
  final f = File('${dir.path}/src/$id.sqlite')..parent.createSync();
  if (f.existsSync()) f.deleteSync();
  final db = sqlite3.open(f.path);
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  final meta = {
    'id': id,
    'version': version,
    'title': '市の防災',
    'name': jsonEncode({'ja': '神戸市の防災', 'en': 'Kobe: be prepared'}),
    'notice': jsonEncode({
      'ja': ['緊急時は119番'],
      'en': ['In an emergency call 119'],
    }),
  };
  for (final e in meta.entries) {
    db.execute('INSERT INTO meta VALUES(?, ?)', [e.key, e.value]);
  }
  db.close();
  return f;
}

void main() {
  late Directory tmp, pubDir;
  late DownloadStore store;
  late LocalPublisher me;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-publish');
    pubDir = Directory('${tmp.path}/publisher');
    store = DownloadStore(
      Directory('${tmp.path}/app'),
      publishers: PublisherList(File('${tmp.path}/app/publishers.json')),
    );
    me = await LocalPublisher.create(
      pubDir,
      name: 'jp.city.kobe',
      title: '神戸市',
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  PublishRequest form(File f) => requestFromPackage(f)!;

  Future<PackageRecord> go(PublishRequest r) =>
      publish(r, publisher: me, store: store, publisherDir: pubDir);

  group('LocalPublisher', () {
    test('is saved, read again, and never replaced', () async {
      final again = (await LocalPublisher.load(pubDir))!;
      expect(again.name, 'jp.city.kobe');
      expect(again.title, '神戸市');
      expect(again.publicKey, me.publicKey);
      expect(
        () => LocalPublisher.create(pubDir, name: 'jp.city.other'),
        throwsArgumentError,
      );
      if (!Platform.isWindows) {
        final mode = LocalPublisher.fileIn(pubDir).statSync().modeString();
        expect(mode, 'rw-------');
      }
    });

    test('a built-in or bad name cannot be used', () async {
      final d = Directory('${tmp.path}/other');
      for (final n in ['lychnion', 'Kobe City', '']) {
        expect(
          () => LocalPublisher.create(d, name: n),
          throwsArgumentError,
          reason: n,
        );
      }
    });

    test('its link is what phones scan', () {
      final l = PublisherLink.fromUri(me.link.toUri())!;
      expect(l.name, 'jp.city.kobe');
      expect(l.key, me.publicKey);
    });
  });

  group('publish', () {
    test('a package is prefilled from its file, signed, installed and '
        'passed on by the base', () async {
      final f = packageFile(tmp, 'jp.kobe.bousai', '2026.11.1');
      final req = form(f);
      expect(req.id, 'jp.kobe.bousai');
      expect(req.version, '2026.11.1');
      expect(req.titles['en'], 'Kobe: be prepared');
      expect(req.notice['ja'], ['緊急時は119番']);

      final r = await go(req);
      expect(r.publisher, 'jp.city.kobe');
      expect(me.link.keyId, r.keyId);
      expect(r.files.single.size, f.lengthSync());
      expect(store.installed(ItemKind.package, 'jp.kobe.bousai'), isNotNull);
      expect(
        recordFile(pubDir, 'jp.kobe.bousai', '2026.11.1').existsSync(),
        isTrue,
      );

      // The base's catalog carries the record unchanged, and the file.
      final lib = ShelterLibrary(store);
      final records = lib.catalog()['records']! as List;
      expect(records.single, r.json);
      expect(lib.blob(r.files.single.sha256)!.existsSync(), isTrue);

      // A phone that added the city accepts it; one that did not, not.
      final phone = builtInPublishers.plus({
        'jp.city.kobe': [me.publicKey],
      });
      final json = jsonEncode(lib.catalog());
      expect((await Catalog.parse(json, trust: phone)).items, hasLength(1));
      expect((await Catalog.parse(json)).items, isEmpty);
    });

    test('versions only go up', () async {
      await go(form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.2')));
      for (final v in ['2026.11.2', '2026.11.1']) {
        await expectLater(
          go(form(packageFile(tmp, 'jp.kobe.bousai', v))),
          throwsA(isA<PublishError>().having((e) => e.code, 'code', 'older')),
          reason: v,
        );
      }
      final newer = await go(
        form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.3')),
      );
      expect(newer.version, '2026.11.3');
      expect(
        store.installed(ItemKind.package, 'jp.kobe.bousai')!.version,
        '2026.11.3',
      );
    });

    test('the form must match the package file', () async {
      final f = packageFile(tmp, 'jp.kobe.bousai', '2026.11.1');
      final req = form(f);
      PublishRequest edit({String? version, String? id, List<File>? files}) =>
          PublishRequest(
            kind: req.kind,
            id: id ?? req.id,
            version: version ?? req.version,
            titles: req.titles,
            files: files ?? req.files,
          );
      Future<void> refused(PublishRequest r, String code) => expectLater(
        go(r),
        throwsA(isA<PublishError>().having((e) => e.code, 'code', code)),
      );
      await refused(edit(version: '2026.11.9'), 'meta');
      await refused(edit(version: 'new'), 'version');
      await refused(edit(id: '../x'), 'id');
      await refused(edit(id: 'jp.other'), 'files');
      await refused(edit(files: []), 'files');
      expect(store.installed(ItemKind.package, 'jp.kobe.bousai'), isNull);
    });

    test("an id installed from another publisher is not taken over", () async {
      // Lychnion's package of the same id, installed here before.
      final other = await LocalPublisher.create(
        Directory('${tmp.path}/lychnion-like'),
        name: 'jp.club.x',
      );
      await publish(
        form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.1')),
        publisher: other,
        store: store,
        publisherDir: Directory('${tmp.path}/lychnion-like'),
      );
      await expectLater(
        go(form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.5'))),
        throwsA(isA<PublishError>().having((e) => e.code, 'code', 'taken')),
      );
    });

    test('a map area: several files named after the id', () async {
      final files = [
        for (final ext in ['pmtiles', 'sites.sqlite'])
          File('${tmp.path}/src/jp.map.kobe.$ext')
            ..createSync(recursive: true)
            ..writeAsStringSync('map $ext'),
      ];
      final r = await go(
        PublishRequest(
          kind: ItemKind.map,
          id: 'jp.map.kobe',
          version: '1',
          titles: const {'ja': '地図：神戸', 'en': 'Map: Kobe'},
          licence: '© OpenStreetMap contributors (ODbL)',
          files: files,
        ),
      );
      expect(r.files.map((f) => f.name), [
        'jp.map.kobe.pmtiles',
        'jp.map.kobe.sites.sqlite',
      ]);
      expect(store.installed(ItemKind.map, 'jp.map.kobe'), isNotNull);
    });
  });

  group('review fixes', () {
    test('a refused publish leaves no copies behind', () async {
      final other = Directory('${tmp.path}/other');
      final them = await LocalPublisher.create(other, name: 'jp.club.x');
      await publish(
        form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.1')),
        publisher: them,
        store: store,
        publisherDir: other,
      );
      await expectLater(
        go(form(packageFile(tmp, 'jp.kobe.bousai', '2026.11.5'))),
        throwsA(isA<PublishError>().having((e) => e.code, 'code', 'taken')),
      );
      final left = store
          .dirFor(ItemKind.package)
          .listSync()
          .where((f) => f.path.endsWith('.publishing'));
      expect(left, isEmpty);
      // Nothing of the refused version was kept as signed.
      expect(lastPublished(pubDir, 'jp.kobe.bousai'), isNull);
    });

    test(
      "a file name of another publisher's item is not overwritten",
      () async {
        final other = Directory('${tmp.path}/other');
        final them = await LocalPublisher.create(other, name: 'jp.club.x');
        final theirs = File('${tmp.path}/src/jp.a.b.sqlite')
          ..createSync(recursive: true)
          ..writeAsStringSync('theirs');
        await publish(
          PublishRequest(
            kind: ItemKind.map,
            id: 'jp.a.b',
            version: '1',
            titles: const {'en': 'Theirs'},
            files: [theirs],
          ),
          publisher: them,
          store: store,
          publisherDir: other,
        );
        final mine = File('${tmp.path}/src2/jp.a.b.sqlite')
          ..createSync(recursive: true)
          ..writeAsStringSync('mine!!');
        await expectLater(
          go(
            PublishRequest(
              kind: ItemKind.map,
              id: 'jp.a',
              version: '1',
              titles: const {'en': 'Mine'},
              files: [mine],
            ),
          ),
          throwsA(isA<PublishError>().having((e) => e.code, 'code', 'taken')),
        );
        expect(
          File(
            '${store.dirFor(ItemKind.map).path}/jp.a.b.sqlite',
          ).readAsStringSync(),
          'theirs',
        );
      },
    );

    test('a file name with a space is refused as a file problem', () async {
      final f = File('${tmp.path}/src/jp.map.x y.pmtiles')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      await expectLater(
        go(
          PublishRequest(
            kind: ItemKind.map,
            id: 'jp.map.x',
            version: '1',
            titles: const {'en': 'X'},
            files: [f],
          ),
        ),
        throwsA(isA<PublishError>().having((e) => e.code, 'code', 'files')),
      );
    });

    test('the key file is private and no temporary copy is left', () {
      expect(
        File('${LocalPublisher.fileIn(pubDir).path}.tmp').existsSync(),
        isFalse,
      );
      if (!Platform.isWindows) {
        expect(pubDir.statSync().modeString(), 'rwx------');
      }
    });

    test('an unreadable key file is never replaced', () async {
      LocalPublisher.fileIn(pubDir).writeAsStringSync('{broken');
      expect(await LocalPublisher.load(pubDir), isNull);
      expect(LocalPublisher.existsIn(pubDir), isTrue);
      expect(
        () => LocalPublisher.create(pubDir, name: 'jp.city.kobe'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'm', 'exists')),
      );
    });
  });
}
