import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/lang.dart';
import '../download/catalog.dart';
import '../download/download_manager.dart';
import '../download/publisher_list.dart';
import '../l10n/app_localizations.dart';
import '../util/paths.dart';
import 'key_actions.dart';
import 'local_publisher.dart';
import 'publish.dart';

/// Desktop: a city or a club makes its publisher key, shows phones its
/// code, and signs guides and maps it built (docs/distribution.md, 4b).
/// What it publishes is installed here, so the base passes it on.
class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key, required this.manager, this.dir});

  final DownloadManager manager;

  /// For tests; `<app support>/publisher` otherwise.
  final Directory? dir;

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  Directory? _dir;
  LocalPublisher? _me;

  /// A key file is there but cannot be read: never offer a new key then.
  bool _unreadable = false;
  bool _loading = true, _busy = false;
  final _name = TextEditingController();
  final _title = TextEditingController();
  String? _nameError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dir =
        widget.dir ??
        Directory('${(await appSupportDirectory()).path}/publisher');
    final me = await LocalPublisher.load(dir);
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _me = me;
      _unreadable = me == null && LocalPublisher.existsIn(dir);
      _loading = false;
    });
  }

  Future<void> _create() async {
    if (_busy) return;
    final l = context.l10n;
    final name = _name.text.trim();
    // A name already added on this computer with another key would never
    // be trusted for this key.
    final probe = PublisherLink(name: name, key: 'x' * 43);
    if (widget.manager.store.publishers.problemWith(probe) ==
        PublisherProblem.otherKey) {
      setState(() => _nameError = l.publishErrorKey);
      return;
    }
    setState(() {
      _nameError = null;
      _busy = true;
    });
    String? error;
    LocalPublisher? me;
    try {
      me = await LocalPublisher.create(_dir!, name: name, title: _title.text);
    } on ArgumentError catch (e) {
      error = e.message == 'exists' ? l.publishKeyExists : l.publishBadName;
    } on StateError {
      error = l.publishKeyPrivateFailed;
    } on Object catch (e) {
      error = l.publishFailed('$e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _me = me;
      _nameError = error;
      _unreadable = me == null && LocalPublisher.existsIn(_dir!);
    });
  }

  Future<void> _pick() async {
    final l = context.l10n;
    final picked = await openFiles();
    if (picked.isEmpty || !mounted) return;
    final files = [for (final x in picked) File(x.path)];
    var req = files.length == 1 && files.single.path.endsWith('.sqlite')
        ? requestFromPackage(files.single)
        : null;
    if (req == null &&
        files.length == 1 &&
        files.single.path.endsWith('.sqlite')) {
      // A .sqlite that is not a package: maybe a map's sites file.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.publishNotPackage)));
    }
    req ??= PublishRequest(
      kind: ItemKind.map,
      id: _commonId(files),
      version: '',
      titles: const {},
      files: files,
    );
    final filled = await showDialog<PublishRequest>(
      context: context,
      builder: (_) => _PublishForm(initial: req!),
    );
    if (filled == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await publish(
        filled,
        publisher: _me!,
        store: widget.manager.store,
        publisherDir: _dir!,
      );
      await widget.manager.publishersChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.publishDone(r.id, r.version))));
    } on PublishError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(publishErrorText(l, e))));
    } on Object catch (e) {
      // Disk full, a file in use, a key list that cannot be saved, …
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.publishFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The id the files share (`jp.map.kobe` of `jp.map.kobe.pmtiles` and
  /// `jp.map.kobe.sites.sqlite`), or ''.
  static String _commonId(List<File> files) {
    final names = [for (final f in files) f.uri.pathSegments.last];
    if (names.isEmpty) return '';
    var prefix = names.first;
    for (final n in names.skip(1)) {
      var i = 0;
      while (i < prefix.length && i < n.length && prefix[i] == n[i]) {
        i++;
      }
      prefix = prefix.substring(0, i);
    }
    // One file: drop its extension. Several: cut at the last shared dot.
    final cut = prefix.lastIndexOf('.');
    return cut <= 0 ? '' : prefix.substring(0, cut);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = _me;
    return Scaffold(
      appBar: AppBar(title: Text(l.publishTitle)),
      floatingActionButton: me == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _pick,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(l.publishPick),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(l.publishIntro),
                const SizedBox(height: 16),
                if (me != null)
                  ..._publisher(l, me)
                else if (_unreadable)
                  Text(
                    l.publishKeyUnreadable(LocalPublisher.fileIn(_dir!).path),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else
                  ..._createForm(l),
              ],
            ),
    );
  }

  List<Widget> _createForm(AppLocalizations l) => [
    TextField(
      controller: _name,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: l.publishName,
        helperText: l.publishNameHelp,
        helperMaxLines: 3,
        errorText: _nameError,
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _title,
      decoration: InputDecoration(labelText: l.publishDisplayName),
    ),
    const SizedBox(height: 16),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.key_rounded),
        label: Text(l.publishCreate),
      ),
    ),
    const SizedBox(height: 24),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final me = await restoreKey(context, _dir!, widget.manager);
                  if (me != null && mounted) setState(() => _me = me);
                },
          icon: const Icon(Icons.restore_rounded),
          label: Text(l.publishRestore),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => revokeFromBackup(context, _dir!, widget.manager),
          icon: const Icon(Icons.gpp_bad_outlined),
          label: Text(l.publishRevokeFromBackup),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      l.publishRevokeFromBackupText,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];

  List<Widget> _publisher(AppLocalizations l, LocalPublisher me) {
    final link = me.link.toUri().toString();
    final mine = [
      for (final k in ItemKind.values)
        for (final i in widget.manager.store.allInstalled(k))
          if (i.record.publisher == me.name) i,
    ];
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: link,
                  size: 200,
                  semanticsLabel: context.l10n.publishQrSpoken,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.title ?? me.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      [
                        if (me.title != null) me.name,
                        l.publishersKey(me.link.keyId ?? ''),
                      ].join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Text(l.publishScanHint),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.publishLinkCopied)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(l.publishCopyLink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.publishKeyNote(LocalPublisher.fileIn(_dir!).path),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      PublisherKeyActions(
        dir: _dir!,
        manager: widget.manager,
        me: me,
        busy: _busy,
        onChanged: (n) {
          if (mounted) setState(() => _me = n);
        },
      ),
      const SizedBox(height: 16),
      Text(l.publishPublished, style: Theme.of(context).textTheme.titleMedium),
      if (mine.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(l.publishNothing),
        ),
      for (final i in mine)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            i.kind == ItemKind.map
                ? Icons.map_outlined
                : Icons.menu_book_rounded,
          ),
          title: Text(
            CatalogItem.fromRecord(i.record)
                .title(Localizations.localeOf(context).languageCode),
          ),
          subtitle: Text('${i.id} · ${i.version}'),
        ),
    ];
  }
}

