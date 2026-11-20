import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encoding.dart';
import 'record.dart';

// Key statements (docs/distribution.md, "Replacing a key"): a publisher
// replaces its key, or revokes one. Signed like records, so any catalog,
// stick, base or phone can carry them unchanged; phones apply them to the
// keys they trust (TrustedKeys.withStatements).

final _ed25519 = Ed25519();

enum KeyStatementType {
  /// The old key names its successor; signed by both keys.
  replace,

  /// The key is not to be trusted any more; signed by that key.
  revoke,
}

/// A signed key statement. Only made by [check] (signatures verified) or
/// by [replace] and [revoke] (signed here), so every instance is valid.
class KeyStatement {
  KeyStatement._(this.json);

  /// Statement format.
  static const format = 1;

  /// At most this many statements are read from one catalog or stick.
  static const maxPerSource = 500;

  /// At most this many replacements are kept per publisher (a key that is
  /// replaced every month needs 50 in four years).
  static const maxReplacesPerPublisher = 50;

  /// At most [max] of [statements] to pass on: revocations first (losing
  /// one would trust a stolen key again), then the newest replacements;
  /// order otherwise kept.
  static List<KeyStatement> capped(
    Iterable<KeyStatement> statements, [
    int max = maxPerSource,
  ]) {
    final all = statements.toList();
    if (all.length <= max) return all;
    final keep = <KeyStatement>{
      ...all.where((s) => s.type == KeyStatementType.revoke).take(max),
    };
    for (final s in all.reversed) {
      if (keep.length >= max) break;
      keep.add(s);
    }
    return [
      for (final s in all)
        if (keep.contains(s)) s,
    ];
  }

  /// The whole statement as published, signatures included.
  final Map<String, Object?> json;

  KeyStatementType get type =>
      KeyStatementType.values.byName(json['type']! as String);
  String get publisher => json['publisher']! as String;

  /// The key replaced or revoked (Ed25519, base64url).
  String get oldKey => json['old']! as String;

  /// The successor ([KeyStatementType.replace] only).
  String? get newKey => json['new'] as String?;
  String get signed => json['signed']! as String;

  String get oldKeyId => recordKeyIdOf(unb64(oldKey));
  String? get newKeyId => newKey == null ? null : recordKeyIdOf(unb64(newKey!));

  /// The text both signatures cover.
  String get signedText => canonicalJson(
    Map.of(json)
      ..remove('signature')
      ..remove('new_signature'),
  );

  /// Same statement (whatever the JSON formatting).
  late final String id = canonicalJson(json);

  @override
  bool operator ==(Object other) => other is KeyStatement && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// The statement in [json], or null when its shape or a signature is
  /// wrong. Never throws.
  static Future<KeyStatement?> check(Object? json) async {
    try {
      final j = (json! as Map).cast<String, Object?>();
      if (!_shapeOk(j)) return null;
      final s = KeyStatement._(Map.unmodifiable(j));
      final text = utf8.encode(s.signedText);
      if (!await _verify(text, j['signature']! as String, s.oldKey)) {
        return null;
      }
      if (s.type == KeyStatementType.replace &&
          !await _verify(text, j['new_signature']! as String, s.newKey!)) {
        return null;
      }
      return s;
    } on Object {
      return null;
    }
  }

  /// The valid statements in [list] (a file this device wrote); others,
  /// and any after the first [max] valid ones, are left out. For lists
  /// from elsewhere use [relevantStatements].
  static Future<List<KeyStatement>> checkAll(
    Object? list, {
    int max = maxPerSource,
  }) async {
    if (list is! List) return const [];
    final out = <KeyStatement>[];
    final seen = <String>{};
    for (final raw in list) {
      if (out.length >= max) break;
      if (await check(raw) case final s? when seen.add(s.id)) out.add(s);
    }
    return out;
  }

  static bool _key(Object? v) {
    if (v is! String) return false;
    try {
      return unb64(v).length == 32;
    } on FormatException {
      return false;
    }
  }

  /// The fields a statement may have; other fields would let anyone who
  /// holds a key make statements large enough to fill a catalog.
  static const _fields = {
    'format',
    'type',
    'publisher',
    'old',
    'new',
    'signed',
    'signature',
    'new_signature',
  };

  static bool _shapeOk(Map<String, Object?> j) {
    if (j['format'] != format) return false;
    if (!j.keys.every(_fields.contains)) return false;
    bool short(Object? v, int max) => v is String && v.length <= max;
    if (!short(j['signed'], 64) ||
        !short(j['signature'], 100) ||
        (j.containsKey('new_signature') && !short(j['new_signature'], 100))) {
      return false;
    }
    final type = j['type'];
    final publisher = j['publisher'];
    if (publisher is! String || !publisherNamePattern.hasMatch(publisher)) {
      return false;
    }
    final signed = j['signed'];
    if (signed is! String || signed.isEmpty) return false;
    if (!_key(j['old']) || j['signature'] is! String) return false;
    switch (type) {
      case 'replace':
        if (!_key(j['new']) || j['new_signature'] is! String) return false;
        // The same key written differently is still the same key.
        return b64(unb64(j['old']! as String)) !=
            b64(unb64(j['new']! as String));
      case 'revoke':
        return !j.containsKey('new') && !j.containsKey('new_signature');
      default:
        return false;
    }
  }

