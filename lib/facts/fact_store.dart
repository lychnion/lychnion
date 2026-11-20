import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../util/versioned_file.dart';
import 'fact.dart';
import 'signing.dart';

/// Current facts on this device, kept apart from the knowledge packages.
///
/// Facts are only added, never edited: a newer fact replaces an older one
/// by winning [current]. Expired facts are never returned.
class FactStore extends ChangeNotifier {
  FactStore({
    DateTime Function()? clock,
    this.trust,
    this.signer,
    this.maxFacts = 5000,
  }) : _clock = clock ?? DateTime.now;

  /// Facts kept at most, in memory and on disk. A base may send 500 new
  /// facts a minute; without a limit they would fill the phone. Expired
  /// facts go first, then the oldest that do not decide a topic.
  final int maxFacts;

  /// Keys whose official / sensor facts count as such. Without a trust
  /// list (tests, old setups) every fact is taken as it says.
  final TrustList? trust;

  /// This device's key: official facts entered here are signed with it.
  FactSigner? signer;

  final DateTime Function() _clock;
  final _facts = <Fact>[];
  File? _file;

  DateTime get now => _clock();

  /// Format of facts.jsonl (see versioned_file.dart), in its first line
  /// `{"format": 1}`; then one fact per line. 0: no first line.
  static const format = 1;

  static final _header = jsonEncode({'format': format});

  /// Loads the saved facts from app support, or from [dir] (tests).
  ///
  /// A line that cannot be read is skipped; the file is then kept as
  /// `facts.jsonl.broken` and written again without it. A file from a
  /// newer app is kept as `facts.jsonl.newer` and started anew: new facts
  /// must not be added to a file in a format this build does not know.
  Future<void> load({Directory? dir}) async {
    dir ??= await getApplicationSupportDirectory();
    final file = _file = File('${dir.path}/facts.jsonl');
    await _serial(() => _loadFrom(file));
    // Keys trusted since the facts were saved (a base's code compared
    // after its facts came): checked again at every start, before the
    // limit drops unverified facts first.
    await reverify();
    // Keys no longer trusted (a base removed, and the app stopped before
    // facts.jsonl was written again): their facts are unconfirmed again.
    final dropped = _untrust();
    await _serial(() async {
      if ((_prune() || dropped > 0) &&
          mayReplace(file) &&
          await file.exists()) {
        await _rewrite(file, [for (final f in _facts) _line(f)]);
      }
    });
    notifyListeners();
  }

  /// Marks unconfirmed the verified facts signed by a key id that [trust]
  /// no longer holds; returns how many. Facts from a signed radio message
  /// keep no key id and are left as they are (see [forgetKey]).
  int _untrust() {
    final t = trust;
    if (t == null) return 0;
    var n = 0;
    for (final f in _facts) {
      final id = f.keyId;
      if (!f.verified || f.sourceType == SourceType.citizen || id == null) {
        continue;
      }
      if (t.trusts(id)) continue;
      f.verified = false;
      n++;
    }
    return n;
  }

  /// Reading, upgrading and adding to the file go one after another: an
  /// upgrade must not drop facts added meanwhile.
  Future<void> _io = Future.value();

  Future<void> _serial(Future<void> Function() step) {
    final next = _io.then((_) => step());
    _io = next.catchError((Object _) {});
    return next;
  }

