import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../download/download_manager.dart';
import '../download/downloads_screen.dart';
import 'settings.dart';
import 'brand.dart';
import 'notices.dart';

/// Four groups: language, shelter, offline data, about (with developer
/// options one level down).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.downloads,
    required this.en,
    this.shelter,
  });

  final AppSettings settings;
  final DownloadManager? downloads;
  final bool en;

  /// Shelter section: the QR code on a shelter computer, else connect.
  final Widget? shelter;

  String _t(String ja, String english) => en ? english : ja;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('設定', 'Settings'))),
    body: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Group(
            title: _t('言語', 'Language'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppLanguage>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AppLanguage.system,
                        label: Text(_t('端末の設定', 'Device')),
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
              ),
            ],
          ),
          if (shelter != null)
            _Group(title: _t('避難所', 'Shelter'), children: [shelter!]),
          _Group(
            title: _t('オフラインデータ', 'Offline data'),
            children: [
              _NavTile(
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
            ],
          ),
          _Group(
            title: _t('このアプリについて', 'About'),
            children: [
              _NavTile(
                icon: Icons.info_outline_rounded,
                title: _t('${Brand.nameJa}について', 'About ${Brand.name}'),
                subtitle: _t(
                  'しくみ・ご注意・オープンソース',
                  'How it works, notes, open source',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _AboutPage(settings: settings, en: en),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A titled, rounded group of settings.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.settings, required this.en});

  final AppSettings settings;
  final bool en;

  String _t(String ja, String english) => en ? english : ja;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget point(IconData icon, String title, String text) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: text.isEmpty ? null : Text(text),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('${Brand.nameJa}について', 'About ${Brand.name}')),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Row(
                children: [
                  const LychnionMark(size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${Brand.name} · ${Brand.nameJa}',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          _t(
                            'ギリシャ語で「小さな灯り」。ネットが止まっても使えるガイドです。',
                            'Greek for "small lamp": a guide that keeps working when the network is down.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Group(
              title: _t('しくみ', 'How it works'),
              children: [
                point(
                  Icons.wifi_off_rounded,
                  _t('インターネットなしで動作', 'Works without internet'),
                  _t(
                    '質問への回答、地図、避難場所の検索はすべて端末の中で行います。',
                    'Answers, the map and evacuation sites all work on this device.',
                  ),
                ),
                point(
                  Icons.menu_book_outlined,
                  _t('出典を確認できる回答', 'Answers you can check'),
                  _t(
                    '回答は公的機関の資料にもとづき、出典を表示します。資料にないことには答えません。',
                    'Answers come from official guides and show their source. '
                        'The app does not answer what the guides do not cover.',
                  ),
                ),
                point(
                  Icons.campaign_outlined,
                  _t('最新の情報はAIと分けて表示', 'Current information kept apart'),
                  _t(
                    '避難所の状況や通行止めは、時刻と発信元つきでそのまま表示します。AIは書き換えません。',
                    'Shelter status and blocked roads are shown as reported, with time '
                        'and source. The AI never rewrites them.',
                  ),
                ),
              ],
            ),
            _Group(
              title: _t('ご注意', 'Please note'),
              children: [
                for (final (icon, text) in appNotice(en: en))
                  point(icon, text, ''),
                point(
                  Icons.science_outlined,
                  _t('試作版', 'Prototype'),
                  _t(
                    '研究用の試作版です。緊急時は自治体・気象庁などの公式情報に従ってください。',
                    'A research prototype. In an emergency, follow official '
                        'information from your city and the Japan Meteorological Agency.',
                  ),
                ),
              ],
            ),
            _Group(
              title: _t('オープンソース', 'Open source'),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Icon(
                    Icons.code_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(_t('ソースコード', 'Source code')),
                  subtitle: Text(
                    _t(
                      'だれでも中身を確認・改良できます（GNU AGPL v3）。'
                          '配布する人は、利用者にソースコードを提供する義務があります。',
                      'Anyone can check and improve how it works (GNU AGPL v3). '
                          'Whoever passes it on must give users the source code.',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(Brand.sourceUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(
                    Icons.gavel_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(_t('ライセンス', 'Licences')),
                  subtitle: Text(
                    _t(
                      'アプリ、使用しているソフトウェアとフォント',
                      'The app, the software and fonts it uses',
                    ),
                  ),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: Brand.nameIn(en: en),
                    applicationLegalese:
                        '© the Lychnion authors · GNU AGPL v3 '
                        '(app store exception)\n${Brand.sourceUrl}',
                  ),
                ),
              ],
            ),
            _Group(
              title: _t('開発者向け', 'Developer'),
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(_t('速度とメモリを表示', 'Show speed and memory')),
                  subtitle: Text(_t('回答の下に表示します。', 'Shown under each answer.')),
                  value: settings.showStats,
                  onChanged: settings.setShowStats,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
