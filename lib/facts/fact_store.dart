import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fact.dart';

/// Current facts on this device, kept apart from the knowledge packages.
///
/// Facts are only added, never edited: a newer fact replaces an older one
/// by winning [current]. Expired facts are never returned.
class FactStore extends ChangeNotifier {
  FactStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

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
        _facts.add(Fact.fromJson(jsonDecode(line) as Map<String, dynamic>));
      }
    }
    notifyListeners();
  }

  /// Adds facts not seen before; returns how many were new.
  Future<int> addAll(Iterable<Fact> facts) async {
    final known = {for (final f in _facts) _key(f)};
    final fresh = [
      for (final f in facts)
        if (known.add(_key(f))) f,
    ];
    if (fresh.isEmpty) return 0;
    _facts.addAll(fresh);
    final file = _file;
    if (file != null) {
      await file.writeAsString(
        '${fresh.map((f) => jsonEncode(f.toJson())).join('\n')}\n',
        mode: FileMode.append,
      );
    }
    notifyListeners();
    return fresh.length;
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
    if (a.sourceType.trust != b.sourceType.trust) {
      return a.sourceType.trust > b.sourceType.trust;
    }
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
