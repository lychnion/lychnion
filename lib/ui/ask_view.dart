import 'package:flutter/material.dart';

/// Where the Ask screen stands: shown as a small status pill.
enum AskPhase { noModel, loading, ready, shelter, serving, failed }

/// A developer action in the ⋮ menu (load a model file, run test questions).
class DevAction {
  const DevAction(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;
}

/// Suggested first questions, covered by the core knowledge package.
const _suggestionsJa = [
  (Icons.waves_rounded, '海の近くで強い揺れを感じたら？'),
  (Icons.healing_rounded, 'けがをして出血しているときは？'),
  (Icons.water_drop_outlined, '非常用の水はどれくらい必要？'),
  (Icons.forest_outlined, '山でクマに出会ったら？'),
];
const _suggestionsEn = [
  (Icons.waves_rounded, 'Strong shaking near the sea: what should I do?'),
  (Icons.healing_rounded, 'How do I stop heavy bleeding?'),
  (Icons.water_drop_outlined, 'How much emergency water do I need?'),
  (Icons.forest_outlined, 'What if I meet a bear in the mountains?'),
];

/// The Ask screen: header with status, conversation, input bar.
class AskView extends StatefulWidget {
  const AskView({
    super.key,
    required this.en,
    required this.phase,
    required this.detail,
    required this.ready,
    required this.busy,
    required this.input,
    required this.onSend,
    required this.onAsk,
    required this.onStop,
    required this.itemCount,
    required this.itemBuilder,
    this.shelterName,
    this.onOpenDownloads,
    this.devActions = const [],
  });

  final bool en;
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
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  bool get en => widget.en;
  String _t(String ja, String english) => en ? english : ja;

  @override
  void didUpdateWidget(AskView old) {
    super.didUpdateWidget(old);
    if (widget.itemCount != _lastCount) {
      _lastCount = widget.itemCount;
      // A new question: bring it into view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('fieldkit'),
          ],
        ),
        actions: [
          _StatusPill(
            phase: widget.phase,
            en: en,
            shelterName: widget.shelterName,
            onTap: () => _showDetail(context),
          ),
          if (widget.devActions.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: _t('開発者向け', 'Developer'),
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                for (var i = 0; i < widget.devActions.length; i++)
                  PopupMenuItem(
                    value: i,
                    enabled: widget.devActions[i].onTap != null,
                    child: Text(widget.devActions[i].label),
                  ),
              ],
              onSelected: (i) => widget.devActions[i].onTap?.call(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.itemCount == 0
                ? _emptyState(theme)
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: widget.itemCount,
                    separatorBuilder: (_, _) => const SizedBox(height: 20),
                    itemBuilder: widget.itemBuilder,
                  ),
          ),
          _inputBar(theme),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    final scheme = theme.colorScheme;
    final suggestions = en ? _suggestionsEn : _suggestionsJa;
    final needsData = widget.phase == AskPhase.noModel;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      children: [
        Text(
          _t('もしものときに、\nすぐ聞ける。', 'Ask anything,\neven offline.'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _t(
            '防災と応急手当の公的な資料をもとに、インターネットなしで答えます。出典もいっしょに表示します。',
            'Answers from official safety guides, without internet, '
                'with the source for every answer.',
          ),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
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
                    _t('はじめに：データをダウンロード', 'First: download the data'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t(
                      'Wi-Fi のあるときに一度だけ。その後はオフラインで使えます。',
                      'Once, on Wi-Fi. After that everything works offline.',
                    ),
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: widget.onOpenDownloads,
                    child: Text(_t('ダウンロードへ', 'Go to downloads')),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Text(
            _t('たとえば', 'Try asking'),
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
                          child: Text(q, style: theme.textTheme.bodyLarge),
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
      ],
    );
  }

  Widget _inputBar(ThemeData theme) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.input,
              enabled: widget.ready,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: _t('質問を入力', 'Ask a question'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) => widget.onSend(),
            ),
          ),
          const SizedBox(width: 8),
          widget.busy
              ? IconButton.filledTonal(
                  tooltip: _t('停止', 'Stop'),
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop_rounded),
                )
              : IconButton.filled(
                  tooltip: _t('送信', 'Send'),
                  onPressed: widget.ready ? widget.onSend : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
        ],
      ),
    ),
  );

  void _showDetail(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _StatusPill.label(widget.phase, en, widget.shelterName),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_StatusPill.explain(widget.phase, en)),
          const SizedBox(height: 12),
          SelectableText(
            widget.detail,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.phase,
    required this.en,
    required this.onTap,
    this.shelterName,
  });

  final AskPhase phase;
  final bool en;
  final String? shelterName;
  final VoidCallback onTap;

  static String label(AskPhase p, bool en, String? shelter) => switch (p) {
    AskPhase.noModel => en ? 'Setup needed' : '準備が必要',
    AskPhase.loading => en ? 'Getting ready…' : '準備中…',
    AskPhase.ready => en ? 'Offline ready' : 'オフラインで利用可',
    AskPhase.shelter =>
      en ? 'Shelter: ${shelter ?? ''}' : '避難所に接続：${shelter ?? ''}',
    AskPhase.serving => en ? 'Shelter computer' : '避難所の端末',
    AskPhase.failed => en ? 'Not ready' : '利用できません',
  };

  static String explain(AskPhase p, bool en) => switch (p) {
    AskPhase.noModel =>
      en
          ? 'Download the AI model and the safety guides under Settings → Downloads.'
          : '「設定」→「ダウンロード」でAIモデルと資料を取得してください。',
    AskPhase.loading =>
      en ? 'Loading the AI model on this device.' : 'この端末でAIモデルを読み込んでいます。',
    AskPhase.ready =>
      en
          ? 'The AI runs on this device. No internet is needed.'
          : 'AIはこの端末の中で動いています。インターネットは不要です。',
    AskPhase.shelter =>
      en
          ? 'A computer at the shelter answers, over the local Wi-Fi. Faster than this phone.'
          : '避難所のコンピューターが、施設内のWi-Fiで回答します。この端末より速く答えます。',
    AskPhase.serving =>
      en
          ? 'This computer answers phones on the local network, and shares current information.'
          : 'この端末が、施設内のスマートフォンからの質問に答え、最新の情報を共有します。',
    AskPhase.failed =>
      en ? 'The AI model could not be loaded.' : 'AIモデルを読み込めませんでした。',
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
                if (phase == AskPhase.loading)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: dot,
                    ),
                  )
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label(phase, en, shelterName),
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
