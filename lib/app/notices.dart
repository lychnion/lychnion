import 'dart:async';

import 'package:flutter/material.dart';

import '../knowledge/knowledge_package.dart' show PackageInfo;
import '../l10n/app_localizations.dart';
import '../ui/package_row.dart';
import 'brand.dart';
import 'lang.dart';
import 'settings.dart';

/// Version of the app notice: raise it when the wording changes in a way
/// people should read again.
const appNoticeKey = 'app:1';

/// What the app is and is not, in a few lines. Kept short on purpose: in a
/// disaster, someone opening the app for the first time must get to the
/// answers quickly.
List<(IconData, String)> appNotice(AppLocalizations l) => [
  (Icons.auto_awesome_outlined, l.noticeAi),
  (Icons.campaign_outlined, l.noticeOfficialFirst),
  (Icons.local_hospital_outlined, l.noticeNotADoctor),
  (Icons.record_voice_over_outlined, l.noticeAsk),
  (Icons.wifi_off_rounded, l.noticeOffline),
];

/// First start: the app notice and the notices of the built-in packages,
/// one tap to continue. Covers the home page, which loads underneath.
class NoticeGate extends StatefulWidget {
  const NoticeGate({
    super.key,
    required this.settings,
    required this.packages,
    required this.child,
  });

  final AppSettings settings;

  /// The built-in packages (read only for their notices).
  final Future<List<PackageInfo>> Function() packages;
  final Widget child;

  @override
  State<NoticeGate> createState() => _NoticeGateState();
}

class _NoticeGateState extends State<NoticeGate> {
  List<PackageInfo> _packages = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.settings.hasAcknowledged(appNoticeKey)) {
      unawaited(
        widget
            .packages()
            .then((p) => mounted ? setState(() => _packages = p) : null)
            .catchError((Object _) => null),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      if (widget.settings.hasAcknowledged(appNoticeKey)) return widget.child;
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: NoticeScreen(
              packages: _packages,
              onAccept: () => widget.settings.acknowledge([
                appNoticeKey,
                for (final p in _packages) p.noticeKey,
              ]),
            ),
          ),
        ],
      );
    },
  );
}

class NoticeScreen extends StatelessWidget {
  const NoticeScreen({
    super.key,
    required this.packages,
    required this.onAccept,
  });

  final List<PackageInfo> packages;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: LychnionMark(size: 44),
                  ),
                  const SizedBox(height: 16),
                  Text(l.beforeYouStart, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  for (final (icon, text) in appNotice(l))
                    NoticeLine(icon: icon, text: text),
                  if (packages.any((p) => p.notice.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Text(
                      l.noticeAboutGuides,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final p in packages)
                      if (p.notice.isNotEmpty) PackageNotice(info: p),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAccept,
                  child: Text(l.iUnderstand),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeLine extends StatelessWidget {
  const NoticeLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// One package's name and what it is not for.
class PackageNotice extends StatelessWidget {
  const PackageNotice({super.key, required this.info});

  final PackageInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.lang;
    final (icon, name) = PackageRow.label(info, lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleSmall),
                for (final line in info.noticeIn(lang))
                  Text(line, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A package loaded for the first time (or with a changed notice): show
/// its notice once, then remember it.
Future<void> showPackageNotices(
  BuildContext context,
  AppSettings settings,
  List<PackageInfo> packages,
) async {
  final fresh = [
    for (final p in packages)
      if (p.notice.isNotEmpty && !settings.hasAcknowledged(p.noticeKey)) p,
  ];
  if (fresh.isEmpty || !settings.hasAcknowledged(appNoticeKey)) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(c.l10n.noticeNewGuides),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final p in fresh) PackageNotice(info: p)],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text(c.l10n.iUnderstand),
        ),
      ],
    ),
  );
  await settings.acknowledge([for (final p in fresh) p.noticeKey]);
}
