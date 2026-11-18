import 'package:sqlite3/sqlite3.dart';

// The tables of a guide file, as lychnion-data's tool/build_package.py
// writes them. Optional tables the app also reads when they are there:
// passage_texts (translations) and vectors (search), written by the data
// tools.

/// Creates the tables of a guide in the empty database [db].
void createGuideTables(Database db) => db.execute('''
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE sources(id TEXT PRIMARY KEY, title TEXT, publisher TEXT,
                       url TEXT, licence TEXT, licence_url TEXT,
                       attribution TEXT,
                       region TEXT NOT NULL DEFAULT 'JP');
  CREATE TABLE passages(id INTEGER PRIMARY KEY,
                        source_id TEXT NOT NULL REFERENCES sources(id),
                        heading TEXT, text TEXT NOT NULL,
                        original_heading TEXT, original TEXT);
  CREATE VIRTUAL TABLE passages_fts USING fts5(heading, text,
                        content='passages', content_rowid='id',
                        tokenize='trigram');
  CREATE TABLE alerts(id TEXT PRIMARY KEY,
                      source_id TEXT NOT NULL REFERENCES sources(id),
                      text TEXT NOT NULL, match_all TEXT NOT NULL,
                      text_en TEXT, match_all_en TEXT);
''');

/// Meta keys the app reads. `id` and `version` are required; `name`,
/// `notice`, `suggestions`, `synonyms` and `gaps` hold JSON (see
/// shapes.dart).
const guideMetaKeys = [
  'id',
  'version',
  'title',
  'language',
  'note',
  'translation',
  'notice',
  'name',
  'icon',
  'suggestions',
  'area',
  'gaps',
  'synonyms',
];
