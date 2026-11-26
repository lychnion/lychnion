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
/// the scopes the grant lists ([grantable]); a successor by [replace]
/// holds those of the key it replaces.
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

  /// Grants, and revocations of the publisher's granted keys. Held only by
  /// the roots: it cannot be granted in stage 1 (delegating it returns
  /// with more than one signature, lychnion/lychnion#118 stage 2).
  static const keys = 'keys';

  static const all = {data, models, safetyLines, attestations, keys};

  /// The scopes a grant may list: all but [keys].
  static const grantable = {data, models, safetyLines, attestations};

  /// Valid signatures from distinct keys holding the scope that a record
  /// needs (see PackageRecord's `signatures`): for its kind (`data`,
  /// `models`), and `safety-lines` for a package's official lines. One for
  /// now; it can be raised later. Attestations and key statements carry
  /// one signature each: more for them needs a format change (#118
  /// stage 2).
  static const required = {data: 1, models: 1, safetyLines: 1};

  /// The scope a record of [kind] needs.
  static String forKind(String kind) => kind == 'model' ? models : data;
}

enum KeyStatementType {
  /// The old key names its successor; signed by both keys.
  replace,

  /// The key is not to be trusted any more; signed by that key, or by a
  /// current root of the publisher (`by`) when the key is a granted one.
  revoke,

  /// A current root of the publisher (`old`) names another key of the
  /// publisher (`new`) with a scope ([KeyScope.grantable]); signed by both
  /// keys.
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

  /// At most this many grants and revocations `by` a root, and
  /// replacements within a root chain, are taken per publisher
  /// (lychnion/lychnion#125): only the root's holder makes them, but an
  /// added publisher's root (or a thief of it) must not fill a phone's
  /// list.
  static const maxRootGrantsPerPublisher = 100;
  static const maxRootReplacesPerPublisher = 200;

  /// At most [max] of [statements] to pass on, chosen in [keepOrder];
  /// their order otherwise kept.
  /// With [trust], the current roots' statements come right after the
  /// revocations by the key itself and theft proofs ([keepOrder]).
  static List<KeyStatement> capped(
    Iterable<KeyStatement> statements, [
    int max = maxPerSource,
    TrustedKeys? trust,
  ]) {
    final all = statements.toList();
    if (all.length <= max) return all;
    final keep = keepOrder([
      for (final s in all) s.json,
    ], trust: trust).take(max).toSet();
    return [
      for (var i = 0; i < all.length; i++)
        if (keep.contains(i)) all[i],
    ];
  }

