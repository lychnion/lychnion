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
  static Future<Vouch?> check(Object? json, TrustedKeys trust) async {
    try {
      final j = (json! as Map).cast<String, Object?>();
      final at = _shape(j);
      if (at == null) return null;
      final v = Vouch._(Map.unmodifiable(j), at);
      if (!trust.keysOf(voucherPublisher).contains(v.signer)) return null;
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
      return ok ? v : null;
    } on Object {
      return null;
    }
  }

  /// The valid vouches in [list] (each once), at most [max]; anything
  /// else is left out.
  static Future<List<Vouch>> checkAll(
    Object? list,
    TrustedKeys trust, {
    int max = maxPerSource,
  }) async {
    if (list is! List) return const [];
    final out = <Vouch>[];
    final seen = <String>{};
    // Each one is a signature check: a list far longer than could be kept
    // is not read to its end.
    for (final raw in list.take(max * 4)) {
      if (out.length >= max) break;
      if (await check(raw, trust) case final v? when seen.add(v.id)) {
        out.add(v);
      }
    }
    return out;
  }

  /// At most [max] of [vouches] to pass on: withdrawals first (losing one
  /// would show a publisher as vouched for again), then the newest; their
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
  /// not all fit: withdrawals first, then newest first; entries that are
  /// not vouches last. Used by [capped] and `CatalogDocument.fitted`.
  static List<int> keepOrder(List<Object?> vouches) {
    DateTime? at(Object? m) =>
        m is Map && m['signed'] is String ? _time(m['signed'] as String) : null;
    final idx = List<int>.generate(vouches.length, (i) => i);
    int rank(int i) {
      final m = vouches[i];
      if (m is! Map || at(m) == null) return 2;
      return m['withdrawn'] == true ? 0 : 1;
    }

    idx.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final ta = at(vouches[a]), tb = at(vouches[b]);
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

  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _method = RegExp(r'^[a-z][a-z0-9-]{0,39}$');
  static final _lang = RegExp(r'^[a-z]{2}$');

  /// Characters that could make one name look like another (controls,
  /// zero-width, direction changes); a title with one is refused.
  static final _hidden = RegExp(
    '[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]',
  );

  static DateTime? _time(String s) =>
      s.length > 64 ? null : DateTime.tryParse(s);

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
    if (checked is! String ||
        !_day.hasMatch(checked) ||
        DateTime.tryParse(checked) == null) {
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
      final u = Uri.tryParse(url);
      if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
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

  /// No vouch for its name: added by the user, not checked by Lychnion.
  none,
}

/// The status, and the vouch that decided it (null for `VouchStatus.none`).
typedef VouchResult = ({VouchStatus status, Vouch? vouch});

/// What [vouches] (already checked, see [Vouch.check]) say about
/// [publisher]'s [key]: the newest vouch for that name decides (on the
/// same time, a withdrawal wins). A vouched key's successors, by the
/// publisher's own key [statements], are vouched too; a revoked one is not.
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
    if (n == null ||
        v.signedAt.isAfter(n.signedAt) ||
        (v.signedAt.isAtSameMomentAs(n.signedAt) && v.withdrawn)) {
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
  final keys = resolveKeys(publisher, [newest.key], statements).keys;
  return (
    status: keys.contains(canonical)
        ? VouchStatus.vouched
        : VouchStatus.otherKey,
    vouch: newest,
  );
}
