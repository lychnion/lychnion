import 'package:lychnion_format/lychnion_format.dart';

/// Why a publisher link that Lychnion has not attested deserves a
/// second look before it is added (lychnion/lychnion#119): anyone can make
/// a link with any name, and a fake QR code at a shelter only needs one
/// tap. Never a reason to refuse: an official body that Lychnion has not
/// checked must still be addable offline.
enum Lookalike {
  /// Its name or title is like that of a publisher Lychnion attests.
  attested,

  /// Its name or title is like that of a public body (市, 県, 庁, 消防,
  /// jp.go.*, jp.lg.*, City, Ministry…).
  publicBody,
}

/// Whether publisher [name] with [title] looks like one in [attestations]
/// (another name: an attestation for the same name decides by itself) or like a
/// public body. Null when neither.
Lookalike? lookalikeOf(
  String name,
  String? title,
  Iterable<Attestation> attestations,
) {
  final n = nameSkeleton(name);
  final t = title == null ? '' : foldTitle(title);
  for (final v in attestations) {
    if (v.publisher == name) continue;
    if (nameSkeleton(v.publisher) == n) return Lookalike.attested;
    for (final vt in v.title.values) {
      final f = foldTitle(vt);
      if (f.length < 2 || t.length < 2) continue;
      if (t.contains(f) || f.contains(t)) return Lookalike.attested;
    }
  }
  if (_publicName(name) ||
      _publicJa.any(t.contains) ||
      _publicWords(name) ||
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
/// ideographic space as their ASCII forms, and Cyrillic and Greek letters
/// that look like Latin ones as those ("Ѕеndаі" → "sendai").
String _narrow(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().runes) {
    final n = c >= 0xFF01 && c <= 0xFF5E
        ? c - 0xFEE0
        : c == 0x3000
        ? 0x20
        : c;
    final ch = String.fromCharCode(n).toLowerCase();
    b.write(_latinLookalikes[ch] ?? ch);
  }
  return b.toString();
}

/// Cyrillic and Greek lower-case letters drawn like Latin ones.
const _latinLookalikes = {
  'а': 'a', 'в': 'b', 'е': 'e', 'ё': 'e', 'һ': 'h', 'і': 'i', 'ј': 'j', //
  'к': 'k', 'м': 'm', 'н': 'h', 'о': 'o', 'р': 'p', 'с': 'c', 'ѕ': 's',
  'т': 't', 'у': 'y', 'х': 'x', 'ԁ': 'd', 'ԛ': 'q', 'ԝ': 'w', 'ү': 'y',
  'α': 'a', 'β': 'b', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ν': 'v', 'ο': 'o',
  'ρ': 'p', 'τ': 't', 'υ': 'u', 'χ': 'x', 'ϲ': 'c',
};

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

/// Whether [text] (a title, or a name's parts) has an English word of a
/// public body, also when written together ("KobeCity", "sendai-city").
bool _publicWords(String text) {
  final spaced = text.replaceAllMapped(
    RegExp('([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return _narrow(spaced).split(RegExp('[^a-z]+')).any(_publicEn.contains);
}
