import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../ui/help_screen.dart';
import '../app/region.dart';
import '../knowledge/regions.dart';
import '../l10n/app_localizations.dart';

import 'catalog.dart';
import 'download_manager.dart';
import 'download_store.dart' show MobileData, UpdateMode;
import 'downloader.dart';
import '../shelter/share_nearby.dart';
import 'stick.dart';

/// Download settings: mobile data and updates. A small sheet, opened from
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
                const SizedBox(height: 24),
                Text(
                  l.downloadsUpdates,
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l.downloadsUpdatesHint,
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<UpdateMode>(
                    segments: [
                      ButtonSegment(
                        value: UpdateMode.auto,
                        label: Text(l.downloadsUpdatesAuto),
                      ),
                      ButtonSegment(
                        value: UpdateMode.notify,
                        label: Text(l.downloadsUpdatesNotify),
                      ),
                      ButtonSegment(
                        value: UpdateMode.off,
                        label: Text(l.downloadsUpdatesOff),
                      ),
                    ],
                    selected: {m.updateMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => m.setUpdateMode(s.first),
                  ),
                ),
                if (DownloadManager.isDesktop) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.downloadsKeepAll),
                    subtitle: Text(
                      [
                        l.downloadsKeepAllHint,
                        if (m.keepAll)
                          switch (m.keepAllMissing) {
                            (count: 0, bytes: _) => l.downloadsKeepAllDone,
                            final x => l.downloadsKeepAllMissing(
                              '${x.count}',
                              formatBytes(x.bytes),
                            ),
                          },
                      ].join('\n'),
                    ),
                    value: m.keepAll,
                    onChanged: m.setKeepAll,
                  ),
                  if (m.keepAll)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l.downloadsKeepModels),
                      value: m.keepModels,
                      onChanged: (v) => m.setKeepModels(v ?? false),
                    ),
                  const SizedBox(height: 16),
                  Text(l.stickTitle, style: Theme.of(c).textTheme.titleMedium),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.usb_rounded),
                    title: Text(l.stickCopy),
                    subtitle: Text(l.stickCopyHint),
                    onTap: () => _stick(c, m, copy: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.drive_folder_upload_rounded),
                    title: Text(l.stickLoad),
                    subtitle: Text(l.stickLoadHint(l.appName)),
                    onTap: () => _stick(c, m, copy: false),
                  ),
                ],
                const SizedBox(height: 20),
                Text(l.downloadsFooter, style: Theme.of(c).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );

/// Copies to, or loads from, a USB stick the user picks (step 5d).
Future<void> _stick(
  BuildContext sheet,
  DownloadManager m, {
  required bool copy,
}) async {
  final l = sheet.l10n;
  final nav = Navigator.of(sheet);
  final messenger = ScaffoldMessenger.of(sheet);
  final route = ModalRoute.of(sheet);
  if (!copy && m.busy) {
    messenger.showSnackBar(SnackBar(content: Text(l.stickBusy)));
    return;
  }
  final path = await getDirectoryPath(
    confirmButtonText: copy ? l.stickCopy : l.stickLoad,
  );
  if (path == null) return;
  // The settings sheet, if it is still open.
  if (route != null && route.isActive) nav.removeRoute(route);
  final ctx = nav.context;
  if (!ctx.mounted) return;
  unawaited(
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(copy ? l.stickCopying : l.stickLoading)),
            ],
          ),
        ),
      ),
    ),
  );
  String text;
  try {
    final dir = Directory(path);
    if (copy) {
      final r = await copyToStick(m.store, dir);
      text = l.stickCopied(
        '${r.added}',
        '${r.notNewer}',
        stickFolder(dir).path,
      );
      if (r.failed.isNotEmpty) {
        text += '\n${l.stickFailedItems(r.failed.join(', '))}';
      }
    } else {
      if (m.busy) throw const _Busy();
      final r = await m.withoutDownloads(() => loadFromStick(m.store, dir));
      m.installedChanged();
      text = l.stickLoaded(
        '${r.added}',
        '${r.notNewer}',
        '${r.notTrusted + r.taken}',
      );
      if (r.failed.isNotEmpty) {
        text += '\n${l.stickFailedItems(r.failed.join(', '))}';
      }
    }
  } on _Busy {
    text = l.stickBusy;
  } on UnreadableStick catch (e) {
    text = l.stickUnreadable(e.reason);
  } on FileSystemException catch (e) {
    text = e.message == 'no catalog'
        ? l.stickNoCatalog
        : l.stickFailed(e.osError?.message ?? e.message);
  } on Object catch (e) {
    text = l.stickFailed(e is FormatException ? e.message : '${e.runtimeType}');
  }
  nav.pop(); // the progress dialog
  messenger.showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 8)),
  );
}

class _Busy implements Exception {
  const _Busy();
}

