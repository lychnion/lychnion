import 'package:flutter/material.dart';

import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart' show Alert, foreignLabel;
import '../map/hazard_detect.dart';
import '../map/map_screen.dart' show formatDistance, noSiteWarning;
import '../map/map_state.dart';
import 'answer_text.dart';
import 'source_link.dart';
import '../app/brand.dart';
import 'breathing_light.dart';

/// One question with its safety lines, answer and the sources it cites.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    super.key,
    required this.answer,
    required this.grounded,
    required this.done,
    this.map,
    this.onShowOnMap,
    this.showStats = false,
  });

  final GroundedAnswer answer;
  final bool grounded;
  final bool done;

  /// Developer aid: speed and memory under the answer.
  final bool showStats;

  /// When set, answers about a hazard also show the nearest evacuation site.
  final MapState? map;
  final void Function()? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = answer.stats;
    final en = answer.lang == 'en';
    final thinking = !done && answer.text.isEmpty;
    final sources = done && grounded ? _sourceNumbers() : const <int>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The question, as a chat bubble on the right.
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                answer.question,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (answer.answeredBy != null)
                      Icon(
                        Icons.cell_tower_rounded,
                        size: 16,
                        color: scheme.primary,
                      )
                    else
                      const LychnionMark(size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        answer.answeredBy != null
                            ? (en
                                  ? 'Shelter computer · ${answer.answeredBy}'
                                  : '避難所のコンピューター · ${answer.answeredBy}')
                            : Brand.nameIn(en: en),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final a in answer.alerts) SafetyLine(alert: a, en: en),
                const SizedBox(height: 12),
                if (thinking)
                  Row(
                    children: [
                      const BreathingLight(size: 24),
                      const SizedBox(width: 10),
                      Text(
                        en ? 'Looking in the guides…' : '資料を確認しています…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else if (_shownText case final t when t.isNotEmpty)
                  SelectableText(t, style: theme.textTheme.bodyLarge),
                if (grounded && done) ..._notes(theme, en),
                const SizedBox(height: 14),
                ..._whereToGo(theme),
                if (done && (sources.isNotEmpty || answer.alerts.isNotEmpty))
                  _SourcesFooter(
                    answer: answer,
                    numbers: sources,
                    en: en,
                    onTap: () => _showSources(context, sources, en),
                  ),
                if (showStats && s != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'first token ${s.timeToFirstToken.inMilliseconds} ms · '
                      '${s.tokensPerSecond.toStringAsFixed(1)} tok/s · '
                      '${s.outputTokens} tokens · RAM ${s.rssBytes ~/ (1024 * 1024)} MB',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The answer without citation numbers and without sentences that only
  /// repeat a safety line shown above (the full text is kept for checks).
  String get _shownText => shownAnswer(answer.text, answer.alerts);

  /// Passages to list under "Sources": the cited ones, or all found ones
  /// when the answer only had related material.
  List<int> _sourceNumbers() {
    if (answer.relatedOnly) {
      return [for (var n = 1; n <= answer.hits.length; n++) n];
    }
    if (answer.saysNoSource) return const [];
    return [
      for (final n in answer.citedNumbers.toList()..sort())
        if (n >= 1 && n <= answer.hits.length) n,
    ];
  }

  /// Short notes when the answer is not fully backed by the sources.
  List<Widget> _notes(ThemeData theme, bool en) => [
    if (answer.relatedOnly)
      _note(
        theme,
        en
            ? 'The guides have related information, but no direct answer.'
            : '資料に関連する情報はありますが、直接の答えはありません。',
        Icons.info_outline,
      )
    else if (answer.saysNoSource || answer.hits.isEmpty)
      _note(
        theme,
        en
            ? 'The installed guides do not cover this question.'
            : 'この質問に答える資料は入っていません。',
        Icons.info_outline,
      )
    else ...[
      if (answer.admitsGap)
        _note(
          theme,
          en
              ? 'Only partly covered by the guides. Check official information.'
              : '資料で一部しか確認できません。公的な情報も確認してください。',
          Icons.warning_amber,
        ),
      if (!answer.isGrounded || answer.invalidCitations.isNotEmpty)
        _note(
          theme,
          en
              ? 'This answer could not be checked against the guides.'
              : 'この回答は資料で確認できませんでした。',
          Icons.warning_amber,
        ),
    ],
  ];

  void _showSources(
    BuildContext context,
    List<int> numbers,
    bool en,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (c, scroll) {
        final theme = Theme.of(c);
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(
              en ? 'Sources' : '出典',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final a in answer.alerts) ...[
              const SizedBox(height: 12),
              _SafetyLineSource(alert: a, en: en),
            ],
            if (numbers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                en
                    ? 'The answer is based only on these passages from official guides.'
                    : '回答は、公的な資料の次の部分だけにもとづいています。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final n in numbers) ...[
                const SizedBox(height: 16),
                _passage(theme, n, en),
              ],
            ],
          ],
        );
      },
    ),
  );

  Widget _passage(ThemeData theme, int n, bool en) {
    final p = answer.hits[n - 1].passage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    '$n',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${p.source.publisher}「${p.source.title}」',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (foreignLabel(p.source, 'JP', en: en) case final l?)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(l),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(p.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            SourceLink(
              source: p.source,
              suffix: '（${p.source.licence}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              en
                  ? 'Excerpt shown by ${Brand.name}.'
                  : '※ ${Brand.nameJa}が一部を抜き出して表示しています。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nearest emergency evacuation site for the hazard the question is about.
  List<Widget> _whereToGo(ThemeData theme) {
    final m = map;
    if (m == null || !m.ready) return const [];
    final hazard = hazardFor(answer.question, answer.alerts);
    if (hazard == null) return const [];
    // Suggest a site that can take people; mention a nearer one that cannot.
    final near = m.nearest(hazard, limit: 1, skipAvoided: true);
    if (near.isEmpty) return const [];
    final n = near.first;
    final closest = m.nearest(hazard, limit: 1).first;
    final skipped = closest.site == n.site ? null : closest;
    final skippedFact = skipped == null ? null : m.statusOf(skipped.site);
    final en = answer.lang == 'en';
    final noSiteCity = m.cityWithoutSiteFor(hazard);
    final facts = m.facts;
    final current =
        facts?.currentOf({FactKind.warning, FactKind.roadBlocked}) ??
        const <Fact>[];
    final on = theme.colorScheme.onSecondaryContainer;
    void open() {
      m.showOnMap(hazard, n.site.point);
      onShowOnMap?.call();
    }

    return [
      Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.secondary,
                      child: Icon(
                        Icons.directions_walk_rounded,
                        color: theme.colorScheme.onSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            en
                                ? 'Go to: ${hazard.en.toLowerCase()} evacuation site'
                                : '${hazard.ja}の避難場所',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: on,
                            ),
                          ),
                          Text(
                            n.site.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: on,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              n.label(en),
                              if (m.prefersHigh(hazard) &&
                                  n.heightLabel(en).isNotEmpty)
                                n.heightLabel(en),
                              if (m.prefersHigh(hazard))
                                en ? 'keeps to higher ground' : '高い道を優先',
                              if (m.wayOut(hazard) case final out?)
                                en
                                    ? 'out of the inundation area: ${formatDistance(out.meters)} walk'
                                    : '浸水想定区域の外まで 徒歩${formatDistance(out.meters)}',
                              if (m.avoidsBlocked && n.walk != null)
                                en ? 'blocked roads considered' : '通行止めを考慮',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: on,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.map_rounded, color: on),
                    Icon(Icons.chevron_right_rounded, color: on),
                  ],
                ),
                if (skipped != null && skippedFact != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, size: 16, color: on),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            en
                                ? 'Not ${skipped.site.name} (${formatDistance(skipped.walk ?? skipped.meters)}): '
                                      '${skippedFact.shelterStatus?.en ?? skippedFact.value}, '
                                      '${skippedFact.age(facts!.now, en: true)}'
                                : '${skipped.site.name}（${formatDistance(skipped.walk ?? skipped.meters)}）は'
                                      '${skippedFact.shelterStatus?.ja ?? skippedFact.value}'
                                      '（${skippedFact.age(facts!.now, en: false)}）',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: on,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (noSiteCity != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      noSiteWarning(noSiteCity, hazard, en),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: on,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      if (current.isNotEmpty)
        CurrentFactsBox(facts: current, now: facts!.now, en: en),
    ];
  }

  Widget _note(ThemeData theme, String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    ),
  );
}

