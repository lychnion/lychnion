import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart';
import '../knowledge/retriever.dart';
import '../llm/local_llm.dart';

/// JSON format between a base computer and phones on its Wi-Fi.
///
/// The phone rebuilds the same objects it would create with its own model,
/// so the answer card, citation check and map link work unchanged.
const baseProtocolVersion = 1;

/// [label]: how this device labels the source's signer (a base sends
/// it with its answers).
Map<String, Object?> sourceToWire(Source s, {SourceLabel? label}) => {
  'id': s.id,
  'title': s.title,
  'publisher': s.publisher,
  'url': s.url,
  'licence': s.licence,
  'attribution': s.attribution,
  'region': s.region,
  // Who signed the source's package (#119): kept with saved answers, so
  // their labels follow the vouches; never looked up for a base's answer.
  'signer': ?s.signer,
  'signer_key': ?s.signerKeyId,
  'label': ?(label ?? s.label)?.toWire(),
};

/// A source as a base sent it. Its link is kept only when it is a web
/// address (http or https): the phone opens it when tapped.
Source sourceFromWire(Map<String, dynamic> j) => Source(
  j['id'] as String,
  j['title'] as String,
  j['publisher'] as String,
  _webUrl(j['url'] as String),
  j['licence'] as String,
  j['attribution'] as String,
  region: j['region'] as String? ?? 'JP',
  signer: _plain(j['signer'], _signer),
  signerKeyId: _plain(j['signer_key'], _keyId),
  // The sender's word, checked only for form (see SourceLabel.fromWire).
  label: SourceLabel.fromWire(j['label']),
);

String? _plain(Object? v, RegExp form) =>
    v is String && form.hasMatch(v) ? v : null;

/// A publisher name, and a key's short id (6 bytes, base64url).
final _signer = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
final _keyId = RegExp(r'^[A-Za-z0-9_-]{8}$');

String _webUrl(String s) {
  final u = Uri.tryParse(s.trim());
  return u != null &&
          (u.isScheme('http') || u.isScheme('https')) &&
          u.host.isNotEmpty
      ? s.trim()
      : '';
}

/// An answer cites a few passages and shows a few safety lines; a base
/// that sends more than this is not answering.
const maxWireHits = 30;
const maxWireAlerts = 30;

/// [labelOf]: how this device labels each source's signer (a base sends
/// its labels; saved answers keep the signer instead).
Map<String, Object?> answerToWire(
  GroundedAnswer a, {
  SourceLabel? Function(Source)? labelOf,
}) => {
  'v': baseProtocolVersion,
  'question': a.question,
  'lang': a.lang,
  'search_query': a.searchQuery,
  'judged_relevant': a.judgedRelevant,
  'text': a.text,
  'alerts': [
    for (final al in a.alerts)
      {
        'id': al.id,
        'text': al.text,
        'translations': al.translations,
        // Phones from before translations were maps read this one.
        'text_en': al.translations['en'],
        'source': sourceToWire(al.source, label: labelOf?.call(al.source)),
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
          if (h.passage.original != null) 'original': h.passage.original,
          if (h.passage.originalHeading != null)
            'original_heading': h.passage.originalHeading,
          if (h.passage.texts.isNotEmpty)
            'texts': {
              for (final e in h.passage.texts.entries)
                e.key: {'heading': e.value.$1, 'text': e.value.$2},
            },
          'source': sourceToWire(
            h.passage.source,
            label: labelOf?.call(h.passage.source),
          ),
        },
      },
  ],
  if (a.stats != null) 'stats': a.stats!.toJson(),
};

/// Rebuilds an answer received from a base. Throws [FormatException] on
/// anything that does not look like this protocol (also a wrong type, a
/// missing field or too many hits).
GroundedAnswer answerFromWire(Map<String, dynamic> j) {
  if (j['v'] != baseProtocolVersion) {
    throw const FormatException('unsupported base protocol');
  }
  if (j['alerts'] case final List<Object?> l when l.length > maxWireAlerts) {
    throw const FormatException('base answer: too many alerts');
  }
  if (j['hits'] case final List<Object?> l when l.length > maxWireHits) {
    throw const FormatException('base answer: too many hits');
  }
  try {
    return _answerFromWire(j);
  } on FormatException {
    rethrow;
  } on Object {
    // TypeError, a cast that failed: not this protocol.
    throw const FormatException('base answer: not well formed');
  }
}

GroundedAnswer _answerFromWire(Map<String, dynamic> j) {
  final a = GroundedAnswer(j['question'] as String, lang: j['lang'] as String?)
    ..searchQuery = j['search_query'] as String?
    ..judgedRelevant = j['judged_relevant'] as bool?
    ..text = j['text'] as String;
  a.alerts = [
    for (final al in (j['alerts'] as List).cast<Map<String, dynamic>>())
      Alert(
        al['id'] as String,
        sourceFromWire(al['source'] as Map<String, dynamic>),
        al['text'] as String,
        translations: {
          if (al['text_en'] case final String en) 'en': en,
          ...?(al['translations'] as Map?)?.cast<String, String>(),
        },
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
          original: (h['passage'] as Map)['original'] as String?,
          originalHeading: (h['passage'] as Map)['original_heading'] as String?,
          texts: {
            for (final e
                in ((h['passage'] as Map)['texts'] as Map? ?? const {}).entries)
              e.key as String: (
                (e.value as Map)['heading'] as String? ?? '',
                (e.value as Map)['text'] as String,
              ),
          },
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
