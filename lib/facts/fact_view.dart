import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import 'fact.dart';

/// 「満員」 / "full"; an unknown value as it is.
String shelterStatusName(AppLocalizations l, Fact f) =>
    f.shelterStatus == null ? f.value : l.shelterStatus(f.shelterStatus!.key);

/// "2時間前" / "2 h ago".
String factAge(AppLocalizations l, Fact f, DateTime now) {
  final d = now.difference(f.observedAt);
  if (d.inMinutes < 1) return l.justNow;
  if (d.inMinutes < 60) return l.minutesAgo('${d.inMinutes}');
  if (d.inHours < 48) return l.hoursAgo('${d.inHours}');
  return l.daysAgo('${d.inDays}');
}

/// "市・公式", "センサー", "住民の報告・未確認".
String factSourceLabel(AppLocalizations l, Fact f) {
  final type = switch (f.sourceType) {
    SourceType.official when !f.verified => l.factSourceOfficialUnverified,
    SourceType.sensor when !f.verified => l.factSourceSensorUnverified,
    SourceType.official => l.factSourceOfficial,
    SourceType.sensor => l.factSourceSensor,
    SourceType.citizen => l.factSourceCitizen,
  };
  return f.sourceName.isEmpty ? type : '${f.sourceName} · $type';
}

/// One line for a fact: what, how old, from whom.
/// e.g. 「満員 · 20分前 · 西宮市 · 公式」 / "full · 20 min ago · Nishinomiya · official"
String factLine(AppLocalizations l, Fact f, DateTime now) {
  final what = switch (f.kind) {
    FactKind.shelterStatus => shelterStatusName(l, f),
    FactKind.roadBlocked => l.factRoadBlocked,
    FactKind.waterPoint => l.factWater(f.value),
    FactKind.warning => f.value,
  };
  final note = f.note.isEmpty ? '' : '（${f.note}）';
  return '$what$note · ${factAge(l, f, now)} · ${factSourceLabel(l, f)}';
}

/// Colour hint: red for full/closed or warnings, amber (Glow) for
/// unconfirmed.
Color factColor(Fact f, ColorScheme c) {
  if (f.kind == FactKind.warning || (f.shelterStatus?.avoid ?? false)) {
    return c.error;
  }
  // Tertiary (Glow Deep by day, Glow by night) is readable as text;
  // plain amber is about 2:1 on Paper.
  return f.unconfirmed ? c.tertiary : c.onSurfaceVariant;
}

/// "Current information" box: facts that are not in the knowledge package.
class CurrentFactsBox extends StatelessWidget {
  const CurrentFactsBox({
    super.key,
    required this.facts,
    required this.now,
    this.onTap,
    this.onAdd,
  });

  final List<Fact> facts;
  final DateTime now;

  /// Set where facts can be entered (base computer): edit one fact.
  final void Function(Fact)? onTap;

  /// Set where facts can be entered: add a warning.
  final VoidCallback? onAdd;

  static IconData _icon(FactKind k) => switch (k) {
    FactKind.warning => Icons.campaign_rounded,
    FactKind.roadBlocked => Icons.do_not_disturb_on_rounded,
    FactKind.waterPoint => Icons.water_drop_rounded,
    FactKind.shelterStatus => Icons.home_work_rounded,
  };

  static String _what(AppLocalizations l, Fact f) => switch (f.kind) {
    FactKind.shelterStatus => shelterStatusName(l, f),
    FactKind.roadBlocked => l.factsBoxRoadBlocked,
    FactKind.waterPoint => l.factsBoxWater(f.value),
    FactKind.warning => f.value,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
            l.factsBoxTitle,
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
                                ? _what(l, f)
                                : '${_what(l, f)}（${f.note}）',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: factColor(f, scheme),
                            ),
                          ),
                          Text(
                            '${factAge(l, f, now)} · ${factSourceLabel(l, f)}',
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
              label: Text(l.factsBoxAddWarning),
            ),
        ],
      ),
    );
  }
}

/// Small coloured label: 満員 · 20分前.
/// Text and background of a [StatusChip]: Material's matching container
/// pairs, readable on any card. (A 12% tint of the fact colour was not,
/// on Home's blue card.)
(Color, Color) statusChipColors(Fact f, ColorScheme c) {
  final color = factColor(f, c);
  if (color == c.error) return (c.onErrorContainer, c.errorContainer);
  if (color == c.tertiary) return (c.onTertiaryContainer, c.tertiaryContainer);
  return (c.onSurface, c.surfaceContainerHighest);
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.fact, required this.now});

  final Fact fact;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (color, background) = statusChipColors(fact, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${shelterStatusName(l, fact)} · ${factAge(l, fact, now)}'
        '${fact.unconfirmed ? ' · ${l.factUnconfirmed}' : ''}',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
