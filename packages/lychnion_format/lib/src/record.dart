import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encoding.dart';
import 'key_statement.dart';

// Signed package records (docs/distribution.md, step 1).
//
// Pure Dart (no Flutter), so the signing tool (lychnion-data/tool/records.dart) and a
// later headless node use the same code as the app.

final _ed25519 = Ed25519();

String _b64(List<int> b) => b64(b);
List<int> _unb64(String s) => unb64(s);

/// Short id of a public key: its first 6 bytes, base64url (8 characters).
/// Same as the key ids of signed base facts (lib/facts/signing.dart).
String recordKeyIdOf(List<int> publicKey) => _b64(publicKey.sublist(0, 6));

/// The bytes a signature covers: JSON with keys sorted, no spaces, and
/// only the escapes JSON requires (RFC 8785 for the values records use:
/// strings, integers, booleans, null, lists and objects). Any JSON
/// formatting of the same record gives the same text, so a record stays
/// valid however a node stores or re-serialises it.
String canonicalJson(Object? v) {
  final out = StringBuffer();
  void write(Object? v) {
    switch (v) {
      case null:
        out.write('null');
      case bool b:
        out.write(b);
      case int i:
        out.write(i);
      case double d when d == d.truncateToDouble() && d.abs() < 1e15:
        out.write(d.toInt());
      case String s:
        _writeString(out, s);
      case List<Object?> l:
        out.write('[');
        for (var i = 0; i < l.length; i++) {
          if (i > 0) out.write(',');
          write(l[i]);
        }
        out.write(']');
      case Map<Object?, Object?> m:
        final keys = [for (final k in m.keys) k as String]..sort();
        out.write('{');
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) out.write(',');
          _writeString(out, keys[i]);
          out.write(':');
          write(m[keys[i]]);
        }
        out.write('}');
      default:
        throw FormatException('Not allowed in a record: $v');
    }
  }

  write(v);
  return out.toString();
}

void _writeString(StringBuffer out, String s) {
  out.write('"');
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x09:
        out.write(r'\t');
      case 0x0a:
        out.write(r'\n');
      case 0x0c:
        out.write(r'\f');
      case 0x0d:
        out.write(r'\r');
      default:
        if (c < 0x20) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}

final _areaCode = RegExp(r'^[A-Z]{2}(-[A-Z0-9]{1,3})?$');

final _versionPattern = RegExp(r'^\d{1,9}(\.\d{1,9}){0,3}$');

/// Compares dotted version numbers ("2026.11.1" < "2026.11.10");
/// missing parts count as 0. Throws on anything else.
int compareVersions(String a, String b) {
  if (!_versionPattern.hasMatch(a) || !_versionPattern.hasMatch(b)) {
    throw FormatException('Not a version number: $a / $b');
  }
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 4; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// True when [version] is a valid version and lower than [installed].
/// An installed version that is not a number (before records existed)
/// blocks nothing.
bool isOlder(String version, String installed) {
  try {
    return compareVersions(version, installed) < 0;
  } on FormatException {
    return false;
  }
}

/// Ids and file names end up in file paths: letters, digits, `.`, `_`
/// and `-` only, not starting with a dot.
final _safeNamePattern = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');

/// Windows device names, also with an ending (`NUL`, `con.sqlite`): Windows
/// opens the device instead of a file.
final _windowsDevice = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\.|$)',
  caseSensitive: false,
);

/// A name that is the same file on every system: no trailing dot (Windows
/// drops it, so `x.sqlite.` would be `x.sqlite`) and no Windows device
/// name (lychnion/lychnion#76).
bool _safeName(String s) =>
    _safeNamePattern.hasMatch(s) &&
    !s.endsWith('.') &&
    !_windowsDevice.hasMatch(s);

class RecordFile {
  const RecordFile(this.name, this.size, this.sha256);
  final String name;
  final int size;

  /// Lower-case hex.
  final String sha256;

  Map<String, Object?> toJson() => {
    'name': name,
    'size': size,
    'sha256': sha256,
  };
}

/// One version of one package, map area or model, signed by its publisher.
///
/// A record says *what* a download is (files with size and SHA-256), not
/// *where* to get it: catalogs say that, so any node can serve the files
/// and carry the record unchanged.
class PackageRecord {
  PackageRecord._(this.json, this.files);

  /// The whole record as published, signature included.
  final Map<String, Object?> json;
  final List<RecordFile> files;

