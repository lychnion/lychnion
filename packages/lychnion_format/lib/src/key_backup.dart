import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'encoding.dart';
import 'key_statement.dart';
import 'record.dart';

// A publisher key backup (docs/distribution.md, "Backing up the key"):
// a file the publisher keeps offline. The private key in it is encrypted
// with a passphrase (Argon2id, then AES-256-GCM); name and public key are
// bound to it, so a file with another name or key does not open. A
// revocation of the key is in it unencrypted, so a publisher who forgot
// the passphrase can still revoke the key.

/// Why a backup cannot be opened.
enum KeyBackupProblem {
  /// Not a Lychnion key backup (or not JSON at all).
  notABackup,

  /// Made by a newer app.
  newer,

  /// Parts missing, changed or cut off.
  damaged,

  /// The passphrase does not open it (or the file was changed).
  wrongPassphrase,
}

class KeyBackupException implements Exception {
  const KeyBackupException(this.problem);
  final KeyBackupProblem problem;

  @override
  String toString() => 'KeyBackupException(${problem.name})';
}

/// Argon2id costs. Read back from the file, within limits.
class KeyBackupKdf {
  const KeyBackupKdf({
    this.memory = 65536,
    this.iterations = 3,
    this.parallelism = 1,
  });

  /// KiB.
  final int memory;
  final int iterations, parallelism;

  /// What a file may ask for: more would let a file stall the app.
  bool get withinLimits =>
      memory >= 8 &&
      memory <= 131072 &&
      iterations >= 1 &&
      iterations <= 4 &&
      parallelism >= 1 &&
      parallelism <= 4 &&
      memory >= 8 * parallelism;
}

/// What a backup holds once opened.
class RestoredKey {
  const RestoredKey(
    this.name,
    this.title,
    this.seed,
    this.publicKey, {
    this.made,
  });
  final String name;
  final String? title;

  /// When the backup was made (the date of the revocation in it), or null.
  final String? made;

  /// 32-byte private seed, base64url.
  final String seed;

  /// Ed25519, base64url.
  final String publicKey;
}

class KeyBackup {
  static const format = 1;
  static const type = 'lychnion-publisher-key';

  /// Suggested file name ending.
  static const extension = '.lychnion-key';

  static const minPassphraseLength = 12;

  static const warning = {
    'en':
        'This file can sign packages in this publisher\'s name. Keep it '
        'offline (1Password, or a USB stick in a safe). Never put it on '
        'a server, in a repository or on a stick you hand out. Without '
        'the passphrase it cannot be opened. Whoever has the file can '
        'revoke the key with it, even without the passphrase.',
    'ja':
        'このファイルがあれば、この発行者の名前でパッケージに署名できます。'
        'オフラインで保管してください（1Password、金庫の USB メモリなど）。'
        'サーバー、リポジトリ、人に渡す USB メモリには置かないでください。'
        'パスフレーズがないと開けません。このファイルがあれば、パスフレーズが'
        'なくても鍵を無効にできます。',
  };

  static final _aes = AesGcm.with256bits();

  /// [passphrase] in Unicode NFKC: what is typed as the same text on
  /// another system (NFC or NFD, full-width or half-width letters and
  /// digits) gives the same key.
  static String normalizedPassphrase(String passphrase) =>
      unorm.nfkc(passphrase);

