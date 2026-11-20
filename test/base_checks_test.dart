// The phone's checks on a base (lychnion/lychnion#24): a key that does
// not match the link is refused, a matching one connects but is trusted
// for facts only after its code was compared (#63), and a base that fails
// leaves the answer to the phone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/answer_signing.dart';
import 'package:lychnion/base/base_checks.dart';
import 'package:lychnion/base/base_client.dart';
import 'package:lychnion/facts/compact_codec.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';

/// A base that answers with [reply], or throws [error].
class _FakeBase extends BaseClient {
  _FakeBase({this.reply, this.error}) : super('http://192.0.2.1:8642') {
    name = 'Hall';
  }
  final String? reply;
  final Exception? error;

  @override
  Future<GroundedAnswer> ask(
    String question, {
    String? pinnedKey,
    bool requireSignature = false,
  }) async {
    if (error case final e?) throw e;
    return GroundedAnswer(question)..text = reply!;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 19, 6);
  late FactSigner base;

  setUpAll(() async => base = await FactSigner.generate());

  Fact status() => Fact(
    kind: FactKind.shelterStatus,
    subject: '34.73,135.34',
    value: 'full',
    observedAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(hours: 3)),
    sourceType: SourceType.official,
  );

  test('only a mismatch keeps the phone from connecting', () {
    expect(
      {for (final c in BaseKeyCheck.values) c: (c.connects, c.logEvent)},
      {
        BaseKeyCheck.notPinned: (true, 'base_key_not_pinned'),
        BaseKeyCheck.mismatch: (false, 'base_key_mismatch'),
        BaseKeyCheck.pinned: (true, 'base_key_pinned'),
        BaseKeyCheck.trusted: (true, 'base_key_trusted'),
      },
    );
  });

  group('the base key', () {
    test('without a link key nothing is pinned', () {
      final r = checkBaseKey({'key': base.publicKeyText}, pinned: null);
      expect(r, BaseKeyCheck.notPinned);
    });

    test('another key, no key or not a text is refused', () async {
      final other = (await FactSigner.generate()).publicKeyText;
      final trust = TrustList();
      for (final info in [
        {'key': other},
        <String, dynamic>{},
        {'key': 42},
      ]) {
        final r = checkBaseKey(info, pinned: base.publicKeyText, trust: trust);
        expect(r, BaseKeyCheck.mismatch, reason: '$info');
      }
      // Nothing was trusted on the way.
      expect(trust.names, isEmpty);
    });

    // lychnion/lychnion#63: a web page can open the same link as the QR
    // code, so the link's key alone gives no fact trust.
    test('a link key connects, but its facts stay unverified', () async {
      final trust = TrustList();
      final facts = FactStore(clock: () => now, trust: trust);
      await facts.addAll([await base.sign(status())]);

      final r = checkBaseKey(
        {'key': base.publicKeyText},
        pinned: base.publicKeyText,
        trust: trust,
      );
      expect(r, BaseKeyCheck.pinned);
      expect(r.connects, isTrue);
      expect(trust.names, isEmpty);
      expect(facts.all.single.verified, isFalse);
    });

    test('after the code is compared the key is trusted, and earlier facts '
        'are checked again', () async {
      final trust = TrustList();
      final facts = FactStore(clock: () => now, trust: trust);
      // Pulled before the code was compared: not verified yet.
      await facts.addAll([await base.sign(status())]);
      expect(facts.all.single.verified, isFalse);

      expect(
        await trustBaseKey(base.publicKeyText, name: 'Hall', facts: facts),
        isTrue,
      );
      expect(trust.names, ['Hall']);
      expect(trust.keysOf(TrustedKeyKind.base).single.name, 'Hall');
      expect(facts.all.single.verified, isTrue);
      expect(
        checkBaseKey(
          {'key': base.publicKeyText},
          pinned: base.publicKeyText,
          trust: trust,
        ),
        BaseKeyCheck.trusted,
      );
    });

    test('a malformed key is not trusted', () async {
      final facts = FactStore(clock: () => now, trust: TrustList());
      expect(
        await trustBaseKey('not-a-key', name: 'Hall', facts: facts),
        isFalse,
      );
      expect(facts.trust!.names, isEmpty);
    });

    test('a removed base key makes its facts unconfirmed again', () async {
      final trust = TrustList();
      final facts = FactStore(clock: () => now, trust: trust);
      final own = await FactSigner.generate();
      await trust.add(
        own.publicKeyText,
        'This computer',
        kind: TrustedKeyKind.own,
      );
      await trustBaseKey(base.publicKeyText, name: 'Hall', facts: facts);
      await facts.addAll([
        await base.sign(status()),
        await own.sign(
          Fact(
            kind: FactKind.shelterStatus,
            subject: '34.70,135.30',
            value: 'open',
            observedAt: now.subtract(const Duration(minutes: 1)),
            expiresAt: now.add(const Duration(hours: 3)),
            sourceType: SourceType.official,
          ),
        ),
      ]);
      expect(facts.all.every((f) => f.verified), isTrue);

      final id = trust.keysOf(TrustedKeyKind.base).single.id;
      await forgetBaseKey(id, name: 'Hall', facts: facts);

      expect(trust.trustsKey(base.publicKeyText), isFalse);
      // Only the own key is left, and it is not listed as a base.
      expect(trust.keysOf(TrustedKeyKind.base), isEmpty);
      expect(trust.trustsKey(own.publicKeyText), isTrue);
      final byValue = {for (final f in facts.all) f.value: f.verified};
      expect(byValue, {'full': false, 'open': true});
    });

    test('radio facts of a removed base are unconfirmed again', () async {
      final trust = TrustList();
      final facts = FactStore(clock: () => now, trust: trust);
      await trustBaseKey(base.publicKeyText, name: 'Hall', facts: facts);
      final codec = CompactCodec(['site-a']);
      final messages = await base.packSigned(codec, [
        Fact(
          kind: FactKind.shelterStatus,
          subject: 'site-a',
          value: 'full',
          observedAt: now.subtract(const Duration(minutes: 5)),
          expiresAt: now.add(const Duration(hours: 3)),
          sourceType: SourceType.official,
        ),
      ]);
      final unpacked = await trust.unpackSigned(codec, messages.single);
      await facts.addAll(unpacked, checked: true);
      expect(facts.all.single.verified, isTrue);
      expect(facts.all.single.keyId, isNull);

      final id = trust.keysOf(TrustedKeyKind.base).single.id;
      await forgetBaseKey(id, name: 'Hall', facts: facts);
      expect(facts.all.single.verified, isFalse);
    });

    test(
      'a key with the same short id does not replace a trusted one',
      () async {
        final trust = TrustList();
        await trust.add(base.publicKeyText, 'Me', kind: TrustedKeyKind.own);
        final bytes = base.publicKey.toList();
        bytes[31] ^= 1;
        final lookalike = base64Url.encode(bytes).replaceAll('=', '');
        expect(await trust.add(lookalike, 'Hall'), isNull);
        expect(trust.keysOf(TrustedKeyKind.own).single.name, 'Me');
        expect(trust.keysOf(TrustedKeyKind.base), isEmpty);
        // The same key may be added again (a new name).
        expect(
          await trust.add(base.publicKeyText, 'Me 2', kind: TrustedKeyKind.own),
          isNotNull,
        );
      },
    );
  });

  group('answers from the base', () {
    test(
      'an answer carries the base name and whether it was checked',
      () async {
        final a = await answerFromBase(
          _FakeBase(reply: '高い所へ [1]。'),
          '津波は？',
          pinnedKey: null,
        );
        expect(a!.text, '高い所へ [1]。');
        expect(a.answeredBy, 'Hall');
        expect(a.baseUnchecked, isTrue);
      },
    );

    test('with a pinned key the answer is checked', () async {
      final a = await answerFromBase(
        _FakeBase(reply: '高い所へ [1]。'),
        '津波は？',
        pinnedKey: base.publicKeyText,
      );
      expect(a!.baseUnchecked, isFalse);
    });

    // #63: a pinned key from a link only proves it is the computer the
    // link named; until its code is compared the answer says so.
    test('a pinned key whose code was not compared stays unchecked', () async {
      final a = await answerFromBase(
        _FakeBase(reply: '高い所へ [1]。'),
        '津波は？',
        pinnedKey: base.publicKeyText,
        keyTrusted: false,
      );
      expect(a!.baseUnchecked, isTrue);
    });

    test('an error or a timeout leaves the answer to the phone', () async {
      for (final e in [
        TimeoutException('slow'),
        const HttpException('base: 500'),
        const FormatException('not this protocol'),
        const BadAnswerSignature('bad signature'),
      ]) {
        final errors = <Object>[];
        final a = await answerFromBase(
          _FakeBase(error: e),
          '津波は？',
          pinnedKey: base.publicKeyText,
          onError: errors.add,
        );
        expect(a, isNull, reason: '$e');
        expect(errors, [e]);
      }
    });

    test('a base that is gone leaves the answer to the phone', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      final c = BaseClient('http://127.0.0.1:$port');
      addTearDown(c.close);
      expect(
        await answerFromBase(c, '津波は？', pinnedKey: base.publicKeyText),
        isNull,
      );
    });
  });
}
