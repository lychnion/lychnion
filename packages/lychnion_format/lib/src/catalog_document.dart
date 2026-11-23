import 'dart:convert';

import 'key_statement.dart';
import 'record.dart';
import 'attestation.dart';

// A catalog (catalog.json, format 2), as written by the app (base, USB
// stick), the headless node and lychnion-data's tools, and read by all of
// them. Only the shape: what to trust and which addresses to use is up to
// the reader (signatures, its own host, private networks).

/// A catalog.json, format 2.
///
/// ```json
/// {"format": 2,
///  "records": [<signed record>, …],
///  "urls": {"<sha256>": "<address, relative to the catalog>"},
///  "mirrors": ["https://node.example.org/"],
///  "keys": [<key statement>, …],
///  "attestations": [<attestation>, …],
///  "base": "https://…/", "refresh": "https://…/catalog.json"}
/// ```
///
/// `records` is required; the rest is optional. Older apps read only
/// `records`, `urls` (one address per file), `base` and `refresh`, and
/// ignore the rest. Apps before `attestations` (lychnion/lychnion#119) ignore
/// them, and leave them out when they write a catalog (a base, a stick).
class CatalogDocument {
  CatalogDocument({
    required List<Object?> records,
    Map<String, String> urls = const {},
    List<String> mirrors = const [],
    List<Object?> keys = const [],
    List<Object?> attestations = const [],
    this.base,
    this.refresh,
  }) : records = List.unmodifiable(records),
       urls = Map.unmodifiable(urls),
       mirrors = List.unmodifiable(mirrors),
       keys = List.unmodifiable(keys),
       attestations = List.unmodifiable(attestations);

  static const format = 2;

  /// Larger catalogs are refused by readers (also while they arrive).
  static const maxBytes = 2 << 20;

  /// The records as given: not checked, not even their shape.
  final List<Object?> records;

  /// File SHA-256 → address (absolute, or relative to the catalog).
  final Map<String, String> urls;

  /// Nodes with the `blobs/sha256/<hash>` layout, as given.
  final List<String> mirrors;

  /// Key statements as given (see relevantStatements).
  final List<Object?> keys;

  /// Attestations as given (see Attestation.checkAll).
  final List<Object?> attestations;

  final String? base, refresh;

