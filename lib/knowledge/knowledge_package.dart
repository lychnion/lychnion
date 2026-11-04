import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class Source {
  Source(
    this.id,
    this.title,
    this.publisher,
    this.url,
    this.licence,
    this.attribution,
  );
  final String id, title, publisher, url, licence, attribution;
}

class Passage {
  Passage(this.id, this.source, this.heading, this.text);
  final int id;
  final Source source;
  final String heading, text;
}

/// A fixed safety line, quoted word for word from its source.
class Alert {
  Alert(
    this.id,
    this.source,
    this.text,
    this.matchAll,
    this.textEn,
    this.matchAllEn,
  );
  final String id;
  final Source source;
  final String text;

  /// Every group needs at least one word present in the question.
  final List<List<String>> matchAll;

  /// Our English translation (not official) and its trigger words.
  final String? textEn;
  final List<List<String>> matchAllEn;

  bool matches(String question) {
    bool all(List<List<String>> groups, String q) =>
        groups.isNotEmpty && groups.every((g) => g.any(q.contains));
    return all(matchAll, question) || all(matchAllEn, question.toLowerCase());
  }
}

/// A knowledge package: one SQLite file built by tool/build_package.py.
///
/// Small enough to keep in memory; SQLite is the file format.
class KnowledgePackage {
  KnowledgePackage._(
    this.id,
    this.title,
    this.version,
    this.sources,
    this.passages,
    this.alerts,
    this.synonyms,
    this.vectors,
  );

  final String id, title, version;
  final Map<String, Source> sources;
  final List<Passage> passages;
  final List<Alert> alerts;

  /// Words to add to a question before keyword search (飲み水 → 飲料水).
  final Map<String, List<String>> synonyms;

  /// Precomputed passage vectors per embedding model file name, in passage
  /// order (tool/add_vectors.py). Saves phones from indexing the package.
  final Map<String, List<List<double>>> vectors;

  /// Copies a bundled package out of the assets (SQLite needs a real file) and loads it.
  static Future<KnowledgePackage> fromAsset(String name) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/packages',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    final data = await rootBundle.load('assets/packages/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return open(file.path);
  }

  static KnowledgePackage open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      final sources = {
        for (final r in db.select('SELECT * FROM sources'))
          r['id'] as String: Source(
            r['id'],
            r['title'],
            r['publisher'],
            r['url'],
            r['licence'],
            r['attribution'],
          ),
      };
      final passages = [
        for (final r in db.select(
          'SELECT id, source_id, heading, text FROM passages ORDER BY id',
        ))
          Passage(
            r['id'],
            sources[r['source_id']]!,
            r['heading'] ?? '',
            r['text'],
          ),
      ];
      List<List<String>> groups(Object? json) => [
        for (final g in jsonDecode(json as String? ?? '[]') as List)
          List<String>.from(g as List),
      ];
      final alerts = [
        for (final r in db.select('SELECT * FROM alerts'))
          Alert(
            r['id'],
            sources[r['source_id']]!,
            r['text'],
            groups(r['match_all']),
            r['text_en'] as String?,
            groups(r['match_all_en']),
          ),
      ];
      final synonyms = {
        for (final e in (jsonDecode(meta['synonyms'] ?? '{}') as Map).entries)
          e.key as String: List<String>.from(e.value as List),
      };
      final vectors = <String, List<List<double>>>{};
      final hasVectors = db
          .select("SELECT 1 FROM sqlite_master WHERE name = 'vectors'")
          .isNotEmpty;
      if (hasVectors) {
        for (final r in db.select(
          'SELECT model, vec FROM vectors ORDER BY model, passage_id',
        )) {
          final bytes = r['vec'] as Uint8List;
          final floats = bytes.buffer.asFloat32List(
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ 4,
          );
          (vectors[r['model'] as String] ??= []).add(List<double>.from(floats));
        }
      }
      return KnowledgePackage._(
        meta['id']!,
        meta['title'] ?? '',
        meta['version'] ?? '',
        sources,
        passages,
        alerts,
        synonyms,
        vectors,
      );
    } finally {
      db.close();
    }
  }
}
