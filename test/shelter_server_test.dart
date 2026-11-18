// A base answering phones: /info, /ask and /facts, and the phone's client.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/facts/compact_codec.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/llm/local_llm.dart';
import 'package:lychnion/map/evac_sites.dart';
import 'package:lychnion/shelter/shelter_client.dart';
import 'package:lychnion/shelter/shelter_protocol.dart';
import 'package:lychnion/shelter/shelter_server.dart';

import 'support/fake_llm.dart';

/// Records how many answers run at the same time.
class _SlowLlm extends FakeLlm {
  int active = 0, most = 0;

  @override
  Stream<String> ask(
    String prompt, {
    void Function(AnswerStats)? onDone,
  }) async* {
    prompts.add(prompt);
    most = max(most, ++active);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    active--;
    yield '高い所へ [1]。';
  }
}

/// The first answer fails, as when the model runs out of memory.
class _FailOnceLlm extends FakeLlm {
  _FailOnceLlm() : super(['高い所へ [1]。']);
  var failed = false;

  @override
  Stream<String> ask(String prompt, {void Function(AnswerStats)? onDone}) {
    if (failed) return super.ask(prompt, onDone: onDone);
    failed = true;
    return Stream.error(StateError('model'));
  }
}

/// A port that was free a moment ago (ShelterServer cannot bind port 0
/// and tell us the port yet: lychnion/lychnion#24).
Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  final sites = EvacSites.open('assets/maps/jp.map.nishinomiya.sites.sqlite');
  final codec = CompactCodec(sites.siteIds);
  final site = sites.siteIds[10];
  final now = DateTime.utc(2026, 11, 18, 6);

  Fact full() => Fact(
    kind: FactKind.shelterStatus,
    subject: site,
    value: 'full',
    observedAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(hours: 3)),
    sourceType: SourceType.official,
  );

  late FactSigner signer;
  late ShelterServer server;
  late String base;

  Future<ShelterServer> startServer(LocalLlm llm) async {
    final store = FactStore(clock: () => now, signer: signer);
    await store.addOwn([full()]);
    final s = ShelterServer(
      answerer: GroundedAnswerer(llm, pkg),
      name: 'Test base',
      modelName: 'fake',
      facts: store,
      codec: codec,
    );
    final port = await _freePort();
    await s.start(port: port);
    base = 'http://127.0.0.1:$port';
    return s;
  }

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, [
    String? body,
  ]) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl(method, Uri.parse('$base$path'));
      if (body != null) req.add(utf8.encode(body));
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
    } finally {
      c.close(force: true);
    }
  }

  Future<(int, Map<String, dynamic>)> ask(Object? question) =>
      call('POST', '/ask', jsonEncode({'question': question}));

  setUp(() async {
    signer = await FactSigner.generate();
  });
  tearDown(() => server.stop());

  group('a base', () {
    setUp(() async => server = await startServer(FakeLlm(['高い所へ [1]。'])));

    test('says who it is, that it answers, and its key', () async {
      final (status, info) = await call('GET', '/info');
      expect(status, 200);
      expect(info['v'], shelterProtocolVersion);
      expect(info['name'], 'Test base');
      expect(info['answers'], isTrue);
      expect(info['package'], pkg.id);
      expect(info['key'], signer.publicKeyText);
    });

    test('answers a question and counts it', () async {
      final (status, j) = await ask('津波は一回だけですか？');
      expect(status, 200);
      final a = answerFromWire(j);
      expect(a.text, '高い所へ [1]。');
      expect(a.isGrounded, isTrue);
      expect((j['web'] as Map)['shown'], '高い所へ。');
      expect(server.answered, 1);
    });

    test('refuses empty, too long and missing questions', () async {
      expect((await ask('')).$1, 400);
      expect((await ask('   ')).$1, 400);
      expect((await ask('あ' * 501)).$1, 400);
      expect((await ask(null)).$1, 400);
      expect((await ask(42)).$1, 400);
      expect(server.answered, 0);
    });

    test(
      'a body that is not JSON gets an error, and the base goes on',
      () async {
        final (status, j) = await call('POST', '/ask', '{not json');
        expect(status, greaterThanOrEqualTo(400));
        expect(j['error'], isNotNull);
        expect((await ask('津波は一回だけですか？')).$1, 200);
      },
    );

    test('GET /ask and unknown paths are not found', () async {
      expect((await call('GET', '/ask')).$1, 404);
      expect((await call('GET', '/nothing')).$1, 404);
    });

    test(
      'facts reach a phone and are verified once the key is trusted',
      () async {
        final (status, j) = await call('GET', '/facts');
        expect(status, 200);
        final got = [
          for (final f in (j['facts'] as List).cast<Map<String, dynamic>>())
            Fact.fromJson(f),
        ];
        expect(got.single.value, 'full');

        final trust = TrustList();
        final phone = FactStore(clock: () => now, trust: trust);
        await phone.addAll(got);
        expect(phone.shelterStatus(site)!.verified, isFalse);
        await trust.add(signer.publicKeyText, 'Test base');
        await phone.reverify();
        expect(phone.shelterStatus(site)!.verified, isTrue);
      },
    );

    test('compact facts are signed, and tampering shows', () async {
      final (status, j) = await call('GET', '/facts?compact=1');
      expect(status, 200);
      final msgs = (j['messages'] as List).cast<String>();
      expect(msgs, isNotEmpty);
      final trust = TrustList();
      await trust.add(signer.publicKeyText, 'Test base');
      final facts = await trust.unpackSigned(codec, msgs.first);
      expect(facts.single.verified, isTrue);
      final stranger = TrustList();
      await stranger.add((await FactSigner.generate()).publicKeyText, 'x');
      final unknown = await stranger.unpackSigned(codec, msgs.first);
      expect(unknown.single.verified, isFalse);
    });
  });

  test('questions are answered one after another', () async {
    final llm = _SlowLlm();
    server = await startServer(llm);
    final results = await Future.wait([
      for (var i = 0; i < 3; i++) ask('津波は一回だけですか？'),
    ]);
    expect([for (final r in results) r.$1], [200, 200, 200]);
    expect(llm.prompts, hasLength(3));
    expect(llm.most, 1);
  });

  test('a failed answer is an error, and the next question works', () async {
    server = await startServer(_FailOnceLlm());
    final (s1, j1) = await ask('津波は一回だけですか？');
    expect(s1, 500);
    expect(j1['error'], isNotNull);
    expect((await ask('津波は一回だけですか？')).$1, 200);
    expect(server.answered, 1);
  });

  group('ShelterClient', () {
    setUp(() async => server = await startServer(FakeLlm(['高い所へ [1]。'])));

    test('info, facts and an answer', () async {
      final c = ShelterClient(base);
      addTearDown(c.close);
      final info = await c.info();
      expect(c.name, 'Test base');
      expect(info['key'], signer.publicKeyText);
      expect((await c.facts()).single.value, 'full');
      final a = await c.ask('津波は一回だけですか？');
      expect(a.text, '高い所へ [1]。');
    });

    test('an error answer throws, so the phone can answer itself', () async {
      final c = ShelterClient(base);
      addTearDown(c.close);
      await expectLater(
        c.ask(''),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('400'),
          ),
        ),
      );
    });

    test('a base that is gone throws', () async {
      final c = ShelterClient('http://127.0.0.1:${await _freePort()}');
      addTearDown(c.close);
      await expectLater(c.info(), throwsA(isA<Exception>()));
    });

    test('an error page that is not JSON throws', () async {
      // A router or captive portal at the base's address.
      final portal = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => portal.close(force: true));
      portal.listen((req) {
        req.response
          ..statusCode = 502
          ..headers.contentType = ContentType.html
          ..write('<html>Bad gateway</html>');
        unawaited(req.response.close());
      });
      final c = ShelterClient('http://127.0.0.1:${portal.port}');
      addTearDown(c.close);
      await expectLater(c.ask('津波は？'), throwsA(isA<Exception>()));
    });
  });
}
