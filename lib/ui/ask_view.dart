import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../app/brand.dart';
import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import 'breathing_light.dart';
import 'suggestions.dart';
import '../knowledge/knowledge_package.dart' show PackageInfo;

/// Where the Ask screen stands: shown as a small status pill.
enum AskPhase { noModel, loading, ready, shelter, serving, failed }

/// A developer action in the ⋮ menu (load a model file, run test questions).
class DevAction {
  const DevAction(this.label, this.onTap, {this.icon = Icons.build_outlined});
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
}

/// Home screen: status, warnings and nearest site, suggested questions,
/// recent conversations, and the question bar.
class AskView extends StatefulWidget {
  const AskView({
    super.key,
    required this.phase,
    required this.detail,
    required this.ready,
    required this.busy,
    required this.input,
    required this.onSend,
    required this.onAsk,
    required this.onStop,
    this.shelterName,
    this.recent,
    this.onOpenSettings,
    this.onShowNotice,
    this.updates,
    this.onOpenDownloads,
    this.devActions = const [],
    this.detailExtra,
    this.home,
    this.packages,
    this.packageInfos = const [],
  });

  /// Shown on the empty screen above the suggestions (nearest site, warnings).
  final Widget? home;

  /// The loaded knowledge packages: they bring the suggested questions.
  final List<PackageInfo> packageInfos;

  /// Below the suggestions: the knowledge packages (see PackageRow).
  final Widget? packages;

  /// Shown under the status details, e.g. the shelter QR code.
  final Widget? detailExtra;

  final AskPhase phase;

  /// Technical status (backend, load time), shown when the pill is tapped.
  final String detail;
  final String? shelterName;
  final bool ready;
  final bool busy;
  final TextEditingController input;
  final VoidCallback onSend;
  final void Function(String) onAsk;
  final VoidCallback onStop;
  final VoidCallback? onOpenDownloads;
  final List<DevAction> devActions;

  /// Recent conversations, under the suggestions.
  final Widget? recent;

  /// First entry of the ⋮ menu.
  final VoidCallback? onOpenSettings;

  /// Second entry: the first-start notice again.
  final VoidCallback? onShowNotice;

