import 'dart:convert';

import 'key_statement.dart';
import 'record.dart';

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
///  "base": "https://…/", "refresh": "https://…/catalog.json"}
/// ```
///
/// `records` is required; the rest is optional. Older apps read only
/// `records`, `urls` (one address per file), `base` and `refresh`, and
/// ignore the rest.
class CatalogDocument {
  CatalogDocument({
    required List<Object?> records,
    Map<String, String> urls = const {},
    List<String> mirrors = const [],
    List<Object?> keys = const [],
    this.base,
    this.refresh,
  }) : records = List.unmodifiable(records),
       urls = Map.unmodifiable(urls),
       mirrors = List.unmodifiable(mirrors),
       keys = List.unmodifiable(keys);

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

  final String? base, refresh;

  /// Reads [text]. Throws [FormatException] when it is not a format 2
  /// catalog, or when a field has the wrong type. Entries of `urls` and
  /// `mirrors` that are not strings are left out.
  factory CatalogDocument.parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Catalog: not JSON');
    }
    if (j is! Map) throw const FormatException('Catalog: not an object');
    final Map<Object?, Object?> m = j;
    if (m['format'] != format) {
      throw const FormatException('Catalog: unknown format');
    }
    final records = m['records'];
    if (records is! List) throw const FormatException('Catalog: no records');
    T? opt<T>(String k) {
      final v = m[k];
      if (v == null || v is T) return v as T?;
      throw FormatException('Catalog: $k of the wrong type');
    }

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
      base: opt<String>('base'),
      refresh: opt<String>('refresh'),
    );
  }

  /// A catalog of [records] whose files are served by hash next to it
  /// (`blobs/sha256/<hash>`), as a base, a USB stick and a node lay them
  /// out. Sorted by id, so the same records give the same text.
  factory CatalogDocument.byHash(
    Iterable<PackageRecord> records, {
    Iterable<KeyStatement> keys = const [],
    List<String> mirrors = const [],
  }) {
    final sorted = [...records]..sort((a, b) => a.id.compareTo(b.id));
    final seen = <String>{};
    return CatalogDocument(
      records: [for (final r in sorted) r.json],
      urls: {
        for (final r in sorted)
          for (final f in r.files) f.sha256: 'blobs/sha256/${f.sha256}',
      },
      mirrors: mirrors,
      keys: [
        for (final s in keys)
          if (seen.add(s.id)) s.json,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'records': records,
    if (urls.isNotEmpty) 'urls': urls,
    if (mirrors.isNotEmpty) 'mirrors': mirrors,
    if (keys.isNotEmpty) 'keys': keys,
    'base': ?base,
    'refresh': ?refresh,
  };

  /// The file text (indented, ending in a newline). Throws
  /// [CatalogTooLarge] when it is over [maxBytes]: no reader would take
  /// it.
  String encode() {
    final text = '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
    if (utf8.encode(text).length > maxBytes) throw const CatalogTooLarge();
    return text;
  }
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
      return await KeyStatement.checkAll((jsonDecode(text) as Map)['keys']);
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
