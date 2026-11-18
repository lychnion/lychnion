// A catalog from a base, a phone sharing nearby or a mirror can be
// anything: random and cut-off input never gives an item that was not
// signed as it is.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late TrustedKeys trust;
  late String text;
  late PackageRecord record;
  final from = Uri.parse('http://192.168.1.20:8642/catalog.json');

  setUpAll(() async {
    final key = await Ed25519().newKeyPair();
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
    record = await PackageRecord.sign({
      'format': 1,
      'id': 'jp.test.package',
      'kind': 'package',
      'version': '2026.11.1',
      'publisher': 'lychnion',
      'title': {'ja': 'テスト', 'en': 'Test'},
      'files': [
        {'name': 'jp.test.package.sqlite', 'size': 3, 'sha256': 'a' * 64},
      ],
      'signed': '2026-11-18T09:00:00+09:00',
    }, key);
    text = jsonEncode({
      'format': 2,
      'records': [record.json],
      'urls': {'a' * 64: 'blobs/sha256/${'a' * 64}'},
      'mirrors': ['http://192.168.1.21:8642/'],
    });
  });

  /// Parses [s]; null when it is refused as a whole.
  Future<Catalog?> parse(String s) async {
    try {
      return await Catalog.parse(s, fetchedFrom: from, trust: trust);
    } on Object {
      return null;
    }
  }

  /// Every item that was accepted is the signed record, unchanged.
  void onlySigned(Catalog? c) {
    for (final i in c?.items ?? const <CatalogItem>[]) {
      expect(i.id, record.id);
      expect(i.version, record.version);
      expect([for (final f in i.files) f.sha256], ['a' * 64]);
      expect([for (final f in i.files) f.name], ['jp.test.package.sqlite']);
      for (final f in i.files) {
        for (final u in c!.urlsOf(f)) {
          expect(u.scheme, anyOf('http', 'https'));
        }
      }
    }
  }

  test('the catalog itself parses', () async {
    final c = await parse(text);
    expect(c!.items.single.id, record.id);
  });

  test('cut off at every character', () async {
    for (var n = 0; n < text.length; n++) {
      onlySigned(await parse(text.substring(0, n)));
    }
  });

  test('random bytes', () async {
    final rnd = Random(1);
    for (var i = 0; i < 300; i++) {
      final s = utf8.decode([
        for (var n = rnd.nextInt(200); n > 0; n--) rnd.nextInt(256),
      ], allowMalformed: true);
      onlySigned(await parse(s));
    }
  });

  test('random changes to the JSON', () async {
    final rnd = Random(2);
    final odd = <Object?>[
      null,
      0,
      -1,
      '',
      'javascript:alert(1)',
      'file:///etc/passwd',
      '../../x',
      'b' * 64,
      true,
      <Object?>[],
      <String, Object?>{},
    ];
    void mutate(Object? o) {
      if (o is Map && o.isNotEmpty) {
        final k = o.keys.elementAt(rnd.nextInt(o.length));
        switch (rnd.nextInt(3)) {
          case 0:
            o[k] = odd[rnd.nextInt(odd.length)];
          case 1:
            o.remove(k);
          default:
            mutate(o[k]);
        }
      } else if (o is List && o.isNotEmpty) {
        final i = rnd.nextInt(o.length);
        if (rnd.nextBool()) {
          o[i] = odd[rnd.nextInt(odd.length)];
        } else {
          mutate(o[i]);
        }
      }
    }

    var refused = 0;
    for (var i = 0; i < 400; i++) {
      final j = jsonDecode(text);
      for (var n = 1 + rnd.nextInt(3); n > 0; n--) {
        mutate(j);
      }
      final c = await parse(jsonEncode(j));
      if (c == null || c.items.isEmpty) refused++;
      onlySigned(c);
    }
    expect(refused, greaterThan(0));
  });
}
