import '../llm/local_llm.dart';
import 'knowledge_package.dart';
import 'retriever.dart';

const groundedSystemInstruction =
    'あなたは日本の防災とアウトドアの安全について答えるアシスタントです。'
    '必ず、与えられた資料に書かれていることだけを使って、日本語で短く答えてください。'
    '文の終わりに、根拠にした資料の番号を [1] のように付けてください。'
    '資料に答えが書かれていない場合は「資料に答えがありません」とだけ答えてください。'
    '自分の知識で補ったり、資料にない数字や手順を足したりしないでください。';

const noSourceText = '資料に答えがありません';

/// What the app shows for one question.
class GroundedAnswer {
  GroundedAnswer(this.question);

  final String question;
  List<Alert> alerts = [];
  List<Hit> hits = [];
  String text = '';
  AnswerStats? stats;

  /// Passage numbers (1-based, as given to the model) that the answer cites.
  Set<int> get citedNumbers => {
    for (final m in RegExp(r'\[(\d+)\]').allMatches(text))
      int.parse(m.group(1)!),
  };

  /// Citations that point to a passage the model was not given.
  Set<int> get invalidCitations =>
      citedNumbers.where((n) => n < 1 || n > hits.length).toSet();

  List<Hit> get citedHits => [
    for (final n in citedNumbers.toList()..sort())
      if (n >= 1 && n <= hits.length) hits[n - 1],
  ];

  bool get saysNoSource => text.contains(noSourceText);

  /// The check the UI relies on: an answer without valid citations is not shown as fact.
  bool get isGrounded =>
      !saysNoSource && citedHits.isNotEmpty && invalidCitations.isEmpty;

  Map<String, Object?> toJson() => {
    'q': question,
    'alerts': [for (final a in alerts) a.id],
    'retrieved': [
      for (final h in hits)
        {
          'id': h.passage.id,
          'source': h.passage.source.id,
          'score': double.parse(h.score.toStringAsFixed(1)),
        },
    ],
    'a': text,
    'cited': citedNumbers.toList()..sort(),
    'invalid_citations': invalidCitations.toList(),
    'grounded': isGrounded,
    'no_source': saysNoSource || hits.isEmpty,
    ...?stats?.toJson(),
  };
}

class GroundedAnswerer {
  GroundedAnswerer(this.llm, this.package) : retriever = Retriever(package);

  final LocalLlm llm;
  final KnowledgePackage package;
  final Retriever retriever;

  /// Fills [answer] step by step; [onUpdate] is called as tokens arrive.
  Future<void> answer(GroundedAnswer answer, void Function() onUpdate) async {
    final q = answer.question;
    answer.alerts = package.alerts.where((a) => a.matches(q)).toList();
    answer.hits = retriever.search(q);
    onUpdate();
    if (answer.hits.isEmpty) {
      // Nothing relevant in the package: do not let the model guess.
      answer.text = noSourceText;
      onUpdate();
      return;
    }
    await llm.newChat(systemInstruction: groundedSystemInstruction);
    await for (final t in llm.ask(
      _prompt(q, answer.hits),
      onDone: (s) => answer.stats = s,
    )) {
      answer.text += t;
      onUpdate();
    }
  }

  static String _prompt(String question, List<Hit> hits) {
    final b = StringBuffer('資料:\n');
    for (var i = 0; i < hits.length; i++) {
      final p = hits[i].passage;
      b.writeln(
        '[${i + 1}] ${p.source.publisher}「${p.source.title}」${p.heading.isEmpty ? '' : ' / ${p.heading}'}',
      );
      b.writeln(p.text);
      b.writeln();
    }
    b.writeln('質問: $question');
    return b.toString();
  }
}
