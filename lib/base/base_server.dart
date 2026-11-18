import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../app/lang.dart' show appTextLang;
import '../facts/compact_codec.dart';
import '../facts/fact_store.dart';
import '../facts/signing.dart';
import '../knowledge/grounded_answer.dart';
import 'base_library.dart';
import 'base_protocol.dart';
import 'base_web.dart';
import 'watched_socket.dart';

/// Answers questions from phones on the base's local network.
///
/// GET /       → a page for phones without the app (assets/web/base.html)
/// GET /web.json?lang=ja → that page's texts and the current facts
/// GET /info  → {name, model, package, version}
/// GET /facts → current facts (JSON, or ?compact=1 for radio-sized messages)
/// POST /ask  {"question": "…"} → an answer (base_protocol.dart)
/// GET /catalog.json        → signed records of what this base has
/// GET `/blobs/sha256/<hash>` → one of those files (resumable with Range)
///
/// No login: anyone on the base Wi-Fi may ask. One model, so questions
/// are answered one after another.
///
/// Anyone on the Wi-Fi can also send anything, so every request has
/// limits: at most [maxConnections] connections, idle ones close after
/// [idleTimeout], a question is at most [maxBodyBytes] and must arrive
/// within [bodyTimeout], at most [maxQuestions] wait for the model and
/// [maxQuestionsPerPhone] per address, and a question that waited longer
/// than the phone waits ([maxWait]) is dropped. A question whose phone
/// closed the connection is dropped too, and its answer stopped when the
/// model is on it already. Errors say what was wrong
/// in a few words, never the exception (paths, internals).
///
/// Without an [answerer] it only passes on files: a phone sharing its
/// downloads with phones nearby (`sharePort`, no /ask, no page).
class BaseServer {
  BaseServer({
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
    this.sendStall = const Duration(seconds: 30),
  });

  /// A shelter's name from its ID (the map's evacuation sites), for the
  /// browser page. Null when there is no map.
  final String? Function(String id)? placeName;

  /// The page for phones without the app (HTML), or null for none.
  final String? page;

  /// Packages, maps and models passed on to phones (null: none).
  final BaseLibrary? library;

  /// Current facts the base shares with phones (GET /facts).
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

  /// The phone gives up after 2 minutes (BaseClient.ask): a question
  /// that waited this long for the model is not answered any more, and
  /// no longer counts for the limits (its phone may ask again). It is
  /// less than 2 minutes, so an answer started just before has time.
  final Duration maxWait;

  /// A download that cannot send anything for this long (the phone
  /// stopped reading) is closed; a slow one goes on as long as data
  /// moves. Other responses (small) must be sent within this in all.
  /// [idleTimeout] does not cover a response being sent.
  final Duration sendStall;

  static const defaultPort = 8642;

  /// A phone sharing its downloads: another port, so it never clashes with
  /// a base computer on the same machine.
  static const sharePort = 8643;

  /// Called after a file was sent (its name), e.g. to count on screen.
  void Function(String file)? onBlobServed;
  static const _maxQuestionChars = 500;

  HttpServer? _server;
  ServerSocket? _socket;
  Future<void> _queue = Future.value();
  int answered = 0;

  /// Questions taken in, until they are answered or dropped.
  final _questions = <_Question>[];

  /// Questions that count for the limits: being answered, or waiting
  /// and their phone still waits. With [phone], only that address's.
  int _live([String? phone]) => _questions
      .where((q) => q.live(maxWait) && (phone == null || q.phone == phone))
      .length;

  /// Questions that count for the limits now.
  @visibleForTesting
  int get questionsWaiting => _live();

  /// Open connections by the phone's address and port, to tell when the
  /// phone of a question has gone.
  final _connections = <String, WatchedSocket>{};

  static String _connKey(InternetAddress a, int port) => '${a.address}:$port';

