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
