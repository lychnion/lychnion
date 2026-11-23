import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'attestation.dart';
import 'encoding.dart';
import 'key_statement.dart';
import 'record.dart';

// Publisher status (lychnion/lychnion#117): a publisher signs, now and then,
// what is newest from it: the newest version of each of its items, its own
// key statements (replacements, revocations) and, for Lychnion, the
// attestations it took back. Signed like records, so any catalog, stick,
// base or phone carries it unchanged.
//
// Offline, a carrier can always hold data back; no signature prevents that.
// A status makes it visible: a phone that keeps the newest status it has
// seen can say that a newer version exists, how old its news is, and whose
// key was revoked or which check was taken back, even when the carrier
// passed on only the status. It never stops anything from working.

final _ed25519 = Ed25519();

/// A signed status. Only made by [check] (shape and signature verified) or
/// [sign], so every instance is valid; [check] also makes sure the signer is
/// a key the device trusts for the status's publisher.
///
/// ```json
/// {"format": 1, "publisher": "lychnion",
///  "signed": "2026-11-24T09:00:00+09:00",
///  "items": {"jp.bousai.core": "2026.11.10", …},
///  "keys": [<key statement>, …],
///  "attestations": [<withdrawn attestation>, …],
///  "signer": "<key>", "signature": "…"}
/// ```
///
/// `keys` and `attestations` are optional, and checked by their own rules
/// when a device takes them in; `attestations` only in Lychnion's status
/// ([attesterPublisher]), and only withdrawals.
class PublisherStatus {
  PublisherStatus._(this.json, this.signedAt);

  /// Status format.
  static const format = 1;

  /// At most this many statuses are read from one catalog or stick: one per
  /// publisher.
  static const maxPerSource = 100;

  /// At most this many items, key statements and attestations in one status.
  static const maxItems = 1000;
  static const maxKeys = KeyStatement.maxPerSource;
  static const maxAttestations = Attestation.maxPerSource;

  /// A status larger than this (its canonical text) is refused.
  static const maxBytes = 512 << 10;

  /// After this many wrong signatures from one source, the rest of it is
  /// not checked (as for key statements and attestations).
  static const maxBadSignatures = 32;

  /// The whole status as published, signature included.
  final Map<String, Object?> json;

  /// When it was signed: the newest status of a publisher decides.
  final DateTime signedAt;

  String get publisher => json['publisher']! as String;
  String get signed => json['signed']! as String;
  String get signer => json['signer']! as String;

  /// Item id → its newest version from this publisher.
  Map<String, String> get items =>
      (json['items'] as Map?)?.cast<String, String>() ?? const {};

  /// The publisher's key statements, as given (check with
  /// `KeyStatement.checkAll` before use).
  List<Object?> get keys => (json['keys'] as List?) ?? const [];

  /// Withdrawn attestations, as given (Lychnion's status only; check with
  /// `Attestation.checkAll` before use).
  List<Object?> get attestations => (json['attestations'] as List?) ?? const [];

  /// The text the signature covers.
  String get signedText => canonicalJson(Map.of(json)..remove('signature'));

  /// Same status (whatever the JSON formatting).
  late final String id = canonicalJson(json);

  @override
  bool operator ==(Object other) => other is PublisherStatus && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// True when this status is newer than [other] (of the same publisher):
  /// signed later; on the same time, the one whose text sorts last, so every
  /// device keeps the same one.
  bool decidesOver(PublisherStatus other) {
    if (!signedAt.isAtSameMomentAs(other.signedAt)) {
      return signedAt.isAfter(other.signedAt);
    }
    return id.compareTo(other.id) > 0;
  }

  /// True when this status names a newer version of item [id] than
  /// [version].
  bool hasNewer(String id, String version) {
    final v = items[id];
    return v != null && compareVersions(v, version) > 0;
  }

  /// The status in [json], or null when its shape or signature is wrong, or
  /// when its signer is not a key [trust] has for its publisher (after key
  /// statements, also those in the status itself: a successor key may sign
  /// it together with the statement that names it). Never throws.
  static Future<PublisherStatus?> check(
    Object? json,
    TrustedKeys trust,
  ) async => (await _checked(json, trust)).status;

