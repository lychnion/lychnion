import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../util/versioned_file.dart';
import 'compact_codec.dart';
import 'fact.dart';

final _ed25519 = Ed25519();

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// Short id of a public key: its first 6 bytes, base64url (8 characters).
String keyIdOf(List<int> publicKey) => _b64(publicKey.sublist(0, 6));

/// This device's signing key (Ed25519). A base computer signs the
/// official facts its staff enter; phones check them against keys they trust.
class FactSigner {
  FactSigner._(this._pair, this.publicKey) : keyId = keyIdOf(publicKey);

  final SimpleKeyPair _pair;
  final List<int> publicKey;
  final String keyId;

  /// Public key as text, for QR codes and /info.
  String get publicKeyText => _b64(publicKey);

  static Future<FactSigner> generate() async {
    final pair = await _ed25519.newKeyPair();
    return FactSigner._(pair, (await pair.extractPublicKey()).bytes);
  }

  /// Loads the key from [file], or creates and saves one. The file holds
  /// the 32-byte private seed; it never leaves the device.
  ///
  /// A key that cannot be read is kept as `<name>.broken` and a new one is
  /// made: the device then signs with a new key, and phones need its QR
  /// code again.
  static Future<FactSigner> loadOrCreate(File file) async {
    if (await file.exists()) {
      try {
        final seed = _unb64((await file.readAsString()).trim());
        if (seed.length != 32) throw const FormatException('seed length');
        final pair = await _ed25519.newKeyPairFromSeed(seed);
        return FactSigner._(pair, (await pair.extractPublicKey()).bytes);
      } on Object {
        // Never written over without a copy.
        if (await keepAside(file, 'broken') == null) rethrow;
      }
    }
    final pair = await _ed25519.newKeyPair();
    await file.writeAsString(_b64(await pair.extractPrivateKeyBytes()));
    return FactSigner._(pair, (await pair.extractPublicKey()).bytes);
  }

  Future<String> signText(String text) => signBytes(utf8.encode(text));

  /// Signature of [bytes], base64url without padding (86 characters).
  Future<String> signBytes(List<int> bytes) async =>
      _b64((await _ed25519.sign(bytes, keyPair: _pair)).bytes);

  Future<Fact> sign(Fact f) async =>
      f.signed(keyId, await signText(f.canonical));

  /// Packs facts for radio and signs each message as a whole:
  /// `<facts>~<keyId>.<signature>`. One signature (86 characters) per
  /// message instead of per fact keeps updates small.
  Future<List<String>> packSigned(
    CompactCodec codec,
    Iterable<Fact> facts, {
    int maxBytes = 200,
  }) async {
    final suffix = 1 + keyId.length + 1 + 86;
    return [
      for (final m in codec.pack(facts, maxBytes: maxBytes - suffix))
        '$m~$keyId.${await signText(m)}',
    ];
  }
}

/// Why a key is in the [TrustList].
enum TrustedKeyKind {
  /// This device's own signing key, added at every start.
  own,

  /// A base computer's key, trusted after the user compared its code in
  /// person (base_key_code.dart). The user can remove it.
  base,
}

/// A key in the [TrustList].
typedef TrustedKey = ({String id, String keyText, String name});

/// Keys this device trusts, with a name for each (e.g. the base).
/// Saved in trusted_keys.json.
class TrustList extends ChangeNotifier {
  File? _file;
  final _keys = <String, ({List<int> key, String name, TrustedKeyKind kind})>{};

  Iterable<String> get names => _keys.values.map((k) => k.name);
  bool trusts(String keyId) => _keys.containsKey(keyId);
  String? nameOf(String keyId) => _keys[keyId]?.name;

  /// Whether exactly [publicKeyText] is trusted (not only a key with the
  /// same short id).
  bool trustsKey(String? publicKeyText) {
    if (publicKeyText == null) return false;
    final List<int> key;
    try {
      key = _unb64(publicKeyText);
    } on FormatException {
      return false;
    }
    if (key.length != 32) return false;
    final k = _keys[keyIdOf(key)];
    return k != null && listEquals(k.key, key);
  }

