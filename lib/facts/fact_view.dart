import 'package:flutter/material.dart';

import 'fact.dart';

/// One line for a fact: what, how old, from whom.
/// e.g. 「満員 · 20分前 · 西宮市 · 公式」 / "full · 20 min ago · Nishinomiya · official"
String factLine(Fact f, DateTime now, {required bool en}) {
  final what = switch (f.kind) {
    FactKind.shelterStatus =>
      (en ? f.shelterStatus?.en : f.shelterStatus?.ja) ?? f.value,
    FactKind.roadBlocked => en ? 'road blocked' : '通行止め',
    FactKind.waterPoint => en ? 'water: ${f.value}' : '給水：${f.value}',
    FactKind.warning => f.value,
  };
  final note = f.note.isEmpty ? '' : '（${f.note}）';
  return '$what$note · ${f.age(now, en: en)} · ${f.sourceLabel(en: en)}';
}

/// Colour hint: red for full/closed or warnings, amber for unconfirmed.
Color factColor(Fact f, ColorScheme c) {
  if (f.kind == FactKind.warning || (f.shelterStatus?.avoid ?? false)) {
    return c.error;
  }
  return f.unconfirmed ? Colors.amber.shade700 : c.onSurfaceVariant;
}

/// "Current information" box: facts that are not in the knowledge package.
class CurrentFactsBox extends StatelessWidget {
  const CurrentFactsBox({
    super.key,
    required this.facts,
    required this.now,
    required this.en,
    this.onTap,
    this.onAdd,
  });

  final List<Fact> facts;
  final DateTime now;
  final bool en;

  /// Set where facts can be entered (shelter computer): edit one fact.
  final void Function(Fact)? onTap;

  /// Set where facts can be entered: add a warning.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            en
                ? 'Current information (not from the AI)'
                : '最新の情報（AIの回答ではありません）',
            style: theme.textTheme.labelMedium,
          ),
          for (final f in facts)
            InkWell(
              onTap: onTap == null ? null : () => onTap!(f),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${factLine(f, now, en: en)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: factColor(f, theme.colorScheme),
                  ),
                ),
              ),
            ),
          if (onAdd != null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: Text(en ? 'Add warning' : '警報・注意報を追加'),
            ),
        ],
      ),
    );
  }
}
