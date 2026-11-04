import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../facts/fact.dart';
import '../knowledge/grounded_answer.dart';
import 'shelter_protocol.dart';

/// Asks a shelter computer on the local network (see ShelterServer).
class ShelterClient {
  ShelterClient(this.baseUrl);

  /// For example http://192.168.1.20:8642
  final String baseUrl;
  String? name;

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  /// Checks that the shelter is reachable and remembers its name.
  Future<Map<String, dynamic>> info() async {
    final j = await _json('GET', '/info', timeout: const Duration(seconds: 5));
    name = j['name'] as String?;
    return j;
  }

  /// The shelter's current facts (shelter status, blocked roads, warnings).
  Future<List<Fact>> facts() async {
    final j = await _json(
      'GET',
      '/facts',
      timeout: const Duration(seconds: 10),
    );
    return [
      for (final f in (j['facts'] as List).cast<Map<String, dynamic>>())
        Fact.fromJson(f),
    ];
  }

  /// The shelter's answer. Throws on network errors or timeouts, so the
  /// caller can fall back to the phone's own model.
  Future<GroundedAnswer> ask(String question) async {
    final j = await _json(
      'POST',
      '/ask',
      body: {'question': question},
      timeout: const Duration(minutes: 2),
    );
    return answerFromWire(j);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
    required Duration timeout,
  }) async {
    final req = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout);
    final text = await utf8.decodeStream(res).timeout(timeout);
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw HttpException('shelter: ${res.statusCode} ${j['error']}');
    }
    return j;
  }

  void close() => _http.close(force: true);
}
