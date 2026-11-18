import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import 'download_manager.dart';
import 'followed_catalogs.dart';

/// Settings → Catalogs: the catalogs of cities and clubs this device
/// follows, next to Lychnion's (docs/distribution.md, step 4c).
class CatalogsScreen extends StatefulWidget {
  const CatalogsScreen({super.key, required this.manager});

  final DownloadManager manager;

  @override
  State<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends State<CatalogsScreen> {
  FollowedCatalogs get _list => widget.manager.store.followed;

  Future<void> _add() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (text == null || !mounted) return;
    final link = catalogLinkFrom(text);
    if (link == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.catalogsNotALink)));
      return;
    }
    await followCatalog(context, widget.manager, link);
  }

  Future<void> _remove(FollowedCatalog c) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.catalogsRemoveTitle(c.name ?? c.url.host)),
        content: Text(l.catalogsRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(l.catalogsRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.manager.unfollow(c.url);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.catalogsSaveFailed)));
      }
    }
  }

  String _status(CatalogStatus? s) {
    final l = context.l10n;
    final when = s?.fetched == null
        ? l.catalogsNeverFetched
        : l.catalogsFetched(
            MaterialLocalizations.of(context)
                .formatMediumDate(s!.fetched!.toLocal()),
          );
    return [
      if (s != null && s.fetched != null)
        l.catalogsStatus('${s.shown}', '${s.notShown}'),
      when,
      if (s?.error case final e?) catalogErrorText(l, e),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = widget.manager;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.catalogsTitle),
        actions: [
          ListenableBuilder(
            listenable: m,
            builder: (context, _) => IconButton(
              tooltip: l.catalogsRefresh,
              onPressed: m.refreshing ? null : m.refreshCatalog,
              icon: m.refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_link_rounded),
        label: Text(l.catalogsAdd),
      ),
      body: ListenableBuilder(
        listenable: _list,
        builder: (context, _) {
          final all = _list.all;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.catalogsNone),
                ),
              for (final c in all)
                ListTile(
                  leading: const Icon(Icons.list_alt_rounded),
                  title: Text(c.name ?? c.url.host),
                  subtitle: Text('${c.url}\n${_status(_list.status[c.url])}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: l.catalogsRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _remove(c),
                  ),
                ),
              if (all.any((c) => (_list.status[c.url]?.notShown ?? 0) > 0))
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.catalogsNotShownHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Why a followed catalog could not be read, for people.
String catalogErrorText(AppLocalizations l, String code) => switch (code) {
  'offline' => l.catalogsOffline,
  'invalid' || 'too large' => l.catalogsInvalid,
  _ => l.catalogsError(code),
};

/// A catalog address, or a lychnion://catalog link, from pasted text.
CatalogLink? catalogLinkFrom(String text) {
  final t = text.trim();
  final u = Uri.tryParse(t);
  final link = u == null ? null : CatalogLink.fromUri(u);
  if (link != null) return link;
  final url = CatalogLink.normalize(t);
  return url == null ? null : CatalogLink(url);
}

/// Asks, then follows [link]. Returns true when it was added.
Future<bool> followCatalog(
  BuildContext context,
  DownloadManager manager,
  CatalogLink link,
) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (manager.store.followed.follows(link.url)) {
    messenger.showSnackBar(SnackBar(content: Text(l.catalogsKnown)));
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.list_alt_rounded),
      title: Text(l.catalogsAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (link.name != null)
            Text(link.name!, style: Theme.of(c).textTheme.titleMedium),
          SelectableText('${link.url}'),
          const SizedBox(height: 12),
          Text(l.catalogsAddBody(l.appName)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(l.catalogsFollow),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final CatalogStatus? status;
  try {
    status = await manager.follow(link);
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l.catalogsSaveFailed)));
    return false;
  }
  if (status == null) {
    messenger.showSnackBar(SnackBar(content: Text(l.catalogsKnown)));
    return false;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        status.error != null && status.fetched == null
            ? catalogErrorText(l, status.error!)
            : l.catalogsStatus('${status.shown}', '${status.notShown}'),
      ),
    ),
  );
  return true;
}

/// Asks for a catalog address or link. Owns its controller, so it is
/// disposed only after the dialog has closed.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
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
      title: Text(l.catalogsAdd),
      content: TextField(
        controller: _text,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l.catalogsUrlLabel,
          hintText: 'https://…/catalog.json',
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
          child: Text(l.catalogsFollow),
        ),
      ],
    );
  }
}
