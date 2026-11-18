import 'dart:async';

import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../knowledge/app_help.dart';

/// The app's help to read and search, without the AI (lychnion#9): works
/// before any model is downloaded. With [topic], opens that topic (from a
/// "?" button on a screen).
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.topic, this.book});

  /// A topic id such as 'help-05-base'.
  final String? topic;

  /// For tests; the bundled help otherwise.
  final HelpBook? book;

  /// Opens the help, at [topic] when given.
  static Future<void> open(BuildContext context, {String? topic}) =>
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => HelpScreen(topic: topic)));

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  HelpBook? _book;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    final given = widget.book;
    if (given != null) {
      _book = given;
    } else {
      unawaited(
        HelpBook.load().then((b) {
          if (mounted) setState(() => _book = b);
        }),
      );
    }
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final book = _book;
    final topic = widget.topic == null ? null : book?.topic(widget.topic!);
    if (topic != null) return _TopicPage(topic: topic, showAll: true);
    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: book == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: l.helpSearch,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ..._body(context, book),
              ],
            ),
    );
  }

  List<Widget> _body(BuildContext context, HelpBook book) {
    final lang = context.lang;
    final q = _query.text.trim();
    if (q.isEmpty) {
      return [
        for (final t in book.topics)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(t.title(lang)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _TopicPage(topic: t)),
              ),
            ),
          ),
      ];
    }
    final hits = book.search(q, lang);
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.l10n.helpNoResults),
        ),
      ];
    }
    final theme = Theme.of(context);
    return [
      for (final (t, s) in hits.take(8))
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _TopicPage(topic: t)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title(lang),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(s.inLang(lang).$1, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(s.inLang(lang).$2, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}

/// One topic, all its sections.
class _TopicPage extends StatelessWidget {
  const _TopicPage({required this.topic, this.showAll = false});

  final HelpTopic topic;

  /// Opened from a "?" button: offer the whole help too.
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(topic.title(lang)),
        actions: [
          if (showAll)
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
              ),
              child: Text(l.helpAllTopics),
            ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final s in topic.sections) ...[
              Text(s.inLang(lang).$1, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(s.inLang(lang).$2, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}