  /// Reads [text]. Throws [CatalogFormatException] when it is not JSON,
  /// not a format 2 catalog, or `urls` is not an object (its addresses
  /// matter). Optional fields only advise (`mirrors`, `keys`, `attestations`,
  /// `base`, `refresh`): of the wrong type they are ignored, as older
  /// readers did.
  /// Entries of `urls` and `mirrors` that are not strings are left out.
  factory CatalogDocument.parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const CatalogFormatException('not JSON', notJson: true);
    }
    if (j is! Map) throw const CatalogFormatException('not an object');
    final Map<Object?, Object?> m = j;
    if (m['format'] != format) {
      throw const CatalogFormatException('unknown format');
    }
    final records = m['records'];
    if (records is! List) throw const CatalogFormatException('no records');
    if (m['urls'] != null && m['urls'] is! Map) {
      throw const CatalogFormatException('urls is not an object');
    }
    T? opt<T>(String k) => m[k] is T ? m[k] as T : null;

    return CatalogDocument(
      records: records,
      urls: {
        for (final e
            in (opt<Map<Object?, Object?>>('urls') ?? const {}).entries)
          if (e.key is String && e.value is String && e.value != '')
            e.key! as String: e.value! as String,
      },
      mirrors: [
        for (final m in opt<List<Object?>>('mirrors') ?? const [])
          if (m is String && m.isNotEmpty) m,
      ],
      keys: opt<List<Object?>>('keys') ?? const [],
      attestations: opt<List<Object?>>('attestations') ?? const [],
      base: opt<String>('base'),
      refresh: opt<String>('refresh'),
    );
  }

  /// A catalog of [records] whose files are served by hash next to it
  /// (`blobs/sha256/<hash>`), as a base, a USB stick and a node lay them out.
  /// Sorted by id ([sort]), so the same records give the same text; a base
  /// keeps the order it shows. At most [KeyStatement.maxPerSource] of [keys],
  /// revocations first ([KeyStatement.capped]), and at most
  /// [Attestation.maxPerSource] of [attestations], withdrawals first
  /// ([Attestation.capped]).
  factory CatalogDocument.byHash(
    Iterable<PackageRecord> records, {
    Iterable<KeyStatement> keys = const [],
    Iterable<Attestation> attestations = const [],
    List<String> mirrors = const [],
    bool sort = true,
  }) {
    final sorted = [...records];
    if (sort) sorted.sort((a, b) => a.id.compareTo(b.id));
    final seen = <String>{};
    return CatalogDocument(
      records: [for (final r in sorted) r.json],
      urls: {
        for (final r in sorted)
          for (final f in r.files) f.sha256: 'blobs/sha256/${f.sha256}',
      },
      mirrors: mirrors,
      keys: [
        for (final s in KeyStatement.capped([
          for (final s in keys)
            if (seen.add(s.id)) s,
        ]))
          s.json,
      ],
      attestations: [
        for (final v in Attestation.capped({...attestations})) v.json,
      ],
    );
  }

  /// Fields in the order the tools always wrote them; `urls` always
  /// there (older apps read it).
  Map<String, Object?> toJson() => {
    'format': format,
    'base': ?base,
    'refresh': ?refresh,
    'records': records,
    'urls': urls,
    if (mirrors.isNotEmpty) 'mirrors': mirrors,
    if (keys.isNotEmpty) 'keys': keys,
    if (attestations.isNotEmpty) 'attestations': attestations,
  };

  /// How many of [given] (each once) [written] leaves out to fit
  /// ([fitted], [KeyStatement.capped]): to tell whoever writes it
  /// (lychnion/lychnion#59).
  static int keysLeftOut(
    Iterable<KeyStatement> given,
    CatalogDocument written,
  ) => {for (final s in given) s.id}.length - written.keys.length;

  /// How many of [given] (each once) [written] leaves out to fit, as
  /// [keysLeftOut] for attestations.
  static int attestationsLeftOut(
    Iterable<Attestation> given,
    CatalogDocument written,
  ) => {for (final v in given) v.id}.length - written.attestations.length;

  /// The file text (indented, ending in a newline). Records come first: when
  /// the catalog would be over [maxBytes], attestations and then key statements
  /// are left out ([fitted]). Throws [CatalogTooLarge] when the records alone
  /// are over it: no reader would take it.
  String encode() => _text(fitted());

  static String _text(CatalogDocument c) =>
      '${const JsonEncoder.withIndent('  ').convert(c.toJson())}\n';

  static int _size(CatalogDocument c) => utf8.encode(_text(c)).length;

  /// This catalog, with attestations and then key statements left out until it
  /// fits in [maxBytes]. Attestations go first (they only change labels),
  /// chosen as [Attestation.capped] chooses them (withdrawals last). Key
  /// statements go only when all attestations are out, chosen as
  /// [KeyStatement.capped] chooses them ([KeyStatement.keepOrder]: revocations
  /// and theft proofs last, chains cut from their newest end). Their order is
  /// otherwise kept. Throws [CatalogTooLarge] when even without both it does
  /// not fit.
  CatalogDocument fitted() {
    if (_size(this) <= maxBytes) return this;
    final keyOrder = KeyStatement.keepOrder(keys);
    final attestationOrder = Attestation.keepOrder(attestations);
    List<Object?> firstOf(List<Object?> all, List<int> order, int n) {
      final keep = order.take(n).toSet();
      return [
        for (var i = 0; i < all.length; i++)
          if (keep.contains(i)) all[i],
      ];
    }

    CatalogDocument keeping(int nKeys, int nAttestations) => CatalogDocument(
      records: records,
      urls: urls,
      mirrors: mirrors,
      keys: firstOf(keys, keyOrder, nKeys),
      attestations: firstOf(attestations, attestationOrder, nAttestations),
      base: base,
      refresh: refresh,
    );

    /// The largest n in 0..max with fits(n), given fits(0): a binary
    /// search, a few encodings instead of one per entry left out.
    int most(int max, bool Function(int) fits) {
      var lo = 0, hi = max; // fits(lo), and not fits(hi + 1)
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fits(mid)) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      return lo;
    }

    bool fits(CatalogDocument c) => _size(c) <= maxBytes;
    if (!fits(keeping(0, 0))) throw const CatalogTooLarge();
    if (fits(keeping(keys.length, 0))) {
      return keeping(
        keys.length,
        most(attestations.length, (n) => fits(keeping(keys.length, n))),
      );
    }
    return keeping(most(keys.length, (n) => fits(keeping(n, 0))), 0);
  }
}

/// A catalog.json that cannot be read; [notJson] when it is not JSON at
/// all.
class CatalogFormatException extends FormatException {
  const CatalogFormatException(String message, {this.notJson = false})
    : super('Catalog: $message');
  final bool notJson;
}

class CatalogTooLarge implements Exception {
  const CatalogTooLarge();

  @override
  String toString() => 'catalog.json would be over 2 MB';
}

/// `keys.json` as the desktop app writes it for a publisher's catalog:
/// `{"keys": [<key statement>, …]}`.
class KeysFile {
  /// The valid statements in [text]; empty when it cannot be read.
  static Future<List<KeyStatement>> parse(String text) async {
    try {
      return await KeyStatement.checkAll(
        (jsonDecode(text) as Map)['keys'],
        max: 1000,
      );
    } on Object {
      return const [];
    }
  }

  /// The file text of [statements] (duplicates once).
  static String encode(Iterable<KeyStatement> statements) {
    final seen = <String>{};
    return '${const JsonEncoder.withIndent('  ').convert({
      'keys': [for (final s in statements)
        if (seen.add(s.id)) s.json],
    })}\n';
  }
}
