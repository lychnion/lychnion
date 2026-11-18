import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../download/publisher_list.dart' show cleanShownText;
import '../facts/fact.dart';
import '../knowledge/grounded_answer.dart';
import 'answer_signing.dart';
import 'base_protocol.dart';

/// Asks a base computer on the local network (see BaseServer).
///
/// Anything on the Wi-Fi can claim to be a base, so nothing it sends is
/// trusted: every answer is size and time limited, and what does not look
/// like the protocol throws ([FormatException], [HttpException],
/// [TimeoutException]), so the phone answers itself instead.
class BaseClient {
  BaseClient(this.url);

  /// For example http://192.168.1.20:8642
  final String url;

  /// The base's name, cleaned for showing (at most 60 characters).
  String? name;

  /// /info is a few hundred bytes.
  static const maxInfoBytes = 16 * 1024;

  /// An answer, or a base's facts: a few kilobytes, rarely more.
  static const maxBodyBytes = 1 << 20;

  /// Facts taken from one pull; a base never has this many.
  static const maxFacts = 500;

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 5);

  /// Checks that the base is reachable and remembers its name.
  Future<Map<String, dynamic>> info() async {
    final j = await _json(
      'GET',
      '/info',
      timeout: const Duration(seconds: 5),
      maxBytes: maxInfoBytes,
    );
    final n = j['name'];
    name = cleanShownText(n is String ? n : null);
    return j;
  }

  /// The base's current facts (shelter status, blocked roads, warnings).
  /// Facts that are not well formed are left out.
  Future<List<Fact>> facts() async {
    final j = await _json(
      'GET',
      '/facts',
      timeout: const Duration(seconds: 10),
    );
    final raw = j['facts'];
    if (raw is! List) throw const FormatException('base: no facts');
    final out = <Fact>[];
    for (final f in raw.take(maxFacts)) {
      try {
        out.add(Fact.fromJson((f as Map).cast<String, dynamic>()));
      } on Object {
        // Not a fact (TypeError, FormatException, ArgumentError).
      }
    }
    return out;
  }

  /// The base's answer. Throws on network errors or timeouts, so the
  /// caller can fall back to the phone's own model.
  ///
  /// With [pinnedKey] (the key from the base's QR code) the answer must be
  /// signed by that key for this question, or [BadAnswerSignature] is
  /// thrown. An answer without a signature (an older base) comes back
  /// with [GroundedAnswer.baseUnsigned], unless [requireSignature] (this
  /// base has signed before: someone took the signature off on the way).
  Future<GroundedAnswer> ask(
    String question, {
    String? pinnedKey,
    bool requireSignature = false,
  }) async {
    final nonce = newAnswerNonce();
    final (j, sent, body, signature) = await _request(
      'POST',
      '/ask',
      body: {'question': question, 'nonce': nonce},
      timeout: const Duration(minutes: 2),
      maxBytes: maxBodyBytes,
    );
    final answer = answerFromWire(j);
    if (pinnedKey == null) return answer;
    switch (await checkAnswerSignature(
      header: signature,
      nonce: nonce,
      request: sent,
      body: body,
      pinnedKey: pinnedKey,
    )) {
      case AnswerSignature.bad:
        throw const BadAnswerSignature('bad signature');
      case AnswerSignature.missing when requireSignature:
        throw const BadAnswerSignature('signature missing');
      case AnswerSignature.missing:
        return answer..baseUnsigned = true;
      case AnswerSignature.valid:
        return answer;
    }
  }

  /// One request; [timeout] covers all of it, [maxBytes] the body.
  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
    required Duration timeout,
    int maxBytes = maxBodyBytes,
  }) async => (await _request(
    method,
    path,
    body: body,
    timeout: timeout,
    maxBytes: maxBytes,
  )).$1;

  /// One request: the decoded answer, the request body as sent, the
  /// answer's bytes as received, and the base's answer signature if it
  /// sent one.
  Future<(Map<String, dynamic>, List<int>, Uint8List, String?)> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    required Duration timeout,
    required int maxBytes,
  }) async {
    final sent = body == null ? const <int>[] : utf8.encode(jsonEncode(body));
    final (int, Uint8List, String?) got;
    final pending = _Pending();
    try {
      got = await _fetch(
        method,
        path,
        body == null ? null : sent,
        maxBytes,
        pending,
      ).timeout(timeout);
    } on TimeoutException {
      // The request may still be open (a base that sends slowly or not
      // at all): end this one only. Others (an answer while facts are
      // pulled) go on.
      pending.cancel();
      rethrow;
    }
    final (status, bytes, signature) = got;
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw HttpException('base: $status, not an answer');
    }
    if (j is! Map<String, dynamic>) {
      throw HttpException('base: $status, not an answer');
    }
    if (status != 200) {
      // The base's own words, cleaned: they are shown and logged.
      final e = j['error'];
      throw HttpException(
        'base: $status ${cleanShownText(e is String ? e : null) ?? ''}'.trim(),
      );
    }
    return (j, sent, bytes, signature);
  }

  Future<(int, Uint8List, String?)> _fetch(
    String method,
    String path,
    List<int>? body,
    int maxBytes,
    _Pending pending,
  ) async {
    final req = await _http.openUrl(method, Uri.parse('$url$path'));
    pending.request = req;
    // Timed out while connecting: not sent at all.
    if (pending.cancelled) req.abort();
    req.followRedirects = false;
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(body);
    }
    final res = await req.close();
    if (res.contentLength > maxBytes) {
      // Not read, not kept open: the connection is closed at once.
      (await res.detachSocket()).destroy();
      throw HttpException('base: answer too large');
    }
    final out = BytesBuilder(copy: false);
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = res.listen(
      (chunk) {
        if (out.length + chunk.length > maxBytes) {
          unawaited(sub.cancel());
          done.completeError(HttpException('base: answer too large'));
          return;
        }
        out.add(chunk);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    // A timeout cancels this: the connection closes, not kept waiting.
    pending.response = sub;
    if (pending.cancelled) unawaited(sub.cancel());
    await done.future;
    return (
      res.statusCode,
      out.takeBytes(),
      // Sent more than once: never one valid signature, and never a
      // throw (HttpHeaders.value would throw on a list).
      res.headers[answerSignatureHeader]?.join(','),
    );
  }

  void close() => _http.close(force: true);
}

/// One request in flight, so a timeout can end just that one.
class _Pending {
  HttpClientRequest? request;
  StreamSubscription<List<int>>? response;
  var cancelled = false;

  void cancel() {
    cancelled = true;
    request?.abort();
    unawaited(response?.cancel());
  }
}
