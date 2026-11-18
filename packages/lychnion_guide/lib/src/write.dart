import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'check.dart';
import 'schema.dart';

/// Where passages come from (an official page, a leaflet).
class GuideSource {
  const GuideSource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.url,
    required this.licence,
    required this.attribution,
    this.licenceUrl,
    this.region = 'JP',
  });

  final String id, title, publisher, url, licence, attribution, region;
  final String? licenceUrl;
}

class GuidePassage {
  const GuidePassage({
    required this.sourceId,
    required this.text,
    this.heading = '',
  });

  final String sourceId, heading, text;
}

/// A safety line shown first when a question matches all words of one of
/// the groups in [matchAll] (for example a tsunami).
class GuideAlert {
  const GuideAlert({
    required this.id,
    required this.sourceId,
    required this.text,
    required this.matchAll,
    this.textEn,
    this.matchAllEn,
  });

  final String id, sourceId, text;
  final List<List<String>> matchAll;
  final String? textEn;
  final List<List<String>>? matchAllEn;
}

/// Writes a guide to [out] and returns it. [meta] holds the meta table as
/// text (JSON values already encoded; see [guideMetaKeys]).
///
/// Written next to [out] first and checked with [checkGuide] before it
/// replaces a guide there: a guide the app could not open never takes the
/// place of one it can. Throws [GuideProblem] (then [out] is unchanged).
File writeGuide(
  File out, {
  required Map<String, String> meta,
  required List<GuideSource> sources,
  required List<GuidePassage> passages,
  List<GuideAlert> alerts = const [],
}) {
  // A name of its own: two builds of the same guide never share one.
  final tmp = File(
    '${out.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.building',
  );
  var done = false;
  try {
    out.parent.createSync(recursive: true);
    final db = sqlite3.open(tmp.path);
    try {
      _fill(db, meta, sources, passages, alerts);
    } finally {
      db.close();
    }
    checkGuide(tmp.path);
    final f = tmp.renameSync(out.path);
    done = true;
    return f;
  } on GuideProblem {
    rethrow;
  } on SqliteException catch (e) {
    throw GuideProblem(e.message);
  } on FileSystemException catch (e) {
    throw GuideProblem('${e.message}: ${e.path}');
  } finally {
    if (!done && tmp.existsSync()) tmp.deleteSync();
  }
}

void _fill(
  Database db,
  Map<String, String> meta,
  List<GuideSource> sources,
  List<GuidePassage> passages,
  List<GuideAlert> alerts,
) {
  createGuideTables(db);
  db.execute('BEGIN');
  final putMeta = db.prepare('INSERT INTO meta VALUES(?, ?)');
  for (final e in meta.entries) {
    putMeta.execute([e.key, e.value]);
  }
  putMeta.close();
  final putSource = db.prepare(
    'INSERT INTO sources VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
  );
  for (final s in sources) {
    putSource.execute([
      s.id,
      s.title,
      s.publisher,
      s.url,
      s.licence,
      s.licenceUrl,
      s.attribution,
      s.region,
    ]);
  }
  putSource.close();
  final putPassage = db.prepare(
    'INSERT INTO passages(source_id, heading, text) VALUES(?, ?, ?)',
  );
  for (final p in passages) {
    putPassage.execute([p.sourceId, p.heading.trim(), p.text.trim()]);
  }
  putPassage.close();
  final putAlert = db.prepare('INSERT INTO alerts VALUES(?, ?, ?, ?, ?, ?)');
  for (final a in alerts) {
    putAlert.execute([
      a.id,
      a.sourceId,
      a.text,
      jsonEncode(a.matchAll),
      a.textEn,
      a.matchAllEn == null ? null : jsonEncode(a.matchAllEn),
    ]);
  }
  putAlert.close();
  db.execute("INSERT INTO passages_fts(passages_fts) VALUES('rebuild')");
  db.execute('COMMIT');
  db.execute('VACUUM');
}
