import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'compact_codec.dart';
import 'fact.dart';

final _ed25519 = Ed25519();

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// Short id of a public key: its first 6 bytes, base64url (8 characters).
String keyIdOf(List<int> publicKey) => _b64(publicKey.sublist(0, 6));

/// This device's signing key (Ed25519). A shelter computer signs the
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
  static Future<FactSigner> loadOrCreate(File file) async {
    if (await file.exists()) {
      final seed = _unb64((await file.readAsString()).trim());
      final pair = await _ed25519.newKeyPairFromSeed(seed);
      return FactSigner._(pair, (await pair.extractPublicKey()).bytes);
    }
    final pair = await _ed25519.newKeyPair();
    await file.writeAsString(_b64(await pair.extractPrivateKeyBytes()));
    return FactSigner._(pair, (await pair.extractPublicKey()).bytes);
  }

  Future<String> signText(String text) async =>
      _b64((await _ed25519.sign(utf8.encode(text), keyPair: _pair)).bytes);

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

/// Keys this device trusts, with a name for each (e.g. the shelter).
/// Saved in trusted_keys.json.
class TrustList extends ChangeNotifier {
  File? _file;
  final _keys = <String, ({List<int> key, String name})>{};

  Iterable<String> get names => _keys.values.map((k) => k.name);
  bool trusts(String keyId) => _keys.containsKey(keyId);
  String? nameOf(String keyId) => _keys[keyId]?.name;

  Future<void> load(File file) async {
    _file = file;
    final f = file;
    if (!await f.exists()) return;
    // An empty or broken file (a write cut short) means no trusted keys,
    // not a crash at start: keys are added again from the shelter QR.
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    for (final e in j.entries) {
      final v = e.value as Map<String, dynamic>;
      _keys[e.key] = (
        key: _unb64(v['key'] as String),
        name: v['name'] as String,
      );
    }
    notifyListeners();
  }

  /// Trusts [publicKeyText]; returns its key id, or null if malformed.
  Future<String?> add(String publicKeyText, String name) async {
    final List<int> key;
    try {
      key = _unb64(publicKeyText);
    } on FormatException {
      return null;
    }
    if (key.length != 32) return null;
    final id = keyIdOf(key);
    _keys[id] = (key: key, name: name);
    notifyListeners();
    await _save();
    return id;
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    await f.writeAsString(
      jsonEncode({
        for (final e in _keys.entries)
          e.key: {'key': _b64(e.value.key), 'name': e.value.name},
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
