// Question language and language maps, without Flutter (also used by the
// base server and tools). Languages are ISO 639-1 codes.

/// Picks the text for [lang] from a language map, falling back to English,
/// then Japanese, then whatever is there.
T? pick<T>(Map<String, T> byLang, String lang) =>
    byLang[lang] ?? byLang['en'] ?? byLang['ja'] ?? byLang.values.firstOrNull;

final _kana = RegExp(r'[぀-ヿ]');
final _han = RegExp(r'[一-鿿]');
final _hangul = RegExp(r'[가-힯]');
final _latin = RegExp(r'[A-Za-z]');

/// The language of a question, by the script most of its letters use:
/// kana (with or without kanji) → 'ja', kanji without kana → 'zh', Hangul →
/// 'ko', Latin letters → the app's language when that uses Latin letters,
/// else 'en'. A few Japanese terms in an English question
/// ("What is 避難指示?") do not make it Japanese.
String questionLanguage(String q, {String appLang = 'en'}) {
  var kana = 0, han = 0, hangul = 0, latin = 0;
  for (final r in q.runes) {
    final c = String.fromCharCode(r);
    if (_kana.hasMatch(c)) {
      kana++;
    } else if (_han.hasMatch(c)) {
      han++;
    } else if (_hangul.hasMatch(c)) {
      hangul++;
    } else if (_latin.hasMatch(c)) {
      latin++;
    }
  }
  // Letters, not words: "What is 避難指示?" (6 Latin, 4 kanji) is English,
  // 「スマホのGPSが使えない」 (3 Latin, 9 kana/kanji) Japanese.
  final cjk = kana + han;
  if (hangul > cjk && hangul > latin) return 'ko';
  if (cjk > latin) return kana > 0 ? 'ja' : 'zh';
  if (latin == 0 && cjk == 0) return appLang;
  return _latinScript.contains(appLang) ? appLang : 'en';
}

/// Whether [lang] is written in Latin letters.
bool usesLatinScript(String lang) => _latinScript.contains(lang);

/// Languages written in Latin letters (enough for app languages to come).
const _latinScript = {
  'en', 'es', 'fr', 'de', 'it', 'pt', 'nl', 'id', 'vi', 'tl', //
};
