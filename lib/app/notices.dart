import 'package:flutter/material.dart';

import '../knowledge/knowledge_package.dart' show PackageInfo;
import '../ui/package_row.dart';
import 'brand.dart';
import 'settings.dart';

/// Version of the app notice: raise it when the wording changes in a way
/// people should read again.
const appNoticeKey = 'app:1';

/// What the app is and is not, in a few lines. Kept short on purpose: in a
/// disaster, someone opening the app for the first time must get to the
/// answers quickly.
List<(IconData, String)> appNotice({required bool en}) => en
    ? const [
        (
          Icons.auto_awesome_outlined,
          'Answers are written by AI from public sources. AI can make '
              'mistakes: check the source shown with each answer.',
        ),
        (
          Icons.campaign_outlined,
          'Instructions from your city, the Japan Meteorological Agency, '
              'police and fire service, and people on site who know, come first.',
        ),
        (
          Icons.local_hospital_outlined,
          'It does not replace a doctor, and it is not a planning tool for '
              'hikes or tours.',
        ),
        (
          Icons.record_voice_over_outlined,
          'When unsure, ask someone who knows. In an emergency call 119 '
              '(ambulance, fire) or 110 (police).',
        ),
        (
          Icons.wifi_off_rounded,
          'It works without internet, so its information may not be the '
              'latest. It does not answer what its sources do not cover.',
        ),
      ]
    : const [
        (
          Icons.auto_awesome_outlined,
          '回答は、公的な資料をもとにAIが作ります。AIはまちがえることがあります。回答といっしょに表示する出典を確かめてください。',
        ),
        (Icons.campaign_outlined, '自治体・気象庁・警察・消防の指示や、その場にいる、わかる人の判断を優先してください。'),
        (
          Icons.local_hospital_outlined,
          '医師の診察の代わりにはなりません。登山やツアーの計画を立てるためのアプリでもありません。',
        ),
        (
          Icons.record_voice_over_outlined,
          '迷ったときは、わかる人に聞いてください。命に関わるときは119（救急・火事）、110（警察）へ。',
        ),
        (
          Icons.wifi_off_rounded,
          'インターネットなしで使えるため、情報が最新とは限りません。資料にないことには答えません。',
        ),
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
      widget
          .packages()
          .then((p) => mounted ? setState(() => _packages = p) : null)
          .catchError((Object _) => null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      if (widget.settings.hasAcknowledged(appNoticeKey)) return widget.child;
      final en = Localizations.localeOf(context).languageCode != 'ja';
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: NoticeScreen(
              en: en,
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
    required this.en,
    required this.packages,
    required this.onAccept,
  });

  final bool en;
  final List<PackageInfo> packages;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    en ? 'Before you start' : 'ご利用の前に',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  for (final (icon, text) in appNotice(en: en))
                    NoticeLine(icon: icon, text: text),
                  if (packages.any((p) => p.notice.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Text(
                      en ? 'About the guides' : '入っている資料について',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final p in packages)
                      if (p.notice.isNotEmpty) PackageNotice(info: p, en: en),
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
                  child: Text(en ? 'I understand' : 'わかりました'),
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
  const PackageNotice({super.key, required this.info, required this.en});

  final PackageInfo info;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, name) = PackageRow.label(info, en);
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
                for (final line in info.noticeIn(en: en))
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
  List<PackageInfo> packages, {
  required bool en,
}) async {
  final fresh = [
    for (final p in packages)
      if (p.notice.isNotEmpty && !settings.hasAcknowledged(p.noticeKey)) p,
  ];
  if (fresh.isEmpty || !settings.hasAcknowledged(appNoticeKey)) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(en ? 'New guides' : '新しい資料'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final p in fresh) PackageNotice(info: p, en: en)],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text(en ? 'I understand' : 'わかりました'),
        ),
      ],
    ),
  );
  await settings.acknowledge([for (final p in fresh) p.noticeKey]);
}
