import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/shelter/shelter_protocol.dart';
import 'package:sqlite3/sqlite3.dart';

/// A tiny package: the same advice from a Japanese and a British source,
/// plus one passage only the British source has.
KnowledgePackage _package() {
  final dir = Directory.systemTemp.createTempSync('locality');
  final path = '${dir.path}/test.sqlite';
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE sources(id TEXT PRIMARY KEY, title TEXT, publisher TEXT, url TEXT,
                         licence TEXT, licence_url TEXT, attribution TEXT,
                         region TEXT NOT NULL DEFAULT 'JP');
    CREATE TABLE passages(id INTEGER PRIMARY KEY, source_id TEXT NOT NULL,
                          heading TEXT, text TEXT NOT NULL);
    CREATE TABLE alerts(id TEXT PRIMARY KEY, source_id TEXT NOT NULL, text TEXT NOT NULL,
                        match_all TEXT NOT NULL, text_en TEXT, match_all_en TEXT);
    INSERT INTO meta VALUES('id', 'test'), ('version', '1');
    INSERT INTO sources VALUES
      ('jp', '低体温症', '国', '', 'PDL1.0', '', '出典：国', 'JP'),
      ('gb', 'Hypothermia', 'NHS', '', 'OGL v3', '', 'Source: NHS', 'GB');
    INSERT INTO passages(source_id, heading, text) VALUES
      ('gb', '', '低体温症のときは、ぬれた服を脱いで毛布で体を包み、温かい飲み物を少しずつ飲みます。'),
      ('jp', '', '低体温症のときは、ぬれた服を脱いで毛布で体を包み、温かい飲み物を少しずつ飲みます。'),
      ('gb', '', '凍傷のときは、こすらずに、ぬるま湯でゆっくり温めます。');
  ''');
  db.close();
  return KnowledgePackage.open(path);
}

void main() {
  test('locality levels', () {
    expect(localityLevel('GB', 'JP'), 0);
    expect(localityLevel('JP', 'JP'), 1);
    expect(localityLevel('JP-27', 'JP-13'), 1); // elsewhere in Japan
    expect(localityLevel('JP-13', 'JP-13'), 2);
    expect(localityLevel('JP', 'JP-13'), 1);
    expect(
      localityBoost('JP-13', 'JP-13'),
      greaterThan(localityBoost('JP', 'JP-13')),
    );
  });

  test('foreign sources get a label, local ones none', () {
    final pkg = _package();
    expect(foreignLabel(pkg.sources['jp']!, 'JP', lang: 'ja'), isNull);
    expect(foreignLabel(pkg.sources['gb']!, 'JP', lang: 'ja'), '海外の資料（英国）');
    expect(
      foreignLabel(pkg.sources['gb']!, 'JP', lang: 'en'),
      'Source from UK',
    );
  });

  test('the local source goes first, the foreign one stays', () {
    final r = Retriever(_package());
    final hits = r.search('低体温症のときはどうする？', limit: 4, minScore: 0);
    expect(hits.first.passage.source.id, 'jp');
    expect(hits.map((h) => h.passage.source.id), contains('gb'));
    // Seen from the UK, the British copy wins.
    r.userRegion = 'GB';
    expect(
      r.search('低体温症のときはどうする？', limit: 4, minScore: 0).first.passage.source.id,
      'gb',
    );
  });

  test('a topic only the foreign source covers is still answered', () {
    final hits = Retriever(_package()).search('凍傷になったら？', minScore: 0);
    expect(hits.first.passage.source.id, 'gb');
  });

  test('older packages without a region column are Japanese', () {
    final pkg = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
    expect(pkg.sources.values.every((s) => s.region == 'JP'), isTrue);
  });

  test('the region travels from shelter to phone', () {
    final gb = _package().sources['gb']!;
    expect(sourceFromWire(sourceToWire(gb)).region, 'GB');
    final old = Map<String, dynamic>.from(sourceToWire(gb))..remove('region');
    expect(sourceFromWire(old).region, 'JP');
  });
}
