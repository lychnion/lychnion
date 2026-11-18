import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../util/versioned_file.dart';

/// Text from a link or a file, made safe to show: no control or
/// direction-changing characters, at most 60 characters; null when empty.
String? cleanShownText(String? t) {
  if (t == null) return null;
  var s = t
      .replaceAll(
        RegExp(
          r'[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]',
        ),
        '',
      )
      .trim();
  if (s.runes.length > 60) s = String.fromCharCodes(s.runes.take(60));
  return s.isEmpty ? null : s;
}

// Publishers the user added (docs/distribution.md, step 4): a city or a
// club that signs its own packages. Added only by an explicit action (a
// scanned or pasted link, then a question), shown with their name, and
// removable. Lychnion's key is built in and cannot be replaced.

/// A publisher's name in records (`publisher`): lower case, digits, `.`,
/// `_` and `-`, for example `jp.city.kobe`.
final _publisherName = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

/// `lychnion://publisher?name=…&title=…&key=…`, shown as a QR code by the
/// publisher (later: its node in the desktop app).
class PublisherLink {
  const PublisherLink({required this.name, required this.key, this.title});

  /// The `publisher` field of its records.
  final String name;

  /// Public key, Ed25519, base64url (43 characters).
  final String key;

  /// A readable name ("神戸市"), shown next to [name]. Not checked: the
  /// user decides whether they know the publisher.
  final String? title;

  static const scheme = 'lychnion';

  /// A title as shown: no control or direction-changing characters (they
  /// could make one name look like another), at most 60 characters, and
  /// never the app's own name (`Lychnion`, `リクニオン`), so a publisher
  /// cannot pass itself off as the built-in one.
  static String? cleanTitle(String? t) {
    final s = cleanShownText(t);
    if (s == null) return null;
    final plain = s.toLowerCase().replaceAll(' ', '');
    if (s.isEmpty || plain == 'lychnion' || plain == 'リクニオン') return null;
    return s;
  }

  Uri toUri() => Uri(
    scheme: scheme,
    host: 'publisher',
    queryParameters: {'name': name, 'title': ?title, 'key': key},
  );

  /// The link, or null when [uri] is something else.
  static PublisherLink? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != 'publisher') return null;
    final q = uri.queryParameters;
    final name = q['name'] ?? '', key = q['key'] ?? '';
    if (name.isEmpty || key.isEmpty) return null;
    return PublisherLink(name: name, key: key, title: cleanTitle(q['title']));
  }

  /// Short id of the key, as records name it (8 characters), or null when
  /// the key is not a 32-byte base64url key.
  String? get keyId {
    try {
      final b = base64Url.decode(base64Url.normalize(key));
      return b.length == 32 ? recordKeyIdOf(b) : null;
    } on FormatException {
      return null;
    }
  }
}

class Publisher {
  const Publisher({
    required this.name,
    required this.key,
    required this.added,
    this.title,
  });

  final String name, key;
  final String? title;

  /// When the user added it.
  final DateTime added;

  String get keyId => PublisherLink(name: name, key: key).keyId ?? '';

  Map<String, Object?> toJson() => {
    'name': name,
    'title': ?title,
    'key': key,
    'added': added.toUtc().toIso8601String(),
  };
}

/// Why a publisher link cannot be added.
enum PublisherProblem {
  /// The name is not a valid publisher name.
  badName,

  /// The key is not a 32-byte Ed25519 key.
  badKey,

  /// A name built into the app (`lychnion`): nobody else may sign as it.
  builtIn,

  /// Already added with another key. Remove it first; a changed key is
  /// not taken over silently.
  otherKey,

  /// Already added with this key (or the key that replaced it).
  known,

  /// A key statement revoked this key: the publisher gave it up (stolen
  /// or lost). Its new link has another key.
  revoked,
}

/// Where an added publisher's key stands after the key statements this
/// device learned.
enum PublisherKeyState {
  /// The key added by its link.
  added,

  /// Replaced by a newer key, signed by the old one.
  replaced,

