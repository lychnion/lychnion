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
  FactStore({DateTime Function()? clock, this.trust, this.signer})
    : _clock = clock ?? DateTime.now;

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
    // Keys trusted since the facts were saved (a base's QR code scanned
    // after its facts came): checked again at every start.
    await reverify();
    notifyListeners();
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
        final text = const Utf8Decoder(
          allowMalformed: true,
        ).convert(await file.readAsBytes());
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
    final fresh = [
      for (final f in facts)
        if (known.add(_key(f))) f,
    ];
    if (fresh.isEmpty) return 0;
    final t = trust;
    if (t != null && !checked) {
      for (final f in fresh) {
        f.verified = f.sourceType == SourceType.citizen || await t.verify(f);
      }
    }
    _facts.addAll(fresh);
    final file = _file;
    if (file != null) {
      await _serial(() async {
        // Checked in the queue, after a running load kept its copy.
        if (!mayReplace(file)) return;
        if (!await file.exists()) await _rewrite(file, const []);
        await file.writeAsString(
          '${fresh.map((f) => jsonEncode({...f.toJson(), 'v_ok': f.verified})).join('\n')}\n',
          mode: FileMode.append,
        );
      });
    }
    notifyListeners();
    return fresh.length;
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
  List<Fact> get all => [
    for (final f in _facts)
      if (!f.isExpired(now)) f,
  ];

  /// The winning fact per topic: the most trusted source first, then the
  /// newest report from that source. Expired facts never win. A winning
  /// "cleared" fact (road reopened, warning lifted) hides the topic.
  List<Fact> get current {
    final best = <String, Fact>{};
    for (final f in all) {
      final b = best[f.topic];
      if (b == null || _beats(f, b)) best[f.topic] = f;
    }
    return [
      for (final f in best.values)
        if (!f.isCleared) f,
    ]..sort((a, b) => b.observedAt.compareTo(a.observedAt));
  }

  static bool _beats(Fact a, Fact b) {
    if (a.trust != b.trust) return a.trust > b.trust;
    return a.observedAt.isAfter(b.observedAt);
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
