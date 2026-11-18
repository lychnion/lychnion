import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../map/evac_sites.dart';
import '../map/map_labels.dart';
import '../map/map_state.dart';

/// Home screen: active warnings and the nearest evacuation site that can
/// take people, before any question is asked.
class NearestSiteCard extends StatelessWidget {
  const NearestSiteCard({
    super.key,
    required this.map,
    this.onShowOnMap,
    this.onOpenDownloads,
  });

  final MapState map;
  final VoidCallback? onShowOnMap;

  /// "Choose a map", when the user is outside the downloaded area.
  final VoidCallback? onOpenDownloads;

  /// A nearest site farther than this is not "near": the map is of
  /// another area.
  static const farMeters = 30000.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: map,
    builder: (context, _) {
      if (!map.ready) return const SizedBox.shrink();
      final l = context.l10n;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      // During a warning, the nearest site for its hazard (a tsunami
      // warning: the nearest tsunami site, often a hill rather than the
      // nearest building). Without a warning, or without a site for that
      // hazard here, the nearest site for any hazard.
      var hazard = map.warningHazard;
      var near = hazard == null
          ? const <SiteDistance>[]
          : map.nearest(hazard, limit: 1, skipAvoided: true);
      if (near.isEmpty) {
        hazard = null;
        near = map.nearest(null, limit: 1, skipAvoided: true);
      }
      final facts = map.facts;
      final warnings = facts?.currentOf({FactKind.warning}) ?? const <Fact>[];
      // Outside the downloaded area: a site 100 km away is no help. Say so
      // and offer the right map instead.
      final here = map.here;
      final outside =
          (here != null && map.sites?.covers(here) == false) ||
          (near.isNotEmpty && near.first.meters > farMeters);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A live region: TalkBack reads a new warning when it arrives.
          for (final w in warnings)
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                            '${w.subject} · ${factAge(l, w, facts!.now)} · ${factSourceLabel(l, w)}',
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
            ),
          if (outside)
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.secondary,
                      child: Icon(
                        Icons.wrong_location_outlined,
                        color: scheme.onSecondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.nearestOutsideTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.nearestOutsideText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          if (onOpenDownloads != null) ...[
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: onOpenDownloads,
                              child: Text(l.firstStepMapAction),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (near.isNotEmpty)
            Card(
              color: scheme.secondaryContainer,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  map.showOnMap(hazard ?? map.hazard, near.first.site.point);
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
                              hazard == null
                                  ? l.nearestEmergencySite
                                  : l.nearestSiteFor(
                                      hazardInSentence(l, hazard),
                                    ),
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
                              siteLabel(l, near.first),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            if (map.statusOf(near.first.site) case final f?)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: StatusChip(fact: f, now: facts!.now),
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
