import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../app/lang.dart' show appTextLang;
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
///
/// Anyone on the Wi-Fi can also send anything, so every request has
/// limits: at most [maxConnections] connections, idle ones close after
/// [idleTimeout], a question is at most [maxBodyBytes] and must arrive
/// within [bodyTimeout], at most [maxQuestions] wait for the model and
/// [maxQuestionsPerPhone] per address, and a question that waited longer
/// than the phone waits ([maxWait]) is dropped. Errors say what was wrong
/// in a few words, never the exception (paths, internals).
///
/// Without an [answerer] it only passes on files: a phone sharing its
/// downloads with phones nearby (`sharePort`, no /ask, no page).
class ShelterServer {
  ShelterServer({
    required this.answerer,
    required this.name,
    this.modelName = '',
    this.facts,
    this.codec,
    this.library,
    this.page,
    this.placeName,
    this.maxConnections = 100,
    this.idleTimeout = const Duration(seconds: 30),
    this.maxBodyBytes = 8 * 1024,
    this.bodyTimeout = const Duration(seconds: 10),
    this.maxQuestions = 8,
    this.maxQuestionsPerPhone = 1,
    this.maxWait = const Duration(seconds: 100),
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

  final GroundedAnswerer? answerer;
  final String name;
  final String modelName;

  /// Open connections at most; more are closed at once. A Mac app may
  /// have only 256 files and sockets open, and the model needs some.
  final int maxConnections;

  /// A connection without a request (or with half a request) closes
  /// after this, at most twice this.
  final Duration idleTimeout;

  /// A question's request body, in bytes.
  final int maxBodyBytes;

  /// The whole body of a question must arrive within this.
  final Duration bodyTimeout;

  /// Questions waiting for the model or being answered; more get 503.
  final int maxQuestions;

  /// Questions from one address at a time; more get 429.
  final int maxQuestionsPerPhone;

  /// The phone gives up after 2 minutes (ShelterClient.ask): a question
  /// that waited this long for the model is not answered any more.
  final Duration maxWait;

  static const defaultPort = 8642;

  /// A phone sharing its downloads: another port, so it never clashes with
  /// a shelter computer on the same machine.
  static const sharePort = 8643;

  /// Called after a file was sent (its name), e.g. to count on screen.
  void Function(String file)? onBlobServed;
  static const _maxQuestionChars = 500;

  HttpServer? _server;
  ServerSocket? _socket;
  Future<void> _queue = Future.value();
  int answered = 0;

  /// Questions waiting or being answered, in all and by address.
  int _questions = 0;
  final _byPhone = <String, int>{};

  /// The port actually bound (useful with port 0 in tests).
  int get port => _server!.port;

  Future<void> start({int port = defaultPort, InternetAddress? address}) async {
    final socket = await ServerSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _socket = socket;
    late final HttpServer server;
    // HttpServer has no limit of its own: connections over the limit are
    // closed before it sees them.
    final limited = _LimitedSocket(
      socket,
      socket.where((s) {
        if (server.connectionsInfo().total < maxConnections) return true;
        s.destroy();
        return false;
      }),
    );
    server = HttpServer.listenOn(limited)
      ..idleTimeout = idleTimeout
      ..serverHeader = null;
    _server = server;
    server.listen(
      (req) => unawaited(_handle(req)),
      onError: (Object e) => _log('base_error', e),
    );
  }

  /// Closes every connection and frees the port.
  Future<void> stop() async {
    await _server?.close(force: true);
    await _socket?.close();
  }

  /// IPv4 addresses phones can use, e.g. 192.168.1.20: Wi-Fi and hotspot
  /// first, never mobile data (other phones cannot reach it).
  static Future<List<String>> localAddresses() async {
    final found = [
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal && !_cellular.hasMatch(i.name))
            (i.name, a.address),
    ];
    int rank((String, String) x) => _wifi.hasMatch(x.$1) ? 0 : 1;
    found.sort((a, b) => rank(a).compareTo(rank(b)));
    return [for (final (_, a) in found) a];
  }

  /// Interface names: Android mobile data (rmnet, ccmni), iOS (pdp_ip).
  static final _cellular = RegExp(r'^(rmnet|ccmni|pdp_ip|v4-rmnet)');

  /// Wi-Fi, hotspot and wired: Android wlan/swlan/ap, Apple en/bridge
  /// (Internet Sharing), Linux and Windows names.
  static final _wifi = RegExp(r'^(wlan|swlan|ap|en|bridge|eth|wl|Wi-Fi)');

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      if (req.method == 'GET' && req.uri.path == '/' && page != null) {
        res.headers.contentType = ContentType.html;
        res.headers.set('Cache-Control', 'no-cache');
        res.write(page);
        await _close(res);
      } else if (req.method == 'GET' && req.uri.path == '/web.json') {
        final lang = req.uri.queryParameters['lang'] ?? 'en';
        _send(
          res,
          200,
          webInfo(
            lang: appTextLang(lang),
            name: name,
            facts: facts?.current ?? const [],
            now: facts?.now ?? DateTime.now(),
            placeName: placeName,
          ),
        );
      } else if (req.method == 'GET' && req.uri.path == '/info') {
        final a = answerer;
        _send(res, 200, {
          'v': shelterProtocolVersion,
          'name': name,
          'answers': a != null,
          if (a != null) ...{
            'model': modelName,
            'package': a.package.id,
            'version': a.package.version,
            'answered': answered,
          },
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
          _blob.hasMatch(req.uri.path) &&
          library != null) {
        await _sendBlob(req, library!.blob(req.uri.pathSegments.last));
      } else if (req.method == 'POST' &&
          req.uri.path == '/ask' &&
          answerer != null) {
        await _ask(req);
      } else {
        _send(res, 404, {'error': 'not found'});
      }
    } on Object catch (e) {
      // The details stay in this computer's log.
      _log('base_error', e, req);
      _send(res, 500, {'error': 'something went wrong'});
    }
  }

  Future<void> _ask(HttpRequest req) async {
    final res = req.response;
    final phone = req.connectionInfo?.remoteAddress.address ?? '?';
    // Refused before the body is read: the connection closes after the
    // answer, so the rest of the body does not matter.
    if (_questions >= maxQuestions) {
      res.headers.set(HttpHeaders.retryAfterHeader, '30');
      return _refuse(res, 503, 'busy, try again soon');
    }
    if ((_byPhone[phone] ?? 0) >= maxQuestionsPerPhone) {
      return _refuse(res, 429, 'one question at a time');
    }
    // The place is taken before the body arrives, so questions sent at
    // the same moment cannot all pass the limits.
    _questions++;
    _byPhone[phone] = (_byPhone[phone] ?? 0) + 1;
    try {
      await _answer(req);
    } finally {
      _questions--;
      final n = _byPhone[phone]! - 1;
      if (n == 0) {
        _byPhone.remove(phone);
      } else {
        _byPhone[phone] = n;
      }
    }
  }

  Future<void> _answer(HttpRequest req) async {
    final res = req.response;
    final Object? j;
    try {
      final body = await _readBody(req).timeout(bodyTimeout);
      if (body == null) return _refuse(res, 413, 'question too large');
      j = jsonDecode(utf8.decode(body));
    } on TimeoutException {
      return _refuse(res, 408, 'question took too long to arrive');
    } on FormatException {
      return _send(res, 400, {'error': 'not a question'});
    }
    final q = j is Map ? j['question'] : null;
    if (q is! String || q.trim().isEmpty || q.length > _maxQuestionChars) {
      return _send(res, 400, {
        'error': 'question must be 1 to $_maxQuestionChars characters',
      });
    }
    // The browser page sends its language: it decides between
    // Latin-script languages (an English or Spanish question).
    final lang = (j as Map)['lang'];
    final answer = GroundedAnswer(
      q.trim(),
      appLang: appTextLang(lang is String ? lang : 'en'),
    );
    final waiting = Stopwatch()..start();
    var expired = false;
    // One model: run questions one after another.
    final done = _queue.then((_) async {
      // The phone has given up: do not keep the others waiting for it.
      if (waiting.elapsed > maxWait) {
        expired = true;
        return;
      }
      await answerer!.answer(answer, () {});
    });
    _queue = done.catchError((Object _) {});
    await done;
    if (expired) {
      res.headers.set(HttpHeaders.retryAfterHeader, '30');
      return _send(res, 503, {'error': 'busy, try again soon'});
    }
    answered++;
    _send(res, 200, {...answerToWire(answer), 'web': webAnswer(answer)});
  }

  /// The body, or null when it is larger than [maxBodyBytes].
  Future<List<int>?> _readBody(HttpRequest req) async {
    if (req.contentLength > maxBodyBytes) return null;
    final out = BytesBuilder(copy: false);
    await for (final chunk in req) {
      if (out.length + chunk.length > maxBodyBytes) return null;
      out.add(chunk);
    }
    return out.takeBytes();
  }

  /// An error for a request whose body was not read to the end: the
  /// connection closes after it.
  void _refuse(HttpResponse res, int status, String error) {
    res.persistentConnection = false;
    _send(res, status, {'error': error});
  }

  static final _blob = RegExp(r'^/blobs/sha256/[0-9a-f]{64}$');

  /// Streams a file, from a byte offset when the phone resumes
  /// (`Range: bytes=N-`): models are gigabytes, Wi-Fi drops.
  Future<void> _sendBlob(HttpRequest req, File? file) async {
    final res = req.response;
    if (file == null || !file.existsSync()) {
      _send(res, 404, {'error': 'not found'});
      return;
    }
    final size = file.lengthSync();
    // Only `bytes=N-` (what the app sends); anything else gets the whole
    // file. At most 18 digits, so the number always fits.
    final range = RegExp(
      r'^bytes=(\d{1,18})-$',
    ).firstMatch(req.headers.value(HttpHeaders.rangeHeader)?.trim() ?? '');
    final from = range == null ? 0 : int.parse(range[1]!);
    if (from > size) {
      res
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      await _close(res);
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
    try {
      await res.addStream(file.openRead(from));
      await res.close();
    } on Object catch (e) {
      // The phone went away, or the file could not be read half-way. The
      // headers are sent, so the connection just ends; the phone resumes.
      _log('blob_failed', e, req);
      try {
        (await res.detachSocket(writeHeaders: false)).destroy();
      } on Object {
        // Already closed.
      }
      return;
    }
    onBlobServed?.call(file.uri.pathSegments.last);
    // For whoever runs the shelter: what was passed on, to whom.
    debugPrint(
      'LYCHNION ${jsonEncode({'event': 'blob_served', 'file': file.uri.pathSegments.last, 'from_byte': from, 'bytes': size - from, 'to': req.connectionInfo?.remoteAddress.address})}',
    );
  }

  void _send(HttpResponse res, int status, Map<String, Object?> body) {
    try {
      res
        ..statusCode = status
        ..write(jsonEncode(body));
    } on StateError {
      // Headers already sent: nothing more can be said.
    }
    unawaited(_close(res));
  }

  /// Closes [res]; a phone that went away is not an error.
  static Future<void> _close(HttpResponse res) async {
    try {
      await res.close();
    } on Object {
      // The other side went away.
    }
  }

  /// For whoever runs the base: what went wrong, on this computer only.
  static void _log(String event, Object error, [HttpRequest? req]) {
    debugPrint(
      'LYCHNION ${jsonEncode({'event': event, 'path': ?req?.uri.path, 'error': '$error'})}',
    );
  }
}

/// A server socket that passes on only the connections its stream lets
/// through.
class _LimitedSocket extends StreamView<Socket> implements ServerSocket {
  _LimitedSocket(this._socket, super.stream);

  final ServerSocket _socket;

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;

  @override
  Future<ServerSocket> close() => _socket.close();
}
