import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/knowledge/subjects.dart';
import 'package:lychnion/shelter/shelter_protocol.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';

void main() {
  final firstAid = KnowledgePackage.open(
    'assets/packages/intl.firstaid.basics.sqlite',
  );
  final all = KnowledgePackage.merge([
    KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite'),
    KnowledgePackage.open('assets/packages/jp.outdoor.hiking.sqlite'),
    firstAid,
  ]);
  final r = Retriever(all);
  List<String> sources(String q) => [
    for (final h in sameAnimal([q], r.search(q, minScore: 0)))
      h.passage.source.id,
  ];

  test('all sources are from the US and labelled as foreign', () {
    expect(firstAid.sources.values.map((s) => s.region).toSet(), {'US'});
    for (final s in firstAid.sources.values) {
      expect(foreignLabel(s, 'JP', lang: 'ja'), '海外の資料（米国）');
    }
  });

  test('no US emergency numbers, no rabies, no wrong temperature', () {
    for (final p in firstAid.passages) {
      expect(p.text, isNot(contains('911')));
      expect(p.text.toLowerCase(), isNot(contains('rabies')));
      expect(p.text, isNot(contains('5.68')));
    }
  });

  test('snake bites now find first aid, about snakes', () {
    final s = sources('ヘビにかまれたらどうする？');
    expect(s, isNotEmpty);
    expect(s, everyElement('army-atp-4-02-11'));
  });

  test('hypothermia and frostbite find the cold weather manual', () {
    expect(sources('低体温症の手当は？'), contains('army-tc-21-3'));
    expect(sources('凍傷になったらどうする？'), contains('army-tc-21-3'));
  });

  test('ticks: the Japanese sources still come first', () {
    final s = sources('マダニに刺されたらどうすればいい？');
    expect(s.first, anyOf('mhlw-sfts-qa', 'rinya-dani'));
  });

  test('every passage is translated and keeps its original', () {
    for (final p in firstAid.passages) {
      expect(p.translated, isTrue);
      expect(questionLanguage(p.text), 'ja', reason: p.text);
      expect(questionLanguage(p.original!), 'en', reason: p.original);
    }
    // The snakebite bandage keeps its limit.
    expect(firstAid.passages.map((p) => p.text).join(), contains('きつく締めすぎない'));
  });

  test('the original travels from shelter to phone', () {
    final a = GroundedAnswer('ヘビにかまれたら？')
      ..hits = [Hit(firstAid.passages.first, 1)];
    final back = answerFromWire(answerToWire(a));
    expect(back.hits.single.passage.original, firstAid.passages.first.original);
  });

  test('English questions read the original, Japanese the translation', () {
    final p = firstAid.passages.first;
    expect(p.textIn('en'), p.original);
    expect(p.textIn('ja'), p.text);
    expect(p.textIn('es'), p.text); // no Spanish: the package's own text
  });

  test('per-language texts travel from shelter to phone', () {
    final a = GroundedAnswer('Snake bite?')
      ..hits = [Hit(firstAid.passages.first, 1)];
    final back = answerFromWire(answerToWire(a)).hits.single.passage;
    expect(back.textIn('en'), firstAid.passages.first.original);
  });
}
