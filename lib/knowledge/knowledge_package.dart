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
  Alert(this.id, this.source, this.text, this.matchAll);
  final String id;
  final Source source;
  final String text;

  /// Every group needs at least one word present in the question.
  final List<List<String>> matchAll;

  bool matches(String question) =>
      matchAll.every((group) => group.any(question.contains));
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
  );

  final String id, title, version;
  final Map<String, Source> sources;
  final List<Passage> passages;
  final List<Alert> alerts;

  /// Words to add to a question before keyword search (飲み水 → 飲料水).
  final Map<String, List<String>> synonyms;

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
      final alerts = [
        for (final r in db.select('SELECT * FROM alerts'))
          Alert(r['id'], sources[r['source_id']]!, r['text'], [
            for (final g in jsonDecode(r['match_all']) as List)
              List<String>.from(g as List),
          ]),
      ];
      final synonyms = {
        for (final e in (jsonDecode(meta['synonyms'] ?? '{}') as Map).entries)
          e.key as String: List<String>.from(e.value as List),
      };
      return KnowledgePackage._(
        meta['id']!,
        meta['title'] ?? '',
        meta['version'] ?? '',
        sources,
        passages,
        alerts,
        synonyms,
      );
    } finally {
      db.close();
    }
  }
}