  /// The indexes of [statements] (statement JSON) in the order they are
  /// kept when not all fit (lychnion/lychnion#59): revocations by the key
  /// itself first, then replacements that prove a theft (losing either
  /// would trust a stolen key again), then, with [trust], statements made
  /// by a current root of their publisher there (#125: its rotation and
  /// grants are never cut for others'), then revocations by another key,
  /// grants, and the other replacements chain by chain from the first key,
  /// nearest first, so what is kept still connects to a key a device
  /// knows. Ties keep the list order. Used by [capped] and
  /// `CatalogDocument.fitted`.
  static List<int> keepOrder(List<Object?> statements, {TrustedKeys? trust}) {
    String? key(Object? v) {
      try {
        return v is String ? b64(unb64(v)) : null;
      } on FormatException {
        return null;
      }
    }

    final revokes = <int>[], thefts = <int>[], grants = <int>[];
    final byRevokes = <int>[], rooted = <int>[];
    final rootsOf = <String, Set<String>>{};
    final chainOf = <String, Set<String>>{};
    bool byRoot(Map<Object?, Object?> m) {
      final p = m['publisher'], maker = m['by'] ?? m['old'];
      if (trust == null || p is! String || maker is! String) return false;
      return _byRoot(
        p,
        '${m['type']}',
        maker,
        m['new'] is String ? m['new'] as String : null,
        (p) => rootsOf[p] ??= trust.currentRootsOf(p),
        (p) => chainOf[p] ??= trust.rootChainOf(p),
      );
    }

    // Replacements: (publisher, old, new) by index.
    final replaces = <int, (String, String, String)>{};
    for (var i = 0; i < statements.length; i++) {
      final m = statements[i];
      if (m is! Map) continue;
      final p = m['publisher'], old = key(m['old']), next = key(m['new']);
      if (m['type'] == 'revoke' && m['by'] == null) {
        revokes.add(i);
      } else if (m['type'] == 'revoke') {
        (byRoot(m) ? rooted : byRevokes).add(i);
      } else if (m['type'] == 'grant') {
        (byRoot(m) ? rooted : grants).add(i);
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
      if (successors[(p, old)]!.length > 1) {
        thefts.add(e.key);
      } else if (byRoot(statements[e.key]! as Map)) {
        rooted.add(e.key);
      } else {
        rest.add(e.key);
      }
    }
    rooted.sort();
    // In a loop with no first key: after the rest.
    int d(int i) => depth[i] ?? 1 << 30;
    rest.sort((a, b) {
      final c = d(a).compareTo(d(b));
      return c != 0 ? c : a.compareTo(b);
    });
    final ordered = [
      ...revokes,
      ...thefts,
      ...rooted,
      ...byRevokes,
      ...grants,
      ...rest,
    ];
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
  /// [oldKey] itself ([KeyStatementType.revoke] only); it counts only for
  /// a current root revoking a granted key (see [resolveKeys]).
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

  /// A non-empty list of [KeyScope.grantable] scopes, sorted and each
  /// once: one way to write each grant; never `keys`.
  static bool _scopeOk(Object? v) {
    if (v is! List || v.isEmpty || v.length > KeyScope.grantable.length) {
      return false;
    }
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x is! String || !KeyScope.grantable.contains(x)) return false;
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
  /// With [by] (a current root of the publisher), [key] is named by its
  /// public key [revoked] and [by] signs: the root cuts off a stolen
  /// granted key it does not hold.
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

  /// [granter] (a current root of [publisher]) names [newKey] as a key of
  /// [publisher] that may sign [scope] (never [KeyScope.keys]); signed by
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

/// What [resolveKeys] finds for one publisher. Keys are base64url,
/// unpadded.
typedef KeyGraph = ({
  /// The trusted keys.
  Set<String> keys,

  /// What each trusted key may sign ([KeyScope]).
  Map<String, Set<String>> scopes,

  /// Ids of the revoked keys.
  Set<String> revokedIds,

  /// The current roots: of each chain from a key trusted on its own, the
  /// newest key (no trusted successor). Only they grant and revoke `by`,
  /// and their statements are never crowded out (lychnion/lychnion#125).
  Set<String> currentRoots,

  /// The trusted keys reached through a grant (granted keys and their
  /// successors): what a current root may revoke `by`.
  Set<String> granted,

  /// The trusted roots and their successors by `replace`, current or not.
  Set<String> rootChain,
});

/// What [statements] say about [publisher], starting from the keys a
/// device trusts on its own ([roots]: built in, or added by a link; they
/// hold every [KeyScope]).
///
/// - A revoked key is not trusted, nor any key reached only through it.
///   A revocation by the key itself always counts. A key that names two
///   different successors is treated as revoked: only a thief and the
///   owner both holding it would do that.
/// - The roots and their successors by `replace` (each with every scope)
///   form root chains; the newest key of each, with no trusted successor,
///   is a **current root**.
/// - Only a current root grants (lychnion/lychnion#125): a granted key is
///   trusted with the scopes its grants list (never `keys`: there are no
///   delegates in stage 1). After a root is replaced, its grants lapse;
///   the new root grants again. A granted key's successor by `replace`
///   holds its scopes.
/// - Only a current root revokes another key (`by`), and only a key
///   trusted through a grant: never a root or a key of a root chain,
///   which only revoke themselves or are replaced. Any current root may
///   revoke any granted key.
/// - Records name a key by a short id ([recordKeyIdOf]), so no two
///   trusted keys may share one: a trusted key outside the roots whose id
///   is a root's or another trusted key's is not trusted (the roots
///   always are). Only the root's holder can grant, so making such a key
///   takes the root anyway. [keyIdOf] replaces the id function in tests.
KeyGraph resolveKeys(
  String publisher,
  Iterable<String> roots,
  Iterable<KeyStatement> statements, {
  String Function(String key)? keyIdOf,
}) {
  String norm(String k) => b64(unb64(k));
  final idOf = keyIdOf ?? (String k) => recordKeyIdOf(unb64(k));
  final rootSet = {for (final k in roots) norm(k)};
  final selfRevoked = <String>{};
  final successors = <String, Set<String>>{};
  final grants = <String, List<(String, List<String>)>>{};
  final byRevokes = <(String, String)>[];
  for (final s in statements) {
    if (s.publisher != publisher) continue;
    final old = norm(s.oldKey);
    switch (s.type) {
      case KeyStatementType.replace:
        successors.putIfAbsent(old, () => {}).add(norm(s.newKey!));
      case KeyStatementType.grant:
        grants.putIfAbsent(old, () => []).add((norm(s.newKey!), s.scope));
      case KeyStatementType.revoke:
        if (s.by == null) {
          selfRevoked.add(old);
        } else {
          byRevokes.add((norm(s.by!), old));
        }
    }
  }
  for (final e in successors.entries) {
    if (e.value.length > 1) selfRevoked.add(e.key);
  }

  ({
    Map<String, Set<String>> scopes,
    Set<String> chain,
    Set<String> current,
    Set<String> granted,
    Set<String> revoked,
  })
  build(Set<String> excluded) {
    bool ok(String k) => !selfRevoked.contains(k) && !excluded.contains(k);
    final chain = <String>{};
    final todo = [
      for (final k in rootSet)
        if (!selfRevoked.contains(k)) k,
    ];
    while (todo.isNotEmpty) {
      final x = todo.removeLast();
      if (!chain.add(x)) continue;
      for (final n in successors[x] ?? const <String>{}) {
        if (rootSet.contains(n) ? !selfRevoked.contains(n) : ok(n)) {
          todo.add(n);
        }
      }
    }
    final current = {
      for (final k in chain)
        if (!(successors[k]?.any(chain.contains) ?? false)) k,
    };
    Map<String, Set<String>> grantedWithout(Set<String> revoked) {
      bool take(String k) =>
          !chain.contains(k) &&
          !rootSet.contains(k) &&
          ok(k) &&
          !revoked.contains(k);
      final out = <String, Set<String>>{};
      for (final r in current) {
        for (final (g, scope)
            in grants[r] ?? const <(String, List<String>)>[]) {
          if (take(g)) out.putIfAbsent(g, () => {}).addAll(scope);
        }
      }
      var grew = true;
      while (grew) {
        grew = false;
        for (final e in [...out.entries]) {
          for (final n in successors[e.key] ?? const <String>{}) {
            if (!take(n)) continue;
            final have = out.putIfAbsent(n, () => {});
            final before = have.length;
            have.addAll(e.value);
            if (have.length != before) grew = true;
          }
        }
      }
      return out;
    }

    final before = grantedWithout(const {});
    final revoked = {
      ...selfRevoked,
      for (final (maker, target) in byRevokes)
        if (current.contains(maker) && before.containsKey(target)) target,
    };
    final granted = grantedWithout(revoked);
    return (
      scopes: {
        for (final k in chain) k: {...KeyScope.all},
        ...granted,
      },
      chain: chain,
      current: current,
      granted: granted.keys.toSet(),
      revoked: revoked,
    );
  }

  var r = build(const {});
  // Short ids shared among trusted keys: the roots win, then the other
  // keys of root chains; a granted key that clashes is not trusted.
  final rootIds = {for (final k in rootSet) idOf(k)};
  final chainIds = {for (final k in r.chain) idOf(k)};
  final byId = <String, Set<String>>{};
  for (final k in r.scopes.keys) {
    if (!r.chain.contains(k)) byId.putIfAbsent(idOf(k), () => {}).add(k);
  }
  final clashing = {
    for (final k in r.chain)
      if (!rootSet.contains(k) && rootIds.contains(idOf(k))) k,
    for (final e in byId.entries)
      if (e.value.length > 1 || chainIds.contains(e.key)) ...e.value,
  };
  if (clashing.isNotEmpty) r = build(clashing);
  return (
    keys: r.scopes.keys.toSet(),
    scopes: r.scopes,
    revokedIds: {for (final k in r.revoked) recordKeyIdOf(unb64(k))},
    currentRoots: r.current,
    granted: r.granted,
    rootChain: r.chain,
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
/// replacement that names it still counts; a grant by a root's successor
/// waits for the replacement that names it).
///
/// Only those statements are verified: anyone can sign statements about
/// keys of their own, and they cost nothing here and never crowd out real
/// ones. Entries that name a trusted key with a bad signature stop being
/// verified after a few; repeated entries are verified once. Grants and
/// revocations `by` another key (lychnion/lychnion#125) count only when
/// made by a current root (`currentRoots` of [KeyGraph]), a revocation
/// only of a granted key: both checked before verifying, so a granted
/// key or a replaced root costs nothing with them.
///
/// Taken in [statementRank] order: revocations by the key itself, then
/// the current roots' statements, then the rest in list order. At most
/// [max] of the rest are returned (not counting those [trust] has), and
/// at most [KeyStatement.maxReplacesPerPublisher] replacements are kept
/// per publisher (a thief could sign a long chain of keys of its own);
/// the first two kinds always count. Returned in that order.
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

  final pending =
      <
        ({
          int index,
          String publisher,
          String maker,
          String? target,
          String? newKey,
          Object raw,
          String kind,
        })
      >[];
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
    final (publisher, maker, target, newKey) = switch (e) {
      KeyStatement s => (
        s.publisher,
        norm(s.maker),
        norm(s.oldKey),
        norm(s.newKey),
      ),
      Map<Object?, Object?> m => (
        m['publisher'],
        norm(m['by'] ?? m['old']),
        norm(m['old']),
        norm(m['new']),
      ),
      _ => (null, null, null, null),
    };
    // `revoke` (by the key itself), `revoke-by`, `grant` or `replace`.
    final kind = switch (e) {
      KeyStatement s =>
        s.type == KeyStatementType.revoke && s.by != null
            ? 'revoke-by'
            : s.type.name,
      Map<Object?, Object?> m =>
        m['type'] == 'revoke' && m['by'] != null ? 'revoke-by' : '${m['type']}',
      _ => '',
    };
    if (publisher is String && maker != null && known.contains(publisher)) {
      pending.add((
        index: pending.length,
        publisher: publisher,
        maker: maker,
        target: target,
        newKey: newKey,
        raw: e as Object,
        kind: kind,
      ));
    }
  }
  final all = [...trust.statements];
  final seen = {for (final s in all) s.id};
  final taken = <(int, int, KeyStatement)>[];
  var others = 0;
  final graphs = <String, KeyGraph>{};
  KeyGraph graphOf(String p) =>
      graphs[p] ??= resolveKeys(p, trust.rootsOf(p), all);
  int rankOf(String kind, String publisher, String maker) => kind == 'revoke'
      ? 0
      : graphOf(publisher).currentRoots.contains(maker)
      ? 1
      : 2;
  final replaces = <String, int>{};
  // Grants and revocations `by` another key, per publisher.
  final rootGrants = <String, int>{};
  for (final s in all) {
    if (s.type == KeyStatementType.replace) {
      replaces[s.publisher] = (replaces[s.publisher] ?? 0) + 1;
    } else if (s.type == KeyStatementType.grant || s.by != null) {
      rootGrants[s.publisher] = (rootGrants[s.publisher] ?? 0) + 1;
    }
  }
  final done = <int>{};
  // Publishers whose graph a taken grant changed: resolved again at the
  // next round, not after each grant (a grant only adds a granted key,
  // whose own statements wait for that round).
  final stale = <String>{};
  var bad = 0;
  var grew = true;
  while (grew) {
    grew = false;
    stale.forEach(graphs.remove);
    stale.clear();
    final order = [
      for (final c in pending)
        if (!done.contains(c.index)) (rankOf(c.kind, c.publisher, c.maker), c),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.index - b.$2.index);
    for (final (_, c) in order) {
      final g = graphOf(c.publisher);
      // Not trusted (yet): it stays pending, a later statement may change
      // that.
      if (!g.scopes.containsKey(c.maker)) continue;
      final rank = rankOf(c.kind, c.publisher, c.maker);
      if (rank == 2 && others >= max) continue;
      // Only a current root grants or revokes another key, and only a
      // granted key: checked before verifying.
      final byRoot = c.kind == 'grant' || c.kind == 'revoke-by';
      if (byRoot) {
        if (rank != 1) continue;
        if (c.kind == 'revoke-by' && !g.granted.contains(c.target)) continue;
        if ((rootGrants[c.publisher] ?? 0) >=
            KeyStatement.maxRootGrantsPerPublisher) {
          continue;
        }
      }
      // A replacement past the cap counts only as proof of a theft: its
      // old key already names another successor. A current root's has a
      // larger cap. Checked before verifying.
      final isReplace = c.kind == 'replace';
      if (isReplace &&
          (replaces[c.publisher] ?? 0) >=
              (rank == 1
                  ? KeyStatement.maxRootReplacesPerPublisher
                  : KeyStatement.maxReplacesPerPublisher) &&
          !_namesOther(all, c.publisher, c.maker, c.newKey)) {
        continue;
      }
      final KeyStatement? s;
      if (c.raw case final KeyStatement k) {
        s = k;
      } else {
        if (bad >= _maxBadSignatures) continue;
        s = await KeyStatement.check(c.raw);
        if (s == null) bad++;
      }
      // Verified once, whatever the outcome.
      done.add(c.index);
      if (s == null || !seen.add(s.id)) continue;
      if (isReplace) replaces[s.publisher] = (replaces[s.publisher] ?? 0) + 1;
      if (byRoot) rootGrants[s.publisher] = (rootGrants[s.publisher] ?? 0) + 1;
      all.add(s);
      taken.add((rank, taken.length, s));
      if (rank == 2) others++;
      // A grant only adds a granted key: resolved at the next round. A
      // revocation or replacement may change the roots: now.
      if (s.type == KeyStatementType.grant) {
        stale.add(s.publisher);
      } else {
        graphs.remove(s.publisher);
        stale.remove(s.publisher);
      }
      grew = true;
    }
  }
  taken.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final (_, _, s) in taken) s];
}

/// The order in which a statement is taken and kept when not all fit
/// (lychnion/lychnion#125): 0 for a revocation by the key itself, 1 for a
/// statement made by a current root of its publisher in [trust]
/// (`currentRoots` of [KeyGraph]) or a replacement within a root chain
/// (the root's rotations, also once the newer key is current), 2 for any
/// other.
int statementRank(KeyStatement s, TrustedKeys trust) {
  if (s.type == KeyStatementType.revoke && s.by == null) return 0;
  return _byRoot(
        s.publisher,
        s.type.name,
        s.maker,
        s.newKey,
        trust.currentRootsOf,
        trust.rootChainOf,
      )
      ? 1
      : 2;
}

/// True for a statement made by a current root, or a replacement from a
/// key of a root chain to another (see [statementRank]).
bool _byRoot(
  String publisher,
  String type,
  String maker,
  String? newKey,
  Set<String> Function(String) currentRootsOf,
  Set<String> Function(String) rootChainOf,
) {
  String? norm(String? k) {
    if (k == null) return null;
    try {
      return b64(unb64(k));
    } on FormatException {
      return null;
    }
  }

  final m = norm(maker);
  if (m == null) return false;
  if (currentRootsOf(publisher).contains(m)) return true;
  final chain = rootChainOf(publisher);
  return type == 'replace' && chain.contains(m) && chain.contains(norm(newKey));
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