  /// New versions of installed downloads: a badge on the ⋮ menu.
  final ValueListenable<int>? updates;

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  AppLocalizations get l => context.l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const LychnionMark(size: 34),
            const SizedBox(width: 8),
            // Gives way to the status label on narrow phones.
            Flexible(
              child: Text(
                l.appName,
                overflow: TextOverflow.ellipsis,
                style: Brand.wordmarkStyle(
                  lang: context.lang,
                  color: theme.brightness == Brightness.dark
                      ? scheme.onSurface
                      : Brand.night,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Quiet when the app is ready on this phone (the question bar
          // says enough); a chip only when a shelter computer is involved.
          if (widget.phase == AskPhase.shelter ||
              widget.phase == AskPhase.serving)
            _StatusPill(
              phase: widget.phase,
              shelterName: widget.shelterName,
              onTap: () => _showDetail(context),
            ),
          AppMenu(
            onOpenSettings: widget.onOpenSettings,
            onShowNotice: widget.onShowNotice,
            updates: widget.updates,
            devActions: [
              DevAction(
                'Status details',
                () => _showDetail(context),
                icon: Icons.monitor_heart_outlined,
              ),
              ...widget.devActions,
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _emptyState(theme)),
          QuestionBar(
            input: widget.input,
            ready: widget.ready,
            loading: widget.phase == AskPhase.loading,
            busy: widget.busy,
            onSend: widget.onSend,
            onStop: widget.onStop,
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    children: [..._home(theme), ?widget.recent],
  );

  List<Widget> _home(ThemeData theme) {
    final scheme = theme.colorScheme;
    final suggestions = suggestionsFor(widget.packageInfos, lang: context.lang);
    final needsData = widget.phase == AskPhase.noModel;
    return [
      Text(l.askHeadline, style: theme.textTheme.headlineMedium),
      const SizedBox(height: 10),
      Text(
        l.askIntro,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      if (widget.home case final h?) ...[h, const SizedBox(height: 24)],
      if (widget.phase == AskPhase.failed) ...[
        Card(
          color: scheme.errorContainer,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
            title: Text(
              l.askPhaseFailed,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            subtitle: Text(
              l.askExplainFailed,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            trailing: TextButton(
              onPressed: widget.onOpenDownloads,
              child: Text(l.downloadsTitle),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
      if (needsData)
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  l.askFirstDownload,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.askFirstDownloadText,
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.onOpenDownloads,
                  child: Text(l.askGoToDownloads),
                ),
              ],
            ),
          ),
        )
      else ...[
        Text(
          l.askTryAsking,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (final (icon, q) in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.ready ? () => widget.onAsk(q) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: scheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(q, style: theme.textTheme.bodyMedium),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: scheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
      if (widget.packages case final p?) ...[const SizedBox(height: 14), p],
      const SizedBox(height: 8),
    ];
  }

  void _showDetail(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _StatusPill.label(widget.phase, l),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (widget.phase == AskPhase.shelter && widget.shelterName != null)
            Text(
              widget.shelterName!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          Text(_StatusPill.explain(widget.phase, l)),
          const SizedBox(height: 12),
          SelectableText(
            widget.detail,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.detailExtra case final w?) ...[
            const SizedBox(height: 16),
            w,
          ],
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.phase,
    required this.onTap,
    this.shelterName,
  });

  final AskPhase phase;
  final String? shelterName;
  final VoidCallback onTap;

  static String label(AskPhase p, AppLocalizations l) => switch (p) {
    AskPhase.noModel => l.askPhaseNoModel,
    AskPhase.loading => l.askPhaseLoading,
    AskPhase.ready => l.askPhaseReady,
    // Short: the header is narrow on phones; details name the shelter.
    AskPhase.shelter => l.askPhaseShelter,
    AskPhase.serving => l.askPhaseServing,
    AskPhase.failed => l.askPhaseFailed,
  };

  static String explain(AskPhase p, AppLocalizations l) => switch (p) {
    AskPhase.noModel => l.askExplainNoModel,
    AskPhase.loading => l.askExplainLoading,
    AskPhase.ready => l.askExplainReady,
    AskPhase.shelter => l.askExplainShelter,
    AskPhase.serving => l.askExplainServing,
    AskPhase.failed => l.askExplainFailed,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (dot, bg) = switch (phase) {
      AskPhase.ready => (const Color(0xFF2E9D5B), scheme.surfaceContainerHigh),
      AskPhase.shelter ||
      AskPhase.serving => (scheme.primary, scheme.primaryContainer),
      AskPhase.failed => (scheme.error, scheme.errorContainer),
      _ => (scheme.tertiary, scheme.surfaceContainerHigh),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  phase == AskPhase.serving
                      ? Icons.qr_code_rounded
                      : Icons.cell_tower_rounded,
                  size: 16,
                  color: dot,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    phase == AskPhase.shelter && shelterName != null
                        ? '${label(phase, context.l10n)}: $shelterName'
                        : label(phase, context.l10n),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred message with an action, for screens that have nothing to show yet.
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  icon,
                  size: 30,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Question field and send / stop button, on the home and conversation
/// screens.
class QuestionBar extends StatelessWidget {
  const QuestionBar({
    super.key,
    required this.input,
    required this.ready,
    required this.busy,
    required this.onSend,
    required this.onStop,
    this.loading = false,
  });

  final TextEditingController input;
  final bool ready;

  /// The model is loading: say so where people would type.
  final bool loading;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: input,
              enabled: ready,
              textInputAction: TextInputAction.send,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: loading && !ready
                    ? context.l10n.askPhaseLoading
                    : context.l10n.askHint,
                prefixIcon: loading && !ready
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: BreathingLight(size: 20),
                      )
                    : const Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          busy && !loading
              ? IconButton.filledTonal(
                  tooltip: context.l10n.askStop,
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                )
              : IconButton.filled(
                  tooltip: context.l10n.askSend,
                  onPressed: ready ? onSend : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
        ],
      ),
    ),
  );
}

/// ⋮ menu: settings, what the app can and cannot do, developer actions.
class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    this.onOpenSettings,
    this.onShowNotice,
    this.updates,
    this.devActions = const [],
  });

  /// New versions of installed downloads: a badge on the menu and on
  /// Settings.
  final ValueListenable<int>? updates;

  final VoidCallback? onOpenSettings;

  /// The first-start notice again ("Before you start").
  final VoidCallback? onShowNotice;
  final List<DevAction> devActions;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    icon: ValueListenableBuilder(
      valueListenable: updates ?? ValueNotifier(0),
      builder: (context, n, _) => Badge(
        isLabelVisible: n > 0,
        smallSize: 9,
        child: const Icon(Icons.more_vert),
      ),
    ),
    itemBuilder: (_) => [
      if (onOpenSettings != null)
        PopupMenuItem(
          value: -1,
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(context.l10n.settings),
          ),
        ),
      if (onShowNotice != null)
        PopupMenuItem(
          value: -2,
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(context.l10n.beforeYouStart),
          ),
        ),
      if (devActions.isNotEmpty) ...[
        const PopupMenuDivider(),
        // Developer tools: labelled, so nobody mistakes them for features.
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('Developer', style: TextStyle(fontSize: 12)),
        ),
      ],
      for (var i = 0; i < devActions.length; i++)
        PopupMenuItem(
          value: i,
          enabled: devActions[i].onTap != null,
          child: ListTile(
            dense: true,
            leading: Icon(devActions[i].icon),
            title: Text(devActions[i].label),
          ),
        ),
    ],
    onSelected: (i) => switch (i) {
      -1 => onOpenSettings?.call(),
      -2 => onShowNotice?.call(),
      _ => devActions[i].onTap?.call(),
    },
  );
}
