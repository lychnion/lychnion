import 'package:fieldkit/knowledge/knowledge_package.dart';
import 'package:fieldkit/knowledge/retriever.dart';
import 'package:fieldkit/spike/bench_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
  final retriever = Retriever(pkg);

  List<String> topSources(String q) => [
    for (final h in retriever.search(q)) h.passage.source.id,
  ];

  test('prints what each test question retrieves', () {
    for (final q in benchPrompts) {
      final hits = retriever.search(q);
      // ignore: avoid_print
      print(
        '$q\n  ${[for (final h in hits) '${h.passage.source.id}#${h.passage.id} ${h.score.toStringAsFixed(1)}'].join(', ')}'
        '\n  alerts: ${[for (final a in pkg.alerts)
          if (a.matches(q)) a.id]}',
      );
    }
  });

  test('finds the right source for questions the package covers', () {
    expect(topSources(benchPrompts[0]), contains('kantei-jishin'));
    expect(topSources(benchPrompts[1]).first, 'kantei-tsunami');
    expect(topSources(benchPrompts[2]), contains('kantei-sonae'));
    // The bear source is disabled (OCR mixed its columns).
    expect(topSources(benchPrompts[5]), isNot(contains('env-kuma')));
    expect(topSources(benchPrompts[6]).first, 'kantei-setsugai');
    expect(topSources(benchPrompts[7]), contains('fdma-shiketsu'));
  });

  test('tsunami safety line fires only near the sea', () {
    final tsunami = pkg.alerts.singleWhere((a) => a.id == 'tsunami-go-high');
    expect(tsunami.matches(benchPrompts[1]), isTrue);
    expect(tsunami.matches(benchPrompts[0]), isFalse);
    expect(tsunami.matches('山でクマに出会いました'), isFalse);
  });
}
