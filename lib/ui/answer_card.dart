import 'package:flutter/material.dart';

import '../knowledge/grounded_answer.dart';

/// One question with its safety lines, answer and the sources it cites.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    super.key,
    required this.answer,
    required this.grounded,
    required this.done,
  });

  final GroundedAnswer answer;
  final bool grounded;
  final bool done;

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
        if (n >= 1 && n <= answer.hits.length)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '[$n] ${answer.hits[n - 1].passage.source.publisher}「${answer.hits[n - 1].passage.source.title}」',
              style: theme.textTheme.bodySmall,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  '${answer.hits[n - 1].passage.text}\n\n'
                  '${answer.hits[n - 1].passage.source.attribution}（${answer.hits[n - 1].passage.source.licence}）\n'
                  '${en ? 'Excerpt shown by fieldkit (source in Japanese).' : '※ fieldkit が一部を抜き出して表示しています。'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
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
