import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encoding.dart';
import 'key_statement.dart';
import 'record.dart';

// Vouches (lychnion/lychnion#119): Lychnion says which key belongs to an
// official publisher, how and when it checked that, so the app can label
// that publisher as vouched for. A vouch only changes labels and wording:
// a publisher is never needed on the list to publish, and a vouch never
// adds a publisher by itself, nor lets it publish anything more (models,
// safety lines). Signed like records, so any catalog, stick, base or phone
// carries them unchanged.

final _ed25519 = Ed25519();

/// The publisher whose vouches count. Its key is built in; its key
/// statements apply to vouches too (a replaced key's successor may vouch,
/// a revoked key's vouches lapse).
const voucherPublisher = 'lychnion';

/// A signed vouch. Only made by [check] (shape and signature verified) or
/// [sign], so every instance is valid; [check] also makes sure the signer
/// is a key of [voucherPublisher] that the device trusts.
///
/// ```json
/// {"format": 1,
///  "publisher": "jp.city.sendai", "key": "<Ed25519, base64url>",
///  "title": {"ja": "仙台市", "en": "Sendai City"},
///  "checked": "2026-11-23", "method": "official-website",
///  "url": "https://www.city.sendai.jp/…",
///  "signed": "2026-11-23T14:00:00+09:00",
///  "signer": "<Lychnion's key>", "signature": "…"}
/// ```
///
/// `"withdrawn": true` takes a vouch back: the newest vouch for a
/// publisher name decides ([vouchFor]).
class Vouch {
  Vouch._(this.json, this.signedAt);

  /// Vouch format.
  static const format = 1;

  /// At most this many vouches are read from one catalog or stick (each
  /// is about 600 bytes).
  static const maxPerSource = 500;

  /// The whole vouch as published, signature included.
  final Map<String, Object?> json;

  /// When it was signed: the newest vouch for a publisher decides.
  final DateTime signedAt;

  /// The publisher's name in records.
  String get publisher => json['publisher']! as String;

  /// The publisher's key that was checked (Ed25519, base64url).
  String get key => json['key']! as String;

  /// The publisher's name for people, by language (`ja`, `en`).
  Map<String, String> get title =>
      (json['title'] as Map?)?.cast<String, String>() ?? const {};

  /// The day the key was checked (`YYYY-MM-DD`).
  String get checked => json['checked']! as String;

  /// How it was checked, for example `official-website`.
  String get method => json['method']! as String;

  /// Where the key's code was found, when given (https).
  String? get url => json['url'] as String?;

  /// True for a vouch that takes an earlier one back.
  bool get withdrawn => json['withdrawn'] == true;

  /// The key that signed it, one of [voucherPublisher]'s.
  String get signer => json['signer']! as String;

  String get signed => json['signed']! as String;

  /// The text the signature covers.
  String get signedText => canonicalJson(Map.of(json)..remove('signature'));

  /// Same vouch (whatever the JSON formatting).
  late final String id = canonicalJson(json);

  @override
  bool operator ==(Object other) => other is Vouch && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// The vouch in [json], or null when its shape or signature is wrong, or
  /// when its signer is not a key [trust] has for [voucherPublisher] (after
  /// key statements). Never throws.
  ///
  /// A [Vouch] does not remember the keys it was checked with: vouches a
  /// device keeps are checked again with its current keys whenever they
  /// are read, so a revoked Lychnion key's vouches lapse there too.
  static Future<Vouch?> check(Object? json, TrustedKeys trust) async =>
      (await _checked(json, trust)).vouch;

