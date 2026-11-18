import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';
import '../ui/help_screen.dart';

import '../download/download_manager.dart';
import '../download/download_store.dart' show MobileData, UpdateMode;
import '../download/catalogs_screen.dart';
import '../download/downloads_screen.dart';
import '../download/publishers_screen.dart';
import '../l10n/app_localizations.dart';
import '../knowledge/knowledge_package.dart' show PackageInfo;
import '../util/versioned_file.dart';
import 'settings.dart';
import 'versions.dart';
import 'brand.dart';
import 'lang.dart';
import 'notices.dart';

/// Four groups: language, shelter, offline data, about (with developer
/// options one level down).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.downloads,
    this.shelter,
    this.onShareNearby,
    this.region,
    this.userRegion,
    this.bundledPackages,
  });

  /// The packages shipped with the app, for the versions in About.
  final Future<List<PackageInfo>> Function()? bundledPackages;

  final AppSettings settings;
  final DownloadManager? downloads;

  /// Shelter section: the QR code on a shelter computer, else connect.
  final Widget? shelter;

  /// Phones: pass on downloads to phones nearby.
  final VoidCallback? onShareNearby;

  /// The region local sources are ranked for (RegionTile).
  final Widget? region;

  /// For Downloads: items for the user's region first.
  final Future<String> Function()? userRegion;

  /// Segment value for "follow the device".
  static const _device = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings),
        actions: [
          IconButton(
            tooltip: l.helpTitle,
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => HelpScreen.open(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            ValueListenableBuilder(
              valueListenable: keptAside,
              builder: (context, files, _) => files.isEmpty
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: Text(l.settingsKeptAside(files.join(', '))),
                    ),
            ),
            _Group(
              title: l.settingsLanguage,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: _device,
                          label: Text(l.settingsLanguageDevice),
                        ),
                        // Each language by its own name.
                        for (final code in appLanguages)
                          ButtonSegment(
                            value: code,
                            label: Text(
                              lookupAppLocalizations(Locale(code)).languageName,
                            ),
                          ),
                      ],
                      selected: {settings.language ?? _device},
                      onSelectionChanged: (s) => settings.setLanguage(
                        s.first == _device ? null : s.first,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (region != null)
              _Group(title: l.settingsRegion, children: [region!]),
            if (shelter != null)
              _Group(title: l.settingsShelter, children: [shelter!]),
            _Group(
              title: l.settingsOfflineData,
              children: [
                _NavTile(
                  icon: Icons.download_for_offline_outlined,
                  badge: downloads?.updates,
                  title: l.downloadsTitle,
                  subtitle: l.settingsDownloadsHint,
                  onTap: downloads == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DownloadsScreen(
                              manager: downloads!,
                              userRegion: userRegion,
                            ),
                          ),
                        ),
                ),
                if (downloads != null)
                  _NavTile(
                    icon: Icons.badge_outlined,
                    title: l.publishersTitle,
                    subtitle: l.publishersHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PublishersScreen(manager: downloads!),
                      ),
                    ),
                  ),
                if (downloads != null)
                  _NavTile(
                    icon: Icons.list_alt_rounded,
                    title: l.catalogsTitle,
                    subtitle: l.catalogsHint(l.appName),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CatalogsScreen(manager: downloads!),
                      ),
                    ),
                  ),
                if (onShareNearby != null)
                  _NavTile(
                    icon: Icons.share_rounded,
                    title: l.shareNearby,
                    subtitle: l.shareNearbyHint,
                    onTap: onShareNearby,
                  ),
                if (downloads != null)
                  ListenableBuilder(
                    listenable: downloads!,
                    builder: (context, _) => _NavTile(
                      icon: Icons.signal_cellular_alt_rounded,
                      title: l.downloadsSettings,
                      subtitle:
                          '${l.downloadsMobileData}: ${switch (downloads!.mobileData) {
                            MobileData.never => l.downloadsMobileNever,
                            MobileData.ask => l.downloadsMobileAsk,
                            MobileData.always => l.downloadsMobileAlways,
                          }} · ${l.downloadsUpdates}: ${switch (downloads!.updateMode) {
                            UpdateMode.auto => l.downloadsUpdatesAuto,
                            UpdateMode.notify => l.downloadsUpdatesNotify,
                            UpdateMode.off => l.downloadsUpdatesOff,
                          }}',
                      onTap: () => showMobileDataSheet(context, downloads!),
                    ),
                  ),
              ],
            ),
            _Group(
              title: l.settingsAboutGroup,
              children: [
                _NavTile(
                  icon: Icons.info_outline_rounded,
                  title: l.settingsAboutApp(l.appName),
                  subtitle: l.settingsAboutAppHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _AboutPage(
                        settings: settings,
                        bundledPackages: bundledPackages,
                      ),
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
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// A count shown on the icon while above zero (e.g. updates).
  final ValueListenable<int>? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: ValueListenableBuilder(
          valueListenable: badge ?? ValueNotifier(0),
          builder: (context, n, _) => Badge.count(
            count: n,
            isLabelVisible: n > 0,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.settings, this.bundledPackages});

  final AppSettings settings;
  final Future<List<PackageInfo>> Function()? bundledPackages;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget point(IconData icon, String title, String text) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: text.isEmpty ? null : Text(text),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsAboutApp(l.appName))),
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
                          l.aboutTagline,
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
              title: l.aboutHowItWorks,
              children: [
                point(
                  Icons.wifi_off_rounded,
                  l.aboutOffline,
                  l.aboutOfflineText,
                ),
                point(
                  Icons.menu_book_outlined,
                  l.aboutCheckable,
                  l.aboutCheckableText,
                ),
                point(Icons.campaign_outlined, l.aboutFacts, l.aboutFactsText),
              ],
            ),
            _Group(
              title: l.aboutPleaseNote,
              children: [
                for (final (icon, text) in appNotice(l)) point(icon, text, ''),
                point(
                  Icons.science_outlined,
                  l.aboutPrototype,
                  l.aboutPrototypeText,
                ),
              ],
            ),
            _VersionSection(bundledPackages: bundledPackages),
            _Group(
              title: l.aboutOpenSource,
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
                  title: Text(l.aboutSourceCode),
                  subtitle: Text(l.aboutSourceCodeText),
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
                  title: Text(l.aboutLicences),
                  subtitle: Text(l.aboutLicencesText),
                  onTap: () async {
                    final v = await Versions.load(context.lang);
                    if (!context.mounted) return;
                    showLicensePage(
                      context: context,
                      applicationName: l.appName,
                      applicationVersion: l.aboutVersionValue(v.app, v.build),
                      applicationLegalese:
                          '© the Lychnion authors · GNU AGPL v3 '
                          '(app store exception)\n${Brand.sourceUrl}',
                    );
                  },
                ),
              ],
            ),
            _Group(
              title: l.aboutDeveloper,
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l.aboutShowStats),
                  subtitle: Text(l.aboutShowStatsHint),
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

