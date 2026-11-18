import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Loads the saved facts (one JSON object per line).
  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/facts.jsonl');
    if (await _file!.exists()) {
      for (final line in await _file!.readAsLines()) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        // The check result is kept on this device (it is never sent on).
        _facts.add(Fact.fromJson(j)..verified = j['v_ok'] as bool? ?? true);
      }
    }
    notifyListeners();
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
      await file.writeAsString(
        '${fresh.map((f) => jsonEncode({...f.toJson(), 'v_ok': f.verified})).join('\n')}\n',
        mode: FileMode.append,
      );
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
    for (final f in _facts) {
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
