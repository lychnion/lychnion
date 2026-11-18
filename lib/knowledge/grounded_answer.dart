import '../llm/local_llm.dart';
import 'hybrid_retriever.dart';
import 'knowledge_package.dart';
import 'retriever.dart';
import 'language.dart';
import 'subjects.dart';

export 'language.dart' show questionLanguage, pick;

/// Everything the answerer says to the model or the user, by language.
/// A language without its own entry uses English, told to answer in the
/// question's language (better: add an entry, and package texts for it).
class AnswerTexts {
  const AnswerTexts({
    required this.instruction,
    required this.noSource,
    required this.sources,
    required this.question,
    required this.foreignNote,
  });

  final String instruction, noSource, sources, question, foreignNote;

  static AnswerTexts of(String lang) =>
      _texts[lang] ??
      AnswerTexts(
        instruction:
            '${_texts['en']!.instruction} Answer in the language of the '
            'question (language code "$lang").',
        noSource: _texts['en']!.noSource,
        sources: _texts['en']!.sources,
        question: _texts['en']!.question,
        foreignNote: _texts['en']!.foreignNote,
      );

  /// Every "no answer" text, to recognise it in any language.
  static Iterable<String> get allNoSource =>
      _texts.values.map((t) => t.noSource);
}

const _texts = <String, AnswerTexts>{
  'ja': AnswerTexts(
    instruction:
        'あなたは日本の防災とアウトドアの安全について答えるアシスタントです。'
        '必ず、与えられた資料に書かれていることだけを使って、日本語で答えてください。'
        'いちばん大切なことから、3文以内で短く答えてください。'
        '文の終わりに、根拠にした資料の番号を [1] のように付けてください。'
        '資料に答えが書かれていない場合は「資料に答えがありません」とだけ答えてください。'
        '自分の知識で補ったり、資料にない数字や手順を足したりしないでください。',
    noSource: '資料に答えがありません',
    sources: '資料',
    question: '質問',
    foreignNote:
        '海外の資料も含まれています。すべての資料を組み合わせて答えてください。'
        '日本の資料と海外の資料の内容が違う場合は、日本の資料に従ってください。'
        '電話番号、法律、窓口などは海外の資料から使わないでください。',
  ),
  'en': AnswerTexts(
    instruction:
        'You answer questions about disaster preparedness and outdoor safety in Japan. '
        'Use only what the given sources say. Answer in plain English, '
        'in at most three short sentences, most important first. '
        'End each sentence with the number of the source you used, like [1]. '
        'If the sources do not answer the question, reply only: "No answer in the sources." '
        'Do not add facts, numbers or steps that are not in the sources.',
    noSource: 'No answer in the sources.',
    sources: 'Sources',
    question: 'Question',
    foreignNote:
        'Some sources are from abroad. Combine all sources. Where a '
        'Japanese source and a foreign one disagree, follow the '
        'Japanese one. Do not take phone numbers, laws or services '
        'from foreign sources.',
  ),
};

/// What the app shows for one question.
class GroundedAnswer {
  /// [lang] when already known (from a shelter computer); otherwise from
  /// the question, with [appLang] deciding between Latin-script languages.
  GroundedAnswer(this.question, {String? lang, String appLang = 'en'})
    : lang = lang ?? questionLanguage(question, appLang: appLang);

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

  /// Passage numbers (1-based, as given to the model) that the answer cites:
  /// [1], [1][2], and also [1, 2] or [1、2] (seen on the Pixel 5a).
  Set<int> get citedNumbers => {
    for (final m in citation.allMatches(text))
      for (final n in RegExp(r'\d+').allMatches(m.group(0)!))
        int.parse(n.group(0)!),
  };

  /// One citation mark: [1], [1, 2], [1,2], [1、2].
  static final citation = RegExp(r'\[\d{1,2}(?:\s*[,、，]\s*\d{1,2})*\]');

  /// Citations that point to a passage the model was not given.
  Set<int> get invalidCitations =>
      citedNumbers.where((n) => n < 1 || n > hits.length).toSet();

  List<Hit> get citedHits => [
    for (final n in citedNumbers.toList()..sort())
      if (n >= 1 && n <= hits.length) hits[n - 1],
  ];

  bool get saysNoSource {
    final t = text.toLowerCase();
    return AnswerTexts.allNoSource.any(
      (n) => t.contains(n.toLowerCase().replaceAll('.', '')),
    );
  }

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
    final lang = answer.lang;
    final say = AnswerTexts.of(lang);
    // Vector search is multilingual: an English question finds Japanese
    // passages as it is. Translating first cost 6-10 s on a Pixel 5a and
    // went wrong at times ("avalanche" became 「あらわせ」). Keyword search
    // alone (no search model installed) still needs a Japanese question.
    final search = lang != 'ja' && hybrid == null ? await _toJapanese(q) : q;
    if (search != q) answer.searchQuery = search;
    answer.alerts = package.alerts
        .where((a) => a.matches(q) || a.matches(search))
        .toList();
    retriever.userRegion = userRegion;
    hybrid?.userRegion = userRegion;
    answer.hits = sameAnimal(
      [q, search],
      hybrid != null
          ? await hybrid!.search(search, limit: topK, original: q)
          : retriever.search(search, limit: topK),
    );
    onUpdate();
    if (answer.hits.isEmpty) {
      // Nothing relevant in the package: do not let the model guess.
      answer.text = say.noSource;
      onUpdate();
      return;
    }
    if (checkRelevance) {
      answer.judgedRelevant = await _answersQuestion(search, answer.hits);
      if (answer.relatedOnly) {
        // Related but not an answer: show the passages, do not generate.
        answer.text = say.noSource;
        onUpdate();
        return;
      }
    }
    await llm.newChat(systemInstruction: say.instruction);
    await for (final t in llm.ask(
      _prompt(q, answer.hits, lang, userRegion: userRegion),
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
        StringBuffer(_prompt(question, hits, 'ja', userRegion: userRegion))
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
    String lang, {
    String userRegion = 'JP',
  }) {
    final say = AnswerTexts.of(lang);
    final b = StringBuffer('${say.sources}:\n');
    var foreign = false;
    for (var i = 0; i < hits.length; i++) {
      final p = hits[i].passage;
      final label = foreignLabel(p.source, userRegion, lang: lang);
      foreign |= label != null;
      // Each question reads the passages in its own language, translated
      // when the package was built: the phone model never translates.
      final heading = p.headingIn(lang);
      b.writeln(
        '[${i + 1}] ${p.source.publisher}「${p.source.title}」'
        '${heading.isEmpty ? '' : ' / $heading'}'
        '${label == null ? '' : ' [$label]'}',
      );
      b.writeln(p.textIn(lang));
      b.writeln();
    }
    if (foreign) {
      // Combine both; only where they disagree does the local one win.
      b.writeln(say.foreignNote);
      b.writeln();
    }
    b.writeln('${say.question}: $question');
    return b.toString();
  }
}
