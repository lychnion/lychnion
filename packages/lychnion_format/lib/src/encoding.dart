import 'dart:convert';

// Shared by the files in src/; not exported.

/// base64url without padding.
String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// base64url, with or without padding. Throws [FormatException].
List<int> unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// A publisher's name in records (`publisher`): lower case, digits, `.`,
/// `_` and `-`, for example `jp.city.kobe`.
final publisherNamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

/// A signing time with seconds and a zone (`Z` or `+09:00`), so every
/// device orders signed statements the same way.
final _stamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?'
  r'(Z|[+-](\d{2}):(\d{2}))$',
);

/// Years a signed statement may name (see [signedTime]).
const signedYears = (first: 2020, last: 2100);

/// [s] as a signing time, or null unless it is written as [_stamp] says, is
/// a real time (no February 31st) and between 2020 and 2100: a time far in
/// the future would decide over everything signed later.
DateTime? signedTime(String s) {
  final m = _stamp.firstMatch(s);
  if (m == null) return null;
  int n(int g) => int.parse(m[g]!);
  final y = n(1), mo = n(2), d = n(3);
  if (y < signedYears.first ||
      y > signedYears.last ||
      mo < 1 ||
      mo > 12 ||
      d < 1 ||
      d > DateTime.utc(y, mo + 1, 0).day ||
      n(4) > 23 ||
      n(5) > 59 ||
      n(6) > 59) {
    return null;
  }
  if (m[8] != 'Z' && (n(9) > 14 || n(10) > 59)) return null;
  return DateTime.tryParse(s);
}
