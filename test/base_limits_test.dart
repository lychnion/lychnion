// A base on a Wi-Fi where anyone can send anything, and a phone talking
// to a base that may not be one: limits, error paths, random input.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/llm/local_llm.dart';
import 'package:lychnion/base/base_client.dart';
import 'package:lychnion/base/base_library.dart';
import 'package:lychnion/base/base_protocol.dart';
import 'package:lychnion/base/base_server.dart';

import 'support/fake_llm.dart';

/// Answers only when [release] completes, so tests decide how long the
/// model is busy.
class _GatedLlm extends FakeLlm {
  _GatedLlm() : super(['高い所へ [1]。']);
  var release = Completer<void>();

  /// Questions the model started on.
  var started = 0;

  @override
  Stream<String> ask(String prompt, {void Function(AnswerStats)? onDone}) =>
      Stream.fromFuture(
        Future(() => started++).then((_) => release.future).then((_) {
          prompts.add(prompt);
          return '高い所へ [1]。';
        }),
      );
}

/// A [_GatedLlm] that counts [stop] calls; a stop ends the answer.
class _StoppableLlm extends _GatedLlm {
  var stops = 0;

  @override
  Future<void> stop() async {
    stops++;
    if (!release.isCompleted) release.complete();
  }
}

/// Sends a question on a raw connection and returns the connection, so a
/// test can close it as a phone that gives up would.
Future<Socket> _askRaw(int port, String q) async {
  final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final body = utf8.encode(jsonEncode({'question': q}));
  s.add([
    ...utf8.encode(
      'POST /ask HTTP/1.1\r\nHost: x\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: ${body.length}\r\n\r\n',
    ),
    ...body,
  ]);
  await s.flush();
  s.listen((_) {}, onError: (Object _) {});
  return s;
}

/// Waits until [ready] is true (checked every 10 ms, at most 5 s), so tests
/// wait for a state and not for a time that a slow machine may need.
Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 500; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('state not reached');
}

/// Fails with a message that must not reach the phone.
class _LeakyLlm extends FakeLlm {
  @override
  Stream<String> ask(String prompt, {void Function(AnswerStats)? onDone}) =>
      Stream.error(
        const FileSystemException('cannot read', '/Users/someone/model.gguf'),
      );
}

/// A library of one file, without a download store.
class _OneFile implements BaseLibrary {
  _OneFile(this.file, this.sha);
  final File file;
  final String sha;

  @override
  Map<String, Object?> catalog() => {'format': 2, 'records': <Object>[]};
  @override
  File? blob(String sha256) => sha256 == sha ? file : null;
  @override
  DownloadStore get store => throw UnimplementedError();
  @override
  List<Installed> get items => throw UnimplementedError();
}

/// What came back on a raw connection: the status line's code (0 when the
/// server closed without answering) and the body.
Future<(int, String)> _raw(int port, List<int> bytes) async {
  final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final got = <int>[];
  final done = Completer<void>();
  s.listen(
    got.addAll,
    onDone: done.complete,
    onError: (Object _) => done.isCompleted ? null : done.complete(),
  );
  s.add(bytes);
  try {
    await s.flush();
  } on Object {
    // The server closed while this was still writing.
  }
  await done.future.timeout(const Duration(seconds: 5));
  s.destroy();
  final text = utf8.decode(got, allowMalformed: true);
  final m = RegExp(r'^HTTP/1\.1 (\d{3})').firstMatch(text);
  final body = text.contains('\r\n\r\n')
      ? text.substring(text.indexOf('\r\n\r\n') + 4)
      : '';
  return (m == null ? 0 : int.parse(m[1]!), body);
}

