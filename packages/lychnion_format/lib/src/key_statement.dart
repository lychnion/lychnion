import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encoding.dart';
import 'record.dart';

// Key statements (docs/distribution.md, "Replacing a key"): a publisher
// replaces its key, or revokes one. Signed like records, so any catalog,
// stick, base or phone can carry them unchanged; phones apply them to the
// keys they trust (TrustedKeys.withStatements).

final _ed25519 = Ed25519();

/// What a publisher's key may sign (lychnion/lychnion#125). A record, an
/// attestation or a status signed by a key outside the scope it needs is
/// refused like a bad signature. Keys a device trusts on its own (built in,
/// or added by a link) hold every scope; a key named by a [grant] holds
/// the scopes the grant lists; a successor by [replace] holds those of the
/// key it replaces.
///
/// [grant]: KeyStatementType.grant
/// [replace]: KeyStatementType.replace
abstract final class KeyScope {
  /// Guides, maps, contour lines and other items that are not models, and
  /// a publisher's status.
  static const data = 'data';

  /// Records of kind `model`.
  static const models = 'models';

  /// The official safety lines (alerts) in a package: they count only when
  /// the package's signer holds this scope.
  static const safetyLines = 'safety-lines';

  /// Lychnion's attestations for official publishers.
  static const attestations = 'attestations';

  /// Grants, and revocations of the publisher's other keys.
  static const keys = 'keys';

  static const all = {data, models, safetyLines, attestations, keys};

  /// Valid signatures from distinct keys holding the scope that a record
  /// needs (see PackageRecord's `signatures`). One for every scope for
  /// now; it can be raised for `models`, `safety-lines` and `keys` later.
  static const required = {
    data: 1,
    models: 1,
    safetyLines: 1,
    attestations: 1,
    keys: 1,
  };

  /// The scope a record of [kind] needs.
  static String forKind(String kind) => kind == 'model' ? models : data;
}

enum KeyStatementType {
  /// The old key names its successor; signed by both keys.
  replace,

  /// The key is not to be trusted any more; signed by that key, or by
  /// another key of the publisher holding [KeyScope.keys] (`by`).
  revoke,

  /// A key holding [KeyScope.keys] (`old`) names another key of the
  /// publisher (`new`) with a scope; signed by both keys.
  grant,
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

  /// At most [max] of [statements] to pass on, chosen in [keepOrder];
  /// their order otherwise kept.
  static List<KeyStatement> capped(
    Iterable<KeyStatement> statements, [
    int max = maxPerSource,
  ]) {
    final all = statements.toList();
    if (all.length <= max) return all;
    final keep = keepOrder([for (final s in all) s.json]).take(max).toSet();
    return [
      for (var i = 0; i < all.length; i++)
        if (keep.contains(i)) all[i],
    ];
  }

