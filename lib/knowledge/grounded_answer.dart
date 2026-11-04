import '../llm/local_llm.dart';
import 'hybrid_retriever.dart';
import 'knowledge_package.dart';
import 'retriever.dart';

const groundedSystemInstruction =
    'あなたは日本の防災とアウトドアの安全について答えるアシスタントです。'
    '必ず、与えられた資料に書かれていることだけを使って、日本語で短く答えてください。'
    '文の終わりに、根拠にした資料の番号を [1] のように付けてください。'
    '資料に答えが書かれていない場合は「資料に答えがありません」とだけ答えてください。'
    '自分の知識で補ったり、資料にない数字や手順を足したりしないでください。';

const noSourceText = '資料に答えがありません';

const groundedSystemInstructionEn =
    'You answer questions about disaster preparedness and outdoor safety in Japan. '
    'Use only what the given sources say. The sources are in Japanese; answer in short, plain English. '
    'End each sentence with the number of the source you used, like [1]. '
    'If the sources do not answer the question, reply only: "$noSourceTextEn". '
    'Do not add facts, numbers or steps that are not in the sources.';

const noSourceTextEn = 'No answer in the sources.';

final _japanese = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');

/// 'ja' if the question contains Japanese characters, otherwise 'en'.
String questionLanguage(String q) => _japanese.hasMatch(q) ? 'ja' : 'en';

/// What the app shows for one question.
class GroundedAnswer {
  GroundedAnswer(this.question) : lang = questionLanguage(question);

  final String question;
  final String lang;

  /// The Japanese search query used for an English question.
  String? searchQuery;
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

  bool get saysNoSource =>
      text.contains(noSourceText) ||
      text.toLowerCase().contains('no answer in the sources');

  /// The check the UI relies on: an answer without valid citations is not shown as fact.
  bool get isGrounded =>
      !saysNoSource && citedHits.isNotEmpty && invalidCitations.isEmpty;

  Map<String, Object?> toJson() => {
    'q': question,
    'lang': lang,
    if (searchQuery != null) 'search_query': searchQuery,
    'alerts': [for (final a in alerts) a.id],
    'retrieved': [
      for (final h in hits)
        {
          'id': h.passage.id,
          'source': h.passage.source.id,
          'score': double.parse(h.score.toStringAsFixed(4)),
          if (h is RankedHit) 'cos': double.parse(h.cosine.toStringAsFixed(3)),
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
  GroundedAnswerer(this.llm, this.package, {this.hybrid})
    : retriever = Retriever(package);

  final LocalLlm llm;
  final KnowledgePackage package;
  final Retriever retriever;

  /// Vector + keyword search; falls back to keywords only when null.
  final HybridRetriever? hybrid;

  /// Fills [answer] step by step; [onUpdate] is called as tokens arrive.
  Future<void> answer(GroundedAnswer answer, void Function() onUpdate) async {
    final q = answer.question;
    final en = answer.lang == 'en';
    // The package is Japanese: search with a Japanese version of the question.
    final search = en ? await _toJapanese(q) : q;
    if (en) answer.searchQuery = search;
    answer.alerts = package.alerts
        .where((a) => a.matches(q) || a.matches(search))
        .toList();
    answer.hits = hybrid != null
        ? await hybrid!.search(search)
        : retriever.search(search);
    onUpdate();
    if (answer.hits.isEmpty) {
      // Nothing relevant in the package: do not let the model guess.
      answer.text = en ? noSourceTextEn : noSourceText;
      onUpdate();
      return;
    }
    await llm.newChat(
      systemInstruction: en
          ? groundedSystemInstructionEn
          : groundedSystemInstruction,
    );
    await for (final t in llm.ask(
      _prompt(q, answer.hits, en),
      onDone: (s) => answer.stats = s,
    )) {
      answer.text += t;
      onUpdate();
    }
  }

  Future<String> _toJapanese(String question) async {
    await llm.newChat(
      systemInstruction:
          "Translate the user's question into natural Japanese. "
          'Reply with the Japanese question only, nothing else.',
      maxOutputTokens: 128,
    );
    final b = StringBuffer();
    await for (final t in llm.ask(question)) {
      b.write(t);
    }
    final ja = b.toString().trim();
    return ja.isEmpty ? question : ja;
  }

  static String _prompt(String question, List<Hit> hits, bool en) {
    final b = StringBuffer(en ? 'Sources:\n' : '資料:\n');
    for (var i = 0; i < hits.length; i++) {
      final p = hits[i].passage;
      b.writeln(
        '[${i + 1}] ${p.source.publisher}「${p.source.title}」${p.heading.isEmpty ? '' : ' / ${p.heading}'}',
      );
      b.writeln(p.text);
      b.writeln();
    }
    b.writeln(en ? 'Question: $question' : '質問: $question');
    return b.toString();
  }
}
