// The phone's checks on a base (lychnion/lychnion#24): a key that does
// not match the QR code is refused, a matching one is trusted, and a base
// that fails leaves the answer to the phone.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_checks.dart';
import 'package:lychnion/base/base_client.dart';
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
  Future<GroundedAnswer> ask(String question) async {
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
        BaseKeyCheck.trusted: (true, 'base_key_trusted'),
      },
    );
  });

  group('the base key', () {
    test('without a QR code nothing is pinned', () async {
      final r = await checkBaseKey({'key': base.publicKeyText}, pinned: null);
      expect(r, BaseKeyCheck.notPinned);
    });

    test('another key, no key or not a text is refused', () async {
      final other = (await FactSigner.generate()).publicKeyText;
      final trust = TrustList();
      final facts = FactStore(clock: () => now, trust: trust);
      for (final info in [
        {'key': other},
        <String, dynamic>{},
        {'key': 42},
      ]) {
        final r = await checkBaseKey(
          info,
          pinned: base.publicKeyText,
          facts: facts,
        );
        expect(r, BaseKeyCheck.mismatch, reason: '$info');
      }
      // Nothing was trusted on the way.
      expect(trust.names, isEmpty);
    });

    test(
      'the QR code key is trusted, and earlier facts are checked again',
      () async {
        final trust = TrustList();
        final facts = FactStore(clock: () => now, trust: trust);
        // Pulled before the QR code was scanned: not verified yet.
        await facts.addAll([await base.sign(status())]);
        expect(facts.all.single.verified, isFalse);

        final r = await checkBaseKey(
          {'key': base.publicKeyText},
          pinned: base.publicKeyText,
          facts: facts,
          name: 'Hall',
        );
        expect(r, BaseKeyCheck.trusted);
        expect(trust.names, ['Hall']);
        expect(facts.all.single.verified, isTrue);
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
          unchecked: true,
        );
        expect(a!.text, '高い所へ [1]。');
        expect(a.answeredBy, 'Hall');
        expect(a.baseUnchecked, isTrue);
      },
    );

    test('an error or a timeout leaves the answer to the phone', () async {
      for (final e in [
        TimeoutException('slow'),
        const HttpException('base: 500'),
        const FormatException('not this protocol'),
      ]) {
        final errors = <Object>[];
        final a = await answerFromBase(
          _FakeBase(error: e),
          '津波は？',
          unchecked: false,
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
      expect(await answerFromBase(c, '津波は？', unchecked: false), isNull);
    });
  });
}
