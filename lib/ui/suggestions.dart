import 'package:flutter/material.dart';

import '../app/lang.dart';
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

/// The suggested questions of each loaded package, under the package's
/// name (in the question screen; Home shows the packages themselves).
class SuggestionGroups extends StatelessWidget {
  const SuggestionGroups({
    super.key,
    required this.packages,
    required this.onAsk,
    this.perPackage = 3,
  });

  final List<PackageInfo> packages;

  /// Null while questions can't be asked yet.
  final void Function(String)? onAsk;
  final int perPackage;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = [
      for (final p in packages)
        if (p.suggestionsIn(lang) case final s when s.isNotEmpty)
          (p, s.take(perPackage).toList()),
    ];
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.askTryAsking,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        for (final (p, list) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Icon(packageIcon(p.icon), size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(p.nameIn(lang), style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          for (final q in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onAsk == null ? null : () => onAsk!(q.text),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Icon(packageIcon(q.icon), color: scheme.primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            q.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
