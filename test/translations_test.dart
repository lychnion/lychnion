import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Japanese and English must stay in step: app texts (lib/l10n/*.arb),
/// help (help/ja|en, built into assets/help/app.help.sqlite), the bundled
/// packages and the download catalog. Each check lists every problem it
/// finds, so one run shows all of them.
void main() {
  group('app texts (ARB)', () {
    final ja = _arb('lib/l10n/app_ja.arb');
    final en = _arb('lib/l10n/app_en.arb');

    test('the same keys in ja and en', () {
      expect(_diff(ja.keys, en.keys, 'ja', 'en'), isEmpty);
    });

    test('no empty texts', () {
      final empty = [
        for (final (lang, arb) in [('ja', ja), ('en', en)])
          for (final e in arb.entries)
            if (e.value.trim().isEmpty) '$lang ${e.key}',
      ];
      expect(empty, isEmpty);
    });

    test('the same placeholders and select cases in ja and en', () {
      final problems = <String>[];
      for (final key in ja.keys.where(en.containsKey)) {
        final j = _Icu.parse(ja[key]!), e = _Icu.parse(en[key]!);
        if (!_sameSet(j.args, e.args)) {
          problems.add('$key: ja ${j.args}, en ${e.args}');
        }
        for (final arg in {...j.selects.keys, ...e.selects.keys}) {
          if (!_sameSet(j.selects[arg] ?? {}, e.selects[arg] ?? {})) {
            problems.add(
              '$key: select $arg ja ${j.selects[arg]}, en ${e.selects[arg]}',
            );
          }
        }
        for (final (lang, icu) in [('ja', j), ('en', e)]) {
          for (final arg in icu.plurals.keys) {
            if (!icu.plurals[arg]!.contains('other')) {
              problems.add('$key: $lang plural $arg has no "other" case');
            }
          }
          for (final arg in icu.selects.keys) {
            if (!icu.selects[arg]!.contains('other')) {
              problems.add('$key: $lang select $arg has no "other" case');
            }
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('the parser reads plurals and selects', () {
      final icu = _Icu.parse(
        '{n, plural, =1{one {thing}} other{{n} {thing}s}} '
        '{kind, select, a{A} other{B}}',
      );
      expect(icu.args, {'n', 'thing', 'kind'});
      expect(icu.plurals['n'], {'=1', 'other'});
      expect(icu.selects['kind'], {'a', 'other'});
    });
  });

  group('help (help/ja, help/en)', () {
    final ja = _helpFiles('ja'), en = _helpFiles('en');

    test('the same topics in ja and en', () {
      expect(
        _diff(ja.map(_name), en.map(_name), 'help/ja', 'help/en'),
        isEmpty,
      );
    });

    test('the same sections, none empty', () {
      final problems = <String>[];
      for (final file in ja) {
        final name = _name(file);
        final other = File('help/en/$name');
        if (!other.existsSync()) continue;
        final j = _HelpTopic.read(file), e = _HelpTopic.read(other);
        problems
          ..addAll(j.problems.map((p) => 'ja/$name: $p'))
          ..addAll(e.problems.map((p) => 'en/$name: $p'));
        if (j.sections.length != e.sections.length) {
          problems.add(
            '$name: ${j.sections.length} sections in ja, '
            '${e.sections.length} in en',
          );
        }
      }
      expect(problems, isEmpty);
    });

    test('assets/help/app.help.sqlite is built from these files', () {
      // The same version as tool/build_help.py writes: pubspec version
      // plus a hash of the help files. Rebuild with
      // `python3 -I tool/build_help.py` when this fails.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final v = RegExp(
        r'^version:\s*([0-9.]+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      final bytes = <int>[];
      for (final f in [...ja, ...en]) {
        bytes
          ..addAll(utf8.encode(_name(f)))
          ..add(0)
          ..addAll(f.readAsBytesSync());
      }
      final want = '$v+${sha256.convert(bytes).toString().substring(0, 8)}';
      final db = sqlite3.open('assets/help/app.help.sqlite');
      addTearDown(db.close);
      final got = db.select("SELECT value FROM meta WHERE key='version'");
      expect(got.single['value'], want);
    });
  });

  group('bundled packages', () {
    final files =
        Directory('assets/packages')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sqlite'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in [...files, File('assets/help/app.help.sqlite')]) {
      test('${_name(file)}: name, notice and passages in ja and en', () {
        final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
        addTearDown(db.close);
        expect(_packageProblems(db), isEmpty);
      });
    }
  });

  test('download catalog: titles, notes and notices in ja and en', () {
    final catalog =
        jsonDecode(File('assets/downloads/catalog.json').readAsStringSync())
            as Map<String, dynamic>;
    final problems = <String>[];
    for (final r in (catalog['records'] as List).cast<Map<String, dynamic>>()) {
      for (final e in r.entries) {
        if (e.value is Map) {
          problems.addAll(
            _langMapProblems(
              e.value as Map,
            ).map((p) => '${r['id']} ${e.key}: $p'),
          );
        }
      }
    }
    expect(problems, isEmpty);
  });
}

const _langs = ['ja', 'en'];

/// Texts of an ARB file, without its @metadata.
Map<String, String> _arb(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

List<String> _diff(
  Iterable<String> a,
  Iterable<String> b,
  String aName,
  String bName,
) {
  final sa = a.toSet(), sb = b.toSet();
  return [
    for (final k in sa.difference(sb)) 'only in $aName: $k',
    for (final k in sb.difference(sa)) 'only in $bName: $k',
  ]..sort();
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

String _name(File f) => f.uri.pathSegments.last;

List<File> _helpFiles(String lang) =>
    Directory('help/$lang')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList()
      ..sort((a, b) => _name(a).compareTo(_name(b)));

/// Problems in a {lang: value} map: a missing language or an empty text.
/// Values may be strings or lists of strings or of {text: ...} maps.
List<String> _langMapProblems(Map<Object?, Object?> map) {
  final problems = <String>[
    for (final l in _langs)
      if (!map.containsKey(l)) 'no $l',
  ];
  final lengths = <int>{};
  for (final l in _langs.where(map.containsKey)) {
    final v = map[l];
    if (v is List) lengths.add(v.length);
    if (_texts(v).any((t) => t.trim().isEmpty) || _texts(v).isEmpty) {
      problems.add('empty $l');
    }
  }
  if (lengths.length > 1) problems.add('different lengths per language');
  return problems;
}

Iterable<String> _texts(Object? v) sync* {
  if (v is String) {
    yield v;
  } else if (v is List) {
    for (final x in v) {
      yield* _texts(x);
    }
  } else if (v is Map && v['text'] is String) {
    yield v['text'] as String;
  }
}

List<String> _packageProblems(Database db) {
  final problems = <String>[];
  final meta = {
    for (final r in db.select('SELECT key, value FROM meta'))
      r['key'] as String: r['value'] as String,
  };
  for (final key in ['name', 'notice', 'suggestions']) {
    final raw = meta[key];
    if (raw == null || raw.isEmpty) continue;
    final map = jsonDecode(raw) as Map;
    if (map.isEmpty && key != 'name') continue; // no notice: nothing to match
    problems.addAll(_langMapProblems(map).map((p) => 'meta $key: $p'));
  }
  if (meta['topics'] case final topics?) {
    for (final t
        in (jsonDecode(topics) as List).cast<Map<Object?, Object?>>()) {
      problems.addAll(_langMapProblems(t).map((p) => 'topic ${t['id']}: $p'));
    }
  }

  bool blank(Object? s) => s == null || (s as String).trim().isEmpty;
  final hasTexts = db
      .select("SELECT 1 FROM sqlite_master WHERE name='passage_texts'")
      .isNotEmpty;
  final lang = meta['language'] ?? 'ja';
  final other = lang == 'ja' ? 'en' : 'ja';
  for (final p in db.select('SELECT * FROM passages')) {
    final id = p['id'];
    if (blank(p['text'])) problems.add('passage $id: empty $lang text');
    // The other language: passage_texts for Japanese packages, the
    // original column for a translated foreign source.
    String? heading, text;
    if (p['original'] != null) {
      (heading, text) = (
        p['original_heading'] as String?,
        p['original'] as String?,
      );
    } else if (hasTexts) {
      final t = db.select(
        'SELECT heading, text FROM passage_texts '
        'WHERE passage_id = ? AND lang = ?',
        [id, other],
      );
      if (t.isNotEmpty) {
        (heading, text) = (
          t.single['heading'] as String?,
          t.single['text'] as String?,
        );
      }
    }
    if (blank(text)) {
      problems.add('passage $id: no $other text');
    } else if (blank(p['heading']) != blank(heading)) {
      problems.add('passage $id: heading in one language only');
    }
  }
  for (final a in db.select('SELECT id, text, text_en FROM alerts')) {
    if (blank(a['text']) || blank(a['text_en'])) {
      problems.add('alert ${a['id']}: empty ja or en text');
    }
  }
  return problems;
}

/// One help file read the way tool/build_help.py reads it.
class _HelpTopic {
  _HelpTopic.read(File file) {
    String? heading;
    final lines = <String>[];
    void flush() {
      if (heading == null) return;
      if (heading.isEmpty) problems.add('empty heading');
      if (lines.join('\n').trim().isEmpty) {
        problems.add('section "$heading" is empty');
      }
      sections.add(heading);
      lines.clear();
    }

    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('# ') && title == null) {
        title = line.substring(2).trim();
      } else if (line.startsWith('## ')) {
        flush();
        heading = line.substring(3).trim();
      } else if (heading != null) {
        lines.add(line);
      }
    }
    flush();
    if (title == null || title!.isEmpty) problems.add('no "# " title');
    if (sections.isEmpty) problems.add('no "## " sections');
  }

  String? title;
  final sections = <String>[];
  final problems = <String>[];
}

/// The arguments of an ICU message (as gen-l10n reads ARB texts), with
/// the cases of each plural and select.
class _Icu {
  _Icu._(this._s);

  factory _Icu.parse(String message) {
    final icu = _Icu._(message);
    icu._message(inside: false);
    return icu;
  }

  final String _s;
  int _i = 0;
  final args = <String>{};
  final plurals = <String, Set<String>>{};
  final selects = <String, Set<String>>{};

  void _message({required bool inside}) {
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == '{') {
        _i++;
        _argument();
      } else if (c == '}' && inside) {
        _i++;
        return;
      } else {
        _i++;
      }
    }
  }

  String _until(String stops) {
    final start = _i;
    while (_i < _s.length && !stops.contains(_s[_i])) {
      _i++;
    }
    return _s.substring(start, _i).trim();
  }

  void _argument() {
    final name = _until(',}');
    args.add(name);
    if (_i >= _s.length || _s[_i] == '}') {
      _i++;
      return;
    }
    _i++; // ,
    final type = _until(',}');
    if (_i < _s.length && _s[_i] == '}') {
      _i++;
      return;
    }
    _i++; // ,
    final cases = switch (type) {
      'plural' || 'selectordinal' => plurals.putIfAbsent(name, () => {}),
      'select' => selects.putIfAbsent(name, () => {}),
      _ => null,
    };
    if (cases == null) {
      _until('}'); // a number or date format
      _i++;
      return;
    }
    while (_i < _s.length) {
      // The case name, after any "offset:1".
      final selector = _until('{}').split(RegExp(r'\s+')).last;
      if (_i >= _s.length) return;
      if (_s[_i] == '}') {
        _i++;
        return;
      }
      _i++; // {
      cases.add(selector);
      _message(inside: true);
    }
  }
}