  /// The vouch in [json], and whether a signature check failed (a valid
  /// shape and a trusted signer, but a wrong signature).
  static Future<({Vouch? vouch, bool badSignature})> _checked(
    Object? json,
    TrustedKeys trust,
  ) async {
    const none = (vouch: null, badSignature: false);
    try {
      final j = (json! as Map).cast<String, Object?>();
      final at = _shape(j);
      if (at == null) return none;
      // A copy all the way down: a caller changing its map afterwards
      // cannot change this vouch.
      final v = Vouch._(
        Map.unmodifiable({
          for (final e in j.entries)
            e.key: e.value is Map
                ? Map<String, String>.unmodifiable(
                    (e.value! as Map).cast<String, String>(),
                  )
                : e.value,
        }),
        at,
      );
      if (!trust.keysOf(voucherPublisher).contains(v.signer)) return none;
      final ok = await _ed25519.verify(
        utf8.encode(v.signedText),
        signature: Signature(
          unb64(j['signature']! as String),
          publicKey: SimplePublicKey(
            unb64(v.signer),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      return ok
          ? (vouch: v, badSignature: false)
          : (vouch: null, badSignature: true);
    } on Object {
      return none;
    }
  }

  /// After this many wrong signatures from one source, the rest of it is
  /// not checked: anyone can name Lychnion's (public) key, and each try
  /// costs a signature check, slow on old phones (as for key statements).
  static const maxBadSignatures = 32;

  /// The valid vouches in [list] (each once), at most [max]; anything
  /// else is left out. At most `4 * max` entries are read, each written
  /// the same way only once, and none after [maxBadSignatures] wrong
  /// signatures.
  static Future<List<Vouch>> checkAll(
    Object? list,
    TrustedKeys trust, {
    int max = maxPerSource,
  }) async {
    if (list is! List) return const [];
    final out = <Vouch>[];
    final seen = <String>{};
    var bad = 0;
    for (final raw in list.take(max * 4)) {
      if (out.length >= max || bad >= maxBadSignatures) break;
      // The same entry twice costs one check.
      final String text;
      try {
        text = canonicalJson(raw);
      } on Object {
        continue;
      }
      if (!seen.add(text)) continue;
      final r = await _checked(raw, trust);
      if (r.badSignature) bad++;
      if (r.vouch case final v?) out.add(v);
    }
    return out;
  }

  /// True when vouch JSON [a] (signed at [ta]) decides over [b] (signed at
  /// [tb]) for the same publisher: the newer one; on the same time a
  /// withdrawal; then the one whose text sorts last, so every device picks
  /// the same one whatever the order of its list.
  static bool _decides(
    Map<Object?, Object?> a,
    DateTime ta,
    Map<Object?, Object?> b,
    DateTime tb,
  ) {
    if (!ta.isAtSameMomentAs(tb)) return ta.isAfter(tb);
    final wa = a['withdrawn'] == true, wb = b['withdrawn'] == true;
    if (wa != wb) return wa;
    return canonicalJson(a).compareTo(canonicalJson(b)) > 0;
  }

  /// At most [max] of [vouches] to pass on, chosen in [keepOrder]; their
  /// order otherwise kept.
  static List<Vouch> capped(Iterable<Vouch> vouches, [int max = maxPerSource]) {
    final all = vouches.toList();
    if (all.length <= max) return all;
    final keep = keepOrder([for (final v in all) v.json]).take(max).toSet();
    return [
      for (var i = 0; i < all.length; i++)
        if (keep.contains(i)) all[i],
    ];
  }

  /// The indexes of [vouches] (vouch JSON) in the order they are kept when
  /// not all fit. First the vouch that decides for each publisher (as
  /// [vouchFor] picks it): withdrawals before the others (losing one would
  /// show a publisher as vouched for again), then the newest. Then the
  /// vouches a newer one replaced, which change nothing; entries that are
  /// not vouches last. Used by [capped] and `CatalogDocument.fitted`.
  static List<int> keepOrder(List<Object?> vouches) {
    final at = <int, DateTime>{};
    final newest = <String, int>{};
    for (var i = 0; i < vouches.length; i++) {
      final m = vouches[i];
      if (m is! Map || m['signed'] is! String || m['publisher'] is! String) {
        continue;
      }
      final t = _time(m['signed'] as String);
      if (t == null) continue;
      at[i] = t;
      final name = m['publisher'] as String;
      final cur = newest[name];
      if (cur == null ||
          _decides(m, t, vouches[cur]! as Map<Object?, Object?>, at[cur]!)) {
        newest[name] = i;
      }
    }
    final deciding = newest.values.toSet();
    int rank(int i) {
      if (!at.containsKey(i)) return 3;
      if (!deciding.contains(i)) return 2;
      return (vouches[i]! as Map)['withdrawn'] == true ? 0 : 1;
    }

    final idx = List<int>.generate(vouches.length, (i) => i);
    idx.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final ta = at[a], tb = at[b];
      if (ta != null && tb != null && ta != tb) return tb.compareTo(ta);
      return a.compareTo(b);
    });
    return idx;
  }

  /// The fields a vouch may have; others would let a vouch grow without
  /// bound.
  static const _fields = {
    'format',
    'publisher',
    'key',
    'title',
    'checked',
    'method',
    'url',
    'withdrawn',
    'signed',
    'signer',
    'signature',
  };

  static final _day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// A time with seconds and a zone (`Z` or `+09:00`), so every device
  /// orders vouches the same way.
  static final _stamp = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?'
    r'(Z|[+-](\d{2}):(\d{2}))$',
  );