  /// The indexes of [statements] (statement JSON) in the order they are
  /// kept when not all fit (lychnion/lychnion#59): revocations first, then
  /// replacements that prove a theft (losing either would trust a stolen
  /// key again), then grants (#125), then the other replacements chain by
  /// chain from the
  /// first key, nearest first, so what is kept still connects to a key a
  /// device knows. Ties keep the list order. Used by [capped] and
  /// `CatalogDocument.fitted`.
  static List<int> keepOrder(List<Object?> statements) {
    String? key(Object? v) {
      try {
        return v is String ? b64(unb64(v)) : null;
      } on FormatException {
        return null;
      }
    }

    final revokes = <int>[], thefts = <int>[], grants = <int>[];
    // Replacements: (publisher, old, new) by index.
    final replaces = <int, (String, String, String)>{};
    for (var i = 0; i < statements.length; i++) {
      final m = statements[i];
      if (m is! Map) continue;
      final p = m['publisher'], old = key(m['old']), next = key(m['new']);
      if (m['type'] == 'revoke') {
        revokes.add(i);
      } else if (m['type'] == 'grant') {
        grants.add(i);
      } else if (m['type'] == 'replace' &&
          p is String &&
          old != null &&
          next != null) {
        replaces[i] = (p, old, next);
      }
    }
    final successors = <(String, String), Set<String>>{};
    for (final (p, old, next) in replaces.values) {
      successors.putIfAbsent((p, old), () => {}).add(next);
    }
    // How far each replacement is from a key no replacement names.
    final named = {for (final (p, _, next) in replaces.values) (p, next)};
    final depth = <int, int>{};
    var level = {
      for (final e in replaces.entries)
        if (!named.contains((e.value.$1, e.value.$2))) e.key,
    };
    for (var d = 0; level.isNotEmpty; d++) {
      for (final i in level) {
        depth[i] = d;
      }
      final reached = {
        for (final i in level) (replaces[i]!.$1, replaces[i]!.$3),
      };
      level = {
        for (final e in replaces.entries)
          if (!depth.containsKey(e.key) &&
              reached.contains((e.value.$1, e.value.$2)))
            e.key,
      };
    }
    final rest = <int>[];
    for (final e in replaces.entries) {
      final (p, old, _) = e.value;
      (successors[(p, old)]!.length > 1 ? thefts : rest).add(e.key);
    }
    // In a loop with no first key: after the rest.
    int d(int i) => depth[i] ?? 1 << 30;
    rest.sort((a, b) {
      final c = d(a).compareTo(d(b));
      return c != 0 ? c : a.compareTo(b);
    });
    final ordered = [...revokes, ...thefts, ...grants, ...rest];
    final done = ordered.toSet();
    return [
      ...ordered,
      // Anything else last, in list order.
      for (var i = 0; i < statements.length; i++)
        if (!done.contains(i)) i,
    ];
  }

  /// The whole statement as published, signatures included.
  final Map<String, Object?> json;

  KeyStatementType get type =>
      KeyStatementType.values.byName(json['type']! as String);
  String get publisher => json['publisher']! as String;

  /// The key replaced or revoked (Ed25519, base64url).
  String get oldKey => json['old']! as String;

  /// The successor ([KeyStatementType.replace]) or the key granted
  /// ([KeyStatementType.grant]).
  String? get newKey => json['new'] as String?;
  String get signed => json['signed']! as String;

  /// What a [KeyStatementType.grant] lets its new key sign ([KeyScope]).
  List<String> get scope => [
    for (final x in (json['scope'] as List?) ?? const []) x as String,
  ];

  /// The key that revokes [oldKey] for the publisher, when it is not
  /// [oldKey] itself ([KeyStatementType.revoke] only); it counts when it
  /// holds [KeyScope.keys].
  String? get by => json['by'] as String?;

