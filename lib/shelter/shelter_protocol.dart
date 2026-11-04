import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart';
import '../knowledge/retriever.dart';
import '../llm/local_llm.dart';

/// JSON format between a shelter computer and phones on its Wi-Fi.
///
/// The phone rebuilds the same objects it would create with its own model,
/// so the answer card, citation check and map link work unchanged.
const shelterProtocolVersion = 1;

Map<String, Object?> sourceToWire(Source s) => {
  'id': s.id,
  'title': s.title,
  'publisher': s.publisher,
  'url': s.url,
  'licence': s.licence,
  'attribution': s.attribution,
};

Source sourceFromWire(Map<String, dynamic> j) => Source(
  j['id'] as String,
  j['title'] as String,
  j['publisher'] as String,
  j['url'] as String,
  j['licence'] as String,
  j['attribution'] as String,
);

Map<String, Object?> answerToWire(GroundedAnswer a) => {
  'v': shelterProtocolVersion,
  'question': a.question,
  'search_query': a.searchQuery,
  'judged_relevant': a.judgedRelevant,
  'text': a.text,
  'alerts': [
    for (final al in a.alerts)
      {
        'id': al.id,
        'text': al.text,
        'text_en': al.textEn,
        'source': sourceToWire(al.source),
      },
  ],
  'hits': [
    for (final h in a.hits)
      {
        'score': h.score,
        'passage': {
          'id': h.passage.id,
          'heading': h.passage.heading,
          'text': h.passage.text,
          'source': sourceToWire(h.passage.source),
        },
      },
  ],
  if (a.stats != null) 'stats': a.stats!.toJson(),
};

/// Rebuilds an answer received from a shelter. Throws [FormatException] on
/// anything that does not look like this protocol.
GroundedAnswer answerFromWire(Map<String, dynamic> j) {
  if (j['v'] != shelterProtocolVersion) {
    throw FormatException('unsupported shelter protocol: ${j['v']}');
  }
  final a = GroundedAnswer(j['question'] as String)
    ..searchQuery = j['search_query'] as String?
    ..judgedRelevant = j['judged_relevant'] as bool?
    ..text = j['text'] as String;
  a.alerts = [
    for (final al in (j['alerts'] as List).cast<Map<String, dynamic>>())
      Alert(
        al['id'] as String,
        sourceFromWire(al['source'] as Map<String, dynamic>),
        al['text'] as String,
        const [],
        al['text_en'] as String?,
        const [],
      ),
  ];
  a.hits = [
    for (final h in (j['hits'] as List).cast<Map<String, dynamic>>())
      Hit(
        Passage(
          (h['passage'] as Map)['id'] as int,
          sourceFromWire(
            (h['passage'] as Map)['source'] as Map<String, dynamic>,
          ),
          (h['passage'] as Map)['heading'] as String,
          (h['passage'] as Map)['text'] as String,
        ),
        (h['score'] as num).toDouble(),
      ),
  ];
  final s = j['stats'] as Map<String, dynamic>?;
  if (s != null) {
    a.stats = AnswerStats(
      timeToFirstToken: Duration(milliseconds: s['ttft_ms'] as int),
      total: Duration(milliseconds: s['total_ms'] as int),
      outputTokens: s['output_tokens'] as int,
      inputTokens: s['input_tokens'] as int,
      rssBytes: (s['rss_mb'] as int) * 1024 * 1024,
    );
  }
  return a;
}