  Socket _watch(Socket s) {
    final w = WatchedSocket(s);
    final key = _connKey(s.remoteAddress, s.remotePort);
    _connections[key] = w;
    unawaited(
      w.gone.then((_) {
        if (identical(_connections[key], w)) _connections.remove(key);
      }),
    );
    return w;
  }

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
      socket
          .where((s) {
            if (server.connectionsInfo().total < maxConnections) return true;
            s.destroy();
            return false;
          })
          .map<Socket>(_watch),
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
          'v': baseProtocolVersion,
          'name': name,
          'answers': a != null,
          if (a != null) ...{
            'model': modelName,
            'package': a.package.id,
            'version': a.package.version,
            'answered': answered,
          },
          // Phones trust this key for the facts the base signs.
          'key': ?facts?.signer?.publicKeyText,
        });
      } else if (req.method == 'GET' && req.uri.path == '/facts') {
        // All unexpired facts, so phones apply the same conflict rules.
        final all = facts?.all ?? const [];
        if (req.uri.queryParameters['compact'] == '1' && codec != null) {
          final FactSigner? signer = facts?.signer;
          _send(res, 200, {
            'v': baseProtocolVersion,
            'messages': signer == null
                ? codec!.pack(all)
                : await signer.packSigned(codec!, all),
          });
        } else {
          _send(res, 200, {
            'v': baseProtocolVersion,
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
    final phone = req.connectionInfo?.remoteAddress.address ?? '?';
    // Questions whose phone gave up wait for their turn to be dropped;
    // a hard limit keeps them from piling up while the model is busy.
    if (_live() >= maxQuestions || _questions.length >= 4 * maxQuestions) {
      req.response.headers.set(HttpHeaders.retryAfterHeader, '30');
      return _refuse(req, 503, 'busy, try again soon');
    }
    if (_live(phone) >= maxQuestionsPerPhone) {
      return _refuse(req, 429, 'one question at a time');
    }
    // The place is taken before the body arrives, so questions sent at
    // the same moment cannot all pass the limits.
    final question = _Question(phone);
    final info = req.connectionInfo;
    if (info != null) {
      final gone =
          _connections[_connKey(info.remoteAddress, info.remotePort)]?.gone;
      if (gone == null) {
        // Every connection is watched until it ends: this one has ended
        // already (the phone sent its question and closed at once).
        question.left = true;
      } else {
        unawaited(
          gone.then((_) {
            question.left = true;
            // On it already: stop the model, the answer goes nowhere.
            // The model is shared with this computer's own Ask page; the
            // queue keeps phones' questions apart, not that page's.
            if (question.running) unawaited(answerer?.llm.stop());
          }),
        );
      }
    }
    _questions.add(question);
    try {
      await _answer(req, question);
    } finally {
      _questions.remove(question);
    }
  }

  Future<void> _answer(HttpRequest req, _Question question) async {
    final res = req.response;
    final Object? j;
    try {
      final body = await _readBody(req).timeout(bodyTimeout);
      if (body == null) {
        // Read in part when its size was not given beforehand.
        return _refuse(
          req,
          413,
          'question too large',
          bodyRead: req.contentLength <= maxBodyBytes,
        );
      }
      j = jsonDecode(utf8.decode(body));
    } on TimeoutException {
      return _refuse(
        req,
        408,
        'question took too long to arrive',
        bodyRead: true,
      );
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
    var expired = false;
    // One model: run questions one after another.
    final done = _queue.then((_) async {
      // The phone has given up: do not keep the others waiting for it.
      if (!question.live(maxWait)) {
        expired = true;
        return;
      }
      question.started = true;
      question.running = true;
      try {
        await answerer!.answer(answer, () {
          // Called as passages are found and as words arrive: nothing
          // after this runs for a phone that left (a stop that came
          // while passages were searched stopped nothing).
          if (question.left) {
            unawaited(answerer!.llm.stop());
            throw const _Left();
          }
        });
      } on _Left {
        // Ended on purpose: see below.
      } finally {
        question.running = false;
      }
    });
    _queue = done.catchError((Object _) {});
    await done;
    if (question.left) {
      _log('base_question_left', 'phone closed the connection', req);
      // Ended, so the connection is let go of (HttpServer keeps it open
      // until the response is closed, and it counts for the limit).
      return _close(res);
    }
    if (expired) {
      res.headers.set(HttpHeaders.retryAfterHeader, '30');
      return _send(res, 503, {'error': 'busy, try again soon'});
    }
    answered++;
    _send(res, 200, {...answerToWire(answer), 'web': webAnswer(answer)});
  }

  /// The body, or null when it is larger than [maxBodyBytes]. Not read
  /// at all when its Content-Length says so already.
  Future<List<int>?> _readBody(HttpRequest req) async {
    if (req.contentLength > maxBodyBytes) return null;
    final out = BytesBuilder(copy: false);
    await for (final chunk in req) {
      if (out.length + chunk.length > maxBodyBytes) return null;
      out.add(chunk);
    }
    return out.takeBytes();
  }

  /// Reads and drops the body when it is at most [_readBeforeError]
  /// bytes and arrives within [bodyTimeout]; false (and stops reading)
  /// otherwise. Phones send questions without a length (chunked), so the
  /// size is counted while it arrives.
  Future<bool> _readSmall(HttpRequest req) async {
    if (req.contentLength > _readBeforeError) {
      await req.listen(null).cancel();
      return false;
    }
    var n = 0;
    final done = Completer<bool>();
    late final StreamSubscription<List<int>> sub;
    sub = req.listen(
      (chunk) {
        n += chunk.length;
        if (n > _readBeforeError && !done.isCompleted) done.complete(false);
      },
      onError: (Object _) => done.isCompleted ? null : done.complete(false),
      onDone: () => done.isCompleted ? null : done.complete(true),
      cancelOnError: true,
    );
    final small = await done.future.timeout(
      bodyTimeout,
      onTimeout: () => false,
    );
    if (!small) await sub.cancel();
    return small;
  }

  /// A body up to this size is read before an error, so the phone gets
  /// the error (HTTP reads a body before it can answer).
  static const _readBeforeError = 64 * 1024;

  /// An error for a request whose body was not read (or not to the end):
  /// the connection closes after it. A small body is read first, within
  /// [bodyTimeout], so the error arrives. A large or endless one is not:
  /// the connection just ends, and the phone falls back on its own.
  Future<void> _refuse(
    HttpRequest req,
    int status,
    String error, {
    bool bodyRead = false,
  }) async {
    final res = req.response..persistentConnection = false;
    if (!bodyRead && !await _readSmall(req)) return _close(res);
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
    // Taken now: it is gone once the connection closes.
    final to = req.connectionInfo?.remoteAddress.address;
    try {
      // Chunk by chunk, each with a fresh deadline. When a chunk cannot
      // be sent in time the connection is closed, but flush does not
      // throw: the closed connection shows as no connectionInfo.
      await for (final chunk in file.openRead(from)) {
        res
          ..deadline = sendStall
          ..add(chunk);
        await res.flush();
        if (res.connectionInfo == null) {
          _log('blob_stalled', 'closed after no progress', req);
          return;
        }
      }
      res.deadline = sendStall;
      _closed[res] = true;
      // Sent. The connection may be closed by now, when the phone asked
      // for that (Connection: close, HTTP/1.0): that is not a stall.
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
    try {
      onBlobServed?.call(file.uri.pathSegments.last);
    } on Object catch (e) {
      _log('blob_served_callback', e, req);
    }
    // For whoever runs the base: what was passed on, to whom.
    debugPrint(
      'LYCHNION ${jsonEncode({'event': 'blob_served', 'file': file.uri.pathSegments.last, 'from_byte': from, 'bytes': size - from, 'to': to})}',
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

  /// Responses closed already: a second close must not set a deadline,
  /// which nothing would clear and which would end the connection while
  /// it serves the next request.
  final _closed = Expando<bool>();

  /// Closes [res]; a phone that went away is not an error. A phone that
  /// does not read the response loses the connection after [sendStall].
  Future<void> _close(HttpResponse res) async {
    if (_closed[res] ?? false) return;
    _closed[res] = true;
    try {
      res.deadline = sendStall;
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

/// Thrown to end an answer whose phone has left.
class _Left implements Exception {
  const _Left();
}

/// A question taken in by the base.
class _Question {
  _Question(this.phone);

  /// The phone's address.
  final String phone;
  final _waiting = Stopwatch()..start();

  /// The model was given it.
  var started = false;

  /// The model is on it now.
  var running = false;

  /// Its phone closed the connection.
  var left = false;

  /// Whether it counts: its phone is still there, and it is being
  /// answered or its phone still waits.
  bool live(Duration maxWait) =>
      !left && (started || _waiting.elapsed <= maxWait);
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