  static Future<({PublisherStatus? status, bool badSignature})> _checked(
    Object? json,
    TrustedKeys trust,
  ) async {
    const none = (status: null, badSignature: false);
    try {
      final j = (json! as Map).cast<String, Object?>();
      final at = _shape(j);
      if (at == null) return none;
      // A copy all the way down: a caller changing its map afterwards
      // cannot change this status.
      final s = PublisherStatus._(_frozen(j), at);
      var keys = trust.keysOf(s.publisher);
      if (!keys.contains(s.signer) && s.keys.isNotEmpty) {
        keys = trust
            .withStatements(await KeyStatement.checkAll(s.keys))
            .keysOf(s.publisher);
      }
      if (!keys.contains(s.signer)) return none;
      final ok = await _ed25519.verify(
        utf8.encode(s.signedText),
        signature: Signature(
          unb64(j['signature']! as String),
          publicKey: SimplePublicKey(
            unb64(s.signer),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      return ok
          ? (status: s, badSignature: false)
          : (status: null, badSignature: true);
    } on Object {
      return none;
    }
  }

  /// The valid statuses in [list] (each once), at most [max]; anything else
  /// is left out. At most `4 * max` entries are read, and none after
  /// [maxBadSignatures] wrong signatures.
  static Future<List<PublisherStatus>> checkAll(
    Object? list,
    TrustedKeys trust, {
    int max = maxPerSource,
  }) async {
    if (list is! List) return const [];
    final out = <PublisherStatus>[];
    final seen = <String>{};
    var bad = 0;
    for (final raw in list.take(max * 4)) {
      if (out.length >= max || bad >= maxBadSignatures) break;
      final String text;
      try {
        text = canonicalJson(raw);
      } on Object {
        continue;
      }
      if (!seen.add(text)) continue;
      final r = await _checked(raw, trust);
      if (r.badSignature) bad++;
      if (r.status case final s?) out.add(s);
    }
    return out;
  }

  /// The newest status of each publisher in [statuses] ([decidesOver]), in
  /// the order of their first appearance.
  static List<PublisherStatus> newest(Iterable<PublisherStatus> statuses) {
    final byPublisher = <String, PublisherStatus>{};
    for (final s in statuses) {
      final cur = byPublisher[s.publisher];
      if (cur == null || s.decidesOver(cur)) byPublisher[s.publisher] = s;
    }
    return byPublisher.values.toList();
  }

  /// The indexes of [statuses] (status JSON) in the order they are kept when
  /// not all fit in a catalog: Lychnion's newest first, then the newest of
  /// each other publisher, newest first; then older ones; entries that are
  /// not statuses last. Used by `CatalogDocument.fitted`.
  static List<int> keepOrder(List<Object?> statuses) {
    final at = <int, DateTime>{};
    final newestOf = <String, int>{};
    for (var i = 0; i < statuses.length; i++) {
      final m = statuses[i];
      if (m is! Map || m['signed'] is! String || m['publisher'] is! String) {
        continue;
      }
      final t = signedTime(m['signed'] as String);
      if (t == null) continue;
      at[i] = t;
      final p = m['publisher'] as String;
      final cur = newestOf[p];
      if (cur == null || t.isAfter(at[cur]!)) newestOf[p] = i;
    }
    final deciding = newestOf.values.toSet();
    int rank(int i) {
      if (!at.containsKey(i)) return 3;
      if (!deciding.contains(i)) return 2;
      return (statuses[i]! as Map)['publisher'] == attesterPublisher ? 0 : 1;
    }

    final idx = List<int>.generate(statuses.length, (i) => i)
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final ta = at[a], tb = at[b];
        if (ta != null && tb != null && ta != tb) return tb.compareTo(ta);
        return a.compareTo(b);
      });
    return idx;
  }

  static const _fields = {
    'format',
    'publisher',
    'signed',
    'items',
    'keys',
    'attestations',
    'signer',
    'signature',
  };

  /// Item ids and versions: printable ASCII, short.
  static final _plain = RegExp(r'^[\x21-\x7e]{1,100}$');

  static Map<String, Object?> _frozen(Map<String, Object?> j) =>
      Map.unmodifiable({
        for (final e in j.entries)
          e.key: switch (e.value) {
            final Map<Object?, Object?> m => Map<String, String>.unmodifiable(
              m.cast<String, String>(),
            ),
            final List<Object?> l => List<Object?>.unmodifiable(
              l.map((x) => jsonDecode(jsonEncode(x))),
            ),
            final v => v,
          },
      });

  /// When [j] was signed, or null when its shape is wrong.
  static DateTime? _shape(Map<String, Object?> j) {
    if (j['format'] != format) return null;
    if (!j.keys.every(_fields.contains)) return null;
    final publisher = j['publisher'];
    if (publisher is! String || !publisherNamePattern.hasMatch(publisher)) {
      return null;
    }
    if (!_canonical(j['signer'], 32) || !_canonical(j['signature'], 64)) {
      return null;
    }
    final items = j['items'];
    if (items is! Map || items.length > maxItems) return null;
    for (final e in items.entries) {
      if (e.key is! String || !_plain.hasMatch(e.key as String)) return null;
      if (e.value is! String || !_plain.hasMatch(e.value as String)) {
        return null;
      }
    }
    final keys = j['keys'];
    if (keys != null &&
        (keys is! List ||
            keys.length > maxKeys ||
            keys.any((k) => k is! Map))) {
      return null;
    }
    final attestations = j['attestations'];
    if (attestations != null) {
      if (publisher != attesterPublisher ||
          attestations is! List ||
          attestations.length > maxAttestations ||
          attestations.any((a) => a is! Map || a['withdrawn'] != true)) {
        return null;
      }
    }
    if (utf8.encode(canonicalJson(j)).length > maxBytes) return null;
    final signed = j['signed'];
    return signed is String ? signedTime(signed) : null;
  }

  /// [v] is base64url of [length] bytes, written the one way [b64] writes it.
  static bool _canonical(Object? v, int length) {
    if (v is! String || v.length > 100) return false;
    try {
      final b = unb64(v);
      return b.length == length && b64(b) == v;
    } on FormatException {
      return false;
    }
  }

  /// A status of [publisher] signed with [signer] (one of its keys).
  /// Throws [ArgumentError] when the result would not pass [check]'s shape
  /// rules.
  static Future<PublisherStatus> sign({
    required String publisher,
    required String signed,
    required Map<String, String> items,
    required SimpleKeyPair signer,
    Iterable<KeyStatement> keys = const [],
    Iterable<Attestation> attestations = const [],
  }) async {
    final j = <String, Object?>{
      'format': format,
      'publisher': publisher,
      'signed': signed,
      'items': items,
      if (keys.isNotEmpty) 'keys': [for (final k in keys) k.json],
      if (attestations.isNotEmpty)
        'attestations': [for (final a in attestations) a.json],
      'signer': await publicKeyOf(signer),
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64((await _ed25519.sign(text, keyPair: signer)).bytes);
    final at = _shape(j);
    if (at == null) throw ArgumentError('not a valid status: $publisher');
    return PublisherStatus._(_frozen(j), at);
  }
}
