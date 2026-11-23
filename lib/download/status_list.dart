import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../util/versioned_file.dart';

/// Publishers' signed statuses (lychnion/lychnion#117, docs/distribution.md
/// "Freshness: publisher status"): what is newest from each publisher,
/// learned from catalogs, sticks and bases, and passed on with them.
///
/// It never stops anything from working. It lets the app say that a newer
/// version exists than the one it can get, and how old its news is.
/// The newest status of each publisher is kept in `status.json`, checked
/// again with the device's current keys whenever the file is read, and left
/// out of use when its signer is no longer trusted ([statusFor]).
///
/// A status signed more than [maxAhead] after the device's clock never
/// decides: a thief holding a key could otherwise pin "newest" far ahead.
/// (Its key statements and withdrawals are still taken in, by
/// Catalog.parse, from every status seen.)
class StatusList extends ChangeNotifier {
  StatusList(this.file, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final File file;
  final DateTime Function() _now;

  /// Format of status.json (see versioned_file.dart).
  static const format = 1;

  /// How far a status may be signed after the device's clock and still
  /// decide.
  static const maxAhead = Duration(days: 1);

  /// After this long without a newer status from Lychnion, the app says
  /// gently that its data may be out of date.
  static const quietAfter = Duration(days: 30);

  final _status = <String, PublisherStatus>{};

  /// The kept statuses (the newest of each publisher), as kept.
  List<PublisherStatus> get all => List.unmodifiable(_status.values);

  /// [all] whose signer [trust] has for its publisher: what is passed on
  /// and used, also between a revocation and the next [recheck].
  List<PublisherStatus> statusesFor(TrustedKeys trust) => [
    for (final s in _status.values)
      if (_trusted(s, trust)) s,
  ];

  /// The newest status of [publisher] in use, or null.
  PublisherStatus? statusFor(String publisher, TrustedKeys trust) {
    final s = _status[publisher];
    return s != null && _trusted(s, trust) ? s : null;
  }

  /// [PublisherStatus.id]s a catalog need not check again.
  Set<String> get ids => {for (final s in _status.values) s.id};

  /// The version of item [id] from [publisher] that its status names when
  /// it is newer than [version], else null.
  String? newerVersion(
    String publisher,
    String id,
    String version,
    TrustedKeys trust,
  ) {
    final s = statusFor(publisher, trust);
    return s != null && s.hasNewer(id, version) ? s.items[id] : null;
  }

  /// When the device last heard from Lychnion (its newest status was
  /// signed), or null when it never did.
  DateTime? lastNews(TrustedKeys trust) =>
      statusFor(attesterPublisher, trust)?.signedAt;

  /// True when the newest status from Lychnion is older than [quietAfter].
  /// False without any status: nothing to compare, and before Lychnion's
  /// tools sign one that would be every device.
  bool isQuiet(TrustedKeys trust) {
    final t = lastNews(trust);
    return t != null && _now().difference(t) > quietAfter;
  }

  /// Reads status.json and checks every status again with [trust]: a file
  /// changed by hand proves nothing. Unreadable or newer: a copy is kept
  /// (versioned_file.dart) and the list is empty.
  Future<void> load(TrustedKeys trust) async {
    final json = await readVersioned(file, format, (json, _) => json! as Map);
    final checked = await PublisherStatus.checkAll(
      json?['status'],
      trust,
      max: PublisherStatus.maxPerSource,
    );
    _set(_deciding(checked));
    notifyListeners();
  }

  /// Keeps those of [learned] that are newer than what is kept for their
  /// publisher ([PublisherStatus.decidesOver]), not signed more than
  /// [maxAhead] after the device's clock, and whose signer the device
  /// trusts ([trust], asked again after the save), and saves the list.
  /// Their signatures were checked when they were read. Returns true when
  /// the list changed. Throws the save's error (then nothing changed).
  Future<bool> learn(
    Iterable<PublisherStatus> learned,
    TrustedKeys Function() trust,
  ) => _serial(() async {
    final now = trust();
    final next = Map.of(_status);
    var changed = false;
    for (final s in _deciding(learned)) {
      if (!_trusted(s, now)) continue;
      final cur = next[s.publisher];
      if (cur == null || s.decidesOver(cur)) {
        next[s.publisher] = s;
        changed = true;
      }
    }
    if (!changed) return false;
    final list = next.values.toList();
    await _save(list);
    final after = trust();
    _set([
      for (final s in list)
        if (_trusted(s, after)) s,
    ]);
    notifyListeners();
    return true;
  });

  /// Leaves out the statuses whose signer [trust] no longer has for their
  /// publisher (a revoked key). Not saved: the file is checked again when
  /// it is read.
  void recheck(TrustedKeys trust) {
    final kept = [
      for (final s in _status.values)
        if (_trusted(s, trust)) s,
    ];
    if (kept.length == _status.length) return;
    _set(kept);
    notifyListeners();
  }

  /// The newest of each publisher in [statuses], among those not signed
  /// more than [maxAhead] after the device's clock.
  List<PublisherStatus> _deciding(Iterable<PublisherStatus> statuses) {
    final limit = _now().add(maxAhead);
    return PublisherStatus.newest([
      for (final s in statuses)
        if (!s.signedAt.isAfter(limit)) s,
    ]);
  }

  static bool _trusted(PublisherStatus s, TrustedKeys trust) =>
      trust.keysOf(s.publisher).contains(s.signer);

  void _set(List<PublisherStatus> list) {
    _status
      ..clear()
      ..addAll({for (final s in list) s.publisher: s});
  }

  /// One learn after another: each saves the list as the one before left
  /// it.
  Future<void> _last = Future.value();

  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _last.then((_) => f());
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _save(List<PublisherStatus> list) async {
    if (!mayReplace(file)) {
      throw FileSystemException('kept as it is', file.path);
    }
    await file.parent.create(recursive: true);
    // Written next to the file, then renamed: a cut write leaves the old
    // list.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'format': format,
        'status': [for (final s in list) s.json],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