/// Whether the server closes [s] within [within].
Future<bool> _closedWithin(Socket s, Duration within) async {
  final closed = Completer<bool>();
  s.listen(
    (_) {},
    onDone: () => closed.isCompleted ? null : closed.complete(true),
    onError: (Object _) => closed.isCompleted ? null : closed.complete(true),
  );
  return closed.future.timeout(within, onTimeout: () => false);
}

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  final servers = <BaseServer>[];
  tearDown(() async {
    for (final s in servers) {
      await s.stop();
    }
    servers.clear();
  });

  Future<BaseServer> start({
    LocalLlm? llm,
    BaseLibrary? library,
    int maxConnections = 100,
    Duration idleTimeout = const Duration(seconds: 30),
    Duration bodyTimeout = const Duration(seconds: 10),
    int maxQuestions = 8,
    int perPhone = 1,
    Duration maxWait = const Duration(seconds: 100),
    Duration sendStall = const Duration(seconds: 30),
  }) async {
    final s = BaseServer(
      answerer: GroundedAnswerer(llm ?? FakeLlm(['高い所へ [1]。']), pkg),
      name: 'Test base',
      library: library,
      maxConnections: maxConnections,
      idleTimeout: idleTimeout,
      bodyTimeout: bodyTimeout,
      maxQuestions: maxQuestions,
      maxQuestionsPerPhone: perPhone,
      maxWait: maxWait,
      sendStall: sendStall,
    );
    await s.start(port: 0, address: InternetAddress.loopbackIPv4);
    servers.add(s);
    return s;
  }

  Future<(int, Map<String, dynamic>, HttpHeaders)> call(
    BaseServer s,
    String method,
    String path, {
    List<int>? body,
    Map<String, String> headers = const {},
  }) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${s.port}$path'),
      );
      headers.forEach(req.headers.set);
      if (body != null) req.add(body);
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      Map<String, dynamic> j = const {};
      if (bytes.isNotEmpty &&
          res.headers.contentType?.mimeType == 'application/json') {
        j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
      return (res.statusCode, j, res.headers);
    } finally {
      c.close(force: true);
    }
  }

  List<int> question(String q) => utf8.encode(jsonEncode({'question': q}));

  group('the base refuses', () {
    test('a question over 8 KiB, by its Content-Length', () async {
      final s = await start();
      final big = utf8.encode(jsonEncode({'question': 'x' * 20000}));
      final (code, j, _) = await call(s, 'POST', '/ask', body: big);
      expect(code, 413);
      expect(j['error'], 'question too large');
    });

    test('a question over 8 KiB sent in many small chunks', () async {
      // The old limit counted chunks, not bytes.
      final s = await start();
      final head = utf8.encode(
        'POST /ask HTTP/1.1\r\nHost: x\r\n'
        'Transfer-Encoding: chunked\r\n\r\n',
      );
      final chunks = <int>[
        for (var i = 0; i < 300; i++) ...utf8.encode('40\r\n${'x' * 64}\r\n'),
        ...utf8.encode('0\r\n\r\n'),
      ];
      final (code, body) = await _raw(s.port, [...head, ...chunks]);
      expect(code, 413);
      expect(body, contains('question too large'));
    });

    test('a body that arrives too slowly', () async {
      final s = await start(bodyTimeout: const Duration(milliseconds: 200));
      final sock = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      addTearDown(sock.destroy);
      final got = <int>[];
      final done = Completer<void>();
      sock.listen(got.addAll, onDone: done.complete);
      sock.add(
        utf8.encode(
          'POST /ask HTTP/1.1\r\nHost: x\r\nContent-Length: 100\r\n\r\n{"que',
        ),
      );
      await done.future.timeout(const Duration(seconds: 5));
      expect(utf8.decode(got), startsWith('HTTP/1.1 408'));
    });

    test('bad JSON, JSON that is not an object, and bad UTF-8', () async {
      final s = await start();
      for (final body in [
        utf8.encode('{"question": '),
        utf8.encode('[1, 2]'),
        utf8.encode('"津波"'),
        [0x7b, 0xff, 0xfe, 0x7d],
        <int>[],
      ]) {
        final (code, j, _) = await call(s, 'POST', '/ask', body: body);
        expect(code, 400, reason: '$body');
        expect(j['error'], isA<String>());
      }
    });

    test(
      'a third question when two may wait, and says when to retry',
      () async {
        final llm = _GatedLlm();
        final s = await start(llm: llm, maxQuestions: 2, perPhone: 10);
        final first = [
          for (var i = 0; i < 2; i++)
            call(s, 'POST', '/ask', body: question('津波は？')),
        ];
        await _until(() => s.questionsWaiting == 2);
        final (code, j, h) = await call(
          s,
          'POST',
          '/ask',
          body: question('津波は？'),
        );
        expect(code, 503);
        expect(j['error'], 'busy, try again soon');
        expect(h.value(HttpHeaders.retryAfterHeader), '30');
        llm.release.complete();
        expect([for (final r in await Future.wait(first)) r.$1], [200, 200]);
      },
    );

    test('questions sent at the same moment cannot pass the limit', () async {
      final llm = _GatedLlm();
      final s = await start(llm: llm, maxQuestions: 2, perPhone: 10);
      var refused = 0;
      final all = [
        for (var i = 0; i < 6; i++)
          call(s, 'POST', '/ask', body: question('津波は？')).then((r) {
            if (r.$1 != 200) refused++;
            return r;
          }),
      ];
      // Every question is in or refused before the model answers.
      await _until(() => refused == 4);
      llm.release.complete();
      final codes = [for (final r in await Future.wait(all)) r.$1]..sort();
      expect(codes, [200, 200, 503, 503, 503, 503]);
    });

    test('a second question from the same phone while one waits', () async {
      final llm = _GatedLlm();
      final s = await start(llm: llm);
      final first = call(s, 'POST', '/ask', body: question('津波は？'));
      await _until(() => s.questionsWaiting == 1);
      final (code, j, _) = await call(
        s,
        'POST',
        '/ask',
        body: question('津波は？'),
      );
      expect(code, 429);
      expect(j['error'], 'one question at a time');
      llm.release.complete();
      expect((await first).$1, 200);
      // Answered: the phone may ask again.
      expect((await call(s, 'POST', '/ask', body: question('津波は？'))).$1, 200);
    });

    test('a question that waited longer than the phone waits', () async {
      final llm = _GatedLlm();
      final s = await start(
        llm: llm,
        perPhone: 10,
        maxWait: const Duration(milliseconds: 500),
      );
      final first = call(s, 'POST', '/ask', body: question('津波は？'));
      await _until(() => llm.started == 1);
      final second = call(s, 'POST', '/ask', body: question('避難所は？'));
      await _until(() => s.questionsWaiting == 2);
      // Longer than maxWait: the second one's phone has given up.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // It no longer counts: only the one being answered does.
      expect(s.questionsWaiting, 1);
      // So its phone can ask again.
      final third = call(s, 'POST', '/ask', body: question('避難所は？'));
      await _until(() => s.questionsWaiting == 2);
      llm.release.complete();
      expect((await first).$1, 200);
      expect((await second).$1, 503);
      expect((await third).$1, 200);
      // The model never saw the second one.
      expect(llm.prompts, hasLength(2));
      expect(s.answered, 2);
    });

    test('a phone that leaves stops the answer it waits for', () async {
      final llm = _StoppableLlm();
      final s = await start(llm: llm);
      final phone = await _askRaw(s.port, '津波は？');
      await _until(() => llm.started == 1);
      phone.destroy();
      // The model is stopped, and the question no longer counts.
      await _until(() => llm.stops >= 1);
      await _until(() => s.questionsWaiting == 0);
      expect(s.answered, 0);
      // The next phone is answered as usual.
      expect((await call(s, 'POST', '/ask', body: question('津波は？'))).$1, 200);
      expect(s.answered, 1);
    });

    test('phones that leave do not use up the connections', () async {
      final llm = _StoppableLlm();
      final s = await start(llm: llm, maxConnections: 2, perPhone: 10);
      for (var i = 0; i < 2; i++) {
        final phone = await _askRaw(s.port, '津波は？');
        await _until(() => llm.started == i + 1);
        phone.destroy();
        await _until(() => s.questionsWaiting == 0);
        llm.release = Completer<void>();
      }
      // Both connections were let go of: the base still answers.
      final (code, _, _) = await call(s, 'GET', '/info');
      expect(code, 200);
    });

    test('a waiting question whose phone left is dropped', () async {
      final llm = _StoppableLlm();
      final s = await start(llm: llm, perPhone: 10);
      final first = call(s, 'POST', '/ask', body: question('津波は？'));
      await _until(() => llm.started == 1);
      final phone = await _askRaw(s.port, '避難所は？');
      await _until(() => s.questionsWaiting == 2);
      phone.destroy();
      // It stops counting at once, without stopping the first answer.
      await _until(() => s.questionsWaiting == 1);
      expect(llm.stops, 0);
      llm.release.complete();
      expect((await first).$1, 200);
      await _until(() => s.questionsWaiting == 0);
      // The model never saw the second question.
      expect(llm.prompts, hasLength(1));
      expect(s.answered, 1);
    });

    test('a huge refused upload is not read, the connection ends', () async {
      final llm = _GatedLlm();
      final s = await start(llm: llm);
      // The phone's one question is waiting.
      final first = call(s, 'POST', '/ask', body: question('津波は？'));
      await _until(() => s.questionsWaiting == 1);
      final sock = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      addTearDown(sock.destroy);
      var closed = false;
      sock.listen(
        (_) {},
        onDone: () => closed = true,
        onError: (Object _) => closed = true,
      );
      sock.add(
        utf8.encode(
          'POST /ask HTTP/1.1\r\nHost: x\r\nContent-Length: 1000000000000\r\n\r\n',
        ),
      );
      final junk = Uint8List(64 * 1024);
      final sw = Stopwatch()..start();
      // Keeps sending, as a phone that wants to waste the base's time.
      while (!closed && sw.elapsed < const Duration(seconds: 5)) {
        try {
          sock.add(junk);
          await sock.flush();
        } on Object {
          break;
        }
      }
      // Not after sendStall (30 s), and not 5 s of reading: at once.
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      llm.release.complete();
      expect((await first).$1, 200);
    });

    test('connections over the limit, and closes idle ones', () async {
      final s = await start(
        maxConnections: 2,
        idleTimeout: const Duration(milliseconds: 300),
      );
      final a = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      final b = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      addTearDown(a.destroy);
      addTearDown(b.destroy);
      // Half a request, as a slow client sends it.
      a.add(utf8.encode('GET /info HTTP/1.1\r\nHost: x\r\n'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final c = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      addTearDown(c.destroy);
      expect(await _closedWithin(c, const Duration(seconds: 1)), isTrue);
      // The idle ones close too, so phones can connect again.
      expect(await _closedWithin(a, const Duration(seconds: 2)), isTrue);
      expect(await _closedWithin(b, const Duration(seconds: 2)), isTrue);
      expect((await call(s, 'GET', '/info')).$1, 200);
    });
  });

  group('errors', () {
    test('say what went wrong, not where or how', () async {
      final s = await start(llm: _LeakyLlm());
      final (code, j, _) = await call(
        s,
        'POST',
        '/ask',
        body: question('津波は？'),
      );
      expect(code, 500);
      expect(j, {'error': 'something went wrong'});
    });

    test('the server header does not name the software', () async {
      final s = await start();
      final (_, _, h) = await call(s, 'GET', '/info');
      expect(h.value('server'), isNull);
    });
  });

  group('files', () {
    late Directory dir;
    late File file;
    final sha = 'c' * 64;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('base_limits');
      file = File('${dir.path}/f.bin')..writeAsBytesSync(List.filled(1000, 7));
    });
    tearDown(() => dir.delete(recursive: true));

    test('a range past the end is 416 with the size', () async {
      final s = await start(library: _OneFile(file, sha));
      final (code, _, h) = await call(
        s,
        'GET',
        '/blobs/sha256/$sha',
        headers: {'Range': 'bytes=5000-'},
      );
      expect(code, 416);
      expect(h.value(HttpHeaders.contentRangeHeader), 'bytes */1000');
    });

    test('a range number too large for an int gets the whole file', () async {
      final s = await start(library: _OneFile(file, sha));
      for (final r in [
        'bytes=99999999999999999999999-',
        'bytes=-5',
        'bytes=1-2,3-4',
        'pages=1-',
        'bytes=${'9' * 5000}-',
      ]) {
        final (code, _, h) = await call(
          s,
          'GET',
          '/blobs/sha256/$sha',
          headers: {'Range': r},
        );
        expect(code, 200, reason: r);
        expect(h.contentLength, 1000);
      }
    });

    test('paths that are not exactly a hash are not found', () async {
      final s = await start(library: _OneFile(file, sha));
      for (final p in [
        '/blobs/sha256/$sha/x',
        '/blobs/sha256/../$sha',
        '/blobs/sha256/${sha.toUpperCase()}',
        '/blobs/sha256/%2e%2e%2f$sha',
        '/x/blobs/sha256/$sha',
      ]) {
        expect((await call(s, 'GET', p)).$1, 404, reason: p);
      }
    });

    test('a phone that stops reading loses its connection', () async {
      // Larger than what the system buffers for one connection.
      final big = File('${dir.path}/big.bin')
        ..writeAsBytesSync(Uint8List(64 << 20));
      final s = await start(
        library: _OneFile(big, sha),
        maxConnections: 1,
        sendStall: const Duration(milliseconds: 300),
      );
      var served = 0;
      s.onBlobServed = (_) => served++;
      final sock = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
      addTearDown(sock.destroy);
      final first = Completer<void>();
      final sub = sock.listen((_) {
        if (!first.isCompleted) first.complete();
      }, onError: (Object _) {});
      sock.add(
        utf8.encode('GET /blobs/sha256/$sha HTTP/1.1\r\nHost: x\r\n\r\n'),
      );
      await first.future;
      sub.pause();
      addTearDown(sub.cancel);
      // It held the only place; once closed, the next phone gets in.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await call(s, 'GET', '/info')).$1, 200);
      // Stopped, not read to the end, and not counted as sent.
      expect(served, 0);
    });

    test(
      'a download is counted as sent, also with Connection: close',
      () async {
        final s = await start(library: _OneFile(file, sha));
        var served = 0;
        s.onBlobServed = (_) => served++;
        expect((await call(s, 'GET', '/blobs/sha256/$sha')).$1, 200);
        expect(
          (await call(
            s,
            'GET',
            '/blobs/sha256/$sha',
            headers: {'Connection': 'close'},
          )).$1,
          200,
        );
        // HTTP/1.0: the connection closes after the file.
        await _raw(
          s.port,
          utf8.encode('GET /blobs/sha256/$sha HTTP/1.0\r\n\r\n'),
        );
        await _until(() => served == 3);
      },
    );

    test('a phone that leaves half-way does not stop the base', () async {
      final big = File('${dir.path}/big.bin')
        ..writeAsBytesSync(Uint8List(8 << 20));
      final s = await start(library: _OneFile(big, sha));
      var served = 0;
      s.onBlobServed = (_) => served++;
      for (var i = 0; i < 3; i++) {
        final sock = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
        final first = Completer<void>();
        sock.listen((_) {
          if (!first.isCompleted) first.complete();
        }, onError: (Object _) {});
        sock.add(
          utf8.encode('GET /blobs/sha256/$sha HTTP/1.1\r\nHost: x\r\n\r\n'),
        );
        await first.future;
        sock.destroy();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await call(s, 'GET', '/info')).$1, 200);
      expect(served, 0);
    });
  });

  group('random input to /ask', () {
    test('random bytes are refused, never a server error', () async {
      final s = await start();
      final rnd = Random(42);
      for (var i = 0; i < 150; i++) {
        final body = [
          for (var n = rnd.nextInt(300); n > 0; n--) rnd.nextInt(256),
        ];
        final (code, _, _) = await call(s, 'POST', '/ask', body: body);
        expect(code, anyOf(400, 413), reason: '$body');
      }
      expect((await call(s, 'GET', '/info')).$1, 200);
    });

    test('a question cut off at every byte', () async {
      final s = await start();
      final whole = question('津波は一回だけですか？');
      for (var n = 0; n < whole.length; n++) {
        final (code, _, _) = await call(
          s,
          'POST',
          '/ask',
          body: whole.sublist(0, n),
        );
        expect(code, 400, reason: 'cut at $n');
      }
      expect((await call(s, 'POST', '/ask', body: whole)).$1, 200);
    });

    test('random JSON values for question and lang', () async {
      final s = await start();
      final values = <Object?>[
        null,
        0,
        -1.5,
        true,
        '',
        '   ',
        'x' * 501,
        <Object?>[],
        {'a': 1},
        '津波',
        '\u0000\u202e',
      ];
      for (final q in values) {
        for (final lang in values) {
          final (code, _, _) = await call(
            s,
            'POST',
            '/ask',
            body: utf8.encode(jsonEncode({'question': q, 'lang': lang})),
          );
          expect(code, anyOf(200, 400), reason: '$q / $lang');
        }
      }
    });
  });

  group('a phone and a base that may not be one', () {
    /// A base that sends [head] on every connection and then nothing;
    /// [closed] completes when the phone closes a connection.
    Future<(String, Future<void>)> rawBase(String head) async {
      final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(srv.close);
      final closed = Completer<void>();
      srv.listen((sock) {
        addTearDown(sock.destroy);
        sock.listen(
          (_) => sock.add(utf8.encode(head)),
          onDone: () => closed.isCompleted ? null : closed.complete(),
          onError: (Object _) => closed.isCompleted ? null : closed.complete(),
        );
      });
      return ('http://127.0.0.1:${srv.port}', closed.future);
    }

    /// A fake base that answers every request with [handler].
    Future<String> fakeBase(
      Future<void> Function(HttpRequest req) handler,
    ) async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => srv.close(force: true));
      srv.listen((r) => unawaited(handler(r).catchError((Object _) {})));
      return 'http://127.0.0.1:${srv.port}';
    }

    test('an endless answer is cut off at 1 MiB', () async {
      final url = await fakeBase((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"v":1,"text":"');
        for (var i = 0; i < 40; i++) {
          req.response.write('x' * 65536);
          await req.response.flush();
        }
        await req.response.close();
      });
      final c = BaseClient(url);
      addTearDown(c.close);
      await expectLater(
        c.ask('津波は？'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('a too large Content-Length is refused and closed', () async {
      final (url, closed) = await rawBase(
        'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
        'Content-Length: ${50 << 20}\r\n\r\n{}',
      );
      final c = BaseClient(url);
      addTearDown(c.close);
      await expectLater(c.facts(), throwsA(isA<HttpException>()));
      // Not kept open waiting for the rest.
      await closed.timeout(const Duration(seconds: 2));
    });

    test(
      'a base that never answers times out, and the connection closes',
      () async {
        final (url, closed) = await rawBase(
          'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
          'Transfer-Encoding: chunked\r\n\r\n',
        );
        final c = BaseClient(url);
        addTearDown(c.close);
        await expectLater(c.info(), throwsA(isA<TimeoutException>()));
        await closed.timeout(const Duration(seconds: 2));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('a stalled fact pull does not end an answer on its way', () async {
      final url = await fakeBase((req) async {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/facts') {
          // Headers, then nothing: the pull times out after 10 s.
          await req.response.flush();
          return;
        }
        // The answer comes after the pull has timed out.
        await Future<void>.delayed(const Duration(seconds: 11));
        req.response.write(
          jsonEncode({
            'v': 1,
            'question': '津波は？',
            'lang': 'ja',
            'text': '高い所へ。',
            'alerts': <Object>[],
            'hits': <Object>[],
          }),
        );
        await req.response.close();
      });
      final c = BaseClient(url);
      addTearDown(c.close);
      final answer = c.ask('津波は？');
      await expectLater(c.facts(), throwsA(isA<TimeoutException>()));
      expect((await answer).text, '高い所へ。');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('no more than 500 facts, and broken ones are left out', () async {
      final good = Fact(
        kind: FactKind.warning,
        subject: 'x',
        value: 'tsunami',
        observedAt: DateTime.utc(2026, 11, 18, 6),
        expiresAt: DateTime.utc(2026, 11, 18, 9),
        sourceType: SourceType.citizen,
      ).toJson();
      final url = await fakeBase((req) async {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'v': 1,
              'facts': [
                {'kind': 'nonsense'},
                42,
                {...good, 'observed_at': 'yesterday'},
                for (var i = 0; i < 2000; i++) {...good, 'subject': 's$i'},
              ],
            }),
          );
        await req.response.close();
      });
      final c = BaseClient(url);
      addTearDown(c.close);
      final facts = await c.facts();
      expect(facts.length, lessThanOrEqualTo(BaseClient.maxFacts));
      expect(facts.first.subject, 's0');
    });

    test('a base name and error text are cleaned before showing', () async {
      final url = await fakeBase((req) async {
        final long = '\u202eevil\u0007${'x' * 500}';
        req.response
          ..statusCode = req.uri.path == '/info' ? 200 : 400
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'v': 1, 'name': long, 'error': long}));
        await req.response.close();
      });
      final c = BaseClient(url);
      addTearDown(c.close);
      await c.info();
      expect(c.name, startsWith('evil'));
      expect(c.name!.length, 60);
      try {
        await c.ask('津波は？');
        fail('should throw');
      } on HttpException catch (e) {
        expect(e.message, isNot(contains('\u202e')));
        expect(e.message.length, lessThan(80));
      }
    });

    test('an answer cut off at random places throws, never hangs', () async {
      // A real answer, as a base sends it.
      final s = await start();
      final c0 = HttpClient();
      final req = await c0.postUrl(Uri.parse('http://127.0.0.1:${s.port}/ask'));
      req.add(question('津波は一回だけですか？'));
      final whole = await (await req.close()).fold<List<int>>(
        [],
        (a, b) => a..addAll(b),
      );
      c0.close(force: true);
      var cut = whole.length;
      final url = await fakeBase((req) async {
        req.response
          ..headers.contentType = ContentType.json
          ..add(whole.sublist(0, cut));
        await req.response.close();
      });
      final c = BaseClient(url);
      addTearDown(c.close);
      expect((await c.ask('津波は？')).text, '高い所へ [1]。');
      final rnd = Random(7);
      for (var i = 0; i < 60; i++) {
        cut = rnd.nextInt(whole.length);
        await expectLater(
          c.ask('津波は？'),
          throwsA(anyOf(isA<HttpException>(), isA<FormatException>())),
          reason: 'cut at $cut',
        );
      }
    });
  });

  group('answerFromWire', () {
    Map<String, dynamic> valid() =>
        jsonDecode(
              jsonEncode({
                'v': 1,
                'question': '津波は？',
                'lang': 'ja',
                'text': '高い所へ [1]。',
                'alerts': [
                  {
                    'id': 'a1',
                    'text': '逃げて',
                    'translations': {'en': 'Run'},
                    'source': {
                      'id': 's',
                      'title': 't',
                      'publisher': 'p',
                      'url': 'https://example.org/',
                      'licence': 'CC BY',
                      'attribution': 'p',
                    },
                  },
                ],
                'hits': [
                  {
                    'score': 0.5,
                    'passage': {
                      'id': 1,
                      'heading': 'h',
                      'text': 'x',
                      'source': {
                        'id': 's',
                        'title': 't',
                        'publisher': 'p',
                        'url': 'https://example.org/',
                        'licence': 'CC BY',
                        'attribution': 'p',
                      },
                    },
                  },
                ],
              }),
            )
            as Map<String, dynamic>;

    test('reads a valid answer', () {
      final a = answerFromWire(valid());
      expect(a.hits.single.passage.source.url, 'https://example.org/');
    });

    test('keeps only web links for sources', () {
      for (final bad in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'tel:110',
        'httpx://a',
        'http://',
        'intent://x#Intent;end',
      ]) {
        final j = valid();
        final passage = ((j['hits'] as List).first as Map)['passage'] as Map;
        (passage['source'] as Map)['url'] = bad;
        expect(
          answerFromWire(j).hits.single.passage.source.url,
          '',
          reason: bad,
        );
      }
    });

    test('too many hits or alerts', () {
      final j = valid();
      j['hits'] = List.filled(maxWireHits + 1, (j['hits'] as List).first);
      expect(() => answerFromWire(j), throwsFormatException);
      final k = valid();
      k['alerts'] = List.filled(maxWireAlerts + 1, (k['alerts'] as List).first);
      expect(() => answerFromWire(k), throwsFormatException);
    });

    test('random changes give an answer or a FormatException', () {
      final rnd = Random(3);
      final odd = <Object?>[null, 1, -1.0, '', 'x', true, <Object?>[], {}];

      /// Changes one value somewhere in [o] (a JSON tree).
      void mutate(Object? o) {
        if (o is Map) {
          if (o.isEmpty) return;
          final k = o.keys.elementAt(rnd.nextInt(o.length));
          switch (rnd.nextInt(3)) {
            case 0:
              o.remove(k);
            case 1:
              o[k] = odd[rnd.nextInt(odd.length)];
            default:
              mutate(o[k]);
          }
        } else if (o is List && o.isNotEmpty) {
          if (rnd.nextBool()) {
            o[rnd.nextInt(o.length)] = odd[rnd.nextInt(odd.length)];
          } else {
            mutate(o[rnd.nextInt(o.length)]);
          }
        }
      }

      var refused = 0;
      for (var i = 0; i < 500; i++) {
        final j = valid();
        for (var n = 1 + rnd.nextInt(3); n > 0; n--) {
          mutate(j);
        }
        try {
          answerFromWire(j);
        } on FormatException {
          refused++;
        }
      }
      expect(refused, greaterThan(0));
    });
  });
}