  /// The key that made the statement: [by] when given, else [oldKey].
  String get maker => by ?? oldKey;

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
      final s = KeyStatement._(
        Map.unmodifiable({
          for (final e in j.entries)
            e.key: e.value is List
                ? List<String>.unmodifiable((e.value! as List).cast<String>())
                : e.value,
        }),
      );
      final text = utf8.encode(s.signedText);
      if (!await _verify(text, j['signature']! as String, s.maker)) {
        return null;
      }
      if (s.type != KeyStatementType.revoke &&
          !await _verify(text, j['new_signature']! as String, s.newKey!)) {
        return null;
      }
      return s;
    } on Object {
      return null;
    }
  }

  /// [json] with its signatures written the one way [check] takes them
  /// (base64url without padding), for statements a device stored before
  /// that rule (lychnion/lychnion#59); anything else unchanged. Still to
  /// be verified with [check].
  static Object? respelled(Object? json) {
    if (json is! Map) return json;
    final out = Map<Object?, Object?>.of(json);
    for (final f in const ['signature', 'new_signature']) {
      final v = out[f];
      if (v is! String || v.length > 200) continue;
      try {
        out[f] = b64(unb64(v));
      } on FormatException {
        continue;
      }
    }
    return out;
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

  /// The fields a statement may have; other fields would let anyone who
  /// holds a key make statements large enough to fill a catalog.
  static const _fields = {
    'format',
    'type',
    'publisher',
    'old',
    'new',
    'scope',
    'by',
    'signed',
    'signature',
    'new_signature',
  };

  /// [v] is base64url of [length] bytes, written the one way [b64]
  /// writes it: no padding, no other alphabet or escapes. Otherwise one
  /// statement could be written many ways that all verify, each with its
  /// own [id], and count many times against the caps (lychnion/lychnion#59).
  static bool _canonical(Object? v, int length) {
    if (v is! String || v.length > 100) return false;
    try {
      final b = unb64(v);
      return b.length == length && b64(b) == v;
    } on FormatException {
      return false;
    }
  }

  static bool _shapeOk(Map<String, Object?> j) {
    if (j['format'] != format) return false;
    if (!j.keys.every(_fields.contains)) return false;
    final signed = j['signed'];
    if (signed is! String || signed.isEmpty || signed.length > 64) {
      return false;
    }
    if (!_canonical(j['signature'], 64)) return false;
    final type = j['type'];
    final publisher = j['publisher'];
    if (publisher is! String || !publisherNamePattern.hasMatch(publisher)) {
      return false;
    }
    if (!_canonical(j['old'], 32)) return false;
    switch (type) {
      case 'replace':
        if (j.containsKey('scope') || j.containsKey('by')) return false;
        if (!_canonical(j['new'], 32) || !_canonical(j['new_signature'], 64)) {
          return false;
        }
        return j['old'] != j['new'];
      case 'grant':
        if (j.containsKey('by') || !_scopeOk(j['scope'])) return false;
        if (!_canonical(j['new'], 32) || !_canonical(j['new_signature'], 64)) {
          return false;
        }
        return j['old'] != j['new'];
      case 'revoke':
        if (j.containsKey('new') ||
            j.containsKey('new_signature') ||
            j.containsKey('scope')) {
          return false;
        }
        if (j.containsKey('by')) {
          return _canonical(j['by'], 32) && j['by'] != j['old'];
        }
        return true;
      default:
        return false;
    }
  }

  /// A non-empty list of [KeyScope]s, sorted and each once: one way to
  /// write each grant.
  static bool _scopeOk(Object? v) {
    if (v is! List || v.isEmpty || v.length > KeyScope.all.length) {
      return false;
    }
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x is! String || !KeyScope.all.contains(x)) return false;
      if (i > 0 && (v[i - 1] as String).compareTo(x) >= 0) return false;
    }
    return true;
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
  /// With [by] (another key of the publisher holding [KeyScope.keys]),
  /// [key] is named by its public key [revoked] and [by] signs: the root
  /// cuts off a stolen everyday key it does not hold.
  static Future<KeyStatement> revoke({
    required String publisher,
    SimpleKeyPair? key,
    String? revoked,
    SimpleKeyPair? by,
    required String signed,
  }) async {
    if ((key == null) == (revoked == null)) {
      throw ArgumentError('give key or revoked');
    }
    if (revoked != null && by == null) throw ArgumentError('revoked needs by');
    final j = <String, Object?>{
      'format': format,
      'type': KeyStatementType.revoke.name,
      'publisher': publisher,
      'old': revoked != null
          ? TrustedKeys.canonicalKey(revoked)
          : await publicKeyOf(key!),
      'by': ?(by == null ? null : await publicKeyOf(by)),
      'signed': signed,
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64(
      (await _ed25519.sign(text, keyPair: by ?? key!)).bytes,
    );
    return (await check(j)) ?? (throw ArgumentError('not a valid revocation'));
  }

  /// [granter] (a key of [publisher] holding [KeyScope.keys]) names
  /// [newKey] as a key of [publisher] that may sign [scope]; signed by
  /// both.
  static Future<KeyStatement> grant({
    required String publisher,
    required SimpleKeyPair granter,
    required SimpleKeyPair newKey,
    required Iterable<String> scope,
    required String signed,
  }) async {
    final j = <String, Object?>{
      'format': format,
      'type': KeyStatementType.grant.name,
      'publisher': publisher,
      'old': await publicKeyOf(granter),
      'new': await publicKeyOf(newKey),
      'scope': ({...scope}.toList()..sort()),
      'signed': signed,
    };
    final text = utf8.encode(canonicalJson(j));
    j['signature'] = b64((await _ed25519.sign(text, keyPair: granter)).bytes);
    j['new_signature'] = b64(
      (await _ed25519.sign(text, keyPair: newKey)).bytes,
    );
    return (await check(j)) ?? (throw ArgumentError('not a valid grant'));
  }
}