/// Lists models, knowledge packages and map areas: size, progress,
/// resume, checksum, delete. Filters keep the list short.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.manager, this.userRegion});

  final DownloadManager manager;

  /// The user's region ('JP-30'): items made for it come first. None in
  /// tests; the list then keeps catalog order.
  final Future<String> Function()? userRegion;

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
    unawaited(_loadRegion());
  }

  /// The user's region, and region names for the area labels.
  String? _region;
  RegionLookup? _regions;

  Future<void> _loadRegion() async {
    final regions = await UserRegion.lookup();
    final region = await widget.userRegion?.call();
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _region = region;
    });
  }

  /// "和歌山県" or "大阪府、兵庫県" for an item's area; '' for anywhere.
  String _areaText(List<String> area) => [
    for (final c in area)
      c.contains('-')
          ? (_regions?.nameOf(c, lang) ?? c)
          : (c == 'JP' ? l.areaJapan : c),
  ].join(lang == 'ja' ? '、' : ', ');

  AppLocalizations get l => context.l10n;

  /// What the list shows (a long list otherwise): only downloaded items,
  /// only updates, and one kind or all.
  bool _downloadedOnly = false;
  bool _updatesOnly = false;
  ItemKind? _kind;

  String _kindName(ItemKind? k) => switch (k) {
    null => l.downloadsFilterAll,
    ItemKind.model => l.downloadsKindModels,
    ItemKind.package => l.downloadsFilterPackages,
    ItemKind.map => l.downloadsFilterMaps,
  };

  bool _shows(CatalogItem i) {
    final st = m.stateOf(i).status;
    if (_kind != null && i.kind != _kind) return false;
    if (_updatesOnly && st != ItemStatus.update) return false;
    if (_downloadedOnly &&
        !const {
          ItemStatus.installed,
          ItemStatus.update,
          ItemStatus.running,
          ItemStatus.partial,
        }.contains(st)) {
      return false;
    }
    return true;
  }

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
    'taken' => l.downloadsErrorTaken,
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
          tooltip: l.helpTitle,
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => HelpScreen.open(context, topic: 'help-04-downloads'),
        ),
        IconButton(
          tooltip: l.shareNearby,
          icon: const Icon(Icons.share_rounded),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ShareNearbyScreen()),
          ),
        ),
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
        final items = byArea(m.catalog.items, _region);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // Three short controls: always fit on one line.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text(l.downloadsFilterInstalled),
                    selected: _downloadedOnly,
                    onSelected: (v) => setState(() => _downloadedOnly = v),
                  ),
                  if (m.updates.value > 0 || _updatesOnly)
                    FilterChip(
                      label: Text(l.downloadsFilterUpdates(m.updates.value)),
                      selected: _updatesOnly,
                      onSelected: (v) => setState(() => _updatesOnly = v),
                    ),
                  PopupMenuButton<ItemKind?>(
                    initialValue: _kind,
                    onSelected: (k) => setState(() => _kind = k),
                    itemBuilder: (_) => [
                      for (final k in [null, ...ItemKind.values])
                        PopupMenuItem(value: k, child: Text(_kindName(k))),
                    ],
                    child: Chip(
                      backgroundColor: _kind == null
                          ? null
                          : Theme.of(context).colorScheme.secondaryContainer,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${l.downloadsFilterKind}: ${_kindName(_kind)}'),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
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

    final open = _open.contains(item.id);
    final r = item.record;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    // Compact cards show state only, no buttons: a tap to open the card
    // must never start a download. Actions are in the opened card.
    final Widget? mark = switch (s.status) {
      ItemStatus.installed => Icon(
        Icons.check_circle,
        color: theme.colorScheme.primary,
      ),
      ItemStatus.update => Badge(
        smallSize: 9,
        child: Icon(Icons.update_rounded, color: theme.colorScheme.primary),
      ),
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            setState(() => open ? _open.remove(item.id) : _open.add(item.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title(lang),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (item.area.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  _areaText(item.area),
                                  style: muted,
                                  overflow: TextOverflow.ellipsis,
                                  semanticsLabel:
                                      '${l.settingsRegion}: ${_areaText(item.area)}',
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (r != null) ...[
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                l.downloadsSigned,
                                style: small?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              Text(' · ', style: muted),
                            ],
                            Flexible(
                              child: Text(
                                '${formatBytes(item.size)} · $status',
                                style: muted,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ?mark,
                  const SizedBox(width: 4),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
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
              if (open) ...[
                const SizedBox(height: 8),
                for (final line in lines) Text(line, style: small),
                if (r != null) ...[
                  const SizedBox(height: 8),
                  _detail(l.downloadsPublisher, r.publisher),
                  _detail(l.downloadsSignedOn, _date(r.signed)),
                  _detail(l.downloadsKey, r.keyId),
                  for (final f in r.files)
                    _detail(
                      f.name,
                      '${formatBytes(f.size)} · SHA-256 ${f.sha256.substring(0, 12)}…',
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
                    if (!running &&
                        canGet &&
                        (s.status == ItemStatus.absent ||
                            s.status == ItemStatus.partial ||
                            s.status == ItemStatus.update))
                      FilledButton.icon(
                        onPressed: () => _download(item),
                        icon: Icon(
                          s.status == ItemStatus.update
                              ? Icons.update_rounded
                              : Icons.download_rounded,
                        ),
                        label: Text(switch (s.status) {
                          ItemStatus.partial => l.downloadsResume,
                          ItemStatus.update => l.downloadsUpdate,
                          _ => l.downloadsDownload,
                        }),
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
            ],
          ),
        ),
      ),
    );
  }

  /// Items shown expanded (tap a card to open or close it).
  final _open = <String>{};

  Widget _detail(String label, String value) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: small?.copyWith(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value, style: small),
          ],
        ),
      ),
    );
  }

  /// "2026-11-18" from the record's signing time.
  static String _date(String iso) =>
      iso.length >= 10 ? iso.substring(0, 10) : iso;

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