  Future<void> _loadFrom(File file) async {
    if (await file.exists()) {
      var lines = const <String>[];
      try {
        // A write cut in the middle of a character spoils one line,
        // not the whole file: that line is then skipped below.
        final text = const Utf8Decoder(allowMalformed: true)
            .convert(await file.readAsBytes());
        lines = [
          for (final l in const LineSplitter().convert(text))
            if (l.trim().isNotEmpty) l,
        ];
      } on Object {
        await keepAside(file, 'broken');
      }
      var f = 0;
      if (lines.isNotEmpty) {
        try {
          final j = jsonDecode(lines.first);
          if (j is Map && j.length == 1 && j.containsKey('format')) {
            f = j['format'] is int ? j['format'] as int : format + 1;
            lines = lines.sublist(1);
          }
        } on Object {
          // A broken first line: read below like the others.
        }
      }
      if (f > format) {
        await keepAside(file, 'newer');
        lines = const [];
      }
      final good = <String>[];
      for (final line in lines) {
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          // The check result is kept on this device (it is never sent on).
          _facts.add(Fact.fromJson(j)..verified = j['v_ok'] as bool? ?? true);
          good.add(line);
        } on Object catch (e) {
          debugPrint('fact not read: $e');
        }
      }
      if (good.length < lines.length) await keepAside(file, 'broken');
      // Not when a copy could not be made: the file stays as it is.
      if (mayReplace(file) && (f != format || good.length < lines.length)) {
        await _rewrite(file, good);
      }
    }
  }

  /// Writes [lines] under the current header, next to the file first.
  Future<void> _rewrite(File file, List<String> lines) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      [_header, ...lines].map((l) => '$l\n').join(),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Adds facts not seen before; returns how many were new. Official and
  /// sensor facts are checked against [trust], unless [checked] (a signed
  /// radio message was verified already).
  Future<int> addAll(Iterable<Fact> facts, {bool checked = false}) async {
    final known = {for (final f in _facts) _key(f)};
    final t = now;
    final fresh = [
      for (final f in facts)
        // Expired ones are not kept (a base sends all it has, each time),
        // nor ones outside the time bounds (#70).
        if (!f.isExpired(t) && inTimeBounds(f, t) && known.add(_key(f))) f,
    ];
    if (fresh.isEmpty) return 0;
    final keys = trust;
    if (keys != null && !checked) {
      for (final f in fresh) {
        f.verified = f.sourceType == SourceType.citizen || await keys.verify(f);
      }
    }
    _facts.addAll(fresh);
    final pruned = _prune();
    // Not those the limit dropped at once.
    final kept = pruned
        ? (Set<Fact>.identity()..addAll(_facts))
              .intersection(Set<Fact>.identity()..addAll(fresh))
              .length
        : fresh.length;
    final file = _file;
    if (file != null) {
      // What to write, taken now: facts may arrive while this waits.
      final all = pruned ? [for (final f in _facts) _line(f)] : null;
      await _serial(() async {
        // Checked in the queue, after a running load kept its copy.
        if (!mayReplace(file)) return;
        if (all != null) return _rewrite(file, all);
        if (!await file.exists()) await _rewrite(file, const []);
        await file.writeAsString(
          '${fresh.map(_line).join('\n')}\n',
          mode: FileMode.append,
        );
      });
    }
    notifyListeners();
    return kept;
  }

  /// A fact as saved: the check result is kept on this device only.
  static String _line(Fact f) =>
      jsonEncode({...f.toJson(), 'v_ok': f.verified});

  /// Drops expired facts and copies, then, over [maxFacts], first the
  /// unverified ones (anyone on the Wi-Fi can send those), then those
  /// that do not decide their topic, the oldest first. Returns whether any
  /// were dropped.
  bool _prune() {
    final t = now;
    final before = _facts.length;
    final seen = <String>{};
    // Also facts whose own dates are impossible (#70). Not those that are
    // only ahead of this clock: after a clock correction they count again,
    // and `all` hides them meanwhile.
    // A date more than a year ahead comes only from a far wrong clock or
    // an old file (2099): it would hold a slot for decades, hidden.
    final yearAhead = t.add(const Duration(days: 365));
    _facts.removeWhere(
      (f) =>
          f.isExpired(t) ||
          !_sane(f) ||
          f.observedAt.isAfter(yearAhead) ||
          !seen.add(_key(f)),
    );
    if (_facts.length > maxFacts) {
      final best = <String, Fact>{};
      for (final f in _facts) {
        final b = best[f.topic];
        if (b == null || _beats(f, b, t)) best[f.topic] = f;
      }
      final winners = best.values.toSet();
      int keep(Fact f) =>
          (f.verified && f.sourceType != SourceType.citizen ? 2 : 0) +
          (winners.contains(f) ? 1 : 0);
      // A time after now counts as now: a fact cannot stay by claiming
      // to be from the future.
      DateTime at(Fact f) => f.observedAt.isAfter(t) ? t : f.observedAt;
      final order = List.of(_facts)
        ..sort((a, b) {
          final k = keep(a) - keep(b);
          return k != 0 ? k : at(a).compareTo(at(b));
        });
      final drop = order.take(_facts.length - maxFacts).toSet();
      _facts.removeWhere(drop.contains);
    }
    return _facts.length < before;
  }

  /// Checks the unverified facts again (a key was trusted since, e.g. a
  /// base's QR code was scanned); returns how many are verified now.
  Future<int> reverify() async {
    final t = trust;
    if (t == null) return 0;
    var n = 0;
    // A copy: facts may arrive while this waits.
    for (final f in List.of(_facts)) {
      if (f.verified || f.sourceType == SourceType.citizen) continue;
      if (await t.verify(f)) {
        f.verified = true;
        n++;
      }
    }
    if (n > 0) notifyListeners();
    return n;
  }

  /// The key with id [keyId] (named [name]) is no longer trusted: facts it
  /// signed count as unconfirmed again. Facts from a signed radio message
  /// keep no key id; they are recognised by the key's name, which the
  /// phone gave them when it checked the message. Names are not unique, so
  /// radio facts of another trusted key with the same name are marked too
  /// (unconfirmed, never the other way round). Returns how many changed.
  Future<int> forgetKey(String keyId, {String? name}) async {
    var n = 0;
    for (final f in _facts) {
      if (!f.verified || f.sourceType == SourceType.citizen) continue;
      final signedBy = f.keyId == keyId;
      final fromRadio =
          f.keyId == null &&
          name != null &&
          name.isNotEmpty &&
          f.sourceName == name;
      if (!signedBy && !fromRadio) continue;
      f.verified = false;
      n++;
    }
    if (n == 0) return 0;
    final file = _file;
    try {
      await _serial(() async {
        if (file != null && mayReplace(file) && await file.exists()) {
          await _rewrite(file, [for (final f in _facts) _line(f)]);
        }
      });
    } finally {
      // Shown as unconfirmed now, even when the file could not be written.
      notifyListeners();
    }
    return n;
  }

  /// Facts entered on this device: official and sensor ones are signed
  /// with [signer] first, so other devices can check them.
  Future<int> addOwn(Iterable<Fact> facts) async {
    final s = signer;
    return addAll([
      for (final f in facts)
        s != null && f.sourceType != SourceType.citizen ? await s.sign(f) : f,
    ]);
  }

  static String _key(Fact f) =>
      '${f.topic}|${f.value}|${f.observedAt.millisecondsSinceEpoch}|${f.sourceType.code}';

  /// All facts that have not expired, including ones that lost a conflict.
  List<Fact> get all {
    final t = now;
    return [
      for (final f in _facts)
        if (!f.isExpired(t) && inTimeBounds(f, t)) f,
    ];
  }

  /// How far in the future a fact may be dated: clocks differ, and a
  /// phone without network time (no mobile network in a disaster) drifts
  /// or is set by hand. Until its time comes, such a fact ranks below any
  /// fact not dated in the future ([_beats]); after that it is an ordinary
  /// report, so the window delays nothing more than a report sent then.
  /// A device whose clock is further behind refuses fresh facts.
  static const maxSkew = Duration(minutes: 30);

  /// The longest a fact may claim to stay current. The app's own form
  /// offers at most 24 hours; a shelter status or a blocked road is
  /// reported again when it still holds.
  static const maxLifetime = Duration(days: 3);

  /// Whether [f] is within the time bounds at [now] (lychnion/lychnion#70):
  /// dated at most [maxSkew] ahead, a lifetime of at most [maxLifetime],
  /// and expiring at most that long from now. Otherwise one fact dated
  /// 2099, from a resident or signed once by any trusted key, would win
  /// its topic for years; a "cleared" one would hide the topic. Such a
  /// fact is refused, not shortened: its signature covers both times.
  static bool inTimeBounds(Fact f, DateTime now) =>
      _sane(f) &&
      !f.observedAt.isAfter(now.add(maxSkew)) &&
      !f.expiresAt.isAfter(now.add(maxLifetime + maxSkew));

  /// The part that does not depend on the clock: ends after it begins and
  /// lives at most [maxLifetime]. Only such facts are dropped from storage.
  static bool _sane(Fact f) =>
      !f.expiresAt.isBefore(f.observedAt) &&
      f.expiresAt.difference(f.observedAt) <= maxLifetime;

  /// The winning fact per topic: the most trusted source first, then the
  /// newest report from that source. Expired facts never win. A winning
  /// "cleared" fact (road reopened, warning lifted) hides the topic.
  List<Fact> get current {
    final t = now;
    final best = <String, Fact>{};
    for (final f in all) {
      final b = best[f.topic];
      if (b == null || _beats(f, b, t)) best[f.topic] = f;
    }
    return [
      for (final f in best.values)
        if (!f.isCleared) f,
    ]..sort((a, b) => b.observedAt.compareTo(a.observedAt));
  }

  /// Whether [a] wins its topic over [b] at [t]: the most trusted first;
  /// among the same trust, one dated after [t] loses to any that is not,
  /// so a date in the [maxSkew] window does not override a real report
  /// before that date comes (#70); otherwise the newest. Instants are
  /// compared, so UTC and local times of the same moment are equal.
  static bool _beats(Fact a, Fact b, DateTime t) {
    if (a.trust != b.trust) return a.trust > b.trust;
    final aAhead = a.observedAt.isAfter(t), bAhead = b.observedAt.isAfter(t);
    if (aAhead != bAhead) return bAhead;
    // Both ahead: the one less far ahead. Neither: the newest.
    final c = a.observedAt.compareTo(b.observedAt);
    return aAhead ? c < 0 : c > 0;
  }

  /// The current status of an evacuation site, if any fact says so.
  Fact? shelterStatus(String siteId) {
    for (final f in current) {
      if (f.kind == FactKind.shelterStatus && f.subject == siteId) return f;
    }
    return null;
  }

  /// Current facts of [kinds] (all kinds if empty).
  List<Fact> currentOf(Set<FactKind> kinds) => [
    for (final f in current)
      if (kinds.isEmpty || kinds.contains(f.kind)) f,
  ];
}
