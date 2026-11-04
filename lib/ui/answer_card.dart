import 'package:flutter/material.dart';

import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart' show Alert;
import '../map/hazard_detect.dart';
import '../map/map_screen.dart' show formatDistance, noSiteWarning;
import '../map/map_state.dart';

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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        answer.answeredBy != null
                            ? Icons.cell_tower_rounded
                            : Icons.health_and_safety_rounded,
                        size: 14,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        answer.answeredBy != null
                            ? (en
                                  ? 'Answered by the shelter computer · ${answer.answeredBy}'
                                  : '避難所のコンピューターが回答 · ${answer.answeredBy}')
                            : (en
                                  ? 'fieldkit · from official guides'
                                  : 'fieldkit · 公的な資料から'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final a in answer.alerts) _alert(theme, a, en),
                ..._whereToGo(theme),
                const SizedBox(height: 12),
                if (thinking)
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        en ? 'Looking in the guides…' : '資料を確認しています…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else
                  SelectableText(
                    answer.text,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                  ),
                if (grounded && done) ..._grounding(theme),
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

  /// A fixed safety line, quoted word for word from its official source.
  Widget _alert(ThemeData theme, Alert a, bool en) {
    final on = theme.colorScheme.onErrorContainer;
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
          Icon(Icons.warning_rounded, color: on),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (en && a.textEn != null) ...[
                  Text(
                    a.textEn!,
                    style: TextStyle(color: on, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Translation by fieldkit. Official text:',
                    style: theme.textTheme.bodySmall?.copyWith(color: on),
                  ),
                ],
                Text(
                  a.text,
                  style: TextStyle(
                    color: on,
                    fontWeight: en ? null : FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  a.source.attribution,
                  style: theme.textTheme.bodySmall?.copyWith(color: on),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _grounding(ThemeData theme) {
    final en = answer.lang == 'en';
    if (answer.relatedOnly) {
      return [
        _note(
          theme,
          en
              ? 'The sources have related information, but no direct answer to this question.'
              : '資料には関連する情報がありますが、この質問への直接の答えはありません。',
          Icons.info_outline,
        ),
        for (var n = 1; n <= answer.hits.length; n++)
          _passageTile(theme, n, en),
      ];
    }
    if (answer.saysNoSource || answer.hits.isEmpty) {
      return [
        _note(
          theme,
          en
              ? 'The installed packages have no source that answers this question.'
              : 'この質問に答える資料は、入っているパッケージにありません。',
          Icons.info_outline,
        ),
      ];
    }
    return [
      if (answer.admitsGap)
        _note(
          theme,
          en
              ? 'Only partly covered by the sources. Check the passages below and official information.'
              : '資料で一部しか確認できない回答です。下の資料と公的な情報を確認してください。',
          Icons.warning_amber,
        ),
      if (!answer.isGrounded)
        _note(
          theme,
          en
              ? 'This answer cites no source and cannot be checked.'
              : '出典の付いていない回答です。内容を確認できません。',
          Icons.warning_amber,
        ),
      if (answer.invalidCitations.isNotEmpty)
        _note(
          theme,
          en
              ? 'Cites source numbers that do not exist: ${answer.invalidCitations.join(', ')}.'
              : '存在しない資料番号 ${answer.invalidCitations.join(', ')} を引用しています。',
          Icons.warning_amber,
        ),
      for (final n in answer.citedNumbers.toList()..sort())
        if (n >= 1 && n <= answer.hits.length) _passageTile(theme, n, en),
    ];
  }

  /// Passage [n] (1-based) with its source and licence, collapsed.
  Widget _passageTile(ThemeData theme, int n, bool en) {
    final p = answer.hits[n - 1].passage;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        '[$n] ${p.source.publisher}「${p.source.title}」',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            '${p.text}\n\n'
            '${p.source.attribution}（${p.source.licence}）\n'
            '${en ? 'Excerpt shown by fieldkit (source in Japanese).' : '※ fieldkit が一部を抜き出して表示しています。'}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
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
    return [
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
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
                            ? 'Nearest ${hazard.en.toLowerCase()} evacuation site'
                            : '最寄りの${hazard.ja}の指定緊急避難場所',
                        style: theme.textTheme.labelMedium?.copyWith(color: on),
                      ),
                      Text(
                        n.site.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: on,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        en
                            ? '${formatDistance(n.meters)} ${n.direction(true)} · straight line'
                            : '${n.direction(false)}へ${formatDistance(n.meters)} · 直線距離',
                        style: theme.textTheme.bodySmall?.copyWith(color: on),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    m.showOnMap(hazard, n.site.point);
                    onShowOnMap?.call();
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(en ? 'Map' : '地図'),
                ),
              ],
            ),
            if (skipped != null && skippedFact != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  en
                      ? 'Skipped ${skipped.site.name} (${formatDistance(skipped.meters)}): ${factLine(skippedFact, facts!.now, en: true)}'
                      : '${skipped.site.name}（${formatDistance(skipped.meters)}）は除外：${factLine(skippedFact, facts!.now, en: false)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: on),
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