  /// Revoked: nothing of it is trusted until its new link is added.
  revoked,
}

/// The publishers the user added, saved in a JSON file.
class PublisherList extends ChangeNotifier {
  PublisherList(this.file, {TrustedKeys? builtIn})
    : builtIn = builtIn ?? builtInPublishers;

  final File file;

  /// Publishers the app trusts anyway; their names cannot be added.
  final TrustedKeys builtIn;

  final _added = <String, Publisher>{};

  List<Publisher> get added =>
      [..._added.values]..sort((a, b) => a.name.compareTo(b.name));

  TrustedKeys? _trust;

  /// Key statements learned from catalogs, sticks and devices nearby
  /// (docs/distribution.md, "Replacing a key"). Kept when a publisher is
  /// removed, so a revoked key stays revoked if its old link is added
  /// again.
  final _statements = <KeyStatement>[];

  /// At most this many statements are kept.
  static const maxStatements = 1000;

  List<KeyStatement> get statements => List.unmodifiable(_statements);

  /// Built-in publishers plus the added ones, after the key statements
  /// (built once per change).
  TrustedKeys get trust => _trust ??= builtIn
      .plus({
        for (final p in _added.values) p.name: [p.key],
      })
      .withStatements(_statements);

  /// Where [name]'s key stands (built-in publishers too).
  PublisherKeyState keyStateOf(String name) {
    final now = trust.keysOf(name);
    if (now.isEmpty) return PublisherKeyState.revoked;
    final roots = switch (_added[name]) {
      final p? => {TrustedKeys.canonicalKey(p.key)},
      null => builtIn.keysOf(name),
    };
    return now.difference(roots).isEmpty
        ? PublisherKeyState.added
        : PublisherKeyState.replaced;
  }

  /// The statements about [publishers], to pass on (a stick, a base).
  List<Map<String, Object?>> statementsFor(Iterable<String> publishers) {
    final names = publishers.toSet();
    return [
      for (final s in _statements)
        if (names.contains(s.publisher)) s.json,
    ];
  }

  void _changed() {
    _trust = null;
    notifyListeners();
  }

  /// Format of publishers.json (see versioned_file.dart). 0: the same
  /// fields without a format number. 1: without `statements`.
  static const format = 2;

  Future<void> load() async {
    _added.clear();
    _statements.clear();
    // Unreadable or newer: a copy is kept (a later save writes over the
    // file), and no publishers are added.
    final json = await readVersioned(file, format, (json, _) => json! as Map);
    final raw = json?['publishers'];
    // Each one checked again: a file edited by hand proves nothing.
    _statements.addAll(
      await KeyStatement.checkAll(json?['statements'], max: maxStatements),
    );
    // Each entry on its own: one bad entry does not drop the others. A
    // file edited by hand is checked like a link.
    for (final e in raw is List ? raw : const []) {
      try {
        final m = e as Map;
        final link = PublisherLink(
          name: m['name'] as String,
          key: m['key'] as String,
          title: PublisherLink.cleanTitle(m['title'] as String?),
        );
        // A revoked one stays listed (shown as revoked).
        if (_shapeProblem(link) != null) continue;
        _added[link.name] = Publisher(
          name: link.name,
          key: link.key,
          title: link.title,
          added:
              DateTime.tryParse(m['added'] as String? ?? '') ?? DateTime.now(),
        );
      } on Object {
        continue;
      }
    }
    _changed();
  }

  /// True when [name] can be a publisher's name in records.
  static bool isValidName(String name) => _publisherName.hasMatch(name);

  PublisherProblem? _shapeProblem(PublisherLink l) {
    if (!isValidName(l.name)) return PublisherProblem.badName;
    if (l.keyId == null) return PublisherProblem.badKey;
    if (builtIn.known.contains(l.name)) return PublisherProblem.builtIn;
    return null;
  }

