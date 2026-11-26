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
  PublisherList(
    this.file, {
    TrustedKeys? builtIn,
    this.maxStatements = defaultMaxStatements,
  }) : builtIn = builtIn ?? builtInPublishers;

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

  /// At most this many statements are kept in each budget
  /// ([maxStatements]; see [_budgets]): the current roots' statements,
  /// and the others. Revocations (by the key itself, and a current root's
  /// of a granted key within its cap) and theft proofs have a budget of
  /// their own, twice as large, that nothing else uses.
  static const defaultMaxStatements = 1000;

  /// [defaultMaxStatements]; smaller in tests.
  final int maxStatements;

  /// All budgets together, in times [maxStatements]: what [load] reads
  /// back.
  static const _readBack = 4;

  /// The most each budget of [_budgets] keeps.
  List<int> get _budgetMax => [maxStatements * 2, maxStatements, maxStatements];

  /// The most of budget 0 that added publishers' statements (revocations
  /// and theft proofs) may use together: the other half is kept for the
  /// built-in publishers (Lychnion), so added publishers cannot push out
  /// a revocation of Lychnion's keys.
  int get _addedZeroMax => maxStatements;

  bool _isBuiltIn(KeyStatement s) => builtIn.known.contains(s.publisher);

  /// Whether [s], kept in budget [b], counts toward [_addedZeroMax].
  bool _addedZero(int b, KeyStatement s) => b == 0 && !_isBuiltIn(s);

  /// Which of [list] fit, in order, into the budgets ([budgets], one per
  /// statement) after [used] and [usedAdded] (changed in place). Those in
  /// [free] (an added publisher's own chain) always fit and use no room.
  /// The replacements of one old key in budget 0 (a theft proof's halves)
  /// fit together or not at all: a lone half would trust the thief's new
  /// key. [learn] and [_keptOf] both use this, so what a phone takes it
  /// also reads back.
  List<bool> _fit(
    List<KeyStatement> list,
    List<int> budgets,
    Set<String> free,
    List<int> used,
    int usedAdded,
  ) {
    final max = _budgetMax;
    final pairs = <String, List<int>>{};
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      if (budgets[i] != 0 ||
          s.type != KeyStatementType.replace ||
          free.contains(s.id)) {
        continue;
      }
      pairs
          .putIfAbsent(
            '${s.publisher} ${TrustedKeys.canonicalKey(s.oldKey)}',
            () => [],
          )
          .add(i);
    }
    final groupOf = <int, List<int>>{
      for (final g in pairs.values)
        for (final i in g) i: g,
    };
    final out = List<bool?>.filled(list.length, null);
    for (var i = 0; i < list.length; i++) {
      if (out[i] != null) continue;
      if (free.contains(list[i].id)) {
        out[i] = true;
        continue;
      }
      final group = groupOf[i] ?? [i];
      final b = budgets[i];
      final n = group.length;
      final added = _addedZero(b, list[i]);
      final ok =
          used[b] + n <= max[b] && (!added || usedAdded + n <= _addedZeroMax);
      if (ok) {
        used[b] += n;
        if (added) usedAdded += n;
      }
      for (final j in group) {
        out[j] = ok;
      }
    }
    return [for (final o in out) o!];
  }

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
    // Replaced only by a successor in the root chain: a granted key
    // (lychnion/lychnion#125) is not a replacement.
    return trust.rootChainOf(name).difference(roots).isEmpty
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
    // Each one checked again: a file edited by hand proves nothing. All
    // that learn kept are read back: revocations and theft proofs may be
    // past maxStatements (lychnion/lychnion#59), and so may the replacements
    // through an added key (after the links: see _onAddedChains).
    // A signature stored before #59 may be spelled another way (padding,
    // the other alphabet): written the one way first, then verified.
    final stored = json?['statements'];
    _statements.addAll(
      _keptOf(
        await KeyStatement.checkAll(
          stored is List ? stored.map(KeyStatement.respelled).toList() : null,
          max: maxStatements * _readBack,
        ),
      ),
    );
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
  /// every one: a publisher's own revocation on a new computer, so [any]
  /// must only get the user's own statements), and saves them. Returns true when the trusted keys changed (then install
  /// records and catalogs must be checked again). Throws the save's error
  /// (then nothing changed).
  Future<bool> learn(Iterable<KeyStatement> learned, {bool any = false}) =>
      _serial(() async {
        final before = _keySummary();
        final seen = {for (final s in _statements) s.id};
        // Only statements made by a key trusted here (see
        // relevantStatements): statements anyone can make about keys of
        // their own never fill the list. Revocations by the key itself
        // and theft proofs have their own budget: losing one would trust
        // a stolen key again.
        final candidates = any
            ? [
                for (final s in learned)
                  if (seen.add(s.id)) s,
              ]
            : await relevantStatements(trust, learned.toList());
        // Like a revocation: a second successor of a key proves a theft,
        // and losing it would trust the thief's chain. Its other half may
        // be in this batch too, but only for a key trusted before it: a
        // thief's own new keys cannot each add a pair (#59).
        final trustedBefore = trust;
        bool inBatchProof(KeyStatement s) =>
            s.type == KeyStatementType.replace &&
            trustedBefore.keysOf(s.publisher).contains(s.oldKey) &&
            candidates.any(
              (o) =>
                  o.type == KeyStatementType.replace &&
                  o.publisher == s.publisher &&
                  o.oldKey == s.oldKey &&
                  o.newKey != s.newKey,
            );
        // Ranked with the batch included (a new root's statements in the
        // same batch as its rotation), as on reload.
        final basis = trustedBefore.withStatements(candidates);
        // An added publisher's own chain is not counted, as on reload.
        final chains = _onAddedChains(_added.values, [
          ..._statements,
          ...candidates,
        ]);
        final used = [0, 0, 0];
        var usedAdded = 0;
        // A stored half whose partner is in this batch is a theft proof
        // now, as on reload.
        final stored = _budgets(_statements, [
          ..._statements,
          ...candidates,
        ], basis);
        for (var i = 0; i < _statements.length; i++) {
          if (chains.contains(_statements[i].id)) continue;
          used[stored[i]]++;
          if (_addedZero(stored[i], _statements[i])) usedAdded++;
        }
        final budgets = _budgets(
          candidates,
          _statements,
          basis,
          before: _statements,
        );
        final fits = any
            ? const <bool>[]
            : _fit(
                candidates,
                [
                  for (var i = 0; i < candidates.length; i++)
                    inBatchProof(candidates[i]) ? 0 : budgets[i],
                ],
                chains,
                used,
                usedAdded,
              );
        final fresh = <KeyStatement>[];
        // The user's own statements ([any]): kept while all budgets
        // together have room, as far as load reads back; past the limit
        // this computer would forget that its old key was replaced (#59).
        var hard = maxStatements * _readBack - _statements.length;
        for (var i = 0; i < candidates.length; i++) {
          if (any) {
            if (hard-- > 0) fresh.add(candidates[i]);
            continue;
          }
          if (fits[i]) fresh.add(candidates[i]);
        }
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

  /// The budget each of [list] is kept in, in order: 0 for a revocation
  /// by the key itself, a current root's revocation of another key within
  /// its cap (KeyStatement.maxRootRevokesByPerPublisher), or a replacement
  /// that proves a theft ([all]); 1 for another statement of a current
  /// root of [basis] (statementRank 1, lychnion/lychnion#125) within the
  /// caps per publisher (KeyStatement.maxRootGrantsPerPublisher and
  /// maxRootReplacesPerPublisher); 2 for any other. Those of [before]
  /// count toward the caps too. So other publishers' roots cannot use up
  /// the room of a revocation: a dropped revocation would trust a stolen
  /// key again.
  static List<int> _budgets(
    List<KeyStatement> list,
    List<KeyStatement> all,
    TrustedKeys basis, {
    Iterable<KeyStatement> before = const [],
  }) {
    final grants = <String, int>{}, replaces = <String, int>{};
    final revokes = <String, int>{};
    bool fits(KeyStatement s) {
      final (m, cap) = switch (s.type) {
        KeyStatementType.replace => (
          replaces,
          KeyStatement.maxRootReplacesPerPublisher,
        ),
        KeyStatementType.grant => (
          grants,
          KeyStatement.maxRootGrantsPerPublisher,
        ),
        _ => (revokes, KeyStatement.maxRootRevokesByPerPublisher),
      };
      final n = m[s.publisher] ?? 0;
      if (n >= cap) return false;
      m[s.publisher] = n + 1;
      return true;
    }

    bool selfOrTheft(KeyStatement s) =>
        (s.type == KeyStatementType.revoke && s.by == null) ||
        provesTheft(s, all);
    bool rootRevoke(KeyStatement s) =>
        s.type == KeyStatementType.revoke &&
        s.by != null &&
        statementRank(s, basis) == 1;
    for (final s in before) {
      if (!selfOrTheft(s) && statementRank(s, basis) == 1) fits(s);
    }
    return [
      for (final s in list)
        if (selfOrTheft(s) || (rootRevoke(s) && fits(s)))
          0
        else if (!rootRevoke(s) && statementRank(s, basis) == 1 && fits(s))
          1
        else
          2,
    ];
  }

  /// What [learn] could have kept of [read]: as many of each budget
  /// ([_budgets]) as it keeps, in the order read.
  List<KeyStatement> _keptOf(List<KeyStatement> read) {
    // Whose statements are the roots': the current roots after them.
    final basis = builtIn
        .plus({
          for (final p in _added.values) p.name: [p.key],
        })
        .withStatements(read);
    // Not counted in a budget: at most 50 per added publisher.
    final chains = _onAddedChains(_added.values, read);
    final budgets = _budgets(read, read, basis);
    final fits = _fit(read, budgets, chains, [0, 0, 0], 0);
    return [
      for (var i = 0; i < read.length; i++)
        if (fits[i]) read[i],
    ];
  }

  /// The replacements through each added key: back to the first key, and
  /// on while each key has one successor, at most
  /// [KeyStatement.maxReplacesPerPublisher] per publisher. They include
  /// what [learn] kept past the limit for the user's own key (`any`):
  /// after a key change, the new key or the first one is added
  /// (adoptNewKey). Only the holder of a chain's keys can make one, and a
  /// thief's second successor ends it (#59).
  static Set<String> _onAddedChains(
    Iterable<Publisher> added,
    List<KeyStatement> all,
  ) {
    String canon(String k) => TrustedKeys.canonicalKey(k);
    final into = <String, List<KeyStatement>>{};
    final from = <String, List<KeyStatement>>{};
    for (final s in all) {
      if (s.type != KeyStatementType.replace || s.newKey == null) continue;
      into.putIfAbsent('${s.publisher} ${canon(s.newKey!)}', () => []).add(s);
      from.putIfAbsent('${s.publisher} ${canon(s.oldKey)}', () => []).add(s);
    }
    final out = <String>{};
    for (final p in added) {
      var left = KeyStatement.maxReplacesPerPublisher;
      final start = canon(p.key);
      // Back: every predecessor (each needs this chain's newer key).
      final todo = [start];
      final seen = <String>{};
      while (todo.isNotEmpty && left > 0) {
        final k = todo.removeLast();
        if (!seen.add(k)) continue;
        for (final s in into['${p.name} $k'] ?? const <KeyStatement>[]) {
          if (left > 0 && out.add(s.id)) {
            left--;
            todo.add(canon(s.oldKey));
          }
        }
      }
      // On: while there is one successor.
      var k = start;
      final ahead = <String>{k};
      while (left > 0) {
        final next = from['${p.name} $k'] ?? const <KeyStatement>[];
        if (next.length != 1) break;
        final s = next.single;
        k = canon(s.newKey!);
        if (!ahead.add(k) || !out.add(s.id)) break;
        left--;
      }
    }
    return out;
  }

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
