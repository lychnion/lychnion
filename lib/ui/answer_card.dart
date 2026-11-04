import 'package:flutter/material.dart';

import '../knowledge/grounded_answer.dart';
import '../map/hazard_detect.dart';
import '../map/map_screen.dart' show formatDistance;
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
  });

  final GroundedAnswer answer;
  final bool grounded;
  final bool done;

  /// When set, answers about a hazard also show the nearest evacuation site.
  final MapState? map;
  final void Function()? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = answer.stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              answer.question,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final a in answer.alerts)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (answer.lang == 'en' && a.textEn != null) ...[
                      Text(
                        a.textEn!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Translation by fieldkit. Official text:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                    Text(
                      a.text,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: answer.lang == 'en'
                            ? null
                            : FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.source.attribution,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ..._whereToGo(theme),
            const SizedBox(height: 8),
            SelectableText(answer.text),
            if (grounded && done) ..._grounding(theme),
            if (s != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
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
    final near = m.nearest(hazard, limit: 1);
    if (near.isEmpty) return const [];
    final n = near.first;
    final en = answer.lang == 'en';
    return [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.directions_walk,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                en
                    ? 'Nearest ${hazard.en.toLowerCase()} evacuation site: ${n.site.name}, '
                          '${formatDistance(n.meters)} ${n.direction(true)} (straight line)'
                    : '最寄りの${hazard.ja}の指定緊急避難場所：${n.site.name}（${n.direction(false)}へ直線${formatDistance(n.meters)}）',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () {
                m.showOnMap(hazard, n.site.point);
                onShowOnMap?.call();
              },
              child: Text(en ? 'Map' : '地図'),
            ),
          ],
        ),
      ),
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