  PublisherProblem? problemWith(PublisherLink l) {
    if (_shapeProblem(l) case final p?) return p;
    // Also for a publisher removed meanwhile: its statements are kept.
    if (resolveKeys(l.name, [l.key], _statements).keys.isEmpty) {
      return PublisherProblem.revoked;
    }
    final have = _added[l.name];
    if (have != null) {
      // The same key may be written with or without base64 padding.
      final key = TrustedKeys.canonicalKey(l.key);
      if (TrustedKeys.canonicalKey(have.key) == key) {
        return PublisherProblem.known;
      }
      if (trust.keysOf(l.name).contains(key)) return PublisherProblem.known;
      // All its keys revoked: its new link replaces the entry.
      if (keyStateOf(l.name) == PublisherKeyState.revoked) return null;
      return PublisherProblem.otherKey;
    }
    return null;
  }

  /// Keeps the valid [learned] statements about publishers this device
  /// knows (built in, added, or with statements already kept; with [any],
  /// every one: a publisher's own revocation on a new computer), and
  /// saves them. Returns true when the trusted keys changed (then install
  /// records and catalogs must be checked again). Throws the save's error
  /// (then nothing changed).
  Future<bool> learn(Iterable<KeyStatement> learned, {bool any = false}) =>
      _serial(() async {
        final before = _keySummary();
        final room = maxStatements - _statements.length;
        final seen = {for (final s in _statements) s.id};
        // Only statements made by a key trusted here (see
        // relevantStatements): statements anyone can make about keys of
        // their own never fill the list. Revocations are kept even when
        // it is full: losing one would trust a stolen key again.
        final candidates = any
            ? [
                for (final s in learned)
                  if (seen.add(s.id)) s,
              ]
            : await relevantStatements(trust, learned.toList());
        var left = room;
        final fresh = [
          for (final s in candidates)
            // Like a revocation: a second successor of a key proves a
            // theft, and losing it would trust the thief's chain.
            if (s.type == KeyStatementType.revoke ||
                provesTheft(s, _statements) ||
                left-- > 0)
              s,
        ];
        final next = [..._statements, ...fresh];
        if (next.length == _statements.length) return false;
        await _save(_added.values, next);
        _statements
          ..clear()
          ..addAll(next);
        _trust = null;
        final changed = _keySummary() != before;
        _changed();
        return changed;
      });

  String _keySummary() {
    final t = trust;
    return [
      for (final n in [...t.known]..sort())
        '$n:${([...t.keyIdsOf(n)]..sort()).join(',')}',
    ].join(';');
  }

  /// Additions and removals one after another: each checks and saves the
  /// list as the one before left it.
  Future<void> _last = Future.value();

  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _last.then((_) => f());
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Adds [l] (after the user agreed). Throws [ArgumentError] when
  /// [problemWith] finds a problem, and the save's error when it cannot be
  /// saved (then nothing changed: not trusted, not in the list).
  Future<void> add(PublisherLink l) => _serial(() async {
    if (problemWith(l) case final p?) throw ArgumentError(p.name);
    final next = {
      ..._added,
      l.name: Publisher(
        name: l.name,
        key: l.key,
        title: PublisherLink.cleanTitle(l.title),
        added: DateTime.now(),
      ),
    };
    await _save(next.values, _statements);
    _added
      ..clear()
      ..addAll(next);
    _changed();
  });

  /// Removes [name]; throws the save's error when it cannot be saved (then
  /// it stays).
  Future<void> remove(String name) => _serial(() async {
    if (!_added.containsKey(name)) return;
    await _save([
      for (final p in _added.values)
        if (p.name != name) p,
    ], _statements);
    _added.remove(name);
    _changed();
  });

  Future<void> _save(
    Iterable<Publisher> list,
    Iterable<KeyStatement> statements,
  ) async {
    if (!mayReplace(file)) {
      throw FileSystemException('kept as it is', file.path);
    }
    await file.parent.create(recursive: true);
    // Written next to the file, then renamed: a cut write leaves the old list.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'publishers': [
          for (final p in [...list]..sort((a, b) => a.name.compareTo(b.name)))
            p.toJson(),
        ],
        if (statements.isNotEmpty)
          'statements': [for (final s in statements) s.json],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
