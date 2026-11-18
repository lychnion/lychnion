import 'package:flutter/material.dart';

import '../app/lang.dart';
import 'threads.dart';

/// Conversations on the home screen (or the archive): tap to open, swipe
/// left to delete, swipe right to archive (or restore). Both can be undone.
class ThreadList extends StatelessWidget {
  const ThreadList({
    super.key,
    required this.store,
    required this.onOpen,
    this.archive = false,
    this.max = 6,
    this.heading = true,
    this.onSeeAll,
  });

  /// "Recent questions" above the list (home screen).
  final bool heading;

  /// Shown as "See all" when there are more threads than [max].
  final VoidCallback? onSeeAll;

  final ThreadStore store;
  final void Function(Thread) onOpen;

  /// Lists archived threads instead of recent ones.
  final bool archive;
  final int max;

  String _when(BuildContext context, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return context.l10n.minutesAgo('${d.inMinutes}');
    if (d.inHours < 24) return context.l10n.hoursAgo('${d.inHours}');
    return '${t.month}/${t.day}';
  }

  void _undoable(BuildContext context, String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: context.l10n.threadsUndo,
            onPressed: undo,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final l = context.l10n;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final all = archive ? store.archived : store.recent;
      final shown = archive ? all : all.take(max).toList();
      final archivedCount = store.archived.length;
      if (shown.isEmpty && (archive || archivedCount == 0)) {
        return archive
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.threadsNoArchived,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            : const SizedBox.shrink();
      }
      Widget swipeBg(IconData icon, Color bg, Color fg, Alignment a) =>
          Container(
            color: bg,
            alignment: a,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Icon(icon, color: fg),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!archive && heading && shown.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l.threadsRecent,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (shown.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final t in shown)
                    Dismissible(
                      key: ValueKey(t.id),
                      // Right: archive / restore. Left: delete.
                      background: swipeBg(
                        archive
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        scheme.secondaryContainer,
                        scheme.onSecondaryContainer,
                        Alignment.centerLeft,
                      ),
                      secondaryBackground: swipeBg(
                        Icons.delete_outline_rounded,
                        scheme.errorContainer,
                        scheme.onErrorContainer,
                        Alignment.centerRight,
                      ),
                      onDismissed: (dir) {
                        if (dir == DismissDirection.startToEnd) {
                          store.setArchived(t, !archive);
                          _undoable(
                            context,
                            archive ? l.threadsMovedBack : l.threadsArchived,
                            () => store.setArchived(t, archive),
                          );
                        } else {
                          store.delete(t);
                          _undoable(
                            context,
                            l.threadsDeleted,
                            () => store.restore(t),
                          );
                        }
                      },
                      child: ListTile(
                        leading: Icon(
                          archive
                              ? Icons.archive_outlined
                              : Icons.chat_bubble_outline_rounded,
                          color: scheme.onSurfaceVariant,
                          size: 20,
                        ),
                        title: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        trailing: Text(
                          _when(context, t.created),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () => onOpen(t),
                      ),
                    ),
                ],
              ),
            ),
          if (!archive && onSeeAll != null && all.length > shown.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSeeAll,
                child: Text(l.threadsSeeAll('${all.length}')),
              ),
            ),
          if (!archive && onSeeAll == null && archivedCount > 0) ...[
            if (shown.isEmpty) const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(l.threadsArchive)),
                      body: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          ThreadList(
                            store: store,
                            archive: true,
                            onOpen: onOpen,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.threadsArchiveHint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(l.threadsArchiveCount('$archivedCount')),
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// Ask tab: all conversations, the archive, and a new question.
class ConversationsView extends StatelessWidget {
  const ConversationsView({
    super.key,
    required this.store,
    required this.onOpen,
    required this.bar,
    this.onOpenSettings,
    this.suggestions,
  });

  final ThreadStore store;
  final void Function(Thread) onOpen;
  final Widget bar;
  final VoidCallback? onOpenSettings;

  /// Suggested questions by package, above the conversations.
  final Widget? suggestions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text(l.threadsAsk),
        actions: [
          if (onOpenSettings != null)
            IconButton(
              tooltip: l.settings,
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (suggestions case final s?) ...[
                    s,
                    const SizedBox(height: 16),
                  ],
                  if (store.recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.threadsNone,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ThreadList(
                    store: store,
                    onOpen: onOpen,
                    max: 1000,
                    heading: false,
                  ),
                  if (store.recent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.threadsSwipeHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          bar,
        ],
      ),
    );
  }
}
