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
    if (v == null) return false;
    try {
      return compareVersions(v, version) > 0;
    } on FormatException {
      // An installed version that is not a number (before records).
      return false;
    }
  }

  /// The status in [json], or null when its shape or signature is wrong, or
  /// when its signer is not a key [trust] has for its publisher that may
  /// sign data (KeyScope.data, lychnion/lychnion#125) (after key
  /// statements, also those in the status itself: a successor key may sign
  /// it together with the statement that names it). Never throws.
  static Future<PublisherStatus?> check(
    Object? json,
    TrustedKeys trust,
  ) async => (await _checked(json, trust, inline: true)).status;

  /// At most this many statuses of one source may have their inline key
  /// statements verified ([checkAll]). Only a status signed by a new
  /// successor key needs it, before devices know the replacement: rare.
  /// Each try costs up to about 32 signature checks.
  static const maxInlineChecks = 8;

  /// The status in [json]. [inline]: whether its inline key statements may
  /// be verified for its signer. `inlineTried`: they were (to count).
  static Future<
    ({PublisherStatus? status, bool badSignature, bool inlineTried})
  >
  _checked(Object? json, TrustedKeys trust, {required bool inline}) async {
    const none = (status: null, badSignature: false, inlineTried: false);
    try {
      final j = (json! as Map).cast<String, Object?>();
      final at = _shape(j);
      if (at == null) return none;
      // A copy all the way down: a caller changing its map afterwards
      // cannot change this status.
      final s = PublisherStatus._(_frozen(j), at);
      var keys = trust.keysFor(s.publisher, KeyScope.data);
      // A successor key may sign together with the statement that names
      // it. Only then are inline statements verified, and only those a key
      // trusted here made (relevantStatements): anyone can sign statements
      // about keys of their own, and each costs a check.
      var tried = false;
      if (inline &&
          !keys.contains(s.signer) &&
          s.keys.any((k) => k is Map && k['new'] == s.signer)) {
        tried = true;
        keys = trust
            .withStatements(await relevantStatements(trust, s.keys))
            .keysFor(s.publisher, KeyScope.data);
      }
      if (!keys.contains(s.signer)) {
        // Inline statements that did not make the signer trusted count as
        // a bad signature: they cost checks.
        return (status: null, badSignature: tried, inlineTried: tried);
      }
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
          ? (status: s, badSignature: false, inlineTried: tried)
          : (status: null, badSignature: true, inlineTried: tried);
    } on Object {
      return none;
    }
  }

  /// The valid statuses in [list] (each once), at most [max]; anything else
  /// is left out. At most `4 * max` entries are read, and none after
  /// [maxBadSignatures] wrong signatures. Inline key statements are verified
  /// for at most [maxInlineChecks] statuses; a status whose signer only they
  /// could make trusted is left out after that (the reader may know the
  /// statement from the catalog's `keys` anyway), and one they did not make
  /// trusted counts as a wrong signature.
  static Future<List<PublisherStatus>> checkAll(
    Object? list,
    TrustedKeys trust, {
    int max = maxPerSource,
  }) async {
    if (list is! List) return const [];
    final out = <PublisherStatus>[];
    final seen = <String>{};
    var bad = 0, inlineChecks = 0;
    for (final raw in list.take(max * 4)) {
      if (out.length >= max || bad >= maxBadSignatures) break;
      final String text;
      try {
        text = canonicalJson(raw);
      } on Object {
        continue;
      }
      if (!seen.add(text)) continue;
      final r = await _checked(
        raw,
        trust,
        inline: inlineChecks < maxInlineChecks,
      );
      if (r.inlineTried) inlineChecks++;
      if (r.badSignature) bad++;
      if (r.status case final s?) out.add(s);
    }
    return out;
  }

  /// How far a status may be signed after a reader's clock and still
  /// decide ([deciding]).
  static const maxAhead = Duration(days: 1);

  /// [statuses] without those signed more than [maxAhead] after [now]: a
  /// thief holding a key could otherwise pin "newest" far ahead and push
  /// the real status out. Every reader and carrier filters with it before
  /// [newest] (devices, sticks, bases, nodes).
  static List<PublisherStatus> deciding(
    Iterable<PublisherStatus> statuses,
    DateTime now,
  ) {
    final limit = now.add(maxAhead);
    return [
      for (final s in statuses)
        if (!s.signedAt.isAfter(limit)) s,
    ];
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
  /// not statuses last. Used by `CatalogDocument.fitted`. It reads the
  /// entries as given: callers verify them first ([checkAll]), or an entry
  /// dated far ahead would be kept over a real one.
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
      if (cur == null ||
          t.isAfter(at[cur]!) ||
          (t.isAtSameMomentAs(at[cur]!) &&
              _text(m).compareTo(_text(statuses[cur])) > 0)) {
        newestOf[p] = i;
      }
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
        // The same time: by publisher, so the same statuses are kept
        // whatever their order.
        final pa = _publisherOf(statuses[a]), pb = _publisherOf(statuses[b]);
        if (pa != pb) return pa.compareTo(pb);
        return a.compareTo(b);
      });
    return idx;
  }

  static String _publisherOf(Object? m) =>
      m is Map && m['publisher'] is String ? m['publisher'] as String : '';

  static String _text(Object? m) {
    try {
      return canonicalJson(m);
    } on Object {
      return '';
    }
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

  /// Item ids and versions as records have them (record.dart).
  static final _id = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');
  static final _windowsDevice = RegExp(
    r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\.|$)',
    caseSensitive: false,
  );
  static final _version = RegExp(r'^\d{1,9}(\.\d{1,9}){0,3}$');

  /// A copy all the way down, every map and list unmodifiable: a caller
  /// changing its map afterwards cannot change this status, nor anyone the
  /// status (its [id] is computed once). Bounded: [_shape] checked the size.
  static Map<String, Object?> _frozen(Map<String, Object?> j) =>
      _freeze(jsonDecode(jsonEncode(j))) as Map<String, Object?>;

  static Object? _freeze(Object? v) => switch (v) {
    final Map<Object?, Object?> m => Map<String, Object?>.unmodifiable({
      for (final e in m.entries) e.key! as String: _freeze(e.value),
    }),
    final List<Object?> l => List<Object?>.unmodifiable(l.map(_freeze)),
    final x => x,
  };

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
      final id = e.key, v = e.value;
      if (id is! String ||
          !_id.hasMatch(id) ||
          id.endsWith('.') ||
          _windowsDevice.hasMatch(id)) {
        return null;
      }
      if (v is! String || !_version.hasMatch(v)) return null;
    }
    final keys = j['keys'];
    if (keys != null &&
        (keys is! List ||
            keys.length > maxKeys ||
            keys.any((k) => k is! Map || k['publisher'] != publisher))) {
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
    final DateTime? at;
    try {
      final text = utf8.encode(canonicalJson(j));
      j['signature'] = b64((await _ed25519.sign(text, keyPair: signer)).bytes);
      at = _shape(j);
    } on ArgumentError {
      rethrow;
    } on Object catch (e) {
      throw ArgumentError('not a valid status: $publisher ($e)');
    }
    if (at == null) throw ArgumentError('not a valid status: $publisher');
    return PublisherStatus._(_frozen(j), at);
  }
}