String publishErrorText(AppLocalizations l, PublishError e) => switch (e.code) {
  'id' => l.publishErrorId,
  'version' => l.publishErrorVersion,
  'older' => l.publishErrorOlder(e.detail),
  'files' => l.publishErrorFiles,
  'meta' => l.publishErrorMeta,
  'package' => l.publishErrorPackage(e.detail),
  'taken' => l.publishErrorTaken(e.detail),
  'title' => l.publishErrorTitle,
  'key' => l.publishErrorKey,
  _ => '$e',
};

/// Kind, id, version, titles and licence of what is published.
class _PublishForm extends StatefulWidget {
  const _PublishForm({required this.initial});

  final PublishRequest initial;

  @override
  State<_PublishForm> createState() => _PublishFormState();
}

class _PublishFormState extends State<_PublishForm> {
  late ItemKind _kind = widget.initial.kind;
  late final _id = TextEditingController(text: widget.initial.id);
  late final _version = TextEditingController(text: widget.initial.version);
  late final _ja = TextEditingController(text: widget.initial.titles['ja']);
  late final _en = TextEditingController(text: widget.initial.titles['en']);
  late final _licence = TextEditingController(text: widget.initial.licence);

  @override
  void dispose() {
    for (final c in [_id, _version, _ja, _en, _licence]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget field(TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return AlertDialog(
      title: Text(l.publishPick),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<ItemKind>(
                segments: [
                  ButtonSegment(
                    value: ItemKind.package,
                    label: Text(l.publishKindPackage),
                  ),
                  ButtonSegment(
                    value: ItemKind.map,
                    label: Text(l.publishKindMap),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                [for (final f in widget.initial.files) f.uri.pathSegments.last]
                    .join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              field(_id, l.publishId),
              field(_version, l.publishVersion),
              field(_ja, l.publishTitleJa),
              field(_en, l.publishTitleEn),
              field(_licence, l.publishLicence),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PublishRequest(
              kind: _kind,
              id: _id.text.trim(),
              version: _version.text.trim(),
              titles: {'ja': _ja.text, 'en': _en.text},
              licence: _licence.text,
              notice: widget.initial.notice,
              files: widget.initial.files,
            ),
          ),
          child: Text(l.publishSign),
        ),
      ],
    );
  }
}

/// Whether this platform can publish (desktops only).
bool get canPublish =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;
