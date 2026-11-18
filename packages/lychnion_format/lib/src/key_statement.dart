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
  String get id => canonicalJson(json);

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

  /// The valid statements in [list] (a catalog's `keys`); others, and
  /// any after the first [maxPerSource], are left out.
  static Future<List<KeyStatement>> checkAll(Object? list) async {
    if (list is! List) return const [];
    final out = <KeyStatement>[];
    for (final raw in list.take(maxPerSource)) {
      if (await check(raw) case final s? when !out.contains(s)) out.add(s);
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

  static bool _shapeOk(Map<String, Object?> j) {
    if (j['format'] != format) return false;
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
