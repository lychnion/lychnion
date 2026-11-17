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

  /// Name of the shelter computer that answered, if not this device.
  String? answeredBy;

  /// Result of the relevance check: false means the passages are related but
  /// do not answer the question, so no answer was generated.
  bool? judgedRelevant;

  bool get relatedOnly => judgedRelevant == false;

  /// The answer itself says part of the question is not in the sources
  /// (e.g. 「対処法についての記載はありません」). Spike 4: this caught the
  /// near-topic answers that the yes/no check missed.
  bool get admitsGap => isGrounded && _gap.hasMatch(text);

  static final _gap = RegExp(
    r'(記述|記載|情報|説明)(は|が)?(資料に)?(ありません|ない)|(記載|記述)されていません|書かれていません|書かれていない|資料にはありません'
    r'|not (mention|state|say|contain|cover)|do(es)? not (mention|state|say|contain|cover)|no information',
    caseSensitive: false,
  );
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
    if (answeredBy != null) 'answered_by': answeredBy,
    if (judgedRelevant != null) 'judged_relevant': judgedRelevant,
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
    'admits_gap': admitsGap,
    'no_source': saysNoSource || hits.isEmpty,
    ...?stats?.toJson(),
  };
}

class GroundedAnswerer {
  GroundedAnswerer(
    this.llm,
    this.package, {
    this.hybrid,
    this.checkRelevance = false,
    this.topK = 4,
  }) : retriever = Retriever(package);

  /// How many passages the model reads. Reading is the slow part on phones.
  final int topK;

  /// Ask the model first whether the passages answer the question at all.
  final bool checkRelevance;

  final LocalLlm llm;
  final KnowledgePackage package;
  final Retriever retriever;

  /// Vector + keyword search; falls back to keywords only when null.
  final HybridRetriever? hybrid;

  /// Where the user is (ISO 3166, e.g. 'JP' or 'JP-13'): more local
  /// sources rank a little higher, foreign ones are labelled.
  String userRegion = 'JP';

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
    retriever.userRegion = userRegion;
    hybrid?.userRegion = userRegion;
    answer.hits = hybrid != null
        ? await hybrid!.search(search, limit: topK)
        : retriever.search(search, limit: topK);
    onUpdate();
    if (answer.hits.isEmpty) {
      // Nothing relevant in the package: do not let the model guess.
      answer.text = en ? noSourceTextEn : noSourceText;
      onUpdate();
      return;
    }
    if (checkRelevance) {
      answer.judgedRelevant = await _answersQuestion(search, answer.hits);
      if (answer.relatedOnly) {
        // Related but not an answer: show the passages, do not generate.
        answer.text = en ? noSourceTextEn : noSourceText;
        onUpdate();
        return;
      }
    }
    await llm.newChat(
      systemInstruction: en
          ? groundedSystemInstructionEn
          : groundedSystemInstruction,
    );
    await for (final t in llm.ask(
      _prompt(q, answer.hits, en, userRegion: userRegion),
      onDone: (s) => answer.stats = s,
    )) {
      answer.text += t;
      onUpdate();
    }
  }

  /// Short yes/no call. Always in Japanese: the passages are Japanese and
  /// English questions are already translated for the search.
  Future<bool> _answersQuestion(String question, List<Hit> hits) async {
    await llm.newChat(
      systemInstruction:
          'あなたは、資料が質問に答えているかを判定します。'
          '「はい」か「いいえ」だけで答えてください。',
      maxOutputTokens: 8,
    );
    final b =
        StringBuffer(_prompt(question, hits, false, userRegion: userRegion))
          ..writeln()
          ..writeln(
            'この資料を使って、この質問に答えられますか？'
            '資料が質問と違う状況について書いている場合'
            '（例：出会わないための予防策しかなく、出会ったときの対処がない。'
            '別の災害や別の場所の話。）は「いいえ」です。'
            '一部でも質問に答えられる場合は「はい」です。'
            '「はい」か「いいえ」だけで答えてください。',
          );
    final reply = StringBuffer();
    await for (final t in llm.ask(b.toString())) {
      reply.write(t);
    }
    final r = reply.toString().toLowerCase();
    if (r.contains('いいえ') || r.startsWith('no')) return false;
    return true; // "はい", or unclear: do not block the answer
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

  static String _prompt(
    String question,
    List<Hit> hits,
    bool en, {
    String userRegion = 'JP',
  }) {
    final b = StringBuffer(en ? 'Sources:\n' : '資料:\n');
    var foreign = false;
    for (var i = 0; i < hits.length; i++) {
      final p = hits[i].passage;
      final label = foreignLabel(p.source, userRegion, en: en);
      foreign |= label != null;
      b.writeln(
        '[${i + 1}] ${p.source.publisher}「${p.source.title}」'
        '${p.heading.isEmpty ? '' : ' / ${p.heading}'}'
        '${label == null ? '' : ' [$label]'}',
      );
      b.writeln(p.text);
      b.writeln();
    }
    if (foreign) {
      // Combine both; only where they disagree does the local one win.
      b.writeln(
        en
            ? 'Some sources are from abroad. Combine all sources. Where a '
                  'Japanese source and a foreign one disagree, follow the '
                  'Japanese one. Do not take phone numbers, laws or services '
                  'from foreign sources.'
            : '海外の資料も含まれています。すべての資料を組み合わせて答えてください。'
                  '日本の資料と海外の資料の内容が違う場合は、日本の資料に従ってください。'
                  '電話番号、法律、窓口などは海外の資料から使わないでください。',
      );
      b.writeln();
    }
    b.writeln(en ? 'Question: $question' : '質問: $question');
    return b.toString();
  }
}