/// What [statements] say about [publisher], starting from the keys a
/// device trusts on its own ([roots]: built in, or added by a link; they
/// hold every [KeyScope]).
///
/// - A revoked key is not trusted. A revocation by the key itself always
///   counts; one made `by` another key counts when that key holds
///   [KeyScope.keys], judged with the keys trusted before any such
///   revocation (so two keys revoking each other are both revoked).
/// - A key that names two different successors is treated as revoked:
///   only a thief and the owner both holding it would do that. A key may
///   grant many keys.
/// - A successor is trusted, with the scopes of the key that names it,
///   when that key is trusted and not revoked; a granted key is trusted,
///   with the scopes its grant lists, when its granter is trusted, holds
///   [KeyScope.keys] and is not revoked. So a key reached only through a
///   revoked key is dropped: revoking the root also drops the keys it
///   granted, as it drops its successors. Scopes reached more than one
///   way add up.
///
/// Returns the trusted keys (base64url, unpadded), the scopes of each, and
/// the ids of the revoked ones.
({Set<String> keys, Map<String, Set<String>> scopes, Set<String> revokedIds})
resolveKeys(
  String publisher,
  Iterable<String> roots,
  Iterable<KeyStatement> statements,
) {
  String norm(String k) => b64(unb64(k));
  final mine = [
    for (final s in statements)
      if (s.publisher == publisher) s,
  ];
  final selfRevoked = <String>{
    for (final s in mine)
      if (s.type == KeyStatementType.revoke && s.by == null) norm(s.oldKey),
  };
  final successors = <String, Set<String>>{};
  final grants = <String, List<(String, List<String>)>>{};
  for (final s in mine) {
    switch (s.type) {
      case KeyStatementType.replace:
        successors.putIfAbsent(norm(s.oldKey), () => {}).add(norm(s.newKey!));
      case KeyStatementType.grant:
        grants.putIfAbsent(norm(s.oldKey), () => []).add((
          norm(s.newKey!),
          s.scope,
        ));
      case KeyStatementType.revoke:
        break;
    }
  }
  for (final e in successors.entries) {
    if (e.value.length > 1) selfRevoked.add(e.key);
  }
  Map<String, Set<String>> trustedWith(Set<String> revoked) {
    final t = <String, Set<String>>{
      for (final k in roots)
        if (!revoked.contains(norm(k))) norm(k): {...KeyScope.all},
    };
    bool add(String k, Iterable<String> scope) {
      final have = t.putIfAbsent(k, () => {});
      final before = have.length;
      have.addAll(scope);
      return have.length != before;
    }

    var grew = true;
    while (grew) {
      grew = false;
      for (final e in [...t.entries]) {
        for (final next in successors[e.key] ?? const <String>{}) {
          if (!revoked.contains(next) && add(next, e.value)) grew = true;
        }
        if (!e.value.contains(KeyScope.keys)) continue;
        for (final (next, scope)
            in grants[e.key] ?? const <(String, List<String>)>[]) {
          if (!revoked.contains(next) && add(next, scope)) grew = true;
        }
      }
    }
    return t;
  }

  final before = trustedWith(selfRevoked);
  final revoked = {
    ...selfRevoked,
    for (final s in mine)
      if (s.type == KeyStatementType.revoke &&
          s.by != null &&
          (before[norm(s.by!)]?.contains(KeyScope.keys) ?? false))
        norm(s.oldKey),
  };
  final trusted = revoked.length == selfRevoked.length
      ? before
      : trustedWith(revoked);
  return (
    keys: trusted.keys.toSet(),
    scopes: trusted,
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
          (f.value is String ||
              f.value is num ||
              (f.key == 'scope' &&
                  f.value is List &&
                  (f.value as List).length <= KeyScope.all.length &&
                  (f.value as List).every((x) => x is String))),
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
    // Made by `by` when given (a revocation by another key), else by `old`.
    final (publisher, old) = switch (e) {
      KeyStatement s => (s.publisher, norm(s.maker)),
      Map<Object?, Object?> m => (m['publisher'], norm(m['by'] ?? m['old'])),
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