/// The app's version and the installed guides, maps and models. A long
/// press copies them all for a report.
class _VersionSection extends StatefulWidget {
  const _VersionSection({this.bundledPackages});

  final Future<List<PackageInfo>> Function()? bundledPackages;

  @override
  State<_VersionSection> createState() => _VersionSectionState();
}

class _VersionSectionState extends State<_VersionSection> {
  Future<Versions>? _versions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _versions ??= Versions.load(context.lang, bundled: widget.bundledPackages);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<Versions>(
      future: _versions,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const SizedBox(height: 8);
        Future<void> copy() async {
          await Clipboard.setData(ClipboardData(text: v.report(l.appName)));
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.aboutCopied)));
        }

        return _Group(
          title: l.aboutVersion,
          children: [
            ListTile(
              leading: Icon(
                Icons.tag_rounded,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.aboutVersionValue(v.app, v.build)),
              subtitle: Text(l.aboutCopyHint, style: muted),
              onLongPress: copy,
            ),
            if (v.data.isNotEmpty)
              ListTile(
                leading: Icon(
                  Icons.inventory_2_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(l.aboutData),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (t, ver) in v.data)
                      Text('$t  $ver', style: muted),
                  ],
                ),
                onLongPress: copy,
              ),
          ],
        );
      },
    );
  }
}
