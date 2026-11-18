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
  LocalPublisher._(
    this.name,
    this.title,
    this._seed,
    this.publicKey, [
    this.statements = const [],
  ]);

  final String name;
  final String? title;
  final String _seed;

  /// Key statements this publisher made (replaced and revoked keys,
  /// oldest first), kept with the key so both change in one write. To
  /// put in its catalog's `keys` (see [keysFileIn]).
  final List<KeyStatement> statements;

  /// Short id of the key, as records name it.
  String get keyId => link.keyId ?? '';

  /// Ed25519, base64url.
  final String publicKey;

  /// What phones scan to trust this publisher.
  PublisherLink get link =>
      PublisherLink(name: name, key: publicKey, title: title);

  Future<SimpleKeyPair> keyPair() => keyPairFromSeed(_seed);

  /// Format of publisher.json (see versioned_file.dart). 0: the same
  /// fields without a format number. `statements` is optional (older
  /// builds ignore it; they never write this file over).
  static const format = 1;

  static File fileIn(Directory dir) => File('${dir.path}/publisher.json');

  /// `{"keys": [...]}`: this publisher's key statements, for its catalog
  /// (a catalog's `keys`). Never holds a private key.
  static File keysFileIn(Directory dir) => File('${dir.path}/keys.json');

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
        await KeyStatement.checkAll(j['statements']),
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
  }) => _createWith(dir, name, title, null);

  /// Saves the key of an opened backup ([KeyBackup.open]) as this
  /// computer's publisher. Throws what [create] throws (`exists` when a
  /// key is here: a key is never replaced silently).
  static Future<LocalPublisher> restore(Directory dir, RestoredKey k) =>
      _createWith(dir, k.name, k.title, k.seed);

  /// A backup of this key, encrypted with [passphrase] (see [KeyBackup]).
  Future<String> backup(String passphrase, {KeyBackupKdf? kdf}) =>
      KeyBackup.create(
        name: name,
        title: title,
        seed: _seed,
        passphrase: passphrase,
        signed: nowStamp(),
        kdf: kdf ?? const KeyBackupKdf(),
      );

  /// Replaces this key with a new one; the old key signs the new one, so
  /// phones that trust the old key accept the new one. Records signed by
  /// the old key stay valid. Old backups hold the old key: a new backup
  /// is needed.
  Future<LocalPublisher> replaceKey(Directory dir) async {
    final k = await newKeyPair();
    final s = await KeyStatement.replace(
      publisher: name,
      oldKey: await keyPair(),
      newKey: await keyPairFromSeed(k.seed),
      signed: nowStamp(),
    );
    return _renew(dir, k, s);
  }

  /// Revokes this key (stolen or given away) and makes a new one. Phones
  /// stop trusting the old key and everything it signed, and must add the
  /// new link: nothing signed by the old key can vouch for the new one.
  Future<LocalPublisher> revokeAndRenew(Directory dir) async {
    final s = await KeyStatement.revoke(
      publisher: name,
      key: await keyPair(),
      signed: nowStamp(),
    );
    return _renew(dir, await newKeyPair(), s);
  }

  Future<LocalPublisher> _renew(
    Directory dir,
    ({String seed, String publicKey}) k,
    KeyStatement s,
  ) async {
    final f = fileIn(dir);
    // The file must still hold this key: another window may have
    // replaced it meanwhile.
    final now = await load(dir);
    if (now == null || now.publicKey != publicKey) throw ArgumentError('key');
    final p = LocalPublisher._(name, title, k.seed, k.publicKey, [
      ...statements,
      s,
    ]);
    // One write replaces key and statements together: the old key is gone
    // only once its statement is saved with the new one.
    await _save(dir, f, p);
    return p;
  }

  /// Adds [more] to `keys.json` (statements made elsewhere, for example a
  /// revocation from a backup), keeping those there.
  static Future<void> writeKeysFile(
    Directory dir,
    Iterable<KeyStatement> more,
  ) async {
    final f = keysFileIn(dir);
    final all = <KeyStatement>[];
    try {
      all.addAll(
        await KeyStatement.checkAll(
          (jsonDecode(await f.readAsString()) as Map)['keys'],
        ),
      );
    } on Object {
      // None yet, or unreadable: written anew.
    }
    for (final s in more) {
      if (!all.contains(s)) all.add(s);
    }
    await dir.create(recursive: true);
    final tmp = File('${f.path}.$pid.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'keys': [for (final s in all) s.json],
      })}\n',
      flush: true,
    );
    await tmp.rename(f.path);
  }

  static Future<LocalPublisher> _createWith(
    Directory dir,
    String name,
    String? title,
    String? seed,
  ) async {
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
      final k = seed == null
          ? await newKeyPair()
          : (
              seed: seed,
              publicKey: await publicKeyOf(await keyPairFromSeed(seed)),
            );
      final p = LocalPublisher._(
        name,
        PublisherLink.cleanTitle(title),
        k.seed,
        k.publicKey,
      );
      await _save(dir, f, p);
      return p;
    } finally {
      if (await lock.exists()) await lock.delete();
    }
  }

  static Future<void> _save(Directory dir, File f, LocalPublisher p) async {
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
          if (p.statements.isNotEmpty)
            'statements': [for (final s in p.statements) s.json],
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

/// `2026-11-18T09:00:00+09:00`
String nowStamp() {
  final t = DateTime.now();
  final o = t.timeZoneOffset;
  String two(int n) => n.abs().toString().padLeft(2, '0');
  return '${t.toIso8601String().substring(0, 19)}'
      '${o.isNegative ? '-' : '+'}${two(o.inHours)}:${two(o.inMinutes % 60)}';
}
