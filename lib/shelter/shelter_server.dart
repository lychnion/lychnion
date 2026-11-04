import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../facts/compact_codec.dart';
import '../facts/fact_store.dart';
import '../knowledge/grounded_answer.dart';
import 'shelter_protocol.dart';

/// Answers questions from phones on the shelter's local network.
///
/// GET /info  → {name, model, package, version}
/// GET /facts → current facts (JSON, or ?compact=1 for radio-sized messages)
/// POST /ask  {"question": "…"} → an answer (shelter_protocol.dart)
///
/// No login: anyone on the shelter Wi-Fi may ask. One model, so questions
/// are answered one after another.
class ShelterServer {
  ShelterServer({
    required this.answerer,
    required this.name,
    required this.modelName,
    this.facts,
    this.codec,
  });

  /// Current facts the shelter shares with phones (GET /facts).
  final FactStore? facts;
  final CompactCodec? codec;

  final GroundedAnswerer answerer;
  final String name;
  final String modelName;

  static const defaultPort = 8642;
  static const _maxQuestionChars = 500;

  HttpServer? _server;
  Future<void> _queue = Future.value();
  int answered = 0;

  Future<void> start({int port = defaultPort}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  /// IPv4 addresses phones can use, e.g. 192.168.1.20.
  static Future<List<String>> localAddresses() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback) a.address,
  ];

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      if (req.method == 'GET' && req.uri.path == '/info') {
        _send(res, 200, {
          'v': shelterProtocolVersion,
          'name': name,
          'model': modelName,
          'package': answerer.package.id,
          'version': answerer.package.version,
          'answered': answered,
        });
      } else if (req.method == 'GET' && req.uri.path == '/facts') {
        // All unexpired facts, so phones apply the same conflict rules.
        final all = facts?.all ?? const [];
        if (req.uri.queryParameters['compact'] == '1' && codec != null) {
          _send(res, 200, {
            'v': shelterProtocolVersion,
            'messages': codec!.pack(all),
          });
        } else {
          _send(res, 200, {
            'v': shelterProtocolVersion,
            'facts': [for (final f in all) f.toJson()],
          });
        }
      } else if (req.method == 'POST' && req.uri.path == '/ask') {
        final body = await utf8.decodeStream(req.take(8 * 1024));
        final q = (jsonDecode(body) as Map)['question'];
        if (q is! String || q.trim().isEmpty || q.length > _maxQuestionChars) {
          _send(res, 400, {
            'error': 'question must be 1 to $_maxQuestionChars characters',
          });
          return;
        }
        final answer = GroundedAnswer(q.trim());
        // One model: run questions one after another.
        final done = _queue.then((_) => answerer.answer(answer, () {}));
        _queue = done.catchError((_) {});
        await done;
        answered++;
        _send(res, 200, answerToWire(answer));
      } else {
        _send(res, 404, {'error': 'not found'});
      }
    } catch (e) {
      _send(res, 500, {'error': '$e'});
    }
  }

  void _send(HttpResponse res, int status, Map<String, Object?> body) {
    res
      ..statusCode = status
      ..write(jsonEncode(body));
    unawaited(res.close());
  }
}
