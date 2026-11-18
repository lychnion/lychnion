import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';

import 'catalog.dart';
import 'download_manager.dart';
import 'download_store.dart' show MobileData;
import 'downloader.dart';

enum _Filter { all, installed, models, packages, maps }

/// Whether downloads may use mobile data: a small sheet, opened from
/// Downloads and from Settings.
Future<void> showMobileDataSheet(BuildContext context, DownloadManager m) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final l = c.l10n;
        return ListenableBuilder(
          listenable: m,
          builder: (c, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.downloadsMobileData,
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l.downloadsWifiOnlyHint,
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<MobileData>(
                    segments: [
                      ButtonSegment(
                        value: MobileData.never,
                        label: Text(l.downloadsMobileNever),
                      ),
                      ButtonSegment(
                        value: MobileData.ask,
                        label: Text(l.downloadsMobileAsk),
                      ),
                      ButtonSegment(
                        value: MobileData.always,
                        label: Text(l.downloadsMobileAlways),
                      ),
                    ],
                    selected: {m.mobileData},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => m.setMobileData(s.first),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

/// Lists models, knowledge packages and map areas: size, progress,
/// resume, checksum, delete. Filters keep the list short.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.manager});

  final DownloadManager manager;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadManager get m => widget.manager;

  bool get _isPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(m.refreshCatalog());
  }

  AppLocalizations get l => context.l10n;

  /// Which items the list shows (a long list otherwise: models, every
  /// package and every map area).
  _Filter _filter = _Filter.all;

  String _filterName(_Filter f) => switch (f) {
    _Filter.all => l.downloadsFilterAll,
    _Filter.installed => l.downloadsFilterInstalled,
    _Filter.models => l.downloadsKindModels,
    _Filter.packages => l.downloadsFilterPackages,
    _Filter.maps => l.downloadsFilterMaps,
  };

  bool _shows(CatalogItem i) => switch (_filter) {
    _Filter.all => true,
    _Filter.installed => switch (m.stateOf(i).status) {
      ItemStatus.installed ||
      ItemStatus.update ||
      ItemStatus.running ||
      ItemStatus.partial => true,
      _ => false,
    },
    _Filter.models => i.kind == ItemKind.model,
    _Filter.packages => i.kind == ItemKind.package,
    _Filter.maps => i.kind == ItemKind.map,
  };
  String get lang => context.lang;

  String _errorText(String e) => switch (e) {
    'offline' => l.downloadsErrorOffline,
    'wifi-only' => l.downloadsErrorWifiOnly,
    'network' => l.downloadsErrorNetwork,
    'checksum' => l.downloadsErrorChecksum,
    'checksum-local' => l.downloadsErrorChecksumLocal,
    'busy' => l.downloadsErrorBusy,
    'disk-full' => l.downloadsErrorDiskFull,
    'disk' => l.downloadsErrorDisk,
    'signature' => l.downloadsErrorSignature,
    'older' => l.downloadsErrorOlder,
    _ => e,
  };

  Future<void> _download(CatalogItem item) async {
    // "Wi-Fi only" is off and this is mobile data: say how much it uses.
    if (m.mobileData == MobileData.ask && await m.asksBeforeMobile(item)) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l.downloadsMobileTitle(formatBytes(item.size))),
          content: Text(l.downloadsMobileBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l.downloadsDownload),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else if (item.size >= largeDownloadBytes) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(item.title(lang)),
          content: Text(l.downloadsLargeWarning(formatBytes(item.size))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l.downloadsDownload),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await m.download(item);
  }

  Future<void> _delete(CatalogItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.downloadsDeleteTitle),
        content: Text(
          l.downloadsDeleteBody(item.title(lang), formatBytes(item.size)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok == true) await m.delete(item);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(l.downloadsTitle),
      actions: [
        IconButton(
          tooltip: l.downloadsMobileData,
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => showMobileDataSheet(context, m),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final items = m.catalog.items;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // One row, scrolling sideways when it does not fit.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterName(f)),
                        selected: _filter == f,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            if (m.refreshing) const LinearProgressIndicator(),
            for (final kind in ItemKind.values)
              if ([
                    for (final i in items)
                      if (i.kind == kind && _shows(i)) i,
                  ]
                  case final shown when shown.isNotEmpty) ...[
                _header(kind),
                for (final i in shown) _tile(i),
              ],
            if (!items.any(_shows))
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.downloadsNothingHere),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.downloadsFooter,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _header(ItemKind k) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(switch (k) {
      ItemKind.model => l.downloadsKindModels,
      ItemKind.package => l.downloadsKindPackages,
      ItemKind.map => l.downloadsKindMaps,
    }, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _tile(CatalogItem item) {
    final s = m.stateOf(item);
    final theme = Theme.of(context);
    final canGet = m.catalog.canDownload(item);
    final running = s.status == ItemStatus.running;
    final chatPick =
        item.role == 'chat' &&
        (s.status == ItemStatus.installed || s.status == ItemStatus.update);
    final usedChat = chatPick && _isActiveChat(item);

    final lines = <String>[
      [
        item.version,
        formatBytes(item.size),
        if (item.licence.isNotEmpty) item.licence,
      ].join(' · '),
      if (item.note(lang).isNotEmpty) item.note(lang),
      if (item.desktop && _isPhone) l.downloadsTooLargeForPhone,
    ];

    final status = switch (s.status) {
      ItemStatus.absent =>
        canGet ? l.downloadsNotDownloaded : l.downloadsNoSource,
      ItemStatus.partial => l.downloadsPaused(
        formatBytes(s.bytes),
        formatBytes(s.total),
      ),
      ItemStatus.unverified => l.downloadsUnverified,
      ItemStatus.running => _runningText(s),
      ItemStatus.installed => l.downloadsInstalled,
      ItemStatus.update => l.downloadsUpdateAvailable('${s.installedVersion}'),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title(lang),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (s.status == ItemStatus.installed)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
              ],
            ),
            for (final l in lines) Text(l, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(status),
            if (running || s.status == ItemStatus.partial) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: s.total > 0 ? s.bytes / s.total : null,
              ),
            ],
            if (s.error != null) ...[
              const SizedBox(height: 6),
              Text(
                _errorText(s.error!),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (running)
                  OutlinedButton(
                    onPressed: () => m.stop(item),
                    child: Text(l.downloadsStop),
                  ),
                if (!running && canGet && s.status == ItemStatus.absent)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(l.downloadsDownload),
                  ),
                if (!running && canGet && s.status == ItemStatus.partial)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(l.downloadsResume),
                  ),
                if (!running && canGet && s.status == ItemStatus.update)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(l.downloadsUpdate),
                  ),
                if (!running && s.status == ItemStatus.unverified)
                  FilledButton(
                    onPressed: () => m.verifyExisting(item),
                    child: Text(l.downloadsCheckFile),
                  ),
                if (chatPick)
                  usedChat
                      ? Chip(label: Text(l.downloadsInUse))
                      : OutlinedButton(
                          onPressed: () => m.useChatModel(item),
                          child: Text(l.downloadsUseModel),
                        ),
                if (!running && s.status != ItemStatus.absent)
                  TextButton(
                    onPressed: () => _delete(item),
                    child: Text(l.delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isActiveChat(CatalogItem item) => m.store.activeChat()?.id == item.id;

  String _runningText(ItemState s) {
    final pct = s.total > 0 ? (100 * s.bytes / s.total).floor() : 0;
    return switch (s.phase) {
      DownloadPhase.checkingPart => l.downloadsCheckingPart,
      DownloadPhase.verifying => l.downloadsVerifying('$pct'),
      _ =>
        '$pct% · ${formatBytes(s.bytes)} / ${formatBytes(s.total)}'
            '${s.speed > 0 ? ' · ${formatBytes(s.speed.round())}/s' : ''}'
            '${s.speed > 0 ? ' · ${_eta((s.total - s.bytes) / s.speed)}' : ''}',
    };
  }

  String _eta(double seconds) {
    final m = (seconds / 60).ceil();
    if (m < 2) return l.downloadsEtaOneMinute;
    return l.downloadsEtaMinutes('$m');
  }
}