  String get id => json['id']! as String;
  String get kind => json['kind']! as String;
  String get version => json['version']! as String;
  String get publisher => json['publisher']! as String;
  String get keyId => json['key']! as String;
  String get signature => json['signature']! as String;
  String get signed => json['signed']! as String;
  String get licence => json['licence'] as String? ?? '';

  /// Places the item is for, as ISO 3166 codes: a country ('JP') or a
  /// region ('JP-30'). Empty means anywhere. Codes of another form are
  /// left out.
  List<String> get area => [
    for (final c in (json['area'] as List?) ?? const [])
      if (c is String && _areaCode.hasMatch(c)) c,
  ];
  String? get role => json['role'] as String?;
  bool get desktop => json['desktop'] as bool? ?? false;

  /// Platforms a model runs on ('android', 'ios', 'macos', 'windows',
  /// 'linux'). Empty means every one.
  List<String> get platforms => [
    for (final p in (json['platforms'] as List?) ?? const [])
      if (p is String) p,
  ];

  /// Language code → text, e.g. the `title` or `note` field.
  Map<String, String> texts(String field) => {
    for (final e in ((json[field] as Map?) ?? const {}).entries)
      if (e.value is String) e.key as String: e.value as String,
  };

  /// Language → lines shown before the package is relied on.
  Map<String, List<String>> get notice => {
    for (final e in ((json['notice'] as Map?) ?? const {}).entries)
      e.key as String: [for (final l in e.value as List) l as String],
  };

  /// The text the signature (by `key`) covers: the record without
  /// `signature`. It covers a `signatures` list too, so older apps that
  /// check only `key` and `signature` keep reading records that carry one.
  String get signedText => canonicalJson(Map.of(json)..remove('signature'));

  /// The text each entry of [signatures] covers: the record without
  /// `signature` and `signatures` (lychnion/lychnion#125).
  String get listSignedText => canonicalJson(
    Map.of(json)
      ..remove('signature')
      ..remove('signatures'),
  );

  /// More signatures (`signatures: [{"key": <key id>, "signature": …}]`),
  /// next to `key` and `signature`, when a scope needs more than one
  /// (KeyScope.required). Empty when there is none.
  List<({String keyId, String signature})> get signatures => [
    for (final e in (json['signatures'] as List?) ?? const [])
      (
        keyId: (e as Map)['key']! as String,
        signature: e['signature']! as String,
      ),
  ];

  /// Checks the shape (not the signature). Throws [FormatException].
  factory PackageRecord.fromJson(Map<String, Object?> j) {
    String str(String k) {
      final v = j[k];
      if (v is! String || v.isEmpty) throw FormatException('Record: no $k');
      return v;
    }

    if (j['format'] != 1) throw FormatException('Record: unknown format');
    for (final k in ['id', 'kind', 'publisher', 'key', 'signed', 'signature']) {
      str(k);
    }
    if (!_safeName(str('id'))) {
      throw FormatException('Record: bad id ${j['id']}');
    }
    if (!_versionPattern.hasMatch(str('version'))) {
      throw FormatException('Record: bad version ${j['version']}');
    }
    final raw = j['files'];
    if (raw is! List || raw.isEmpty) throw FormatException('Record: no files');
    final files = <RecordFile>[];
    for (final f in raw) {
      final m = f as Map;
      final name = m['name'], size = m['size'], sha = m['sha256'];
      if (name is! String || !_safeName(name)) {
        throw FormatException('Record: bad file name $name');
      }
      if (size is! int || size <= 0) throw FormatException('Record: bad size');
      if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
        throw FormatException('Record: bad sha256 for $name');
      }
      files.add(RecordFile(name, size, sha));
    }
    // Without case, as on macOS and Windows.
    if (files.map((f) => f.name.toLowerCase()).toSet().length != files.length) {
      throw FormatException('Record: duplicate file names');
    }
    final more = j['signatures'];
    if (more != null) {
      if (more is! List || more.isEmpty || more.length > maxSignatures) {
        throw FormatException('Record: bad signatures');
      }
      for (final e in more) {
        if (e is! Map ||
            e.length != 2 ||
            e['key'] is! String ||
            e['signature'] is! String ||
            (e['signature'] as String).length > 200) {
          throw FormatException('Record: bad signatures');
        }
      }
    }
    return PackageRecord._(Map.unmodifiable(j), List.unmodifiable(files));
  }

  /// At most this many entries in `signatures`.
  static const maxSignatures = 8;

  /// Signs [unsigned] (all fields but `signature`; `key` is set here).
  /// [more] keys sign too, in `signatures` (each over the record without
  /// `signature` and `signatures`); [key] signs last, over the record with
  /// that list.
  static Future<PackageRecord> sign(
    Map<String, Object?> unsigned,
    SimpleKeyPair key, {
    List<SimpleKeyPair> more = const [],
  }) async {
    final pub = (await key.extractPublicKey()).bytes;
    final j = Map.of(unsigned)
      ..remove('signature')
      ..remove('signatures')
      ..['key'] = recordKeyIdOf(pub);
    if (more.isNotEmpty) {
      final text = utf8.encode(canonicalJson(j));
      j['signatures'] = [
        for (final k in more)
          {
            'key': recordKeyIdOf((await k.extractPublicKey()).bytes),
            'signature': _b64((await _ed25519.sign(text, keyPair: k)).bytes),
          },
      ];
    }
    final sig = await _ed25519.sign(
      utf8.encode(canonicalJson(j)),
      keyPair: key,
    );
    j['signature'] = _b64(sig.bytes);
    return PackageRecord.fromJson(j);
  }
}

