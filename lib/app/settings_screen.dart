import 'package:flutter/material.dart';

import '../download/download_manager.dart';
import '../download/downloads_screen.dart';
import 'settings.dart';

/// Language, offline data and information about the app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.downloads,
    required this.en,
  });

  final AppSettings settings;
  final DownloadManager? downloads;
  final bool en;

  String _t(String ja, String english) => en ? english : ja;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('設定', 'Settings'))),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _section(context, _t('言語', 'Language')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<AppLanguage>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppLanguage.system,
                    label: Text(_t('端末に合わせる', 'Device')),
                  ),
                  const ButtonSegment(
                    value: AppLanguage.ja,
                    label: Text('日本語'),
                  ),
                  const ButtonSegment(
                    value: AppLanguage.en,
                    label: Text('English'),
                  ),
                ],
                selected: {settings.language},
                onSelectionChanged: (s) => settings.setLanguage(s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                _t(
                  '回答は質問と同じ言語で表示されます。',
                  'Answers use the language of the question.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            _section(context, _t('オフラインデータ', 'Offline data')),
            _tile(
              context,
              icon: Icons.download_for_offline_outlined,
              title: _t('ダウンロード', 'Downloads'),
              subtitle: _t(
                'AIモデル・防災の資料・地図',
                'AI models, safety guides and maps',
              ),
              onTap: downloads == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DownloadsScreen(manager: downloads!, english: en),
                      ),
                    ),
            ),
            _section(context, _t('このアプリについて', 'About')),
            _tile(
              context,
              icon: Icons.wifi_off_rounded,
              title: _t('インターネットなしで動作', 'Works without internet'),
              subtitle: _t(
                '質問への回答、地図、避難場所の検索はすべて端末の中で行います。',
                'Answers, the map and evacuation sites all work on this device.',
              ),
            ),
            _tile(
              context,
              icon: Icons.menu_book_outlined,
              title: _t('出典を確認できる回答', 'Answers you can check'),
              subtitle: _t(
                '回答は公的機関の資料にもとづき、出典を表示します。資料にないことには答えません。',
                'Answers come from official guides and show their source. '
                    'The app does not answer what the guides do not cover.',
              ),
            ),
            _tile(
              context,
              icon: Icons.science_outlined,
              title: _t('試作版', 'Prototype'),
              subtitle: _t(
                '研究用の試作版です。緊急時は自治体・気象庁などの公式情報に従ってください。',
                'A research prototype. In an emergency, follow official '
                    'information from your city and the Japan Meteorological Agency.',
              ),
            ),
            _section(context, _t('開発者向け', 'Developer')),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(_t('速度とメモリを表示', 'Show speed and memory')),
              value: settings.showStats,
              onChanged: settings.setShowStats,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
