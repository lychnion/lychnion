import 'package:lychnion_format/lychnion_format.dart';

/// Why a publisher link that Lychnion has not vouched for deserves a
/// second look before it is added (lychnion/lychnion#119): anyone can make
/// a link with any name, and a fake QR code at a shelter only needs one
/// tap. Never a reason to refuse: an official body that Lychnion has not
/// checked must still be addable offline.
enum Lookalike {
  /// Its name or title is like that of a publisher Lychnion vouches for.
  vouched,

  /// Its name or title is like that of a public body (市, 県, 庁, 消防,
  /// jp.go.*, jp.lg.*, City, Ministry…).
  publicBody,
}

/// Whether publisher [name] with [title] looks like one in [vouches]
/// (another name: a vouch for the same name decides by itself) or like a
/// public body. Null when neither.
Lookalike? lookalikeOf(String name, String? title, Iterable<Vouch> vouches) {
  final n = nameSkeleton(name);
  final t = title == null ? '' : foldTitle(title);
  for (final v in vouches) {
    if (v.publisher == name) continue;
    if (nameSkeleton(v.publisher) == n) return Lookalike.vouched;
    for (final vt in v.title.values) {
      final f = foldTitle(vt);
      if (f.length < 2 || t.length < 2) continue;
      if (t.contains(f) || f.contains(t)) return Lookalike.vouched;
    }
  }
  if (_publicName(name) ||
      _publicJa.any(t.contains) ||
      (title != null && _publicWords(title))) {
    return Lookalike.publicBody;
  }
  return null;
}

/// [s] with full-width letters, digits and signs as ASCII, lower case,
/// without spaces and the usual separators: "Ｓｅｎｄａｉ　City" and
/// "sendai-city" fold alike.
String foldTitle(String s) => [
  for (final r in _narrow(s).runes)
    if (!_separators.contains(String.fromCharCode(r))) String.fromCharCode(r),
].join();

/// [s] in lower case, with full-width ASCII (U+FF01–U+FF5E) and the
/// ideographic space as their ASCII forms.
String _narrow(String s) => String.fromCharCodes([
  for (final c in s.runes)
    c >= 0xFF01 && c <= 0xFF5E
        ? c - 0xFEE0
        : c == 0x3000
        ? 0x20
        : c,
]).toLowerCase();

const _separators = {
  ' ', '\t', '.', ',', '-', '_', '・', '･', '·', '(', ')', '（', '）', //
  '「', '」', '『', '』', '[', ']', '/', '／', '、', '。', '|', ':', '：',
};

/// A publisher name reduced to what a reader tells apart at a glance:
/// letters and digits only, with 0/o, 1/l/i and rn/m alike.
String nameSkeleton(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]'), '')
    .replaceAll('rn', 'm')
    .replaceAll('0', 'o')
    .replaceAll(RegExp('[1i]'), 'l');

/// jp.go.*, jp.lg.*, and names made like a city's or prefecture's web
/// address (city.sendai.jp → jp.city.sendai).
bool _publicName(String name) {
  final s = name.split('.');
  if (s.length < 2 || s.first != 'jp') return false;
  return s.contains('go') ||
      s.contains('lg') ||
      const {'city', 'pref', 'town', 'vill', 'village', 'metro'}.contains(s[1]);
}

/// Japanese words of public bodies, anywhere in the folded title.
const _publicJa = [
  '市', '町', '村', '県', '都', '府', '北海道', '庁', '省', '役所', '役場', //
  '消防', '警察', '自衛隊', '政府', '区役所',
];

/// English words of public bodies, as whole words.
const _publicEn = {
  'city', 'town', 'village', 'ward', 'prefecture', 'prefectural', //
  'ministry', 'government', 'municipal', 'municipality', 'fire', 'police',
  'cabinet', 'agency',
};

/// Whether [title] has an English word of a public body.
bool _publicWords(String title) =>
    _narrow(title).split(RegExp('[^a-z]+')).any(_publicEn.contains);
