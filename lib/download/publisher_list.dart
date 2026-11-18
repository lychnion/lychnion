import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lychnion_format/lychnion_format.dart';

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
    final title = q['title']?.trim();
    return PublisherLink(
      name: name,
      key: key,
      title: title == null || title.isEmpty ? null : title,
    );
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

  /// Already added with this key.
  known,
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

  /// Built-in publishers plus the added ones.
  TrustedKeys get trust => builtIn.plus({
    for (final p in _added.values) p.name: [p.key],
  });

  Future<void> load() async {
    _added.clear();
    try {
      final j = jsonDecode(await file.readAsString()) as Map;
      for (final raw in (j['publishers'] as List?) ?? const []) {
        final m = raw as Map;
        final link = PublisherLink(
          name: m['name'] as String,
          key: m['key'] as String,
          title: m['title'] as String?,
        );
        // A file edited by hand is checked like a link.
        if (problemWith(link) != null) continue;
        _added[link.name] = Publisher(
          name: link.name,
          key: link.key,
          title: link.title,
          added:
              DateTime.tryParse(m['added'] as String? ?? '') ?? DateTime.now(),
        );
      }
    } on Object {
      // No file yet, or a broken one: no added publishers.
    }
    notifyListeners();
  }

  PublisherProblem? problemWith(PublisherLink l) {
    if (!_publisherName.hasMatch(l.name)) return PublisherProblem.badName;
    if (l.keyId == null) return PublisherProblem.badKey;
    if (builtIn.publishers.contains(l.name)) return PublisherProblem.builtIn;
    final have = _added[l.name];
    if (have != null) {
      return have.key == l.key
          ? PublisherProblem.known
          : PublisherProblem.otherKey;
    }
    return null;
  }

  /// Adds [l] (after the user agreed). Throws [ArgumentError] when
  /// [problemWith] finds a problem.
  Future<void> add(PublisherLink l) async {
    if (problemWith(l) case final p?) throw ArgumentError(p.name);
    _added[l.name] = Publisher(
      name: l.name,
      key: l.key,
      title: l.title,
      added: DateTime.now(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> remove(String name) async {
    if (_added.remove(name) == null) return;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    // Written next to the file, then renamed: a cut write leaves the old list.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'publishers': [for (final p in added) p.toJson()],
      }),
    );
    await tmp.rename(file.path);
  }
}
