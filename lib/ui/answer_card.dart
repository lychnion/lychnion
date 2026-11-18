import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../facts/fact.dart';
import '../facts/fact_view.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart' show Alert, Source, foreignLabel;
import '../l10n/app_localizations.dart';
import '../map/hazard_detect.dart';
import '../map/map_labels.dart';
import '../map/map_screen.dart' show noSiteWarning;
import '../map/map_state.dart';
import 'announce.dart';
import 'answer_text.dart';
import 'source_link.dart';
import '../app/brand.dart';
import 'breathing_light.dart';
import 'help_screen.dart';

/// One question with its safety lines, answer and the sources it cites.
/// Its texts follow the question's language, not the app's.
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
  Widget build(BuildContext context) => InLanguage(
    lang: answer.lang,
    // Screen readers: say that the answer is there, with its first
    // safety line (the key message), when it finishes.
    child: AnnounceWhen(
      when: done,
      message: (context) => [
        context.l10n.answerReadyAnnounce,
        if (answer.alerts.isNotEmpty) answer.alerts.first.textIn(answer.lang),
      ].join(' '),
      child: Builder(builder: _build),
    ),
  );

  Widget _build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = answer.stats;
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
                      // The name follows as text: read it once.
                      const ExcludeSemantics(child: LychnionMark(size: 18)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        answer.answeredBy != null
                            ? l.answerShelterComputer(answer.answeredBy!)
                            : l.appName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final a in answer.alerts)
                  SafetyLine(alert: a, lang: answer.lang),
                const SizedBox(height: 12),
                if (thinking)
                  AnswerWaiting(answer: answer)
                else if (_shownText case final t when t.isNotEmpty)
                  // SelectionArea, not SelectableText: screen readers read
                  // plain text, not a read-only text field. Its own node,
                  // so it is not merged with the sources button below.
                  Semantics(
                    container: true,
                    child: SelectionArea(
                      child: Text(t, style: theme.textTheme.bodyLarge),
                    ),
                  ),
                if (grounded && done) ..._notes(theme, l),
                const SizedBox(height: 14),
                ..._whereToGo(theme, l),
                if (done && (sources.isNotEmpty || answer.alerts.isNotEmpty))
                  _SourcesFooter(
                    answer: answer,
                    numbers: sources,
                    onTap: () => _showSources(context, sources),
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
  List<Widget> _notes(ThemeData theme, AppLocalizations l) => [
    if (answer.relatedOnly)
      _note(theme, l.answerRelatedOnly, Icons.info_outline)
    else if (answer.saysNoSource || answer.hits.isEmpty)
      _note(theme, l.answerNotCovered, Icons.info_outline)
    else ...[
      if (answer.admitsGap)
        _note(theme, l.answerPartlyCovered, Icons.warning_amber),
      if (!answer.isGrounded || answer.invalidCitations.isNotEmpty)
        _note(theme, l.answerUnchecked, Icons.warning_amber),
    ],
  ];

  void _showSources(BuildContext context, List<int> numbers) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => InLanguage(
          lang: answer.lang,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            builder: (c, scroll) {
              final theme = Theme.of(c);
              final l = c.l10n;
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Text(
                    l.answerSources,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final a in answer.alerts) ...[
                    const SizedBox(height: 12),
                    _SafetyLineSource(alert: a, lang: answer.lang),
                  ],
                  if (numbers.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l.answerBasedOn,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (final n in numbers) ...[
                      const SizedBox(height: 16),
                      _passage(theme, n, l),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      );

  Widget _passage(ThemeData theme, int n, AppLocalizations l) {
    final p = answer.hits[n - 1].passage;
    final lang = answer.lang;
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
                if (foreignLabel(p.source, 'JP', lang: lang) case final f?)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(f),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // English readers see a translated passage in its original;
            // Japanese readers see our translation, the original one tap away.
            Semantics(
              container: true,
              child: SelectionArea(
                child: Text(p.textIn(lang), style: theme.textTheme.bodyMedium),
              ),
            ),
            if (p.translated && p.textIn(lang) == p.text)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    l.answerOurTranslation(l.appName),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    SelectableText(
                      p.original!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SourceLink(
              source: p.source,
              suffix: '（${p.source.licence}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              l.answerExcerpt(l.appName),
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
  List<Widget> _whereToGo(ThemeData theme, AppLocalizations l) {
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
                            l.answerGoTo(hazardInSentence(l, hazard)),
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
                              siteLabel(l, n),
                              if (m.prefersHigh(hazard) &&
                                  siteHeightLabel(l, n).isNotEmpty)
                                siteHeightLabel(l, n),
                              if (m.prefersHigh(hazard)) l.mapKeepsHigh,
                              if (m.wayOut(hazard) case final out?)
                                l.answerWayOut(formatDistance(out.meters)),
                              if (m.avoidsBlocked && n.walk != null)
                                l.mapBlockedConsidered,
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
                            l.answerSkipped(
                              skipped.site.name,
                              formatDistance(skipped.walk ?? skipped.meters),
                              shelterStatusName(l, skippedFact),
                              factAge(l, skippedFact, facts!.now),
                            ),
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
                      noSiteWarning(l, noSiteCity, hazard),
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
      if (current.isNotEmpty) CurrentFactsBox(facts: current, now: facts!.now),
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
  const SafetyLine({super.key, required this.alert, required this.lang});

  final Alert alert;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onErrorContainer;
    final a = alert;
    // Spoken as "Safety warning: …": the colour and icon say it visually.
    return MergeSemantics(
      child: Semantics(
        label: context.l10n.answerSafetyLineSpoken,
        child: _box(theme, on, a),
      ),
    );
  }

  Widget _box(ThemeData theme, Color on, Alert a) {
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
          ExcludeSemantics(
            child: Icon(Icons.warning_rounded, color: on, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              a.textIn(lang),
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
    required this.onTap,
  });

  final GroundedAnswer answer;
  final List<int> numbers;
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
    final l = context.l10n;
    final label = more > 0
        ? l.answerSourceAndMore(publishers.first, '$more')
        : l.answerSource(publishers.first);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        container: true,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            // A full-size tap target, though the line is small.
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In the sources sheet: where a safety line comes from, and for English
/// the official Japanese text next to our translation.
class _SafetyLineSource extends StatelessWidget {
  const _SafetyLineSource({required this.alert, required this.lang});

  final Alert alert;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = alert;
    final l = context.l10n;
    final translated = a.translatedFor(lang);
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
                    l.answerSafetyLine,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (translated)
              Text(
                l.answerOfficialText(l.appName),
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

/// Before the first word: what is being read, and roughly how long it
/// takes on this device. On slow phones the model reads the sources for
/// half a minute or more (Pixel 5a, docs/device-results.md).
class AnswerWaiting extends StatefulWidget {
  const AnswerWaiting({super.key, required this.answer, this.expected});

  final GroundedAnswer answer;

  /// Expected reading time; [lastReadingTime] otherwise.
  final Duration? expected;

  /// From this long on, a base is worth mentioning.
  static const slow = Duration(seconds: 20);

  @override
  State<AnswerWaiting> createState() => _AnswerWaitingState();
}

class _AnswerWaitingState extends State<AnswerWaiting> {
  final _started = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final hits = widget.answer.hits;
    final fromBase = widget.answer.answeredBy != null;
    // Each source once, in the order found (several passages may come
    // from one page).
    final sources = <String, Source>{};
    for (final h in hits) {
      sources.putIfAbsent(h.passage.source.id, () => h.passage.source);
    }
    final line = Row(
      children: [
        const BreathingLight(size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            hits.isEmpty ? l.answerLooking : l.answerReading(sources.length),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    if (hits.isEmpty || fromBase) return line;

    final elapsed = _started.elapsed;
    final expected = widget.expected ?? lastReadingTime.value;
    final phone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final slow =
        phone &&
        ((expected ?? Duration.zero) > AnswerWaiting.slow ||
            elapsed > AnswerWaiting.slow);
    final double? progress = expected == null || expected.inMilliseconds == 0
        ? null
        : math.min(0.95, elapsed.inMilliseconds / expected.inMilliseconds);
    final left = expected == null
        ? null
        : math.max(1, (expected - elapsed).inSeconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        const SizedBox(height: 8),
        for (final s in sources.values)
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.menu_book_outlined, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${s.publisher}「${s.title}」', style: muted),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            semanticsLabel: l.answerReading(sources.length),
          ),
        ),
        const SizedBox(height: 6),
        if (left != null)
          Text(l.answerTimeLeft(left), style: muted)
        else if (elapsed.inSeconds >= 10)
          Text(l.answerSlowPhone, style: muted),
        if (slow)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.cell_tower_rounded, size: 18),
              label: Text(l.answerBaseHint),
              onPressed: () => HelpScreen.open(context, topic: 'help-05-base'),
            ),
          ),
      ],
    );
  }
}