/// Key pair from a 32-byte private seed (base64url, as stored in 1Password).
Future<SimpleKeyPair> keyPairFromSeed(String seed) {
  final bytes = _unb64(seed.trim());
  if (bytes.length != 32) throw FormatException('Seed must be 32 bytes');
  return _ed25519.newKeyPairFromSeed(bytes);
}

Future<({String seed, String publicKey})> newKeyPair() async {
  final pair = await _ed25519.newKeyPair();
  return (
    seed: _b64(await pair.extractPrivateKeyBytes()),
    publicKey: _b64((await pair.extractPublicKey()).bytes),
  );
}

Future<String> publicKeyOf(SimpleKeyPair pair) async =>
    _b64((await pair.extractPublicKey()).bytes);

/// Publishers' public keys this device accepts records from.
///
/// Made from the keys the device trusts on its own (built in, or added by
/// a link: the roots) and the key statements it learned
/// ([withStatements]): a replaced key's successor is trusted too, a
/// revoked key is not (see [resolveKeys]).
class TrustedKeys {
  TrustedKeys(Map<String, List<String>> publicKeys)
    : this._(_rootsOf(const {}, publicKeys), const []);

  TrustedKeys._(this._roots, List<KeyStatement> statements)
    : statements = List.unmodifiable(statements) {
    for (final e in _roots.entries) {
      final r = resolveKeys(e.key, e.value, statements);
      _keys[e.key] = {
        for (final k in r.keys) recordKeyIdOf(_unb64(k)): _unb64(k),
      };
      _scopes[e.key] = {
        for (final x in r.scopes.entries)
          recordKeyIdOf(_unb64(x.key)): Set.unmodifiable(x.value),
      };
      _revoked[e.key] = r.revokedIds;
      _graphs[e.key] = r;
    }
  }

  /// Publisher name → keys trusted on its own (unpadded base64url).
  final Map<String, Set<String>> _roots;

  /// The key statements applied (only valid ones exist).
  final List<KeyStatement> statements;

  /// Publisher name → key id → 32-byte key, after the statements.
  final _keys = <String, Map<String, List<int>>>{};

  /// Publisher name → key id → what that key may sign ([KeyScope]).
  final _scopes = <String, Map<String, Set<String>>>{};
  final _revoked = <String, Set<String>>{};
  final _graphs = <String, KeyGraph>{};

  /// [publisher]'s current roots (unpadded base64url): the newest key of
  /// each root chain, the only keys that grant and revoke other keys, and
  /// whose statements are never crowded out (lychnion/lychnion#125).
  Set<String> currentRootsOf(String publisher) =>
      _graphs[publisher]?.currentRoots ?? const {};

  /// [publisher]'s trusted roots and their successors by `replace`,
  /// current or not (unpadded base64url).
  Set<String> rootChainOf(String publisher) =>
      _graphs[publisher]?.rootChain ?? const {};

  static Map<String, Set<String>> _rootsOf(
    Map<String, Set<String>> have,
    Map<String, List<String>> more,
  ) {
    final roots = {
      for (final e in have.entries) e.key: {...e.value},
    };
    for (final e in more.entries) {
      roots.putIfAbsent(e.key, () => {}).addAll([
        for (final k in e.value) _b64(_checked(k)),
      ]);
    }
    return roots;
  }

  /// Publisher names with at least one trusted key.
  Iterable<String> get publishers => [
    for (final e in _keys.entries)
      if (e.value.isNotEmpty) e.key,
  ];

