import 'package:flutter/material.dart';

import 'threads.dart';

/// Conversations on the home screen (or the archive): tap to open, swipe
/// left to delete, swipe right to archive (or restore). Both can be undone.
class ThreadList extends StatelessWidget {
  const ThreadList({
    super.key,
    required this.store,
    required this.en,
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
  final bool en;
  final void Function(Thread) onOpen;

  /// Lists archived threads instead of recent ones.
  final bool archive;
  final int max;

  String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) {
      return en ? '${d.inMinutes} min ago' : '${d.inMinutes}分前';
    }
    if (d.inHours < 24) {
      return en ? '${d.inHours} h ago' : '${d.inHours}時間前';
    }
    return '${t.month}/${t.day}';
  }

  void _undoable(BuildContext context, String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: en ? 'Undo' : '元に戻す', onPressed: undo),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
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
                  en ? 'No archived conversations.' : 'アーカイブした会話はありません。',
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
              en ? 'Recent questions' : '最近の質問',
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
                            archive
                                ? (en ? 'Moved back' : '元に戻しました')
                                : (en ? 'Archived' : 'アーカイブしました'),
                            () => store.setArchived(t, archive),
                          );
                        } else {
                          store.delete(t);
                          _undoable(
                            context,
                            en ? 'Deleted' : '削除しました',
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
                          _when(t.created),
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
                child: Text(
                  en ? 'See all (${all.length})' : 'すべて表示（${all.length}）',
                ),
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
                      appBar: AppBar(title: Text(en ? 'Archive' : 'アーカイブ')),
                      body: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          ThreadList(
                            store: store,
                            en: en,
                            archive: true,
                            onOpen: onOpen,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            en
                                ? 'Swipe right to move back, left to delete.'
                                : '右にスワイプで戻す、左にスワイプで削除。',
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
                label: Text(
                  en ? 'Archive ($archivedCount)' : 'アーカイブ（$archivedCount）',
                ),
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
    required this.en,
    required this.store,
    required this.onOpen,
    required this.bar,
    this.onOpenSettings,
  });

  final bool en;
  final ThreadStore store;
  final void Function(Thread) onOpen;
  final Widget bar;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text(en ? 'Ask' : '質問'),
        actions: [
          if (onOpenSettings != null)
            IconButton(
              tooltip: en ? 'Settings' : '設定',
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
                            en
                                ? 'No questions yet. Ask below.'
                                : 'まだ質問はありません。下から質問できます。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ThreadList(
                    store: store,
                    en: en,
                    onOpen: onOpen,
                    max: 1000,
                    heading: false,
                  ),
                  if (store.recent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        en
                            ? 'Swipe right to archive, left to delete.'
                            : '右にスワイプでアーカイブ、左にスワイプで削除。',
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
