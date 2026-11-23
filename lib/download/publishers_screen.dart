import 'package:lychnion_format/lychnion_format.dart' show Vouch;
import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import '../publish/publish_screen.dart';
import 'download_manager.dart';
import 'download_store.dart';
import 'lookalike.dart';
import 'publisher_label.dart';
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
  DownloadStore get store => widget.manager.store;
  PublisherList get _list => store.publishers;

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
    final scheme = Theme.of(context).colorScheme;
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
        // Labels follow the vouches the device learns (#119).
        listenable: Listenable.merge([_list, store.vouches]),
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
                if (store.labelOf(p.name, p.key) case final label)
                  ListTile(
                    leading: Icon(
                      _list.keyStateOf(p.name) == PublisherKeyState.revoked
                          ? Icons.gpp_bad_outlined
                          : publisherLabelIcon(label),
                      color: label.isProblem ? scheme.error : null,
                    ),
                    title: Text(label.titleIn(context.lang, p.title ?? p.name)),
                    subtitle: Text(
                      [
                        if (label.check != PublisherCheck.revoked)
                          publisherLabelText(context, label),
                        if (p.title != null ||
                            label.check == PublisherCheck.vouched)
                          p.name,
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

/// The label of a publisher with [label] (#119): checked by Lychnion,
/// added by the user and not checked, or what is wrong.
String publisherLabelText(BuildContext context, PublisherLabel label) {
  final l = context.l10n;
  final app = l.appName;
  return switch (label.check) {
    PublisherCheck.builtIn => l.publishersBuiltIn,
    PublisherCheck.vouched => l.publishersVouched(
      app,
      _checkedOn(context, label.vouch!),
    ),
    PublisherCheck.notChecked => l.publishersNotChecked(app),
    PublisherCheck.withdrawn => l.publishersWithdrawn(app),
    PublisherCheck.otherKey => l.publishersNotVouchedKey(app),
    PublisherCheck.revoked => l.publishersKeyRevoked,
  };
}

IconData publisherLabelIcon(PublisherLabel label) => switch (label.check) {
  PublisherCheck.builtIn || PublisherCheck.vouched => Icons.verified_rounded,
  PublisherCheck.notChecked => Icons.badge_outlined,
  PublisherCheck.revoked => Icons.gpp_bad_outlined,
  PublisherCheck.withdrawn ||
  PublisherCheck.otherKey => Icons.warning_amber_rounded,
};

/// The day Lychnion checked [v]'s key, in the user's date format.
String _checkedOn(BuildContext context, Vouch v) {
  final d = DateTime.tryParse(v.checked);
  return d == null
      ? v.checked
      : MaterialLocalizations.of(context).formatMediumDate(d);
}

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
  final store = manager.store;
  final label = store.labelOf(link.name, link.key);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _AddDialog(
      link: link,
      label: label,
      lookalike: label.check == PublisherCheck.notChecked
          ? lookalikeOf(
              link.name,
              link.title,
              store.vouches.vouchesFor(store.trust),
            )
          : null,
      replacing: replacing,
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

/// Asks whether to add [link]'s publisher, with what Lychnion's vouches
/// say about it (#119). A name with a problem or one that looks official
/// needs a tick first: the user compared the key's code.
class _AddDialog extends StatefulWidget {
  const _AddDialog({
    required this.link,
    required this.label,
    required this.lookalike,
    required this.replacing,
  });

  final PublisherLink link;
  final PublisherLabel label;
  final Lookalike? lookalike;
  final Publisher? replacing;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  bool _compared = false;

  bool get _needsTick => widget.label.isProblem || widget.lookalike != null;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final app = l.appName;
    final theme = Theme.of(context);
    final error = TextStyle(color: theme.colorScheme.error);
    final link = widget.link;
    final label = widget.label;
    final shown = label.titleIn(context.lang, link.title ?? link.name);
    final replacing = widget.replacing;
    final warning = switch ((label.check, widget.lookalike)) {
      (PublisherCheck.withdrawn, _) => l.publishersWithdrawnBody(app),
      (PublisherCheck.otherKey, _) => l.publishersNotVouchedKeyBody(app),
      // Refused before the dialog (problemWith); said all the same.
      (PublisherCheck.revoked, _) => l.publishersKeyRevoked,
      (_, Lookalike.vouched) => l.publishersLooksVouched(app),
      (_, Lookalike.publicBody) => l.publishersLooksPublic(app),
      _ => null,
    };
    return AlertDialog(
      icon: Icon(
        publisherLabelIcon(label),
        color: _needsTick ? theme.colorScheme.error : null,
      ),
      title: Text(l.publishersAddTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shown, style: theme.textTheme.titleMedium),
            Text(
              [
                if (shown != link.name) link.name,
                l.publishersKey(link.keyId!),
              ].join(' · '),
            ),
            const SizedBox(height: 12),
            if (label.check == PublisherCheck.vouched)
              Text(
                l.publishersVouchedBody(
                  app,
                  _checkedOn(context, label.vouch!),
                  shown,
                ),
              )
            else if (warning == null)
              Text(l.publishersNotCheckedBody(app)),
            if (warning != null) ...[
              Text(warning, style: error),
              const SizedBox(height: 8),
              Text(l.publishersCompareCode(link.keyId!)),
            ],
            const SizedBox(height: 12),
            Text(l.publishersAddBody(app)),
            if (replacing != null) ...[
              const SizedBox(height: 12),
              Text(l.publishersReplacesRevoked(replacing.keyId), style: error),
            ],
            if (_needsTick)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _compared,
                onChanged: (v) => setState(() => _compared = v ?? false),
                title: Text(l.publishersCompared),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: !_needsTick || _compared
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(l.publishersAdd),
        ),
      ],
    );
  }
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
