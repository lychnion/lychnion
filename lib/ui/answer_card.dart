import 'package:flutter/material.dart';

import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart' show Alert;
import '../map/hazard_detect.dart';
import '../map/map_screen.dart' show formatDistance, noSiteWarning;
import '../map/map_state.dart';
import 'source_link.dart';

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
                    Icon(
                      answer.answeredBy != null
                          ? Icons.cell_tower_rounded
                          : Icons.health_and_safety_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        answer.answeredBy != null
                            ? (en
                                  ? 'Shelter computer · ${answer.answeredBy}'
                                  : '避難所のコンピューター · ${answer.answeredBy}')
                            : 'fieldkit',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (sources.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _showSources(context, sources, en),
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: Text(
                          en
                              ? 'Sources (${sources.length})'
                              : '出典 ${sources.length}件',
                        ),
                      ),
                  ],
                ),
                for (final a in answer.alerts) SafetyLine(alert: a, en: en),
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
                    superscriptCitations(answer.text),
                    style: theme.textTheme.bodyLarge,
                  ),
                if (grounded && done) ..._notes(theme, en),
                const SizedBox(height: 14),
                ..._whereToGo(theme),
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
            const SizedBox(height: 4),
            Text(
              en
                  ? 'The answer is based only on these passages from official guides (in Japanese).'
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
                  ? 'Excerpt shown by fieldkit.'
                  : '※ fieldkit が一部を抜き出して表示しています。',
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
                            en
                                ? '${formatDistance(n.meters)} ${n.direction(true)} · straight line'
                                : '${n.direction(false)}へ${formatDistance(n.meters)} · 直線距離',
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
                                ? 'Not ${skipped.site.name} (${formatDistance(skipped.meters)}): '
                                      '${skippedFact.shelterStatus?.en ?? skippedFact.value}, '
                                      '${skippedFact.age(facts!.now, en: true)}'
                                : '${skipped.site.name}（${formatDistance(skipped.meters)}）は'
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

const _sup = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// "…高い場所 [1]。" → "…高い場所¹。": citations stay visible but quiet.
String superscriptCitations(String text) => text.replaceAllMapped(
  RegExp(r'\s?\[(\d{1,2})\]'),
  (m) => m[1]!.split('').map((d) => _sup[int.parse(d)]).join(),
);

/// A fixed safety line, quoted word for word from its official source.
/// In English the translation leads; the official Japanese folds away.
class SafetyLine extends StatefulWidget {
  const SafetyLine({super.key, required this.alert, required this.en});

  final Alert alert;
  final bool en;

  @override
  State<SafetyLine> createState() => _SafetyLineState();
}

class _SafetyLineState extends State<SafetyLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onErrorContainer;
    final a = widget.alert;
    final translated = widget.en && a.textEn != null;
    final small = theme.textTheme.bodySmall?.copyWith(color: on);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_rounded, color: on, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  translated ? a.textEn! : a.text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: on,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (_open && translated) ...[
            const SizedBox(height: 8),
            Text('Official text (translated above by fieldkit):', style: small),
            const SizedBox(height: 2),
            Text(
              a.text,
              style: theme.textTheme.bodyMedium?.copyWith(color: on),
            ),
          ],
          // The source stays visible: the licence (PDL1.0) asks for it.
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 6, bottom: 6),
            child: SourceLink(source: a.source, style: small),
          ),
          if (translated)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: on,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open ? 'Hide official text' : 'Show official text',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
