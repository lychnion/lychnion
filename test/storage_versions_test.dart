import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/downloader.dart';
import 'package:lychnion/download/followed_catalogs.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/ui/threads.dart';
import 'package:lychnion/util/versioned_file.dart';
import 'package:lychnion_format/lychnion_format.dart';

/// Saved files across app updates: format numbers, old files upgraded,
/// broken and newer files kept as copies, never a crash.
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-store');
    resetKeptAside();
  });
  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+w', tmp.path]);
    return tmp.delete(recursive: true);
  });

  /// Copies into [dir] fail while it is read-only (files in it stay
  /// writable).
  void readOnly(Directory dir, {bool on = true}) =>
      Process.runSync('chmod', [if (on) 'a-w' else 'u+w', dir.path]);

  File file(String name) => File('${tmp.path}/$name');

  group('readVersioned', () {
    Future<(Object?, int)?> read(File f) =>
        readVersioned(f, 1, (json, format) => (json, format));

    test('missing file: nothing, no copy', () async {
      expect(await read(file('a.json')), isNull);
      expect(keptAside.value, isEmpty);
    });

    test('format 0 and the current one are given to the caller', () async {
      file('a.json').writeAsStringSync('{"x":1}');
      expect((await read(file('a.json')))!.$2, 0);
      file('a.json').writeAsStringSync('{"format":1,"x":1}');
      expect((await read(file('a.json')))!.$2, 1);
      file('b.json').writeAsStringSync('[1,2]');
      expect((await read(file('b.json')))!.$2, 0);
    });

    test('corrupt JSON: kept as .broken', () async {
      file('a.json').writeAsStringSync('{"x":');
      expect(await read(file('a.json')), isNull);
      expect(file('a.json.broken').readAsStringSync(), '{"x":');
      expect(keptAside.value, ['a.json.broken']);
    });

    test('a format that is not a number counts as broken', () async {
      file('a.json').writeAsStringSync('{"format":"2"}');
      expect(await read(file('a.json')), isNull);
      expect(file('a.json.broken').existsSync(), isTrue);
    });

    test('newer format: kept as .newer, the file is left as it is', () async {
      file('a.json').writeAsStringSync('{"format":2,"x":1}');
      expect(await read(file('a.json')), isNull);
      expect(file('a.json.newer').readAsStringSync(), '{"format":2,"x":1}');
      expect(file('a.json').readAsStringSync(), '{"format":2,"x":1}');
      expect(keptAside.value, ['a.json.newer']);
    });

    test('a shape the caller cannot read counts as broken', () async {
      file('a.json').writeAsStringSync('[1]');
      final r = await readVersioned(file('a.json'), 1, (j, _) => j! as Map);
      expect(r, isNull);
      expect(file('a.json.broken').existsSync(), isTrue);
    });

    test('a failed copy: the file must not be replaced, retried', () async {
      file('a.json').writeAsStringSync('{"format":2}');
      readOnly(tmp);
      expect(await read(file('a.json')), isNull);
      expect(mayReplace(file('a.json')), isFalse);
      expect(keptAside.value, isEmpty);

      readOnly(tmp, on: false);
      expect(await read(file('a.json')), isNull);
      expect(file('a.json.newer').existsSync(), isTrue);
      expect(mayReplace(file('a.json')), isTrue);
    });

    test('two readers get the same single copy', () async {
      file('a.json').writeAsStringSync('{');
      final both = await Future.wait([
        keepAside(file('a.json'), 'broken'),
        keepAside(file('a.json'), 'broken'),
      ]);
      expect(both[0]!.path, both[1]!.path);
      expect(
        tmp.listSync().where((f) => f.path.endsWith('.broken')),
        hasLength(1),
      );
    });

    test('a copy from an earlier run is never written over', () async {
      file('a.json.newer').writeAsStringSync('first');
      file('a.json').writeAsStringSync('{"format":2}');
      expect(await read(file('a.json')), isNull);
      expect(file('a.json.newer').readAsStringSync(), 'first');
      final copies = tmp
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('a.json.') && n.endsWith('.newer'));
      expect(copies, hasLength(2));
      expect(keptAside.value.single, isNot('a.json.newer'));
    });

    test('sync reading does the same', () {
      file('a.json').writeAsStringSync('{"format":9}');
      expect(readVersionedSync(file('a.json'), 1, (j, _) => j), isNull);
      expect(file('a.json.newer').existsSync(), isTrue);
    });
  });

  group('settings.json', () {
    test('an old file is read and saved with a format number', () async {
      file('settings.json').writeAsStringSync(
        jsonEncode({'language': 'system', 'region': 'JP-28'}),
      );
      final s = AppSettings();
      await s.load(dir: tmp);
      expect(s.language, isNull);
      expect(s.region, 'JP-28');
      await s.setShowStats(true);
      final j = jsonDecode(file('settings.json').readAsStringSync()) as Map;
      expect(j['format'], AppSettings.format);
      expect(j['region'], 'JP-28');
    });

    test('the base from older shelter_* keys, saved as base_*', () async {
      file('settings.json').writeAsStringSync(
        '{"format":1,"shelter_url":"http://192.168.1.20:8642",'
        '"shelter_name":"Central school","shelter_key":"k1"}',
      );
      final s = AppSettings();
      await s.load(dir: tmp);
      expect(s.baseUrl, 'http://192.168.1.20:8642');
      expect(s.baseName, 'Central school');
      expect(s.baseKey, 'k1');
      await s.setShowStats(true);
      final j = jsonDecode(file('settings.json').readAsStringSync()) as Map;
      expect(j['base_url'], 'http://192.168.1.20:8642');
      expect(j['base_name'], 'Central school');
      expect(j['base_key'], 'k1');
      expect(j.containsKey('shelter_url'), isFalse);
    });

    // lychnion/lychnion#72: an older build saved any host.
    test(
      'a saved base on the internet is forgotten, with its name and keys',
      () async {
        file('settings.json').writeAsStringSync(
          jsonEncode({
            'format': 1,
            'base_url': 'http://203.0.113.5:8642',
            'base_name': 'Not a base',
            'base_key': 'k1',
            'base_signed_key': 'k1',
          }),
        );
        final s = AppSettings();
        await s.load(dir: tmp);
        expect(s.baseUrl, isNull);
        expect(s.baseName, isNull);
        expect(s.baseKey, isNull);
        expect(s.baseSignedKey, isNull);
        // Saved without it the next time anything is saved.
        await s.setShowStats(true);
        final j = jsonDecode(file('settings.json').readAsStringSync()) as Map;
        expect(j.containsKey('base_url'), isFalse);
      },
    );

    test('a base known to sign is kept for its key only', () async {
      final s = AppSettings();
      await s.load(dir: tmp);
      await s.setBase('http://192.168.1.20:8642', name: 'Hall', key: 'k1');
      await s.setBaseSigned('k1');
      final again = AppSettings();
      await again.load(dir: tmp);
      expect(again.baseSignedKey, 'k1');
      // Same key at a new address: still known to sign.
      await again.setBase('http://192.168.1.21:8642', name: 'Hall', key: 'k1');
      expect(again.baseSignedKey, 'k1');
      // Another key, or disconnected: forgotten.
      await again.setBase('http://192.168.1.21:8642', name: 'Hall', key: 'k2');
      expect(again.baseSignedKey, isNull);
      await again.setBaseSigned('k2');
      await again.setBase(null);
      expect(again.baseSignedKey, isNull);
      final j = jsonDecode(file('settings.json').readAsStringSync()) as Map;
      expect(j.containsKey('base_signed_key'), isFalse);
    });

    test('a late answer from the base before does not count', () async {
      final s = AppSettings();
      await s.load(dir: tmp);
      await s.setBase('http://192.168.1.20:8642', key: 'kA');
      // Switched to base B; then base A's answer arrives, signed.
      await s.setBase('http://192.168.1.30:8642', key: 'kB');
      await s.setBaseSigned('kA');
      expect(s.baseSignedKey, isNull);
      await s.setBaseSigned('kB');
      expect(s.baseSignedKey, 'kB');
      await s.setBaseSigned('kA');
      expect(s.baseSignedKey, 'kB');
    });

    test('a QR code that says the base signs is remembered at once', () async {
      final s = AppSettings();
      await s.load(dir: tmp);
      await s.setBase('http://192.168.1.20:8642', key: 'k1', signs: true);
      expect(s.baseSignedKey, 'k1');
      // Scanned again without the flag (an old printout): still known.
      await s.setBase('http://192.168.1.20:8642', key: 'k1');
      expect(s.baseSignedKey, 'k1');
      // Another key that signs: that key.
      await s.setBase('http://192.168.1.20:8642', key: 'k2', signs: true);
      expect(s.baseSignedKey, 'k2');
      // No key: nothing to check a signature with.
      await s.setBase('http://192.168.1.20:8642', signs: true);
      expect(s.baseSignedKey, isNull);
      // An old QR code: learnt from the first signed answer, as before.
      await s.setBase('http://192.168.1.20:8642', key: 'k3');
      expect(s.baseSignedKey, isNull);
    });

    test('a newer file: defaults, and a copy survives the next save', () async {
      const newer = '{"format":99,"region":"JP-30"}';
      file('settings.json').writeAsStringSync(newer);
      final s = AppSettings();
      await s.load(dir: tmp);
      expect(s.region, isNull);
      await s.setShowStats(true);
      expect(file('settings.json.newer').readAsStringSync(), newer);
    });

    test('newer and the copy fails: a save leaves the file', () async {
      const newer = '{"format":99,"region":"JP-30"}';
      file('settings.json').writeAsStringSync(newer);
      readOnly(tmp);
      final s = AppSettings();
      await s.load(dir: tmp);
      await s.setShowStats(true);
      expect(file('settings.json').readAsStringSync(), newer);
    });

    test('corrupt: defaults, kept as .broken', () async {
      file('settings.json').writeAsStringSync('{');
      final s = AppSettings();
      await s.load(dir: tmp);
      expect(s.showStats, isFalse);
      expect(file('settings.json.broken').existsSync(), isTrue);
    });
  });

  group('threads.json', () {
    test('a bare list (format 0) is read; saved as format 1', () async {
      file('threads.json').writeAsStringSync(
        jsonEncode([
          {
            'id': '1',
            'created': '2026-11-05T00:00:00Z',
            'entries': <Object?>[],
          },
        ]),
      );
      final t = ThreadStore();
      await t.load(dir: tmp);
      expect(t.threads.single.id, '1');
      await t.save();
      final j = jsonDecode(file('threads.json').readAsStringSync()) as Map;
      expect(j['format'], ThreadStore.format);
      expect(j['threads'], isList);
    });

    test('a save during the load waits for the copy', () async {
      const newer = '{"format":2,"threads":[]}';
      file('threads.json').writeAsStringSync(newer);
      final t = ThreadStore();
      final loading = t.load(dir: tmp);
      final saving = t.save();
      await Future.wait([loading, saving]);
      expect(file('threads.json.newer').readAsStringSync(), newer);
    });

    test('format 1 is read', () async {
      file('threads.json').writeAsStringSync(
        jsonEncode({
          'format': 1,
          'threads': [
            {
              'id': '2',
              'created': '2026-11-05T00:00:00Z',
              'entries': <Object?>[],
            },
          ],
        }),
      );
      final t = ThreadStore();
      await t.load(dir: tmp);
      expect(t.threads.single.id, '2');
    });

    test('corrupt or newer: empty, a copy is kept', () async {
      file('threads.json').writeAsStringSync('[{"id":');
      var t = ThreadStore();
      await t.load(dir: tmp);
      expect(t.threads, isEmpty);
      expect(file('threads.json.broken').existsSync(), isTrue);

      file('threads.json').writeAsStringSync('{"format":2,"threads":[]}');
      t = ThreadStore();
      await t.load(dir: tmp);
      expect(t.threads, isEmpty);
      expect(file('threads.json.newer').existsSync(), isTrue);
    });
  });

  group('facts.jsonl', () {
    final now = DateTime.utc(2026, 11, 18, 3);
    Fact fact(String value) => Fact(
      kind: FactKind.shelterStatus,
      subject: 'site-1',
      value: value,
      observedAt: now.subtract(const Duration(minutes: 10)),
      expiresAt: now.add(const Duration(hours: 2)),
      sourceType: SourceType.citizen,
      sourceName: '',
    );
    String line(Fact f) => jsonEncode({...f.toJson(), 'v_ok': true});

    test('an old file without a first line is read and upgraded', () async {
      file('facts.jsonl').writeAsStringSync('${line(fact('open'))}\n');
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      expect(s.all.single.value, 'open');
      final lines = file('facts.jsonl').readAsLinesSync();
      expect(jsonDecode(lines.first), {'format': FactStore.format});
      expect(lines, hasLength(2));
    });

    // #63: the app may stop after a base key was removed but before
    // facts.jsonl was written again.
    test('facts saved as verified whose key is no longer trusted are '
        'unconfirmed at start, and saved so', () async {
      final base = await FactSigner.generate();
      final signed = await base.sign(
        Fact(
          kind: FactKind.shelterStatus,
          subject: 'site-1',
          value: 'full',
          observedAt: now.subtract(const Duration(minutes: 10)),
          expiresAt: now.add(const Duration(hours: 2)),
          sourceType: SourceType.official,
        ),
      );
      file('facts.jsonl').writeAsStringSync(
        '{"format":1}\n${line(signed)}\n${line(fact('open'))}\n',
      );
      final s = FactStore(clock: () => now, trust: TrustList());
      await s.load(dir: tmp);
      final byValue = {for (final f in s.all) f.value: f.verified};
      expect(byValue, {'full': false, 'open': true});
      final saved = file('facts.jsonl')
          .readAsLinesSync()
          .skip(1)
          .map((l) => jsonDecode(l) as Map)
          .firstWhere((j) => j['value'] == 'full');
      expect(saved['v_ok'], isFalse);
    });

    test('a broken line is skipped, the others stay', () async {
      file('facts.jsonl').writeAsStringSync(
        '{"format":1}\n${line(fact('open'))}\n{"kind":\n${line(fact('full'))}\n',
      );
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      expect(s.all.map((f) => f.value).toSet(), {'open', 'full'});
      expect(file('facts.jsonl.broken').existsSync(), isTrue);
      // Written again without the broken line.
      expect(file('facts.jsonl').readAsLinesSync(), hasLength(3));
    });

    test('a line cut inside a character loses only that line', () async {
      final good = utf8.encode('{"format":1}\n${line(fact('開いている'))}\n');
      final cut = utf8.encode(line(fact('満員')));
      // The append stopped in the middle of a 3-byte character.
      final bytes = [...good, ...cut.sublist(0, cut.length - 6)];
      file('facts.jsonl').writeAsBytesSync(bytes.sublist(0, bytes.length - 1));
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      expect(s.all.single.value, '開いている');
    });

    test('a newer file is kept aside; new facts go into a new file', () async {
      const newer = '{"format":2}\n{"something":"new"}\n';
      file('facts.jsonl').writeAsStringSync(newer);
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      expect(s.all, isEmpty);
      expect(file('facts.jsonl.newer').readAsStringSync(), newer);
      await s.addAll([fact('open')]);
      final lines = file('facts.jsonl').readAsLinesSync();
      expect(jsonDecode(lines.first), {'format': 1});
      expect(lines, hasLength(2));
    });

    test('facts added at the same time are all kept', () async {
      file('facts.jsonl').writeAsStringSync('${line(fact('old'))}\n');
      final s = FactStore(clock: () => now);
      final loading = s.load(dir: tmp);
      await Future.wait([
        loading,
        s.addAll([fact('a')]),
        s.addAll([fact('b')]),
      ]);
      final again = FactStore(clock: () => now);
      await again.load(dir: tmp);
      expect(again.all.map((f) => f.value).toSet(), {'old', 'a', 'b'});
    });

    test('newer and the copy fails: the file is left as it is', () async {
      const newer = '{"format":2}\n{"something":"new"}\n';
      file('facts.jsonl').writeAsStringSync(newer);
      readOnly(tmp);
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      await s.addAll([fact('open')]);
      expect(file('facts.jsonl').readAsStringSync(), newer);
    });

    test('the first fact in a new file gets the first line', () async {
      final s = FactStore(clock: () => now);
      await s.load(dir: tmp);
      await s.addAll([fact('open')]);
      final again = FactStore(clock: () => now);
      await again.load(dir: tmp);
      expect(again.all.single.value, 'open');
      expect(file('facts.jsonl').readAsLinesSync(), hasLength(2));
    });
  });

  group('trusted_keys.json', () {
    test('format 0 is read and saved as format 1', () async {
      final base = await FactSigner.generate();
      final old = TrustList();
      await old.load(file('trusted_keys.json'));
      final id = (await old.add(base.publicKeyText, 'Base'))!;
      // Write the file as builds before format numbers did.
      final j = jsonDecode(file('trusted_keys.json').readAsStringSync()) as Map;
      file('trusted_keys.json').writeAsStringSync(jsonEncode(j['keys']));

      final t = TrustList();
      await t.load(file('trusted_keys.json'));
      expect(t.trusts(id), isTrue);
      await t.add(base.publicKeyText, 'Base 2');
      final saved =
          jsonDecode(file('trusted_keys.json').readAsStringSync()) as Map;
      expect(saved['format'], TrustList.format);
    });

    test('a key added while loading is saved', () async {
      final base = await FactSigner.generate();
      final t = TrustList();
      final loading = t.load(file('trusted_keys.json'));
      final id = await t.add(base.publicKeyText, 'Base');
      await loading;
      final again = TrustList();
      await again.load(file('trusted_keys.json'));
      expect(again.trusts(id!), isTrue);
    });

    test('a bad entry is skipped, not a crash', () async {
      final base = await FactSigner.generate();
      final t0 = TrustList();
      await t0.load(file('trusted_keys.json'));
      final id = (await t0.add(base.publicKeyText, 'Base'))!;
      final j = jsonDecode(file('trusted_keys.json').readAsStringSync()) as Map;
      (j['keys'] as Map)['bad'] = 'not a map';
      file('trusted_keys.json').writeAsStringSync(jsonEncode(j));
      final t = TrustList();
      await t.load(file('trusted_keys.json'));
      expect(t.trusts(id), isTrue);
      expect(t.trusts('bad'), isFalse);
    });

    // lychnion/lychnion#63: base keys are listed in Settings and can be
    // removed; the device's own key is not listed.
    test('the kind of a key and a removal are saved', () async {
      final base = await FactSigner.generate();
      final own = await FactSigner.generate();
      final t0 = TrustList();
      await t0.load(file('trusted_keys.json'));
      await t0.add(own.publicKeyText, 'Me', kind: TrustedKeyKind.own);
      final baseId = (await t0.add(base.publicKeyText, 'Hall'))!;

      final t1 = TrustList();
      await t1.load(file('trusted_keys.json'));
      expect(t1.keysOf(TrustedKeyKind.own).single.name, 'Me');
      expect(t1.keysOf(TrustedKeyKind.base).single.name, 'Hall');
      expect(await t1.remove(baseId), isTrue);
      expect(await t1.remove(baseId), isFalse);

      final t2 = TrustList();
      await t2.load(file('trusted_keys.json'));
      expect(t2.trustsKey(base.publicKeyText), isFalse);
      expect(t2.trustsKey(own.publicKeyText), isTrue);
    });

    test('an entry from an older app, without a kind, is a base key', () async {
      final base = await FactSigner.generate();
      final t0 = TrustList();
      await t0.load(file('trusted_keys.json'));
      await t0.add(base.publicKeyText, 'Hall');
      final j = jsonDecode(file('trusted_keys.json').readAsStringSync()) as Map;
      for (final e in (j['keys'] as Map).values) {
        (e as Map).remove('kind');
      }
      file('trusted_keys.json').writeAsStringSync(jsonEncode(j));
      final t = TrustList();
      await t.load(file('trusted_keys.json'));
      expect(t.keysOf(TrustedKeyKind.base).single.name, 'Hall');
    });

    test(
      'only the exact key is trusted, not one with the same short id',
      () async {
        final base = await FactSigner.generate();
        final t = TrustList();
        await t.load(file('trusted_keys.json'));
        await t.add(base.publicKeyText, 'Hall');
        // Same first 6 bytes (the key id), different rest.
        final bytes = base.publicKey.toList();
        bytes[31] ^= 1;
        final lookalike = base64Url.encode(bytes).replaceAll('=', '');
        expect(t.trustsKey(base.publicKeyText), isTrue);
        expect(t.trustsKey(lookalike), isFalse);
        expect(t.trustsKey(null), isFalse);
      },
    );

    test('a list instead of a map: no keys, a copy is kept', () async {
      file('trusted_keys.json').writeAsStringSync('[1,2]');
      final t = TrustList();
      await t.load(file('trusted_keys.json'));
      expect(t.names, isEmpty);
      expect(file('trusted_keys.json.broken').existsSync(), isTrue);
    });
  });

  group('signing_key', () {
    test('a good key is loaded again', () async {
      final a = await FactSigner.loadOrCreate(file('signing_key'));
      final b = await FactSigner.loadOrCreate(file('signing_key'));
      expect(b.publicKeyText, a.publicKeyText);
    });

    test('a broken key is kept as .broken and a new one made', () async {
      file('signing_key').writeAsStringSync('not base64!');
      final s = await FactSigner.loadOrCreate(file('signing_key'));
      expect(s.publicKeyText, isNotEmpty);
      expect(file('signing_key.broken').readAsStringSync(), 'not base64!');
      expect(file('signing_key').readAsStringSync(), isNot('not base64!'));
    });
  });

  group('download lists', () {
    test('publishers.json and catalogs.json from a newer build', () async {
      Directory('${tmp.path}/downloads').createSync();
      final p = File('${tmp.path}/downloads/publishers.json')
        ..writeAsStringSync('{"format":7,"publishers":[]}');
      final list = PublisherList(p);
      await list.load();
      expect(list.added, isEmpty);
      expect(File('${p.path}.newer').existsSync(), isTrue);

      final c = File('${tmp.path}/downloads/catalogs.json')
        ..writeAsStringSync('{"format":7,"catalogs":[]}');
      final followed = FollowedCatalogs(Directory('${tmp.path}/downloads'));
      await followed.load();
      expect(followed.all, isEmpty);
      expect(File('${c.path}.newer').existsSync(), isTrue);
    });

    test('an unreadable catalogs.json keeps the offline copies', () async {
      final cache = File('${tmp.path}/downloads/followed/x.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${tmp.path}/downloads/catalogs.json').writeAsStringSync('{');
      await FollowedCatalogs(Directory('${tmp.path}/downloads')).load();
      expect(cache.existsSync(), isTrue);
    });

    test(
      'downloads/settings.json: a failed copy blocks the first set',
      () async {
        final s = DownloadStore(tmp, trust: TrustedKeys(const {}));
        const newer = '{"format":5,"updates":"auto"}';
        final f = File('${tmp.path}/downloads/settings.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(newer);
        readOnly(f.parent);
        await expectLater(
          s.setKeepAll(true),
          throwsA(isA<FileSystemException>()),
        );
        expect(f.readAsStringSync(), newer);
      },
    );

    test('downloads/settings.json: old read, newer kept aside', () async {
      final s = DownloadStore(tmp, trust: TrustedKeys(const {}));
      final f = File('${tmp.path}/downloads/settings.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"wifi_only":false,"updates":"off"}');
      expect(s.mobileData, MobileData.always);
      expect(s.updateMode, UpdateMode.off);
      await s.setKeepAll(true);
      expect((jsonDecode(f.readAsStringSync()) as Map)['format'], 1);

      f.writeAsStringSync('{"format":5,"updates":"auto"}');
      expect(s.updateMode, UpdateMode.notify);
      await s.setKeepAll(true);
      expect(File('${f.path}.newer').readAsStringSync(), contains('"auto"'));
    });
  });

  group('install markers', () {
    late SimpleKeyPair key;
    late TrustedKeys trust;
    setUpAll(() async {
      key = await Ed25519().newKeyPair();
      trust = TrustedKeys({
        'lychnion': [await publicKeyOf(key)],
      });
    });

    final gguf = List<int>.generate(4000, (i) => i % 251);
    final sum = sha256.convert(gguf).toString();
    const id = 'gemma-4-e2b-q4_0';

    Future<CatalogItem> item({String? sha, String version = '1'}) async =>
        CatalogItem.fromRecord(
          await PackageRecord.sign({
            'format': 1,
            'id': id,
            'kind': 'model',
            'version': version,
            'publisher': 'lychnion',
            'title': {'ja': id, 'en': id},
            'role': 'chat',
            'files': [
              {'name': 'model.gguf', 'size': gguf.length, 'sha256': sha ?? sum},
            ],
            'signed': '2026-11-18T09:00:00+09:00',
          }, key),
        );

    File marker(DownloadStore s) =>
        File('${s.dirFor(ItemKind.model).path}/$id.installed.json');

    /// The Mac's marker from 5 Nov: unsigned, files as name → size.
    Future<DownloadStore> oldDevice() async {
      final s = DownloadStore(tmp, trust: trust);
      final dir = s.dirFor(ItemKind.model)..createSync(recursive: true);
      File('${dir.path}/model.gguf').writeAsBytesSync(gguf);
      marker(s).writeAsStringSync(
        jsonEncode({
          'id': id,
          'kind': 'model',
          'version': '1',
          'role': 'chat',
          'files': {'model.gguf': gguf.length},
        }),
      );
      await s.verifyInstalled();
      return s;
    }

    test('an unsigned marker is never trusted as it is', () async {
      final s = await oldDevice();
      expect(s.installed(ItemKind.model, id), isNull);
      expect(s.chatModelPath(), isNull);
      expect(s.oldMarkers().single.id, id);
    });

    test('upgraded from the signed catalog when the files match', () async {
      final s = await oldDevice();
      final r = await s.upgradeOldMarker(ItemKind.model, id, await item());
      expect(r, OldMarker.upgraded);
      expect(s.chatModelPath(), endsWith('/models/model.gguf'));
      final j = jsonDecode(marker(s).readAsStringSync()) as Map;
      expect(j['format'], DownloadStore.markerFormat);
      expect(j['record'], isMap);
      expect(s.oldMarkers(), isEmpty);
      // And after a restart.
      final again = DownloadStore(tmp, trust: trust);
      await again.verifyInstalled();
      expect(again.installed(ItemKind.model, id), isNotNull);
    });

    test('a hash mismatch: not installed, marker set aside', () async {
      final s = await oldDevice();
      final r = await s.upgradeOldMarker(
        ItemKind.model,
        id,
        await item(sha: 'f' * 64),
      );
      expect(r, OldMarker.retired);
      expect(s.installed(ItemKind.model, id), isNull);
      expect(marker(s).existsSync(), isFalse);
      expect(File('${marker(s).path}.old').existsSync(), isTrue);
      expect(s.oldMarkers(), isEmpty);
    });

    test('not in the catalog yet: not installed, checked again', () async {
      final s = await oldDevice();
      expect(
        await s.upgradeOldMarker(ItemKind.model, id, null),
        OldMarker.kept,
      );
      expect(s.installed(ItemKind.model, id), isNull);
      expect(s.oldMarkers().single.id, id);
    });

    test('a missing file: not installed, marker set aside', () async {
      final s = await oldDevice();
      File('${s.dirFor(ItemKind.model).path}/model.gguf').deleteSync();
      expect(
        await s.upgradeOldMarker(ItemKind.model, id, await item()),
        OldMarker.retired,
      );
    });

    test('a record from an untrusted publisher is not used', () async {
      final s = await oldDevice();
      final other = await Ed25519().newKeyPair();
      final stranger = CatalogItem.fromRecord(
        await PackageRecord.sign({
          'format': 1,
          'id': id,
          'kind': 'model',
          'version': '1',
          'publisher': 'lychnion',
          'files': [
            {'name': 'model.gguf', 'size': gguf.length, 'sha256': sum},
          ],
          'signed': '2026-11-18T09:00:00+09:00',
        }, other),
      );
      expect(
        await s.upgradeOldMarker(ItemKind.model, id, stranger),
        OldMarker.retired,
      );
      expect(s.installed(ItemKind.model, id), isNull);
    });

    test('stopped while hashing: nothing changes, checked again', () async {
      final s = await oldDevice();
      await expectLater(
        s.upgradeOldMarker(
          ItemKind.model,
          id,
          await item(),
          hash: (_) => throw DownloadCancelled(),
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(s.oldMarkers().single.id, id);
    });

    test('stopped after hashing: no marker is written', () async {
      final s = await oldDevice();
      final cancel = CancelToken();
      await expectLater(
        s.upgradeOldMarker(
          ItemKind.model,
          id,
          await item(),
          hash: (f) async {
            cancel.cancel();
            return sum;
          },
          cancel: cancel,
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(s.installed(ItemKind.model, id), isNull);
      expect(s.oldMarkers().single.id, id);
    });

    test('a corrupt marker is checked like an old one', () async {
      final s = await oldDevice();
      marker(s).writeAsStringSync('{"record":');
      expect(s.oldMarkers().single.id, id);
      expect(
        await s.upgradeOldMarker(ItemKind.model, id, await item()),
        OldMarker.upgraded,
      );
    });

    test('a format 1 marker (no format number) still counts', () async {
      final s = DownloadStore(tmp, trust: trust);
      final i = await item();
      final dir = s.dirFor(ItemKind.model)..createSync(recursive: true);
      File('${dir.path}/model.gguf').writeAsBytesSync(gguf);
      marker(s).writeAsStringSync(jsonEncode({'record': i.record!.json}));
      await s.verifyInstalled();
      expect(s.installed(ItemKind.model, id), isNotNull);
      expect(s.oldMarkers(), isEmpty);
    });

    test('a newer marker is left alone, and kept when replaced', () async {
      final s = DownloadStore(tmp, trust: trust);
      final i = await item();
      final dir = s.dirFor(ItemKind.model)..createSync(recursive: true);
      File('${dir.path}/model.gguf').writeAsBytesSync(gguf);
      final newer = jsonEncode({'format': 3, 'record': i.record!.json});
      marker(s).writeAsStringSync(newer);
      await s.verifyInstalled();
      expect(s.installed(ItemKind.model, id), isNull);
      expect(s.oldMarkers(), isEmpty);
      expect(await s.upgradeOldMarker(ItemKind.model, id, i), OldMarker.kept);
      expect(marker(s).readAsStringSync(), newer);

      await s.markInstalled(i);
      expect(File('${marker(s).path}.newer').readAsStringSync(), newer);
      expect(s.installed(ItemKind.model, id), isNotNull);
    });

    test('a newer marker still blocks older versions', () async {
      final s = DownloadStore(tmp, trust: trust);
      final v2 = await item(version: '2');
      s.dirFor(ItemKind.model).createSync(recursive: true);
      marker(
        s,
      ).writeAsStringSync(jsonEncode({'format': 3, 'record': v2.record!.json}));
      expect(s.recordedVersionOf(ItemKind.model, id), '2');
      await expectLater(
        s.markInstalled(await item()),
        throwsA(isA<OlderVersion>()),
      );
    });

    test('deleting an item also removes its old marker', () async {
      final s = await oldDevice();
      await s.upgradeOldMarker(ItemKind.model, id, await item(sha: 'f' * 64));
      await s.delete(await item());
      expect(File('${marker(s).path}.old').existsSync(), isFalse);
    });
  });
}
