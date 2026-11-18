import 'dart:convert';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../download/download_store.dart';
import 'knowledge_package.dart';

/// The app's own help (help/, built by tool/build_help.py into
/// assets/help/app.help.sqlite): answers questions about the app itself,
/// such as "How do I share with other phones?" (lychnion#9).
///
/// Kept apart from the safety packages: it is searched only for
/// questions about the app ([isAppQuestion]), and its passages never mix
/// into an answer about a hazard.
class AppHelp {
  static Future<KnowledgePackage>? _package;

  /// The bundled help package (copied out once per start).
  static Future<KnowledgePackage> load() =>
      _package ??= DownloadStore.instance()
          .then((s) => s.copyBundled('help', 'app.help.sqlite'))
          .then(KnowledgePackage.open);
}

/// Words that only come up when someone asks about the app, not about a
/// hazard. Lower case; matched as substrings.
const _appWords = [
  // Japanese
  'リクニオン', 'アプリ', 'ダウンロード', 'ベース', '共有', '設定', '発行元',
  'カタログ', '使い方', 'ツアー', 'はじめの準備', 'オフラインで使', '履歴',
  'プライバシー', '個人情報', '送信され', 'モバイルデータ', '新しい版',
  '署名', 'qrコード', 'wi-fi', 'wifi', 'テザリング', 'タブ',
  // English
  'lychnion', 'the app', 'this app', 'download', 'a base', 'the base',
  'share with', 'sharing', 'share maps', 'share guides', 'another phone',
  'other phones', 'settings', 'publisher', 'catalog', 'guided tour',
  'first steps', 'offline', 'privacy', 'mobile data', 'new version',
  'qr code', 'hotspot',
];

/// True when [question] is about using the app (downloads, base, sharing,
/// settings, privacy …) rather than about staying safe.
bool isAppQuestion(String question) {
  final q = question.toLowerCase();
  return _appWords.any(q.contains) || _appWholeWords.hasMatch(q);
}

/// English words that are also parts of other words (table, assigned).
final _appWholeWords = RegExp(r'\b(tabs?|signed)\b');

/// One section of a help topic, in each language: (heading, text).
class HelpSection {
  const HelpSection(this.texts);
  final Map<String, (String, String)> texts;

  (String, String) inLang(String lang) =>
      texts[lang] ?? texts['en'] ?? texts.values.first;
}

/// One help topic (one file in `help/<lang>/`).
class HelpTopic {
  const HelpTopic(this.id, this.titles, this.sections);
  final String id;
  final Map<String, String> titles;
  final List<HelpSection> sections;

  String title(String lang) => titles[lang] ?? titles['en'] ?? id;
}

/// The help as a book, for reading and searching without the AI: works
/// before any model is downloaded.
class HelpBook {
  HelpBook(this.topics);
  final List<HelpTopic> topics;

  static Future<HelpBook>? _book;

  /// The bundled help (assets/help/app.help.sqlite).
  static Future<HelpBook> load() => _book ??= DownloadStore.instance()
      .then((s) => s.copyBundled('help', 'app.help.sqlite'))
      .then(open);

  static HelpBook open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      final lang = meta['language'] ?? 'ja';
      final other = <int, Map<String, (String, String)>>{};
      for (final r in db.select('SELECT * FROM passage_texts')) {
        (other[r['passage_id'] as int] ??= {})[r['lang'] as String] = (
          r['heading'] as String? ?? '',
          r['text'] as String,
        );
      }
      final bySource = <String, List<HelpSection>>{};
      for (final r in db.select('SELECT * FROM passages ORDER BY id')) {
        (bySource[r['source_id'] as String] ??= []).add(
          HelpSection({
            lang: (r['heading'] as String? ?? '', r['text'] as String),
            ...?other[r['id'] as int],
          }),
        );
      }
      return HelpBook([
        for (final t in jsonDecode(meta['topics'] ?? '[]') as List)
          HelpTopic((t as Map)['id'] as String, {
            for (final e in t.entries)
              if (e.key != 'id') e.key as String: e.value as String,
          }, bySource[t['id']] ?? const []),
      ]);
    } finally {
      db.close();
    }
  }

  HelpTopic? topic(String id) {
    for (final t in topics) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Sections that fit [query] in [lang], best first. Scored by the
  /// query's character pairs found in the heading and text, rare pairs
  /// counting more than common ones (「共有」 more than 「には」); works for
  /// Japanese without spaces and for English.
  List<(HelpTopic, HelpSection)> search(String query, String lang) {
    var q = query.toLowerCase();
    for (final f in _fillers) {
      q = q.replaceAll(f, ' ');
    }
    final grams = _pairs(q);
    if (grams.isEmpty) return const [];
    final sections = [
      for (final t in topics)
        for (final s in t.sections)
          (t, s, _pairs('${s.inLang(lang).$1} ${s.inLang(lang).$2}')),
    ];
    // Pairs found nowhere say nothing about which section fits: left out.
    final w = <String, double>{};
    for (final g in grams) {
      final df = sections.where((x) => x.$3.contains(g)).length;
      if (df > 0) w[g] = math.log((sections.length + 1) / (df + 0.5));
    }
    final total = w.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return const [];
    final found = <((HelpTopic, HelpSection), double)>[];
    for (final (t, s, have) in sections) {
      // A match in the topic title or the heading counts extra: 「共有」
      // finds the sharing topic before a passage that mentions sharing.
      final head = _pairs('${t.title(lang)} ${s.inLang(lang).$1}');
      var got = 0.0, inHead = 0.0;
      w.forEach((g, weight) {
        if (have.contains(g)) got += weight;
        if (head.contains(g)) inHead += weight;
      });
      final score = got / total;
      if (score >= 0.5) found.add(((t, s), score + 0.5 * inHead / total));
    }
    found.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final f in found) f.$1];
  }

  /// Question words that say nothing about the topic.
  static const _fillers = [
    'どうすれば',
    'どうやって',
    'どうしたら',
    'するには',
    'したい',
    'には',
    'ですか',
    'ますか',
    'でしょうか',
    'とは',
    'やり方',
    '方法',
    'できる',
    'how do i',
    'how can i',
    'how to',
    'can i',
    'what is',
    'where is',
    'where do i',
    'what does',
    'is there',
  ];

  static Set<String> _pairs(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[\s、。？?！!「」"（）()]+'), ' ');
    return {
      for (var i = 0; i + 1 < t.length; i++)
        if (t[i] != ' ' && t[i + 1] != ' ') t.substring(i, i + 2),
    };
  }
}
