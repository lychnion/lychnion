import 'package:flutter/material.dart';

import '../app/lang.dart';

/// Where a new user stands on the way to a working app (lychnion#7):
/// the answer AI, a map of their area, a look at the nearest site, and a
/// first question.
class FirstSteps {
  const FirstSteps({
    required this.aiReady,
    required this.mapReady,
    required this.siteSeen,
    required this.asked,
  });

  final bool aiReady, mapReady, siteSeen, asked;

  List<bool> get _all => [aiReady, mapReady, siteSeen, asked];
  int get done => _all.where((d) => d).length;
  int get total => _all.length;
  bool get allDone => done == total;

  /// Works without a network: it can answer and show the map.
  bool get readyOffline => aiReady && mapReady;

  /// The first step not done yet (0–3), or null.
  int? get current {
    final i = _all.indexOf(false);
    return i < 0 ? null : i;
  }
}

/// The first-steps checklist on Home, until every step is done or the
/// user hides it. Each step says why it matters; the current one has a
/// button.
class FirstStepsCard extends StatelessWidget {
  const FirstStepsCard({
    super.key,
    required this.steps,
    required this.onDownloads,
    required this.onMap,
    required this.onAsk,
    required this.onHide,
  });

  final FirstSteps steps;
  final VoidCallback? onDownloads, onMap, onAsk, onHide;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = [
      (
        steps.aiReady,
        l.firstStepAi,
        l.firstStepAiText,
        l.firstStepAiAction,
        onDownloads,
      ),
      (
        steps.mapReady,
        l.firstStepMap,
        l.firstStepMapText,
        l.firstStepMapAction,
        onDownloads,
      ),
      (
        steps.siteSeen,
        l.firstStepSite,
        l.firstStepSiteText,
        l.firstStepSiteAction,
        onMap,
      ),
      (
        steps.asked,
        l.firstStepAsk,
        l.firstStepAskText,
        l.firstStepAskAction,
        onAsk,
      ),
    ];
    // The map step needs the map: before that, the next open step leads.
    final current = steps.current;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.firstStepsTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  l.firstStepsCount(steps.done, steps.total),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                TextButton(onPressed: onHide, child: Text(l.firstStepsLater)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: steps.done / steps.total,
                  minHeight: 8,
                  semanticsLabel: l.firstStepsTitle,
                  // Screen readers need a number (percent) here.
                  semanticsValue: '${(100 * steps.done / steps.total).round()}',
                ),
              ),
            ),
            for (var i = 0; i < rows.length; i++)
              _StepRow(
                number: i + 1,
                done: rows[i].$1,
                isCurrent: i == current,
                title: rows[i].$2,
                text: rows[i].$3,
                action: rows[i].$4,
                onAction: rows[i].$5,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.done,
    required this.isCurrent,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final int number;
  final bool done, isCurrent;
  final String title, text, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget mark = done
        ? CircleAvatar(
            radius: 14,
            backgroundColor: scheme.tertiaryContainer,
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
          )
        : CircleAvatar(
            radius: 14,
            backgroundColor: isCurrent ? scheme.primary : scheme.surface,
            foregroundColor: isCurrent
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          );
    return Semantics(
      container: true,
      label: done ? l.firstStepDone : null,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mark,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w700 : null,
                      color: done ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (!done) ...[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (isCurrent && onAction != null) ...[
                    const SizedBox(height: 8),
                    FilledButton(onPressed: onAction, child: Text(action)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet line at the top of Home: the app works offline. Tap for the
/// status details.
class ReadyOfflineChip extends StatelessWidget {
  const ReadyOfflineChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: CircleAvatar(
          backgroundColor: scheme.tertiaryContainer,
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
        ),
        label: Text(context.l10n.readyOffline),
        onPressed: onTap,
      ),
    );
  }
}

/// After "Later": a small way back to the first steps.
class ResumeStepsChip extends StatelessWidget {
  const ResumeStepsChip({super.key, required this.steps, this.onTap});

  final FirstSteps steps;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ActionChip(
      avatar: const Icon(Icons.checklist_rounded, size: 18),
      label: Text(context.l10n.firstStepsResume(steps.done, steps.total)),
      onPressed: onTap,
    ),
  );
}
