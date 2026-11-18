import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../util/versioned_file.dart';

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

  /// Format of publisher.json (see versioned_file.dart). 0: the same
  /// fields without a format number.
  static const format = 1;

  static File fileIn(Directory dir) => File('${dir.path}/publisher.json');

  /// Whether a key file is there (also when it cannot be read).
  static bool existsIn(Directory dir) => fileIn(dir).existsSync();

  /// The publisher saved in [dir], or null when there is none or the file
  /// cannot be read (see [existsIn]).
  static Future<LocalPublisher?> load(Directory dir) async {
    try {
      final j =
          jsonDecode(await fileIn(dir).readAsString()) as Map<String, Object?>;
      // A newer build's file counts as unreadable; it is never replaced.
      if (formatOf(j) > format) return null;
      final name = j['name']! as String;
      if (!_usable(name)) return null;
      final seed = j['seed']! as String;
      final pair = await keyPairFromSeed(seed);
      return LocalPublisher._(
        name,
        PublisherLink.cleanTitle(j['title'] as String?),
        seed,
        await publicKeyOf(pair),
      );
    } on Object {
      return null;
    }
  }

  static bool _usable(String name) =>
      PublisherList.isValidName(name) &&
      !builtInPublishers.publishers.contains(name);

  /// Makes a new key for [name] and saves it in [dir], readable by this
  /// user only. Throws [ArgumentError] (`name`) for a name that is not a
  /// valid publisher name, (`exists`) when a key file is already there (a
  /// key is never replaced silently), and [StateError] when the file could
  /// not be made private (then no key is saved).
  static Future<LocalPublisher> create(
    Directory dir, {
    required String name,
    String? title,
  }) async {
    if (!_usable(name)) throw ArgumentError('name');
    final f = fileIn(dir);
    if (await f.exists()) throw ArgumentError('exists');
    await dir.create(recursive: true);
    // One creator at a time, also across app windows: whoever makes the
    // lock file first creates the key; the other gets `exists`. A lock
    // left by a crash is taken over after a minute.
    final lock = File('${f.path}.lock');
    try {
      await lock.create(exclusive: true);
    } on FileSystemException {
      final age = DateTime.now().difference((await lock.stat()).modified);
      if (age < const Duration(minutes: 1)) throw ArgumentError('exists');
      await lock.delete();
      await lock.create(exclusive: true);
    }
    try {
      if (await f.exists()) throw ArgumentError('exists');
      return await _write(dir, f, name, title);
    } finally {
      if (await lock.exists()) await lock.delete();
    }
  }

  static Future<LocalPublisher> _write(
    Directory dir,
    File f,
    String name,
    String? title,
  ) async {
    final k = await newKeyPair();
    final p = LocalPublisher._(
      name,
      PublisherLink.cleanTitle(title),
      k.seed,
      k.publicKey,
    );
    // Folder and file are made private before the key is written into it.
    final tmp = File('${f.path}.$pid.tmp');
    try {
      await _private(dir.path, '700');
      await tmp.writeAsString('');
      await _private(tmp.path, '600');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'name': p.name,
          'title': ?p.title,
          'public_key': p.publicKey,
          'seed': p._seed,
          'note':
              'Private signing key of this publisher. Keep a copy offline; '
              'never put it on a server, a stick or in a repository.',
        }),
        flush: true,
      );
      await tmp.rename(f.path);
    } on Object {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return p;
  }

  /// chmod. Linux needs it (app data folders are usually readable by
  /// everyone): there a failure stops [create]. The macOS app folder
  /// (sandbox container) and Windows' per-user app data are private
  /// already, so a refused chmod there changes nothing.
  static Future<void> _private(String path, String mode) async {
    if (Platform.isWindows) return;
    ProcessResult? r;
    try {
      r = await Process.run('chmod', [mode, path]);
    } on Object {
      r = null;
    }
    if ((r == null || r.exitCode != 0) && Platform.isLinux) {
      throw StateError('chmod $mode failed');
    }
  }
}
