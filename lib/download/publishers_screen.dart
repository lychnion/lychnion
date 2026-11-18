import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import '../publish/publish_screen.dart';
import 'download_manager.dart';
import 'publisher_list.dart';

/// Settings → Publishers: Lychnion (built in) and the publishers the user
/// added, with a way to add one from a link and to remove one.
class PublishersScreen extends StatefulWidget {
  const PublishersScreen({super.key, required this.manager});

  final DownloadManager manager;

  @override
  State<PublishersScreen> createState() => _PublishersScreenState();
}

class _PublishersScreenState extends State<PublishersScreen> {
  PublisherList get _list => widget.manager.store.publishers;

  Future<void> _remove(Publisher p) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.publishersRemoveTitle(p.title ?? p.name)),
        content: Text(l.publishersRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.publishersRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.manager.removePublisher(p.name);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.publishersSaveFailed)),
        );
      }
      return;
    }
  }

  Future<void> _fromLink() async {
    final l = context.l10n;
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (link == null || !mounted) return;
    final parsed = Uri.tryParse(link.trim());
    final p = parsed == null ? null : PublisherLink.fromUri(parsed);
    if (p == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.publishersNotALink)));
      return;
    }
    await addPublisher(context, widget.manager, p);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.publishersTitle),
        actions: [
          if (canPublish)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PublishScreen(manager: widget.manager),
                ),
              ),
              icon: const Icon(Icons.edit_document),
              label: Text(l.publishTitle),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fromLink,
        icon: const Icon(Icons.add_link_rounded),
        label: Text(l.publishersFromLink),
      ),
      body: ListenableBuilder(
        listenable: _list,
        builder: (context, _) {
          final added = _list.added;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final name in _list.builtIn.publishers)
                ListTile(
                  leading: const Icon(Icons.verified_rounded),
                  title: Text(name == 'lychnion' ? l.appName : name),
                  subtitle: Text(l.publishersBuiltIn),
                ),
              const Divider(),
              if (added.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.publishersNone),
                ),
              for (final p in added)
                ListTile(
                  leading: Icon(
                    _list.keyStateOf(p.name) == PublisherKeyState.revoked
                        ? Icons.gpp_bad_outlined
                        : Icons.badge_outlined,
                  ),
                  title: Text(p.title ?? p.name),
                  subtitle: Text(
                    [
                      if (p.title != null) p.name,
                      switch (_list.keyStateOf(p.name)) {
                        PublisherKeyState.added => l.publishersKey(p.keyId),
                        PublisherKeyState.replaced => l.publishersKeyReplaced(
                          ([
                            for (final id in _list.trust.keyIdsOf(p.name))
                              if (id != p.keyId) id,
                          ]..sort()).join(', '),
                        ),
                        PublisherKeyState.revoked => l.publishersKeyRevoked,
                      },
                      l.publishersAddedOn(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(p.added.toLocal()),
                      ),
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: l.publishersRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _remove(p),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Text for a link that cannot be added.
String publisherProblemText(AppLocalizations l, PublisherProblem p, String n) =>
    switch (p) {
      PublisherProblem.badName => l.publishersBadName,
      PublisherProblem.badKey => l.publishersBadKey,
      PublisherProblem.builtIn => l.publishersBuiltInName(n),
      PublisherProblem.otherKey => l.publishersOtherKey(n),
      PublisherProblem.known => l.publishersKnown(n),
      PublisherProblem.revoked => l.publishersRevoked(n),
    };

/// Asks, then adds the publisher of [link] (a scanned or pasted
/// lychnion://publisher link). Returns true when it was added.
Future<bool> addPublisher(
  BuildContext context,
  DownloadManager manager,
  PublisherLink link,
) async {
  final l = context.l10n;
  final list = manager.store.publishers;
  final messenger = ScaffoldMessenger.of(context);
  if (list.problemWith(link) case final p?) {
    messenger.showSnackBar(
      SnackBar(content: Text(publisherProblemText(l, p, link.name))),
    );
    return false;
  }
  // Its new link after a revoked key: anyone can make one, so say so.
  final replacing = list.added.where((p) => p.name == link.name).firstOrNull;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.badge_outlined),
      title: Text(l.publishersAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            link.title ?? link.name,
            style: Theme.of(c).textTheme.titleMedium,
          ),
          Text(
            [
              if (link.title != null) link.name,
              l.publishersKey(link.keyId!),
            ].join(' · '),
          ),
          const SizedBox(height: 12),
          Text(l.publishersAddBody(l.appName)),
          if (replacing != null) ...[
            const SizedBox(height: 12),
            Text(
              l.publishersReplacesRevoked(replacing.keyId),
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(l.publishersAdd),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  // Checked again: the list may have changed while the question was open.
  if (list.problemWith(link) != null) return false;
  try {
    await list.add(link);
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l.publishersSaveFailed)));
    return false;
  }
  await manager.publishersChanged();
  messenger.showSnackBar(
    SnackBar(content: Text(l.publishersAdded(link.title ?? link.name))),
  );
  return true;
}

/// Asks for a pasted publisher link. Owns its text field's controller, so
/// it is disposed only after the dialog has closed.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.publishersFromLink),
      content: TextField(
        controller: _text,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l.publishersLinkLabel,
          hintText: 'lychnion://publisher?…',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(l.publishersAdd),
        ),
      ],
    );
  }
}
