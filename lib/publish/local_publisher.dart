import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../download/publisher_list.dart';

// Publishing on this computer (docs/distribution.md, step 4b): a city or a
// club makes its publisher key here, gives phones its link (QR), and signs
// its own packages. The key stays in this computer's app folder; it is
// never served, shared or put in a catalog.

/// This computer's publisher: name, title and signing key.
class LocalPublisher {
  LocalPublisher._(this.name, this.title, this._seed, this.publicKey);

  final String name;
  final String? title;
  final String _seed;

  /// Ed25519, base64url.
  final String publicKey;

  /// What phones scan to trust this publisher.
  PublisherLink get link =>
      PublisherLink(name: name, key: publicKey, title: title);

  Future<SimpleKeyPair> keyPair() => keyPairFromSeed(_seed);

  static File fileIn(Directory dir) => File('${dir.path}/publisher.json');

  /// The publisher saved in [dir], or null when there is none (or the file
  /// is broken).
  static Future<LocalPublisher?> load(Directory dir) async {
    try {
      final j =
          jsonDecode(await fileIn(dir).readAsString()) as Map<String, Object?>;
      final seed = j['seed']! as String;
      final pair = await keyPairFromSeed(seed);
      return LocalPublisher._(
        j['name']! as String,
        j['title'] as String?,
        seed,
        await publicKeyOf(pair),
      );
    } on Object {
      return null;
    }
  }

  /// Makes a new key for [name] and saves it in [dir]. Throws
  /// [ArgumentError] when the name is not a valid publisher name or a
  /// publisher is already saved there (a key is never replaced silently).
  static Future<LocalPublisher> create(
    Directory dir, {
    required String name,
    String? title,
  }) async {
    final k = await newKeyPair();
    final p = LocalPublisher._(
      name,
      title == null || title.trim().isEmpty ? null : title.trim(),
      k.seed,
      k.publicKey,
    );
    if (!PublisherList.isValidName(name) ||
        builtInPublishers.publishers.contains(name)) {
      throw ArgumentError('name');
    }
    final f = fileIn(dir);
    if (await f.exists()) throw ArgumentError('exists');
    await dir.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'name': p.name,
        'title': ?p.title,
        'public_key': p.publicKey,
        'seed': p._seed,
        'note':
            'Private signing key of this publisher. Keep a copy offline; '
            'never put it on a server, a stick or in a repository.',
      }),
    );
    await _ownerOnly(tmp);
    await tmp.rename(f.path);
    return p;
  }

  /// Readable by this user only. Needed on Linux; the macOS app folder
  /// (sandbox container) and Windows' per-user app data are private to
  /// the user already, so a refused chmod there changes nothing.
  static Future<void> _ownerOnly(File f) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', f.path]);
    } on Object {
      // The file still works; it is only less protected.
    }
  }
}
