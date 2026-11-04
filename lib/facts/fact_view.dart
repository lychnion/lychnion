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

  static IconData _icon(FactKind k) => switch (k) {
    FactKind.warning => Icons.campaign_rounded,
    FactKind.roadBlocked => Icons.do_not_disturb_on_rounded,
    FactKind.waterPoint => Icons.water_drop_rounded,
    FactKind.shelterStatus => Icons.home_work_rounded,
  };

  String _what(Fact f) => switch (f.kind) {
    FactKind.shelterStatus =>
      (en ? f.shelterStatus?.en : f.shelterStatus?.ja) ?? f.value,
    FactKind.roadBlocked => en ? 'Road blocked' : '通行止め',
    FactKind.waterPoint => en ? 'Water: ${f.value}' : '給水：${f.value}',
    FactKind.warning => f.value,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            en
                ? 'Current information · not from the AI'
                : '最新の情報 · AIの回答ではありません',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          for (final f in facts)
            InkWell(
              onTap: onTap == null ? null : () => onTap!(f),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(f.kind), size: 20, color: factColor(f, scheme)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.note.isEmpty
                                ? _what(f)
                                : '${_what(f)}（${f.note}）',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: factColor(f, scheme),
                            ),
                          ),
                          Text(
                            '${f.age(now, en: en)} · ${f.sourceLabel(en: en)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

/// Small coloured label: 満員 · 20分前.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.fact,
    required this.now,
    required this.en,
  });

  final Fact fact;
  final DateTime now;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = fact.shelterStatus;
    final color = factColor(fact, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${(en ? st?.en : st?.ja) ?? fact.value} · ${fact.age(now, en: en)}'
        '${fact.unconfirmed ? (en ? ' · unconfirmed' : ' · 未確認') : ''}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
