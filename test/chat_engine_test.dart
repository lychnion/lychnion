import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/llm/engines.dart';

import 'download_test.dart' show signedRecord;

/// Which chat model (and so which engine) each platform uses.
void main() {
  late SimpleKeyPair key;
  late Installed gguf, liteRt, embed;

  setUpAll(() async {
    key = await Ed25519().newKeyPair();
    gguf = Installed(
      await signedRecord(key, 'model.e2b-gguf', 'model', [
        ('e2b.gguf', 1, 'a' * 64),
      ], role: 'chat'),
    );
    liteRt = Installed(
      await signedRecord(
        key,
        'model.e2b-litertlm',
        'model',
        [('e2b.litertlm', 1, 'b' * 64)],
        role: 'chat',
        platforms: ['android'],
      ),
    );
    embed = Installed(
      await signedRecord(key, 'model.embed', 'model', [
        ('embed.gguf', 1, 'c' * 64),
      ], role: 'embed'),
    );
  });

  test('the record carries the platforms, empty means all', () {
    expect(liteRt.record.platforms, ['android']);
    expect(gguf.record.platforms, isEmpty);
    expect(liteRt.runsOn('android'), isTrue);
    expect(liteRt.runsOn('ios'), isFalse);
    expect(gguf.runsOn('macos'), isTrue);
    final item = CatalogItem.fromRecord(liteRt.record);
    expect(item.platforms, ['android']);
    expect(item.runsOn('android'), isTrue);
    expect(item.runsOn('windows'), isFalse);
  });

  test('the chat file is the .litertlm, else the .gguf', () {
    expect(liteRt.chatFile, 'e2b.litertlm');
    expect(gguf.chatFile, 'e2b.gguf');
  });

  test('Android prefers the model made for it when none is picked', () {
    final all = [gguf, embed, liteRt];
    expect(pickChat(all, want: null, os: 'android', liteRt: true), liteRt);
    expect(pickChat(all, want: 'gone', os: 'android', liteRt: true), liteRt);
  });

  test('a picked model wins', () {
    final all = [gguf, liteRt];
    expect(pickChat(all, want: gguf.id, os: 'android', liteRt: true), gguf);
  });

  test('other platforms never use an Android-only model', () {
    for (final os in ['ios', 'macos', 'windows', 'linux']) {
      expect(
        pickChat([liteRt, gguf], want: liteRt.id, os: os, liteRt: true),
        gguf,
      );
      expect(pickChat([liteRt], want: null, os: os, liteRt: true), isNull);
    }
  });

  test('below Android 11 the LiteRT-LM model is never used', () {
    expect(
      pickChat([liteRt, gguf], want: liteRt.id, os: 'android', liteRt: false),
      gguf,
    );
    expect(
      pickChat([liteRt], want: null, os: 'android', liteRt: false),
      isNull,
    );
  });

  test('a model that failed to load is skipped: the GGUF takes over', () {
    expect(
      pickChat(
        [liteRt, gguf],
        want: null,
        os: 'android',
        liteRt: true,
        skip: {liteRt.id},
      ),
      gguf,
    );
  });

  test('Downloads lists a model only where it runs', () {
    final lite = CatalogItem.fromRecord(liteRt.record);
    final plain = CatalogItem.fromRecord(gguf.record);
    // Android 11 or newer.
    expect(lite.runsHereOn('android', liteRt: true), isTrue);
    // Android 9 and 10: LiteRT-LM does not run.
    expect(lite.runsHereOn('android', liteRt: false), isFalse);
    expect(plain.runsHereOn('android', liteRt: false), isTrue);
    // iPhones and computers.
    for (final os in ['ios', 'macos', 'windows', 'linux']) {
      expect(lite.runsHereOn(os, liteRt: false), isFalse);
      expect(plain.runsHereOn(os, liteRt: false), isTrue);
    }
    expect(lite.needsLiteRt, isTrue);
    expect(plain.needsLiteRt, isFalse);
  });

  test('LiteRT-LM does not run off Android (tests run on a computer)', () {
    expect(Engines.liteRt, isFalse);
    expect(Engines.androidSdk, isNull);
  });

  test('isLiteRtFile', () {
    expect(isLiteRtFile('a.litertlm'), isTrue);
    expect(isLiteRtFile('A.LITERTLM'), isTrue);
    expect(isLiteRtFile('a.gguf'), isFalse);
  });

  test('no chat model: null', () {
    expect(pickChat([embed], want: null, os: 'android', liteRt: true), isNull);
  });
}
