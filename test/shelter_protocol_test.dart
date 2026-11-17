import 'dart:convert';

import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/llm/local_llm.dart';
import 'package:lychnion/shelter/shelter_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');

  test('an answer survives the trip from shelter to phone', () {
    final tsunami = pkg.alerts.singleWhere((a) => a.id == 'tsunami-go-high');
    final sent = GroundedAnswer('海の近くで強い揺れを感じました。')
      ..alerts = [tsunami]
      ..hits = [Hit(pkg.passages[3], 0.03), Hit(pkg.passages[4], 0.02)]
      ..text = '高い場所へ避難してください [1]。'
      ..stats = AnswerStats(
        timeToFirstToken: const Duration(milliseconds: 400),
        total: const Duration(milliseconds: 1500),
        outputTokens: 30,
        inputTokens: 800,
        rssBytes: 5 * 1024 * 1024 * 1024,
      );

    // Through JSON text, as over the network.
    final wire =
        jsonDecode(jsonEncode(answerToWire(sent))) as Map<String, dynamic>;
    final got = answerFromWire(wire);

    expect(got.question, sent.question);
    expect(got.text, sent.text);
    expect(got.isGrounded, isTrue);
    expect(got.citedHits.single.passage.text, pkg.passages[3].text);
    expect(
      got.citedHits.single.passage.source.attribution,
      pkg.passages[3].source.attribution,
    );
    expect(got.alerts.single.text, tsunami.text);
    expect(got.alerts.single.textEn, tsunami.textEn);
    expect(got.stats!.inputTokens, 800);
  });

  test('refuses other protocol versions', () {
    expect(() => answerFromWire({'v': 99}), throwsFormatException);
  });
}