  /// The file text of a backup of [seed] (the publisher [name]'s key).
  /// [signed] dates the revocation inside. Throws [ArgumentError]
  /// (`passphrase`) for a passphrase shorter than [minPassphraseLength].
  static Future<String> create({
    required String name,
    String? title,
    required String seed,
    required String passphrase,
    required String signed,
    KeyBackupKdf kdf = const KeyBackupKdf(),
  }) async {
    // The same passphrase typed on another system may come as other
    // code points (NFC or NFD, full-width digits): normalised first
    // (lychnion/lychnion#59).
    passphrase = normalizedPassphrase(passphrase);
    if (passphrase.runes.length < minPassphraseLength) {
      throw ArgumentError('passphrase');
    }
    if (!publisherNamePattern.hasMatch(name)) throw ArgumentError('name');
    if (!kdf.withinLimits) throw ArgumentError('kdf');
    final pair = await keyPairFromSeed(seed);
    final publicKey = await publicKeyOf(pair);
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _derive(passphrase, salt, kdf);
    final box = await _aes.encrypt(
      unb64(seed),
      secretKey: key,
      aad: _aad(name, publicKey),
    );
    final revocation = await KeyStatement.revoke(
      publisher: name,
      key: pair,
      signed: signed,
    );
    return '${const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'type': type,
      'warning': warning,
      'name': name,
      'title': ?title,
      'public_key': publicKey,
      'kdf': {'name': 'argon2id', 'memory': kdf.memory, 'iterations': kdf.iterations, 'parallelism': kdf.parallelism, 'salt': b64(salt)},
      'cipher': {'name': 'aes-256-gcm', 'nonce': b64(box.nonce), 'data': b64(box.cipherText), 'mac': b64(box.mac.bytes)},
      'revocation': revocation.json,
    })}\n';
  }

  static List<int> _aad(String name, String publicKey) => utf8.encode(
    canonicalJson({
      'type': type,
      'format': format,
      'name': name,
      'public_key': b64(unb64(publicKey)),
    }),
  );

  /// In another isolate: Argon2id runs in Dart here and takes a while.
  static Future<SecretKey> _derive(
    String passphrase,
    List<int> salt,
    KeyBackupKdf kdf,
  ) async {
    final (p, m, t) = (kdf.parallelism, kdf.memory, kdf.iterations);
    final bytes = await Isolate.run(() async {
      final k = await Argon2id(
        parallelism: p,
        memory: m,
        iterations: t,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
      return k.extractBytes();
    });
    return SecretKey(bytes);
  }

  static Map<String, Object?> _parse(String text) {
    Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const KeyBackupException(KeyBackupProblem.notABackup);
    }
    if (j is! Map || j['type'] != type) {
      throw const KeyBackupException(KeyBackupProblem.notABackup);
    }
    final f = j['format'];
    if (f is int && f > format) {
      throw const KeyBackupException(KeyBackupProblem.newer);
    }
    if (f != format) throw const KeyBackupException(KeyBackupProblem.damaged);
    return j.cast<String, Object?>();
  }

  /// The ready-made revocation in a backup (no passphrase needed), or
  /// throws [KeyBackupException].
  static Future<KeyStatement> revocationIn(String text) async {
    final j = _parse(text);
    final s = await KeyStatement.check(j['revocation']);
    if (s == null ||
        s.type != KeyStatementType.revoke ||
        s.publisher != j['name'] ||
        j['public_key'] is! String ||
        b64(unb64(s.oldKey)) != b64(unb64(j['public_key']! as String))) {
      throw const KeyBackupException(KeyBackupProblem.damaged);
    }
    return s;
  }

  /// Opens a backup, or throws [KeyBackupException].
  static Future<RestoredKey> open(String text, String passphrase) async {
    final j = _parse(text);
    late final String name, publicKey, nonce, data, mac, salt;
    late final KeyBackupKdf kdf;
    try {
      name = j['name']! as String;
      publicKey = j['public_key']! as String;
      final k = (j['kdf']! as Map).cast<String, Object?>();
      final c = (j['cipher']! as Map).cast<String, Object?>();
      if (k['name'] != 'argon2id' || c['name'] != 'aes-256-gcm') {
        throw const FormatException();
      }
      kdf = KeyBackupKdf(
        memory: k['memory']! as int,
        iterations: k['iterations']! as int,
        parallelism: k['parallelism']! as int,
      );
      salt = k['salt']! as String;
      nonce = c['nonce']! as String;
      data = c['data']! as String;
      mac = c['mac']! as String;
      if (!publisherNamePattern.hasMatch(name) ||
          unb64(publicKey).length != 32 ||
          unb64(salt).length < 16 ||
          unb64(nonce).length != 12 ||
          unb64(data).length != 32 ||
          unb64(mac).length != 16 ||
          !kdf.withinLimits) {
        throw const FormatException();
      }
    } on Object {
      throw const KeyBackupException(KeyBackupProblem.damaged);
    }
    // Normalised as when created; a backup made before that rule
    // (lychnion/lychnion#59) was made from the passphrase as typed then,
    // which may have been composed or decomposed: tried after.
    List<int>? seed;
    for (final p in {
      normalizedPassphrase(passphrase),
      passphrase,
      unorm.nfc(passphrase),
      unorm.nfd(passphrase),
    }) {
      try {
        seed = await _aes.decrypt(
          SecretBox(unb64(data), nonce: unb64(nonce), mac: Mac(unb64(mac))),
          secretKey: await _derive(p, unb64(salt), kdf),
          aad: _aad(name, publicKey),
        );
        break;
      } on SecretBoxAuthenticationError {
        continue;
      }
    }
    if (seed == null) {
      throw const KeyBackupException(KeyBackupProblem.wrongPassphrase);
    }
    final seedText = b64(seed);
    // The stated public key must be the one of the private key.
    if (await publicKeyOf(await keyPairFromSeed(seedText)) !=
        b64(unb64(publicKey))) {
      throw const KeyBackupException(KeyBackupProblem.damaged);
    }
    final title = j['title'];
    final made = switch (j['revocation']) {
      {'signed': final String d} when d.length <= 64 => d,
      _ => null,
    };
    return RestoredKey(
      name,
      title is String ? title : null,
      seedText,
      b64(unb64(publicKey)),
      made: made,
    );
  }
}