/// A fixed safety line, quoted word for word from its official source: the
/// key message of the answer. In English our translation is shown; the
/// official text and the source are one tap away (sources footer).
class SafetyLine extends StatelessWidget {
  const SafetyLine({super.key, required this.alert, required this.en});

  final Alert alert;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onErrorContainer;
    final a = alert;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_rounded, color: on, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              en && a.textEn != null ? a.textEn! : a.text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: on,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One quiet line under the answer: "ⓘ 出典：首相官邸 ほか1件". The
/// attribution the licences ask for stays visible; details on tap.
class _SourcesFooter extends StatelessWidget {
  const _SourcesFooter({
    required this.answer,
    required this.numbers,
    required this.en,
    required this.onTap,
  });

  final GroundedAnswer answer;
  final List<int> numbers;
  final bool en;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final publishers = <String>{
      for (final a in answer.alerts) a.source.publisher,
      for (final n in numbers) answer.hits[n - 1].passage.source.publisher,
    }.toList();
    final more = publishers.length - 1;
    final label = en
        ? 'Source: ${publishers.first}${more > 0 ? ' and $more more' : ''}'
        : '出典：${publishers.first}${more > 0 ? ' ほか$more件' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// In the sources sheet: where a safety line comes from, and for English
/// the official Japanese text next to our translation.
class _SafetyLineSource extends StatelessWidget {
  const _SafetyLineSource({required this.alert, required this.en});

  final Alert alert;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = alert;
    final translated = en && a.textEn != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    en
                        ? 'Safety line, quoted word for word'
                        : '安全のための一文（原文のまま）',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (translated)
              Text(
                'Official text (the translation in the answer is by ${Brand.name}, not official):',
                style: theme.textTheme.bodySmall,
              ),
            SelectableText(a.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            SourceLink(
              source: a.source,
              suffix: '（${a.source.licence}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
