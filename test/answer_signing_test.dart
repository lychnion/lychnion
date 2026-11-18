// Signed answers from a base (lychnion/lychnion#36): a phone with the
// base's QR key takes only answers signed by that key, for the question
// it asked just now. Something in between on the Wi-Fi is played by a
// small HTTP server that passes requests on to a real base.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/answer_signing.dart';
import 'package:lychnion/base/base_checks.dart';
import 'package:lychnion/base/base_client.dart';
import 'package:lychnion/base/base_server.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';

import 'support/fake_llm.dart';

/// What a base sent: the body bytes and its signature header.
typedef _Sent = ({List<int> body, String? signature});

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  late FactSigner signer, other;

  setUpAll(() async {
    signer = await FactSigner.generate();
    other = await FactSigner.generate();
  });

  group('checkAnswerSignature', () {
    final body = utf8.encode('{"text":"高い所へ"}');
    const nonce = 'AAAAAAAAAAAAAAAAAAAAAA';
    final request = utf8.encode('{"question":"津波は？","nonce":"$nonce"}');

    Future<String> sign(
      FactSigner by, {
      String n = nonce,
      List<int>? r,
      List<int>? b,
    }) => signAnswer(by, nonce: n, request: r ?? request, body: b ?? body);

    Future<AnswerSignature> check(String? header, {List<int>? b}) =>
        checkAnswerSignature(
          header: header,
          nonce: nonce,
          request: request,
          body: b ?? body,
          pinnedKey: signer.publicKeyText,
        );

    test('a signature by the pinned key over this answer is valid', () async {
      expect(await check(await sign(signer)), AnswerSignature.valid);
    });

    test('no signature is missing, not bad', () async {
      expect(await check(null), AnswerSignature.missing);
      expect(await check(''), AnswerSignature.missing);
    });

    test('a changed answer is bad', () async {
      expect(
        await check(await sign(signer), b: utf8.encode('{"text":"低い所へ"}')),
        AnswerSignature.bad,
      );
    });

    test('another key is bad, also under the pinned key id', () async {
      final sig = await sign(other);
      expect(await check(sig), AnswerSignature.bad);
      final forged = '${signer.keyId}${sig.substring(sig.indexOf('.'))}';
      expect(await check(forged), AnswerSignature.bad);
    });

    test('an answer signed for another nonce is bad (replayed)', () async {
      final sig = await sign(signer, n: 'BBBBBBBBBBBBBBBBBBBBBB');
      expect(await check(sig), AnswerSignature.bad);
    });

    test('an answer to a changed question is bad', () async {
      final changed = utf8.encode('{"question":"地震は？","nonce":"$nonce"}');
      expect(await check(await sign(signer, r: changed)), AnswerSignature.bad);
    });

    test('only a signature made for answers passes', () async {
      // The same key signs facts: a signature over the same nonce, question
      // and answer, but not made as an answer signature, must not pass.
      for (final signed in [
        body,
        [...utf8.encode('$nonce\n${sha256.convert(request)}\n'), ...body],
      ]) {
        final sig = await signer.signBytes(signed);
        expect(await check('${signer.keyId}.$sig'), AnswerSignature.bad);
      }
    });

    test('malformed signatures are bad', () async {
      for (final h in [
        'nodot',
        '.abc',
        '${signer.keyId}.',
        '${signer.keyId}.%%%',
        '${signer.keyId}.AAAA',
      ]) {
        expect(await check(h), AnswerSignature.bad, reason: h);
      }
    });

    test('nonces the base signs with', () {
      expect(isAnswerNonce(newAnswerNonce()), isTrue);
      expect(newAnswerNonce(), isNot(newAnswerNonce()));
      for (final n in [null, 5, '', 'short', 'x' * 65, 'a b c d e f g h i']) {
        expect(isAnswerNonce(n), isFalse, reason: '$n');
      }
    });
  });

  group('a phone and a base', () {
    late BaseServer server;
    late String base;

    setUp(() async {
      server = BaseServer(
        answerer: GroundedAnswerer(FakeLlm(['高い所へ [1]。']), pkg),
        name: 'Test base',
        modelName: 'fake',
        facts: FactStore(signer: signer),
        maxQuestionsPerPhone: 3,
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      base = 'http://127.0.0.1:${server.port}';
    });
    tearDown(() => server.stop());

    /// Posts [body] to the real base, as something in between would.
    Future<_Sent> forward(Map<String, Object?> body) async {
      final c = HttpClient();
      try {
        final req = await c.postUrl(Uri.parse('$base/ask'));
        req.add(utf8.encode(jsonEncode(body)));
        final res = await req.close();
        final bytes = [for (final chunk in await res.toList()) ...chunk];
        return (
          body: bytes,
          signature: res.headers.value(answerSignatureHeader),
        );
      } finally {
        c.close(force: true);
      }
    }

    /// A client whose requests pass [between] on their way to the base.
    Future<BaseClient> through(
      Future<_Sent> Function(Map<String, dynamic> request) between, {
      bool twice = false,
    }) async {
      final mid = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => mid.close(force: true));
      mid.listen((req) async {
        final request =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        final sent = await between(request);
        req.response.headers.contentType = ContentType.json;
        if (sent.signature case final s?) {
          req.response.headers.set(answerSignatureHeader, s);
          if (twice) req.response.headers.add(answerSignatureHeader, s);
        }
        req.response.add(sent.body);
        await req.response.close();
      });
      final c = BaseClient('http://127.0.0.1:${mid.port}');
      addTearDown(c.close);
      return c;
    }

    BaseClient direct() {
      final c = BaseClient(base);
      addTearDown(c.close);
      return c;
    }

    test('says in /info that it signs answers', () async {
      final info = await direct().info();
      expect(info['signs_answers'], isTrue);
      expect(info['key'], signer.publicKeyText);
    });

    test('a signed answer is taken with the pinned key', () async {
      final a = await direct().ask(
        '津波は一回だけですか？',
        pinnedKey: signer.publicKeyText,
      );
      expect(a.text, contains('高い所へ'));
      expect(a.baseUnsigned, isFalse);
    });

    test('another key than the QR code\'s is refused', () async {
      await expectLater(
        direct().ask('津波は一回だけですか？', pinnedKey: other.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
    });

    test('an answer changed on the way is refused', () async {
      final c = await through((r) async {
        final sent = await forward(r);
        final changed = utf8.decode(sent.body).replaceAll('高い所へ', '低い所へ');
        expect(changed, isNot(utf8.decode(sent.body)));
        return (body: utf8.encode(changed), signature: sent.signature);
      });
      await expectLater(
        c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
    });

    test('an earlier answer sent again is refused (replayed)', () async {
      _Sent? first;
      final c = await through((r) async => first ??= await forward(r));
      // The same question both times: only the nonce tells them apart.
      await c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText);
      await expectLater(
        c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
    });

    test('a signed answer to another question is refused', () async {
      // Sends the base another question with the phone's nonce.
      final c = await through((r) => forward({...r, 'question': '地震が来たら？'}));
      await expectLater(
        c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
    });

    test('a question with another field added on the way is refused', () async {
      // The base reads `lang`: the signature covers the whole request.
      final c = await through((r) => forward({...r, 'lang': 'en'}));
      await expectLater(
        c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
    });

    test('a signature sent twice is refused', () async {
      final c = await through(forward, twice: true);
      await expectLater(
        c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText),
        throwsA(isA<BadAnswerSignature>()),
      );
      // Without a QR key nothing is checked: still answered.
      expect((await c.ask('津波は一回だけですか？')).text, contains('高い所へ'));
    });

    test('once a base has signed, an unsigned answer is refused', () async {
      var strip = false;
      final c = await through((r) async {
        final sent = await forward(r);
        return (body: sent.body, signature: strip ? null : sent.signature);
      });
      final key = signer.publicKeyText;
      String? signed;
      final errors = <Object>[];
      Future<GroundedAnswer?> ask() => answerFromBase(
        c,
        '津波は一回だけですか？',
        pinnedKey: key,
        signedKey: signed,
        onSigned: (k) => signed = k,
        onError: errors.add,
      );
      expect((await ask())!.baseUnsigned, isFalse);
      expect(signed, key);
      strip = true;
      expect(await ask(), isNull);
      expect(errors.single, isA<BadAnswerSignature>());
      expect('${errors.single}', contains('signature missing'));
    });

    test(
      'an unsigned answer from a base never seen signing is taken',
      () async {
        final c = await through((r) async {
          final sent = await forward(r);
          return (body: sent.body, signature: null);
        });
        String? signed;
        final a = await answerFromBase(
          c,
          '津波は一回だけですか？',
          pinnedKey: signer.publicKeyText,
          onSigned: (k) => signed = k,
        );
        expect(a!.baseUnsigned, isTrue);
        expect(signed, isNull);
      },
    );

    test('an answer without a signature (old base) is marked', () async {
      final c = await through((r) async {
        final sent = await forward(r);
        return (body: sent.body, signature: null);
      });
      final a = await c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText);
      expect(a.text, contains('高い所へ'));
      expect(a.baseUnsigned, isTrue);
    });

    test('without a pinned key nothing is checked', () async {
      final c = await through((r) async {
        final sent = await forward(r);
        return (body: sent.body, signature: 'junk');
      });
      final a = await c.ask('津波は一回だけですか？');
      expect(a.text, contains('高い所へ'));
      expect(a.baseUnsigned, isFalse);
    });

    test('the browser page (no nonce) gets no signature', () async {
      for (final n in [null, 'short', 42]) {
        final sent = await forward({'question': '津波は一回だけですか？', 'nonce': ?n});
        expect(sent.signature, isNull, reason: '$n');
        final j = jsonDecode(utf8.decode(sent.body)) as Map;
        expect(j['web'], isNotNull);
      }
    });

    test('the phone sends a new nonce each time', () async {
      final nonces = <Object?>[];
      final c = await through((r) async {
        nonces.add(r['nonce']);
        return forward(r);
      });
      await c.ask('津波は一回だけですか？');
      await c.ask('津波は一回だけですか？');
      expect(nonces, hasLength(2));
      expect(nonces.every(isAnswerNonce), isTrue);
      expect(nonces.toSet(), hasLength(2));
    });
  });

  test('a base without a signing key sends no signature', () async {
    final server = BaseServer(
      answerer: GroundedAnswerer(FakeLlm(['高い所へ [1]。']), pkg),
      name: 'Test base',
      modelName: 'fake',
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(server.stop);
    final c = BaseClient('http://127.0.0.1:${server.port}');
    addTearDown(c.close);
    expect((await c.info())['signs_answers'], isFalse);
    // Its /info has no key, so a phone with a QR key does not connect;
    // asked anyway, the answer is marked unsigned.
    final a = await c.ask('津波は一回だけですか？', pinnedKey: signer.publicKeyText);
    expect(a.baseUnsigned, isTrue);
  });
}