  /// Printable ASCII only: an address with spaces, line breaks or other
  /// characters could look like another one.
  static final _printable = RegExp(r'^[\x21-\x7e]+$');
  static final _method = RegExp(r'^[a-z][a-z0-9-]{0,39}$');
  static final _lang = RegExp(r'^[a-z]{2}$');

  /// Characters that could make one name look like another or hide part
  /// of it (controls, format characters such as zero-width and direction
  /// marks, line and paragraph separators, private and unassigned code
  /// points, Hangul fillers); a title with one is refused.
  static final _hidden = RegExp(
    r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Co}\p{Cn}\u115f\u1160\u3164\uffa0]',
    unicode: true,
  );

  /// Years a vouch may name: a time far in the future would decide over
  /// every later vouch, a withdrawal too (and never pass).
  static const _years = (first: 2020, last: 2100);

  static bool _validDay(int y, int m, int d) =>
      y >= _years.first &&
      y <= _years.last &&
      m >= 1 &&
      m <= 12 &&
      d >= 1 &&
      d <= DateTime.utc(y, m + 1, 0).day;

  /// [s] as a time, or null unless it is written as [_stamp] says, is a
  /// real time (no February 31st) and in [_years].
  static DateTime? _time(String s) {
    final m = _stamp.firstMatch(s);
    if (m == null) return null;
    int n(int g) => int.parse(m[g]!);
    if (!_validDay(n(1), n(2), n(3)) || n(4) > 23 || n(5) > 59 || n(6) > 59) {
      return null;
    }
    if (m[8] != 'Z' && (n(9) > 14 || n(10) > 59)) return null;
    return DateTime.tryParse(s);
  }

  /// [v] is base64url of [length] bytes, written the one way [b64] writes
  /// it (as for key statements: one vouch, one spelling, one [id]).
  static bool _canonical(Object? v, int length) {
    if (v is! String || v.length > 100) return false;
    try {
      final b = unb64(v);
      return b.length == length && b64(b) == v;
    } on FormatException {
      return false;
    }
  }

  /// When [j] was signed, or null when its shape is wrong.
  static DateTime? _shape(Map<String, Object?> j) {
    if (j['format'] != format) return null;
    if (!j.keys.every(_fields.contains)) return null;
    final publisher = j['publisher'];
    if (publisher is! String ||
        !publisherNamePattern.hasMatch(publisher) ||
        publisher == voucherPublisher) {
      return null;
    }
    if (!_canonical(j['key'], 32) ||
        !_canonical(j['signer'], 32) ||
        !_canonical(j['signature'], 64)) {
      return null;
    }
    final checked = j['checked'];
    final day = checked is String ? _day.firstMatch(checked) : null;
    if (day == null ||
        !_validDay(
          int.parse(day[1]!),
          int.parse(day[2]!),
          int.parse(day[3]!),
        )) {
      return null;
    }
    final method = j['method'];
    if (method is! String || !_method.hasMatch(method)) return null;
    final title = j['title'];
    if (title != null) {
      if (title is! Map || title.isEmpty || title.length > 4) return null;
      for (final e in title.entries) {
        final t = e.value;
        if (e.key is! String || !_lang.hasMatch(e.key as String)) return null;
        if (t is! String || t.trim().isEmpty || t.runes.length > 60) {
          return null;
        }
        if (_hidden.hasMatch(t)) return null;
      }
    }
    final url = j['url'];
    if (url != null) {
      if (url is! String || url.length > 300) return null;
      if (!_printable.hasMatch(url)) return null;
      final u = Uri.tryParse(url);
      // No `user@` before the host (it makes another host look like the
      // one shown), no port, and written as the address reads back.
      if (u == null ||
          u.scheme != 'https' ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty ||
          u.hasPort ||
          u.toString() != url) {
        return null;
      }
    }
    if (j.containsKey('withdrawn') && j['withdrawn'] != true) return null;
    final signed = j['signed'];
    return signed is String ? _time(signed) : null;
  }

  /// A vouch for [publisher]'s [key], signed with [signer] (a key of
  /// [voucherPublisher]). Throws [ArgumentError] when the result would not
  /// pass [check]'s shape rules.
  static Future<Vouch> sign({
    required String publisher,
    required String key,
    required String checked,
    required String method,
    required String signed,
    required SimpleKeyPair signer,
    Map<String, String> title = const {},
    String? url,
    bool withdrawn = false,
  }) async {
    final j = <String, Object?>{
      'format': format,
      'publisher': publisher,
      'key': TrustedKeys.canonicalKey(key),
      if (title.isNotEmpty) 'title': title,
      'checked': checked,
      'method': method,
      'url': ?url,
      if (withdrawn) 'withdrawn': true,
      'signed': signed,
      'signer': await publicKeyOf(signer),
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64((await _ed25519.sign(text, keyPair: signer)).bytes);
    final at = _shape(j);
    if (at == null) throw ArgumentError('not a valid vouch: $j');
    return Vouch._(Map.unmodifiable(j), at);
  }
}

