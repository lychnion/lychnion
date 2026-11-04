import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';
import 'download_manager.dart';
import 'downloader.dart';

/// Lists models, knowledge packages and map areas: size, progress,
/// resume, checksum, delete.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.manager,
    required this.english,
  });

  final DownloadManager manager;
  final bool english;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadManager get m => widget.manager;
  bool get en => widget.english;

  bool get _isPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(m.refreshCatalog());
  }

  String _t(String ja, String english) => en ? english : ja;

  String _errorText(String e) => switch (e) {
    'offline' => _t('インターネットに接続されていません。', 'No internet connection.'),
    'wifi-only' => _t(
      'Wi-Fi に接続してください（モバイルデータは設定でオフ）。',
      'Connect to Wi-Fi (mobile data is off in the setting above).',
    ),
    'network' => _t(
      '接続が切れました。「再開」で続きから取得します。',
      'The connection dropped. "Resume" continues where it stopped.',
    ),
    'checksum' => _t(
      'ファイルが壊れていたため削除しました。もう一度ダウンロードしてください。',
      'The file was damaged and has been removed. Please download again.',
    ),
    'checksum-local' => _t(
      'このファイルはカタログの版と一致しません。削除してダウンロードしてください。',
      'This file does not match the catalog. Delete it and download again.',
    ),
    'busy' => _t(
      '別のウィンドウでダウンロード中です。',
      'Already downloading in another window.',
    ),
    'disk-full' => _t('空き容量が足りません。', 'Not enough free space.'),
    'disk' => _t('ファイルを保存できませんでした。', 'Could not save the file.'),
    _ => e,
  };

  Future<void> _download(CatalogItem item) async {
    if (item.size >= largeDownloadBytes) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(item.title(en)),
          content: Text(
            _t(
              '${formatBytes(item.size)} をダウンロードします。Wi-Fi で行ってください。'
                  '空き容量が ${formatBytes(item.size)} 以上必要です。'
                  '途中で止まっても、続きから再開できます。',
              'This downloads ${formatBytes(item.size)}. Please use Wi-Fi. '
                  'You need at least ${formatBytes(item.size)} of free space. '
                  'If it stops, you can resume where it left off.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(_t('キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(_t('ダウンロード', 'Download')),
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
        title: Text(_t('削除しますか？', 'Delete?')),
        content: Text(
          _t(
            '${item.title(en)}（${formatBytes(item.size)}）を端末から削除します。'
                'オフラインでは再取得できません。',
            'Removes ${item.title(en)} (${formatBytes(item.size)}) from this '
                'device. You cannot get it back while offline.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_t('キャンセル', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(_t('削除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) await m.delete(item);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('ダウンロード', 'Downloads'))),
    body: ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final items = m.catalog.items;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SwitchListTile(
              title: Text(_t('Wi-Fi のときだけダウンロード', 'Download on Wi-Fi only')),
              subtitle: Text(
                _t(
                  'オフにするとモバイルデータも使います（数 GB になることがあります）。',
                  'When off, mobile data is used too (can be several GB).',
                ),
              ),
              value: m.wifiOnly,
              onChanged: m.setWifiOnly,
            ),
            if (m.refreshing) const LinearProgressIndicator(),
            for (final kind in ItemKind.values) ...[
              _header(kind),
              for (final i in items)
                if (i.kind == kind) _tile(i),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _t(
                  'ダウンロードしたものはすべてオフラインで使えます。'
                      'ファイルはチェックサム（SHA-256）で確認してから使います。',
                  'Everything downloaded works offline. Files are checked '
                      '(SHA-256) before the app uses them.',
                ),
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
      ItemKind.model => _t('モデル', 'Models'),
      ItemKind.package => _t('知識パッケージ', 'Knowledge packages'),
      ItemKind.map => _t('地図', 'Map areas'),
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
      if (item.note(en).isNotEmpty) item.note(en),
      if (item.desktop && _isPhone)
        _t('多くのスマートフォンには大きすぎます。', 'Too large for most phones.'),
    ];

    final status = switch (s.status) {
      ItemStatus.absent =>
        canGet
            ? _t('未ダウンロード', 'Not downloaded')
            : _t(
                'ダウンロード元が未設定（アプリ内蔵版を使用）',
                'No download source yet (uses the copy in the app)',
              ),
      ItemStatus.partial => _t(
        '一時停止中：${formatBytes(s.bytes)} / ${formatBytes(s.total)}',
        'Paused: ${formatBytes(s.bytes)} of ${formatBytes(s.total)}',
      ),
      ItemStatus.unverified => _t(
        'ファイルあり（未確認）',
        'File present (not checked yet)',
      ),
      ItemStatus.running => _runningText(s),
      ItemStatus.installed => _t('ダウンロード済み・確認済み', 'Downloaded and checked'),
      ItemStatus.update => _t(
        '新しい版があります（端末: ${s.installedVersion}）',
        'Update available (on device: ${s.installedVersion})',
      ),
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
                    item.title(en),
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
                    child: Text(_t('停止', 'Stop')),
                  ),
                if (!running && canGet && s.status == ItemStatus.absent)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(_t('ダウンロード', 'Download')),
                  ),
                if (!running && canGet && s.status == ItemStatus.partial)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(_t('再開', 'Resume')),
                  ),
                if (!running && canGet && s.status == ItemStatus.update)
                  FilledButton(
                    onPressed: () => _download(item),
                    child: Text(_t('更新', 'Update')),
                  ),
                if (!running && s.status == ItemStatus.unverified)
                  FilledButton(
                    onPressed: () => m.verifyExisting(item),
                    child: Text(_t('ファイルを確認', 'Check file')),
                  ),
                if (chatPick)
                  usedChat
                      ? Chip(label: Text(_t('使用中', 'In use')))
                      : OutlinedButton(
                          onPressed: () => m.useChatModel(item),
                          child: Text(_t('このモデルを使う', 'Use this model')),
                        ),
                if (!running && s.status != ItemStatus.absent)
                  TextButton(
                    onPressed: () => _delete(item),
                    child: Text(_t('削除', 'Delete')),
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
      DownloadPhase.checkingPart => _t(
        '途中までのファイルを確認中…',
        'Checking the part already downloaded…',
      ),
      DownloadPhase.verifying => _t(
        'チェックサムを確認中… $pct%',
        'Checking the checksum… $pct%',
      ),
      _ =>
        '$pct% · ${formatBytes(s.bytes)} / ${formatBytes(s.total)}'
            '${s.speed > 0 ? ' · ${formatBytes(s.speed.round())}/s' : ''}'
            '${s.speed > 0 ? ' · ${_eta((s.total - s.bytes) / s.speed)}' : ''}',
    };
  }

  String _eta(double seconds) {
    final m = (seconds / 60).ceil();
    if (m < 2) return _t('残り約1分', 'about 1 min left');
    return _t('残り約$m分', 'about $m min left');
  }
}
