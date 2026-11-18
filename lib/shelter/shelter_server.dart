import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../facts/compact_codec.dart';
import '../facts/fact_store.dart';
import '../facts/signing.dart';
import '../knowledge/grounded_answer.dart';
import 'shelter_library.dart';
import 'shelter_protocol.dart';
import 'shelter_web.dart';

/// Answers questions from phones on the shelter's local network.
///
/// GET /       → a page for phones without the app (assets/web/shelter.html)
/// GET /web.json?lang=ja → that page's texts and the current facts
/// GET /info  → {name, model, package, version}
/// GET /facts → current facts (JSON, or ?compact=1 for radio-sized messages)
/// POST /ask  {"question": "…"} → an answer (shelter_protocol.dart)
/// GET /catalog.json        → signed records of what this shelter has
/// GET `/blobs/sha256/<hash>` → one of those files (resumable with Range)
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
    this.library,
    this.page,
    this.placeName,
  });

  /// A shelter's name from its ID (the map's evacuation sites), for the
  /// browser page. Null when there is no map.
  final String? Function(String id)? placeName;

  /// The page for phones without the app (HTML), or null for none.
  final String? page;

  /// Packages, maps and models passed on to phones (null: none).
  final ShelterLibrary? library;

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
      if (req.method == 'GET' && req.uri.path == '/' && page != null) {
        res.headers.contentType = ContentType.html;
        res.headers.set('Cache-Control', 'no-cache');
        res.write(page);
        unawaited(res.close());
      } else if (req.method == 'GET' && req.uri.path == '/web.json') {
        final lang = req.uri.queryParameters['lang'] ?? 'en';
        _send(
          res,
          200,
          webInfo(
            lang: lang,
            name: name,
            facts: facts?.current ?? const [],
            now: facts?.now ?? DateTime.now(),
            placeName: placeName,
          ),
        );
      } else if (req.method == 'GET' && req.uri.path == '/info') {
        _send(res, 200, {
          'v': shelterProtocolVersion,
          'name': name,
          'model': modelName,
          'package': answerer.package.id,
          'version': answerer.package.version,
          'answered': answered,
          // Phones trust this key for the facts the shelter signs.
          'key': ?facts?.signer?.publicKeyText,
        });
      } else if (req.method == 'GET' && req.uri.path == '/facts') {
        // All unexpired facts, so phones apply the same conflict rules.
        final all = facts?.all ?? const [];
        if (req.uri.queryParameters['compact'] == '1' && codec != null) {
          final FactSigner? signer = facts?.signer;
          _send(res, 200, {
            'v': shelterProtocolVersion,
            'messages': signer == null
                ? codec!.pack(all)
                : await signer.packSigned(codec!, all),
          });
        } else {
          _send(res, 200, {
            'v': shelterProtocolVersion,
            'facts': [for (final f in all) f.toJson()],
          });
        }
      } else if (req.method == 'GET' &&
          req.uri.path == '/catalog.json' &&
          library != null) {
        _send(res, 200, library!.catalog());
      } else if (req.method == 'GET' &&
          _blob.matchAsPrefix(req.uri.path)?.end == req.uri.path.length &&
          library != null) {
        await _sendBlob(req, library!.blob(req.uri.pathSegments.last));
      } else if (req.method == 'POST' && req.uri.path == '/ask') {
        final body = await utf8.decodeStream(req.take(8 * 1024));
        final j = jsonDecode(body) as Map;
        final q = j['question'];
        // The browser page sends its language: it decides between
        // Latin-script languages (an English or Spanish question).
        final appLang = j['lang'] is String ? j['lang'] as String : 'en';
        if (q is! String || q.trim().isEmpty || q.length > _maxQuestionChars) {
          _send(res, 400, {
            'error': 'question must be 1 to $_maxQuestionChars characters',
          });
          return;
        }
        final answer = GroundedAnswer(q.trim(), appLang: appLang);
        // One model: run questions one after another.
        final done = _queue.then((_) => answerer.answer(answer, () {}));
        _queue = done.catchError((_) {});
        await done;
        answered++;
        _send(res, 200, {...answerToWire(answer), 'web': webAnswer(answer)});
      } else {
        _send(res, 404, {'error': 'not found'});
      }
    } catch (e) {
      _send(res, 500, {'error': '$e'});
    }
  }

  static final _blob = RegExp(r'/blobs/sha256/[0-9a-f]{64}');

  /// Streams a file, from a byte offset when the phone resumes
  /// (`Range: bytes=N-`): models are gigabytes, Wi-Fi drops.
  Future<void> _sendBlob(HttpRequest req, File? file) async {
    final res = req.response;
    if (file == null || !file.existsSync()) {
      _send(res, 404, {'error': 'not found'});
      return;
    }
    final size = file.lengthSync();
    final range = RegExp(
      r'^bytes=(\d+)-$',
    ).firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    final from = range == null ? 0 : int.parse(range[1]!);
    if (from > size) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await res.close();
      return;
    }
    res.headers
      ..contentType = ContentType.binary
      ..contentLength = size - from
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range != null) {
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $from-${size - 1}/$size',
      );
    }
    await res.addStream(file.openRead(from));
    await res.close();
    // For whoever runs the shelter: what was passed on, to whom.
    debugPrint(
      'LYCHNION ${jsonEncode({'event': 'blob_served', 'file': file.uri.pathSegments.last, 'from_byte': from, 'bytes': size - from, 'to': req.connectionInfo?.remoteAddress.address})}',
    );
  }

  void _send(HttpResponse res, int status, Map<String, Object?> body) {
    res
      ..statusCode = status
      ..write(jsonEncode(body));
    unawaited(res.close());
  }
}