  static Future<bool> _verify(List<int> text, String sig, String key) =>
      _ed25519.verify(
        text,
        signature: Signature(
          unb64(sig),
          publicKey: SimplePublicKey(unb64(key), type: KeyPairType.ed25519),
        ),
      );

  /// [oldKey] names [newKey] as the publisher's key from now on.
  static Future<KeyStatement> replace({
    required String publisher,
    required SimpleKeyPair oldKey,
    required SimpleKeyPair newKey,
    required String signed,
  }) async {
    final j = <String, Object?>{
      'format': format,
      'type': KeyStatementType.replace.name,
      'publisher': publisher,
      'old': await publicKeyOf(oldKey),
      'new': await publicKeyOf(newKey),
      'signed': signed,
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64((await _ed25519.sign(text, keyPair: oldKey)).bytes);
    j['new_signature'] = b64(
      (await _ed25519.sign(text, keyPair: newKey)).bytes,
    );
    return (await check(j))!;
  }

  /// [key] is revoked: records and statements it signed are not trusted.
  static Future<KeyStatement> revoke({
    required String publisher,
    required SimpleKeyPair key,
    required String signed,
  }) async {
    final j = <String, Object?>{
      'format': format,
      'type': KeyStatementType.revoke.name,
      'publisher': publisher,
      'old': await publicKeyOf(key),
      'signed': signed,
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64((await _ed25519.sign(text, keyPair: key)).bytes);
    return (await check(j))!;
  }
}

/// What [statements] say about [publisher], starting from the keys a
/// device trusts on its own ([roots]: built in, or added by a link).
///
/// - A revoked key is not trusted.
/// - A key that names two different successors is treated as revoked:
///   only a thief and the owner both holding it would do that.
/// - A successor is trusted when the key that names it is trusted and
///   not revoked, so a key reached only through a revoked key is dropped.
///
/// Returns the trusted keys (base64url, unpadded) and the ids of the
/// revoked ones.
({Set<String> keys, Set<String> revokedIds}) resolveKeys(
  String publisher,
  Iterable<String> roots,
  Iterable<KeyStatement> statements,
) {
  String norm(String k) => b64(unb64(k));
  final mine = [
    for (final s in statements)
      if (s.publisher == publisher) s,
  ];
  final revoked = <String>{
    for (final s in mine)
      if (s.type == KeyStatementType.revoke) norm(s.oldKey),
  };
  final successors = <String, Set<String>>{};
  for (final s in mine) {
    if (s.type != KeyStatementType.replace) continue;
    successors.putIfAbsent(norm(s.oldKey), () => {}).add(norm(s.newKey!));
  }
  for (final e in successors.entries) {
    if (e.value.length > 1) revoked.add(e.key);
  }
  final trusted = {
    for (final k in roots)
      if (!revoked.contains(norm(k))) norm(k),
  };
  var grew = true;
  while (grew) {
    grew = false;
    for (final k in [...trusted]) {
      for (final next in successors[k] ?? const <String>{}) {
        if (!revoked.contains(next) && trusted.add(next)) grew = true;
      }
    }
  }
  return (
    keys: trusted,
    revokedIds: {for (final k in revoked) recordKeyIdOf(unb64(k))},
  );
}

/// At most this many entries of a list from elsewhere are looked at.
const _maxScanned = 2000;

/// Verifying stops after this many bad signatures in one list: entries
/// that name a trusted key but are not signed by it cost a verification
/// each, and anyone can make them.
const _maxBadSignatures = 32;

/// A JSON object with only a key statement's fields, each a string or a
/// number: nothing nested.
bool _flat(Object? e) =>
    e is Map &&
    e.length <= KeyStatement._fields.length &&
    e.entries.every(
      (f) =>
          f.key is String &&
          KeyStatement._fields.contains(f.key) &&
          (f.value is String || f.value is num),
    );

/// The statements in [list] (raw JSON, as in a catalog's `keys`, or
/// [KeyStatement]s) that change something for [trust]: each made by a key
/// [trust] trusts for that publisher, counting the statements taken
/// before it. Taken in rounds until none is added, so the order in the
/// list does not matter (a revocation of a successor listed before the
/// replacement that names it still counts).
///
/// Only those statements are verified: anyone can sign statements about
/// keys of their own, and they cost nothing here and never crowd out real
/// ones. Entries that name a trusted key with a bad signature stop being
/// verified after a few; repeated entries are verified once. At most
/// [max] are returned (not counting those [trust] has), and at most
/// [KeyStatement.maxReplacesPerPublisher] replacements are kept per
/// publisher (a thief could sign a long chain of keys of its own);
/// revocations always count.
Future<List<KeyStatement>> relevantStatements(
  TrustedKeys trust,
  Object? list, {
  int max = KeyStatement.maxPerSource,
}) async {
  if (list is! List) return const [];
  final known = trust.known.toSet();
  String? norm(Object? k) {
    if (k is! String) return null;
    try {
      final b = unb64(k);
      return b.length == 32 ? b64(b) : null;
    } on FormatException {
      return null;
    }
  }

  final pending = <({String publisher, String old, Object raw})>[];
  final rawSeen = <String>{};
  for (final e in list.take(_maxScanned)) {
    // Only a flat object of a statement's own fields is looked at, before
    // anything walks it: a deeply nested entry would overflow the stack
    // (lychnion/lychnion#78).
    if (e is! KeyStatement && !_flat(e)) continue;
    try {
      if (!rawSeen.add(e is KeyStatement ? e.id : canonicalJson(e))) continue;
    } on FormatException {
      // A number JSON cannot write (1e999 decodes to Infinity).
      continue;
    }
    final (publisher, old) = switch (e) {
      KeyStatement s => (s.publisher, norm(s.oldKey)),
      Map<Object?, Object?> m => (m['publisher'], norm(m['old'])),
      _ => (null, null),
    };
    if (publisher is String && old != null && known.contains(publisher)) {
      pending.add((publisher: publisher, old: old, raw: e as Object));
    }
  }
  final all = [...trust.statements];
  final seen = {for (final s in all) s.id};
  final out = <KeyStatement>[];
  final trustedNow = <String, Set<String>>{};
  Set<String> keysOf(String p) =>
      trustedNow[p] ??= resolveKeys(p, trust.rootsOf(p), all).keys;
  final replaces = <String, int>{};
  for (final s in all) {
    if (s.type == KeyStatementType.replace) {
      replaces[s.publisher] = (replaces[s.publisher] ?? 0) + 1;
    }
  }
  var bad = 0;
  var grew = true;
  while (grew && out.length < max) {
    grew = false;
    for (final c in [...pending]) {
      if (out.length >= max) break;
      if (!keysOf(c.publisher).contains(c.old)) continue;
      pending.remove(c);
      // A replacement past the cap counts only as proof of a theft: its
      // old key already names another successor. Checked before
      // verifying, so statements past the cap cost nothing.
      final isReplace = switch (c.raw) {
        KeyStatement k => k.type == KeyStatementType.replace,
        Map<Object?, Object?> m => m['type'] == 'replace',
        _ => false,
      };
      final newKey = norm(switch (c.raw) {
        KeyStatement k => k.newKey,
        Map<Object?, Object?> m => m['new'],
        _ => null,
      });
      final atCap =
          isReplace &&
          (replaces[c.publisher] ?? 0) >= KeyStatement.maxReplacesPerPublisher;
      if (atCap && !_namesOther(all, c.publisher, c.old, newKey)) continue;
      final KeyStatement? s;
      if (c.raw case final KeyStatement k) {
        s = k;
      } else {
        if (bad >= _maxBadSignatures) continue;
        s = await KeyStatement.check(c.raw);
        if (s == null) bad++;
      }
      if (s == null || !seen.add(s.id)) continue;
      if (isReplace) replaces[s.publisher] = (replaces[s.publisher] ?? 0) + 1;
      all.add(s);
      out.add(s);
      trustedNow.remove(s.publisher);
      grew = true;
    }
  }
  return out;
}

/// True when [statements] already have [publisher]'s key [old] name a
/// successor other than [newKey]: one more replacement of [old] is then
/// proof that two people hold it.
bool _namesOther(
  Iterable<KeyStatement> statements,
  String publisher,
  String old,
  String? newKey,
) {
  for (final s in statements) {
    if (s.publisher == publisher &&
        s.type == KeyStatementType.replace &&
        b64(unb64(s.oldKey)) == old &&
        b64(unb64(s.newKey!)) != newKey) {
      return true;
    }
  }
  return false;
}

/// True when [s] is a replacement whose old key already names another
/// successor in [statements] (see [resolveKeys]: the key then counts as
/// revoked). Such a statement protects like a revocation.
bool provesTheft(KeyStatement s, Iterable<KeyStatement> statements) =>
    s.type == KeyStatementType.replace &&
    _namesOther(
      statements,
      s.publisher,
      b64(unb64(s.oldKey)),
      b64(unb64(s.newKey!)),
    );