  /// The trusted keys of [kind], by name.
  List<TrustedKey> keysOf(TrustedKeyKind kind) => [
    for (final e in _keys.entries)
      if (e.value.kind == kind)
        (id: e.key, keyText: _b64(e.value.key), name: e.value.name),
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// Format of trusted_keys.json (see versioned_file.dart). 0: key id →
  /// {key, name} at the top; 1: `{"format": 1, "keys": {...}}`. An entry
  /// may say `"kind": "own"`; one without a kind is a base's key (older
  /// apps trusted only those and their own key, which is added again at
  /// every start).
  static const format = 1;

  /// Reads [file]. A broken file means no trusted keys, not a crash at
  /// start: base keys are trusted again by comparing their code. A broken
  /// entry is skipped.
  Future<void> load(File file) => _loading = _load(file);

  /// The running or finished load: [add] waits for it, so a key added
  /// meanwhile is saved, and only after the file was kept if needed.
  Future<void>? _loading;

  Future<void> _load(File file) async {
    final keys = await readVersioned(file, format, (json, f) {
      final m = (f == 0 ? json : (json! as Map)['keys'])! as Map;
      return m.cast<String, Object?>();
    });
    for (final e in (keys ?? const {}).entries) {
      try {
        final v = e.value! as Map;
        _keys[e.key] = (
          key: _unb64(v['key'] as String),
          name: v['name'] as String,
          kind: v['kind'] == 'own' ? TrustedKeyKind.own : TrustedKeyKind.base,
        );
      } on Object {
        continue;
      }
    }
    // Saves start once the file was read (and kept as a copy if needed).
    _file = file;
    notifyListeners();
  }

  /// Trusts [publicKeyText]; returns its key id, or null if malformed or
  /// if another trusted key has the same id.
  Future<String?> add(
    String publicKeyText,
    String name, {
    TrustedKeyKind kind = TrustedKeyKind.base,
  }) async {
    await _loading;
    final List<int> key;
    try {
      key = _unb64(publicKeyText);
    } on FormatException {
      return null;
    }
    if (key.length != 32) return null;
    final id = keyIdOf(key);
    // Another key with the same short id (6 bytes): never replace it, or
    // a base key could take the place of this device's own key or of
    // another trusted base. The same key is updated (name, kind).
    final old = _keys[id];
    if (old != null && !listEquals(old.key, key)) return null;
    _keys[id] = (key: key, name: name, kind: kind);
    notifyListeners();
    await _save();
    return id;
  }

  /// Stops trusting the key with id [keyId]; returns whether it was
  /// trusted. Facts it signed then count as unconfirmed again
  /// (FactStore.forgetKey).
  Future<bool> remove(String keyId) async {
    await _loading;
    if (_keys.remove(keyId) == null) return false;
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null || !mayReplace(f)) return;
    await f.writeAsString(
      jsonEncode({
        'format': format,
        'keys': {
          for (final e in _keys.entries)
            e.key: {
              'key': _b64(e.value.key),
              'name': e.value.name,
              if (e.value.kind == TrustedKeyKind.own) 'kind': 'own',
            },
        },
      }),
    );
  }

  Future<bool> _check(String keyId, String text, String sig) async {
    final k = _keys[keyId];
    if (k == null) return false;
    try {
      return await _ed25519.verify(
        utf8.encode(text),
        signature: Signature(
          _unb64(sig),
          publicKey: SimplePublicKey(k.key, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  /// True when [f] carries a valid signature from a trusted key.
  Future<bool> verify(Fact f) async {
    final id = f.keyId, sig = f.sig;
    if (id == null || sig == null) return false;
    return _check(id, f.canonical, sig);
  }

  /// Unpacks a signed radio message. Facts are marked verified only when
  /// the message signature checks out; then they also take the key's name
  /// as source when they have none.
  Future<List<Fact>> unpackSigned(CompactCodec codec, String message) async {
    final cut = message.lastIndexOf('~');
    final body = cut < 0 ? message : message.substring(0, cut);
    var ok = false;
    String? id;
    if (cut >= 0) {
      final tail = message.substring(cut + 1);
      final dot = tail.indexOf('.');
      if (dot > 0) {
        id = tail.substring(0, dot);
        ok = await _check(id, body, tail.substring(dot + 1));
      }
    }
    return [
      for (final f in codec.unpack(body))
        Fact(
          kind: f.kind,
          subject: f.subject,
          value: f.value,
          observedAt: f.observedAt,
          expiresAt: f.expiresAt,
          sourceType: f.sourceType,
          sourceName: ok ? (nameOf(id!) ?? '') : '',
        )..verified = ok || f.sourceType == SourceType.citizen,
    ];
  }
}