/// Where a publisher stands with the vouches a device knows.
enum VouchStatus {
  /// The newest vouch for its name is for this key (or a key this key
  /// replaced, by the publisher's own key statements).
  vouched,

  /// The newest vouch for its name takes the vouch back.
  withdrawn,

  /// Its name has a vouch, but for another key: a link with this key is
  /// not the vouched-for publisher (or a key it has not announced).
  otherKey,

  /// This key was revoked by the publisher's own key statement (stolen or
  /// lost): nothing of it counts, vouched for or not.
  revoked,

  /// No vouch for its name: added by the user, not checked by Lychnion.
  none,
}

/// The status, and the vouch that decided it (null for `VouchStatus.none`).
typedef VouchResult = ({VouchStatus status, Vouch? vouch});

/// What [vouches] (already checked, see [Vouch.check]) say about
/// [publisher]'s [key]. The newest vouch for that name decides (on the
/// same time a withdrawal, then the same one on every device; a
/// withdrawal counts for the name, whichever key it names). Key
/// statements of the publisher itself apply: a key the vouched key
/// replaced, or one that replaced it, is vouched too; a revoked key is
/// [VouchStatus.revoked].
VouchResult vouchFor(
  String publisher,
  String key,
  Iterable<Vouch> vouches,
  Iterable<KeyStatement> statements,
) {
  Vouch? newest;
  for (final v in vouches) {
    if (v.publisher != publisher) continue;
    final n = newest;
    if (n == null || Vouch._decides(v.json, v.signedAt, n.json, n.signedAt)) {
      newest = v;
    }
  }
  if (newest == null) return (status: VouchStatus.none, vouch: null);
  if (newest.withdrawn) return (status: VouchStatus.withdrawn, vouch: newest);
  final String canonical;
  try {
    canonical = TrustedKeys.canonicalKey(key);
  } on FormatException {
    return (status: VouchStatus.otherKey, vouch: newest);
  }
  final mine = resolveKeys(publisher, [canonical], statements).keys;
  if (mine.isEmpty) return (status: VouchStatus.revoked, vouch: newest);
  final vouched = resolveKeys(publisher, [newest.key], statements).keys;
  final same =
      vouched.contains(canonical) || mine.intersection(vouched).isNotEmpty;
  return (
    status: same ? VouchStatus.vouched : VouchStatus.otherKey,
    vouch: newest,
  );
}
