import 'package:flutter/material.dart';

import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../map/map_state.dart';

/// Home screen: active warnings and the nearest evacuation site that can
/// take people, before any question is asked.
class NearestSiteCard extends StatelessWidget {
  const NearestSiteCard({
    super.key,
    required this.map,
    required this.en,
    this.onShowOnMap,
  });

  final MapState map;
  final bool en;
  final VoidCallback? onShowOnMap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: map,
    builder: (context, _) {
      if (!map.ready) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final near = map.nearest(null, limit: 1, skipAvoided: true);
      final facts = map.facts;
      final warnings = facts?.currentOf({FactKind.warning}) ?? const <Fact>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in warnings)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.campaign_rounded, color: scheme.onError),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onError,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${w.subject} · ${w.age(facts!.now, en: en)} · ${w.sourceLabel(en: en)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onError,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (near.isNotEmpty)
            Card(
              color: scheme.secondaryContainer,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  map.showOnMap(map.hazard, near.first.site.point);
                  onShowOnMap?.call();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.secondary,
                        child: Icon(
                          Icons.directions_walk_rounded,
                          color: scheme.onSecondary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              en
                                  ? 'Nearest emergency evacuation site'
                                  : '近くの指定緊急避難場所',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            Text(
                              near.first.site.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              near.first.label(en),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            if (map.statusOf(near.first.site) case final f?)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: StatusChip(
                                  fact: f,
                                  now: facts!.now,
                                  en: en,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSecondaryContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