  /// Names of all publishers given to these keys, also those whose keys
  /// were all revoked.
  Iterable<String> get known => _roots.keys;

  /// Trusted key ids of [publisher] (empty when none, or all revoked).
  Set<String> keyIdsOf(String publisher) => {...?_keys[publisher]?.keys};

  /// Keys trusted for [publisher] on their own, before statements
  /// (unpadded base64url).
  Set<String> rootsOf(String publisher) => {...?_roots[publisher]};

  /// [key] as written in these keys: unpadded base64url. Throws
  /// [FormatException] for a key that is not 32 bytes.
  static String canonicalKey(String key) => _b64(_checked(key));

  /// Trusted keys of [publisher] (unpadded base64url), whatever they may
  /// sign; [keysFor] for one scope.
  Set<String> keysOf(String publisher) => {
    for (final k in _keys[publisher]?.values ?? const <List<int>>[]) _b64(k),
  };

  /// Trusted keys of [publisher] that may sign [scope] ([KeyScope]).
  Set<String> keysFor(String publisher, String scope) => {
    for (final e
        in _keys[publisher]?.entries ?? const <MapEntry<String, List<int>>>[])
      if (_scopes[publisher]?[e.key]?.contains(scope) ?? false) _b64(e.value),
  };

  /// What [publisher]'s trusted key with id [keyId] may sign; empty when it
  /// is not trusted.
  Set<String> scopesOfKeyId(String publisher, String keyId) =>
      _scopes[publisher]?[keyId] ?? const {};

  /// Ids of [publisher]'s keys revoked by a statement (or by naming two
  /// successors).
  Set<String> revokedIdsOf(String publisher) => {...?_revoked[publisher]};

  /// True when a statement revoked [key] of [publisher].
  bool isRevoked(String publisher, String key) =>
      revokedIdsOf(publisher).contains(recordKeyIdOf(_checked(key)));

  /// These keys plus [more] (publisher name → public keys), for example
  /// publishers the user added. Keys of the same publisher are combined.
  TrustedKeys plus(Map<String, List<String>> more) =>
      TrustedKeys._(_rootsOf(_roots, more), statements);

  /// These keys after [more] statements too (duplicates count once).
  /// Statements of publishers not given here change nothing.
  TrustedKeys withStatements(Iterable<KeyStatement> more) {
    final all = [...statements];
    final seen = {for (final s in all) s.id};
    for (final s in more) {
      if (seen.add(s.id)) all.add(s);
    }
    return all.length == statements.length ? this : TrustedKeys._(_roots, all);
  }

  static List<int> _checked(String k) {
    final b = _unb64(k);
    if (b.length != 32) throw FormatException('Public key must be 32 bytes');
    return b;
  }

  /// True when [r] is signed by as many distinct keys of its publisher as
  /// the scope of its kind needs (KeyScope.forKind, KeyScope.required),
  /// each holding that scope: `key` and `signature`, and the entries of
  /// `signatures`. A key outside the scope counts like a bad signature; a
  /// key named twice counts once.
  /// [scope] asks for another scope than the kind's (`safety-lines`, for
  /// a package's official lines); [need] overrides the number
  /// KeyScope.required gives (tests).
  Future<bool> verify(PackageRecord r, {String? scope, int? need}) async {
    scope ??= KeyScope.forKind(r.kind);
    need ??= KeyScope.required[scope] ?? 1;
    final valid = <String>{};
    Future<void> count(String keyId, String signature, String text) async {
      if (valid.contains(keyId)) return;
      if (!scopesOfKeyId(r.publisher, keyId).contains(scope)) return;
      final key = _keys[r.publisher]![keyId]!;
      try {
        if (await _ed25519.verify(
          utf8.encode(text),
          signature: Signature(
            _unb64(signature),
            publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
          ),
        )) {
          valid.add(keyId);
        }
      } on Object {
        return;
      }
    }

    await count(r.keyId, r.signature, r.signedText);
    if (valid.length >= need) return true;
    final listText = r.listSignedText;
    for (final e in r.signatures) {
      await count(e.keyId, e.signature, listText);
      if (valid.length >= need) return true;
    }
    return false;
  }

  /// Parses and verifies; null when the shape or signature is wrong.
  Future<PackageRecord?> check(Object? json) async {
    try {
      final r = PackageRecord.fromJson((json as Map).cast());
      return await verify(r) ? r : null;
    } on Object {
      return null;
    }
  }
}
