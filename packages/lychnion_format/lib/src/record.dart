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
final _safeName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');

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

  /// The text the signature covers.
  String get signedText => canonicalJson(Map.of(json)..remove('signature'));

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
    if (!_safeName.hasMatch(str('id'))) {
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
      if (name is! String || !_safeName.hasMatch(name)) {
        throw FormatException('Record: bad file name $name');
      }
      if (size is! int || size <= 0) throw FormatException('Record: bad size');
      if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
        throw FormatException('Record: bad sha256 for $name');
      }
      files.add(RecordFile(name, size, sha));
    }
    if (files.map((f) => f.name).toSet().length != files.length) {
      throw FormatException('Record: duplicate file names');
    }
    return PackageRecord._(Map.unmodifiable(j), List.unmodifiable(files));
  }

  /// Signs [unsigned] (all fields but `signature`; `key` is set here).
  static Future<PackageRecord> sign(
    Map<String, Object?> unsigned,
    SimpleKeyPair key,
  ) async {
    final pub = (await key.extractPublicKey()).bytes;
    final j = Map.of(unsigned)
      ..remove('signature')
      ..['key'] = recordKeyIdOf(pub);
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
      _revoked[e.key] = r.revokedIds;
    }
  }

  /// Publisher name → keys trusted on its own (unpadded base64url).
  final Map<String, Set<String>> _roots;

  /// The key statements applied (only valid ones exist).
  final List<KeyStatement> statements;

  /// Publisher name → key id → 32-byte key, after the statements.
  final _keys = <String, Map<String, List<int>>>{};
  final _revoked = <String, Set<String>>{};

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

  /// Trusted keys of [publisher] (unpadded base64url).
  Set<String> keysOf(String publisher) => {
    for (final k in _keys[publisher]?.values ?? const <List<int>>[]) _b64(k),
  };

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
    for (final s in more) {
      if (!all.contains(s)) all.add(s);
    }
    return all.length == statements.length ? this : TrustedKeys._(_roots, all);
  }

  static List<int> _checked(String k) {
    final b = _unb64(k);
    if (b.length != 32) throw FormatException('Public key must be 32 bytes');
    return b;
  }

  /// True when [r] is signed by a key of its publisher.
  Future<bool> verify(PackageRecord r) async {
    final key = _keys[r.publisher]?[r.keyId];
    if (key == null) return false;
    try {
      return await _ed25519.verify(
        utf8.encode(r.signedText),
        signature: Signature(
          _unb64(r.signature),
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
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
