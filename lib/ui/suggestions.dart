import 'package:flutter/material.dart';

import '../knowledge/knowledge_package.dart' show PackageInfo;
import 'package_icons.dart';

/// Up to [max] suggested first questions in [lang], taking turns between
/// the loaded packages so each one shows up (in load order, core first).
/// Each package brings its own suggestions in its manifest.
List<(IconData, String)> suggestionsFor(
  List<PackageInfo> packages, {
  required String lang,
  int max = 5,
}) {
  final lists = [
    for (final p in packages)
      if (p.suggestionsIn(lang) case final l when l.isNotEmpty) l,
  ];
  final out = <(IconData, String)>[];
  for (var i = 0; out.length < max; i++) {
    final round = [
      for (final l in lists)
        if (i < l.length) l[i],
    ];
    if (round.isEmpty) break;
    for (final s in round) {
      if (out.length < max) out.add((packageIcon(s.icon), s.text));
    }
  }
  return out;
}
