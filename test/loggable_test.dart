// Release builds do not log questions, answers or the region
// (lychnion/lychnion#71): Android puts the app's log in logcat.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/dev_flags.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';

void main() {
  final answer = {
    'event': 'answer',
    'q': '津波が来たら？',
    'a': '高い所へ [1]。',
    'search_query': '津波 避難',
    'lang': 'ja',
    'retrieved': [
      {'id': 3, 'source': 'kantei-tsunami'},
    ],
    'alerts': ['tsunami'],
    'cited': [1],
    'gen_ms': 4200,
  };

  test('a release build leaves out the question, answer, search query and '
      'what matched', () {
    final out = loggable(answer, debug: false, logAnswers: false);
    expect(out.keys, unorderedEquals(['event', 'lang', 'gen_ms']));
    // What benchmarks need stays.
    expect(out['gen_ms'], 4200);
  });

  test('and the region', () {
    expect(
      loggable(
        {'event': 'region', 'region': 'JP-28'},
        debug: false,
        logAnswers: false,
      ),
      {'event': 'region'},
    );
  });

  test('an error keeps only its type', () {
    expect(
      loggable(
        {'event': 'base_failed', 'error': 'FormatException: 津波が来たら？'},
        debug: false,
        logAnswers: false,
      ),
      {'event': 'base_failed', 'error': 'FormatException'},
    );
  });

  test("a real answer's log line holds none of its texts", () {
    final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
    final a = GroundedAnswer('海の近くで強い揺れを感じました。')
      ..searchQuery = '地震 津波 海'
      ..alerts = pkg.alerts.take(1).toList()
      ..hits = [Hit(pkg.passages[3], 0.03)]
      ..text = '高い場所へ避難してください [1]。';
    final line = jsonEncode(
      loggable(
        {'event': 'answer', ...a.toJson()},
        debug: false,
        logAnswers: false,
      ),
    );
    for (final private in [
      '海の近くで',
      '高い場所へ',
      '地震 津波',
      pkg.passages[3].source.id,
    ]) {
      expect(line, isNot(contains(private)), reason: private);
    }
  });

  // A new field in an answer's log line must be sorted into private or
  // safe on purpose, or it would reach release logs unnoticed.
  test("every field of an answer's log line is known private or safe", () {
    const safe = {
      'lang',
      'answered_by',
      'base_unchecked',
      'base_unsigned',
      'base_refused',
      'judged_relevant',
      // Flags and citation numbers, no text.
      'invalid_citations',
      'grounded',
      'admits_gap',
      'no_source',
    };
    final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
    final a = GroundedAnswer('q')
      ..searchQuery = 's'
      ..answeredBy = 'Hall'
      ..baseUnchecked = true
      ..baseUnsigned = true
      ..baseRefused = true
      ..judgedRelevant = true
      ..alerts = pkg.alerts.take(1).toList()
      ..hits = [Hit(pkg.passages[3], 0.03)]
      ..text = 't [1]';
    final unknown = a.toJson().keys.where(
      (k) =>
          !privateLogKeys.contains(k) &&
          !safe.contains(k) &&
          !k.endsWith('_ms') &&
          k != 'stats',
    );
    expect(unknown, isEmpty, reason: 'sort these into private or safe');
  });

  test('a debug build, or LOG_ANSWERS / ASK / AUTO_BENCH, logs everything', () {
    expect(loggable(answer, debug: true, logAnswers: false), answer);
    expect(loggable(answer, debug: false, logAnswers: true), answer);
  });

  test('events without private keys are unchanged', () {
    final e = {'event': 'base_connected', 'name': 'Hall'};
    expect(loggable(e, debug: false, logAnswers: false), e);
  });
}
