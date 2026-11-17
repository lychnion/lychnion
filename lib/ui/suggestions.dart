import 'package:flutter/material.dart';

/// Suggested first questions per knowledge package, each one the package
/// answers well (see test/knowledge_package_test.dart).
const _byPackage = <String, List<(IconData, String, String)>>{
  'jp.bousai.core': [
    (
      Icons.waves_rounded,
      '海の近くで強い揺れを感じたら？',
      'Strong shaking near the sea: what should I do?',
    ),
    (Icons.healing_rounded, 'けがをして出血しているときは？', 'How do I stop heavy bleeding?'),
    (
      Icons.water_drop_outlined,
      '非常用の水はどれくらい必要？',
      'How much emergency water do I need?',
    ),
    (
      Icons.forest_outlined,
      '山でクマに出会ったら？',
      'What if I meet a bear in the mountains?',
    ),
  ],
  'jp.outdoor.hiking': [
    (
      Icons.thunderstorm_outlined,
      '山で雷が鳴ってきたら？',
      'Thunder in the mountains: what should I do?',
    ),
    (
      Icons.bug_report_outlined,
      'マダニに刺されたら？',
      'What should I do after a tick bite?',
    ),
    (
      Icons.volcano_outlined,
      '噴火速報が出たら？',
      'What should I do after an eruption alert?',
    ),
  ],
};

/// Up to [max] questions, taking turns between the loaded packages so each
/// one shows up (core package first). The core list when none are known.
List<(IconData, String)> suggestionsFor(
  List<String> packageIds, {
  required bool en,
  int max = 5,
}) {
  final lists = [for (final id in packageIds) ?_byPackage[id]];
  if (lists.isEmpty) lists.add(_byPackage['jp.bousai.core']!);
  final out = <(IconData, String)>[];
  for (var i = 0; out.length < max; i++) {
    final round = [
      for (final l in lists)
        if (i < l.length) l[i],
    ];
    if (round.isEmpty) break;
    for (final (icon, ja, english) in round) {
      if (out.length < max) out.add((icon, en ? english : ja));
    }
  }
  return out;
}
