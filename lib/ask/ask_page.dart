import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lychnion_format/lychnion_format.dart' show attesterPublisher;
import 'package:path_provider/path_provider.dart';

import '../app/dev_flags.dart';
import '../app/lang.dart';
import '../app/notices.dart';
import '../app/region.dart';
import '../app/settings.dart';
import '../download/catalog.dart';
import '../download/download_store.dart';
import '../ui/source_label_text.dart';
import '../download/publisher_list.dart' show cleanShownText;
import '../facts/compact_codec.dart';
import '../facts/fact_store.dart';
import '../knowledge/app_help.dart';
import '../knowledge/bundled_packages.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/hybrid_retriever.dart';
import '../knowledge/knowledge_package.dart';
import '../llm/engines.dart';
import '../llm/local_embedder.dart';
import '../llm/local_llm.dart';
import '../map/map_state.dart';
import '../base/answer_signing.dart' show BadAnswerSignature;
import '../base/base_discovery.dart';
import '../base/share_nearby.dart';
import '../base/base_checks.dart';
import '../base/base_client.dart';
import '../base/base_library.dart';
import '../base/base_link.dart';
import '../base/base_panel.dart';
import '../base/base_server.dart';
import '../spike/bench_prompts.dart';
import '../spike/eval_questions.dart';
import '../ui/announce.dart';
import '../ui/answer_card.dart';
import '../ui/ask_view.dart';
import '../ui/conversation_page.dart';
import '../ui/first_steps.dart';
import '../ui/guided_tour.dart';
import '../ui/nearest_card.dart';
import '../ui/package_row.dart';
import '../ui/suggestions.dart';
import '../ui/thread_list.dart';
import '../ui/threads.dart';
import '../util/paths.dart';
import 'answer_rules.dart';

part 'base_sharing.dart';
part 'first_steps_hookup.dart';
part 'model_loading.dart';
part 'base_connection.dart';

enum AskPageView { home, conversations }

/// Home and the conversations: asks the base or the model on
/// this device, and shares this computer as a base.
class AskPage extends StatefulWidget {
  const AskPage({
    super.key,
    this.map,
    this.onShowOnMap,
    this.onDemoDone,
    this.onBaseCatalog,
    this.downloadChanges,
    this.facts,
    this.settings,
    this.onOpenDownloads,
    this.baseUrls,
    this.updates,
    this.view = AskPageView.home,
    this.onOpenSettings,
    this.onShowAsk,
    this.tourKeys,
    this.onScreen = true,
  });

  /// Whether Home is the tab on screen (the map tab keeps it built).
  final bool onScreen;

  /// The parts of the screen the guided tour points at.
  final TourKeys? tourKeys;

  /// Home screen or the list of conversations (Ask tab).
  final AskPageView view;
  final VoidCallback? onOpenSettings;

  /// "See all" on the home screen: switch to the Ask tab.
  final VoidCallback? onShowAsk;

  /// Set by the base computer: its addresses, for the QR code.
  final ValueNotifier<List<String>>? baseUrls;

  /// New versions of installed downloads (badge on the ⋮ menu).
  final ValueListenable<int>? updates;

  final MapState? map;
  final FactStore? facts;
  final AppSettings? settings;
  final VoidCallback? onOpenDownloads;

  /// Fires when downloads change; the downloaded model is (re)loaded.
  final Listenable? downloadChanges;
  final void Function()? onShowOnMap;
  final Future<void> Function(List<GroundedAnswer>)? onDemoDone;

  /// Connected to a base: its catalog address, for Downloads.
  final void Function(Uri catalog)? onBaseCatalog;

  @override
  State<AskPage> createState() => _AskPageState();
}

/// State shared by [_AskPageState] and its parts: the model, the
/// conversations, and what the home screen shows.
abstract class _AskPageBase extends State<AskPage> {
  final _llm = LocalLlm();

  final _threads = ThreadStore();

  /// The open conversation; new questions go here.
  Thread? _current;
  List<GroundedAnswer> get _entries => _current?.entries ?? const [];

  /// Bumped on every setState, so an open conversation page rebuilds.
  final _tick = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _tick.value++;
  }

  GroundedAnswerer? _answerer;

  String _status = 'No model loaded. / モデル未読み込み（「ダウンロード」から取得）';
  AskPhase _phase = AskPhase.noModel;

  /// The knowledge packages answers come from (shown on the home screen).
  List<PackageInfo> _packages = const [];

  /// Loading the phone's own model, and answering a question: separate,
  /// so the base can answer while the phone's model still loads.
  bool _loadingModel = false;
  bool _answering = false;
  bool get _busy => _loadingModel || _answering;

  /// The phase when no base answers: loading, ready only when the model
  /// and the guides are loaded, failed when the model loaded without
  /// them, else no model (#65).
  AskPhase get _ownPhase => ownPhase(
    loading: _loadingModel,
    modelLoaded: _llm.isLoaded,
    guidesLoaded: _answerer != null,
  );

  /// Phone side: the base to ask first (BASE_URL, or the
  /// one saved in settings from a QR code or a typed address).
  BaseClient? _base;
  bool _baseReady = false;

  /// Desktop side: answers phones on the local network.
  BaseServer? _server;

  bool get _usesDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// The app's log line. Release builds leave out the question, answer
  /// and region unless a dev define asks for them (#71, [loggable]).
  void _log(Map<String, Object?> data) =>
      debugPrint('LYCHNION ${jsonEncode(loggable(data))}');

  // Implemented by the state and its parts.
  Thread _startThread();
  void _answerWaiting();

  /// Answers [question] in the open conversation. The state's version also
  /// takes `into:`, a conversation to answer in instead.
  Future<void> _ask(String question);
  Future<void> _syncServer();
}

class _AskPageState extends _AskPageBase
    with _ModelLoading, _BaseSharing, _BaseConnection, _FirstStepsHookup {
  final _input = TextEditingController();
  final _threadInput = TextEditingController();

  /// Starts a conversation and shows it.
  @override
  Thread _startThread() {
    final t = _threads.create();
    _openThread(t);
    return t;
  }

  void _openThread(Thread t) {
    _current = t;
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (context) => ValueListenableBuilder(
                valueListenable: _tick,
                builder: (context, _, _) => _conversation(context, t),
              ),
            ),
          )
          .then((_) {
            if (identical(_current, t)) _current = null;
            setState(() {});
          }),
    );
  }

  /// Questions asked before anything could answer them, shown in their
  /// conversation, answered in order as soon as the base or the model
  /// is ready. A tap is never lost.
  final _waiting = <(Thread, String, GroundedAnswer)>[];

  bool get _canAnswer => _ownAnswers || _baseReady;

  /// This device answers by itself: the chat model and the guides (the
  /// answerer) are loaded (answersOnDevice, #65).
  bool get _ownAnswers => answersOnDevice(
    modelLoaded: _llm.isLoaded,
    guidesLoaded: _answerer != null,
  );

  @override
  void _answerWaiting() {
    if (_waiting.isEmpty || _answering || !mounted) return;
    // Nothing can answer: wait while the model or guides still load, or
    // while a base is set (it is tried again every 30 s). Otherwise each
    // waiting question gets its explanation (_ask's backstop) instead of
    // staying an empty card (#65); also when the base is removed.
    if (!_canAnswer && (_loadingModel || _base != null)) return;
    final (thread, question, placeholder) = _waiting.removeAt(0);
    thread.entries.remove(placeholder);
    unawaited(_ask(question, into: thread));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_threads.load());
    // Until packages load here (or when a base answers instead), show
    // the built-in packages' names and suggestions.
    unawaited(
      builtInPackageInfo()
          .then((p) {
            if (mounted && _packages.isEmpty) setState(() => _packages = p);
          })
          .catchError((Object _) {}),
    );
    widget.settings?.addListener(_baseChanged);
    widget.settings?.addListener(_sharingChanged);
    _baseChanged();
    _startModel();
  }

  @override
  void dispose() {
    widget.downloadChanges?.removeListener(_loadDownloaded);
    _reloadLater?.cancel();
    widget.settings?.removeListener(_baseChanged);
    widget.settings?.removeListener(_sharingChanged);
    unawaited(_server?.stop());
    unawaited(_announcer.dispose().catchError((Object _) {}));
    _factsTimer?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  /// Screen readers: this answer is complete (once per answer, here and
  /// not in its card, which may be off screen or rebuilt).
  void _sayAnswerReady(GroundedAnswer a) {
    if (mounted) announce(context, answerReadyMessage(a));
  }

  /// Screen readers: this question ended without an answer.
  void _sayAnswerFailed(GroundedAnswer a) {
    if (mounted) announce(context, answerFailedMessage(a));
  }

  @override
  Future<void> _ask(String question, {Thread? into}) async {
    final thread = into ?? (_current ??= _threads.create());
    final lang = appLang(context);
    final noGuides = context.l10n.askNoGuides;
    final noModel = context.l10n.askExplainFailed;
    // Nothing can answer yet (the model is loading, or another question is
    // being answered): show the question now, answer it when ready.
    if (_answering || (!_canAnswer && _loadingModel)) {
      final placeholder = GroundedAnswer(question, appLang: lang);
      setState(() {
        thread.entries.add(placeholder);
        _waiting.add((thread, question, placeholder));
      });
      return;
    }
    // The base's answer was refused for its signature: the phone's own
    // answer says so.
    var baseRefused = false;
    // A base computer answers first: faster and better than a phone.
    final base = _base;
    if (base != null && _baseReady) {
      // Its key matched the link when it connected, or there was none.
      // Checked only once the user compared the key's code (#63).
      final trust = widget.facts?.trust;
      final keyTrusted = trust == null || trust.trustsKey(_baseKeyUsed);
      final unchecked = _baseKeyUsed == null || !keyTrusted;
      final placeholder = GroundedAnswer(question, appLang: lang)
        ..answeredBy = base.name
        ..baseUnchecked = unchecked;
      setState(() {
        _answering = true;
        thread.entries.add(placeholder);
      });
      final (answer: remote, :refused) = await askBase(
        base,
        question,
        pinnedKey: _baseKeyUsed,
        keyTrusted: keyTrusted,
        settings: widget.settings,
        onError: (e) => _log({
          'event': e is BadAnswerSignature
              ? 'base_answer_bad_signature'
              : 'base_failed',
          'error': '$e',
        }),
      );
      baseRefused = refused;
      if (remote != null) {
        try {
          setState(() {
            final i = thread.entries.indexOf(placeholder);
            // The conversation may have been cleared meanwhile.
            if (i >= 0) thread.entries[i] = remote;
          });
          unawaited(_threads.save());
          _log({'event': 'answer', ...remote.toJson()});
          _sayAnswerReady(remote);
        } finally {
          // Never left answering: later questions would wait for good.
          if (mounted) setState(() => _answering = false);
        }
        _answerWaiting();
        return;
      } else {
        setState(() {
          thread.entries.remove(placeholder);
          _answering = false;
        });
        // The phone's own model or guides are still loading: answer with
        // them then (not with the model alone, #65).
        if (!_ownAnswers && _loadingModel) {
          final waiting = GroundedAnswer(question, appLang: lang);
          setState(() {
            thread.entries.add(waiting);
            _waiting.add((thread, question, waiting));
          });
          return;
        }
        if (!_llm.isLoaded) {
          if (!mounted) return;
          final failed = GroundedAnswer(question, appLang: lang)
            // Refused, not unreachable: say that, once.
            ..text = baseRefused
                ? context.l10n.answerBaseRefusedNoModel
                : context.l10n.answerBaseUnreachable
            // A note, not an answer: no sources or "not covered" line.
            ..fromGuides = false;
          setState(() {
            thread.entries.add(failed);
            _answering = false;
          });
          _sayAnswerFailed(failed);
          return;
        }
      }
    }
    // Local sources rank a little higher: the region where the user is,
    // from the real (or mock) position only, never from the map area alone.
    final region = await UserRegion.current(
      widget.settings,
      widget.map,
      mockLocation: DevFlags.mockLocation,
    );
    if (_answerer case final a? when a.userRegion != region) {
      a.userRegion = region;
      _log({'event': 'region', 'region': region});
    }
    final entry = GroundedAnswer(question, appLang: lang)
      ..baseRefused = baseRefused;
    setState(() {
      _answering = true;
      thread.entries.add(entry);
    });
    try {
      final answerer = _answerer;
      if (answerer != null) {
        await answerer.answer(entry, () => setState(() {}));
      } else if (!DevFlags.bare && _loadingModel) {
        // A reload started while this question waited for the region:
        // it waits for the guides like the others (#65).
        _waiting.add((thread, question, entry));
        return;
      } else if (!DevFlags.bare) {
        // No guides (they or the search model failed to load): never the
        // model alone, whatever let the question through (#65).
        // Which of the two failed: the model itself, or what came after.
        entry
          ..text = _llm.isLoaded ? noGuides : noModel
          ..fromGuides = false;
        _log({'event': 'answer_no_guides'});
        _sayAnswerFailed(entry);
        return;
      } else {
        // BARE (dev): the model alone, shown without sources or notes.
        entry.fromGuides = false;
        await for (final t in _llm.ask(
          question,
          onDone: (s) => entry.stats = s,
        )) {
          entry.text += t;
          setState(() {});
        }
      }
      _log({'event': 'answer', ...entry.toJson()});
      _sayAnswerReady(entry);
    } catch (e) {
      entry.text += '\n[error: $e]';
      _sayAnswerFailed(entry);
    } finally {
      setState(() => _answering = false);
      unawaited(_threads.save());
      _answerWaiting();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Questions are taken while the model loads or another answer is
    // written: they wait in their conversation (see _waiting).
    final ready = _canAnswer || _loadingModel;
    if (widget.view == AskPageView.conversations) {
      return ConversationsView(
        store: _threads,
        onOpen: _openThread,
        onOpenSettings: widget.onOpenSettings,
        suggestions: SuggestionGroups(
          packages: _packages,
          onAsk: ready
              ? (q) {
                  _startThread();
                  unawaited(_ask(q));
                }
              : null,
        ),
        bar: QuestionBar(
          input: _input,
          ready: ready,
          loading: _phase == AskPhase.loading,
          busy: _answering,
          onSend: _sendNew,
          onStop: _llm.stop,
        ),
      );
    }
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([?settings, _threads]),
      builder: (context, _) => _home(context, ready, settings),
    );
  }

  Widget _home(BuildContext context, bool ready, AppSettings? settings) {
    final steps = _firstSteps(settings);
    final hidden = settings?.firstSteps.contains('hidden') ?? false;
    final showSteps = settings != null && !steps.allDone && !hidden;
    _maybeStartTour(steps, settings);
    return AskView(
      tourKeys: widget.tourKeys,
      onTour: widget.tourKeys == null ? null : _startTour,
      firstSteps: showSteps
          ? FirstStepsCard(
              steps: steps,
              onDownloads: widget.onOpenDownloads,
              onMap: widget.onShowOnMap,
              onAsk: widget.onShowAsk,
              onHide: () => unawaited(settings.markFirstStep('hidden')),
            )
          : null,
      status: showSteps
          ? null
          : !steps.allDone && settings != null
          ? ResumeStepsChip(
              steps: steps,
              onTap: () =>
                  unawaited(settings.markFirstStep('hidden', on: false)),
            )
          : steps.readyOffline
          ? ReadyOfflineChip(onTap: widget.onOpenDownloads)
          : null,
      onOpenSettings: widget.onOpenSettings,
      phase: _phase,
      detail: _status,
      // Sharing: this computer's name; connected: the base's.
      baseName: _server != null ? sharingName(widget.settings) : _base?.name,
      home: widget.map == null
          ? null
          : NearestSiteCard(
              map: widget.map!,
              onShowOnMap: widget.onShowOnMap,
              onOpenDownloads: widget.onOpenDownloads,
            ),
      packageInfos: _packages,
      updates: widget.updates,
      onShareNearby: _usesDownload
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ShareNearbyScreen(),
              ),
            )
          : null,
      onShowNotice: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (c) => NoticeScreen(
            packages: _packages,
            onAccept: () => Navigator.of(c).pop(),
          ),
        ),
      ),
      packages: _packages.isEmpty
          ? null
          : PackageRow(packages: _packages, onAdd: widget.onOpenDownloads),
      detailExtra: _server == null
          ? null
          : BaseQrCard(
              urls: widget.baseUrls?.value ?? const [],
              name: sharingName(widget.settings),
              keyText: widget.facts?.signer?.publicKeyText,
            ),
      ready: ready,
      busy: _answering,
      input: _input,
      onSend: _sendNew,
      onAsk: (q) {
        _startThread();
        unawaited(_ask(q));
      },
      recent: ThreadList(
        store: _threads,
        onOpen: _openThread,
        max: 3,
        onSeeAll: widget.onShowAsk,
      ),
      onStop: _llm.stop,
      onOpenDownloads: widget.onOpenDownloads,
      devActions: [
        // Phones get models from Downloads (signed); computers can also
        // open a model file from disk for testing.
        if (!_usesDownload)
          DevAction(
            'Open a model file…',
            _busy ? null : _pickFile,
            icon: Icons.folder_open_rounded,
          ),
        DevAction(
          'Run test questions',
          ready ? _bench : null,
          icon: Icons.fact_check_outlined,
        ),
      ],
    );
  }

  /// The conversation page for [t], rebuilt on every state change.
  Widget _conversation(BuildContext context, Thread t) {
    // Questions are taken while the model loads or another answer is
    // written: they wait in their conversation (see _waiting).
    final ready = _canAnswer || _loadingModel;
    final l = context.l10n;
    final settings = widget.settings;
    return ConversationPage(
      title: t.title,
      actions: [
        PopupMenuButton<String>(
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'archive',
              child: ListTile(
                leading: Icon(
                  t.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  t.archived ? l.conversationMoveBack : l.conversationArchive,
                ),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l.delete),
              ),
            ),
          ],
          onSelected: (v) async {
            final nav = Navigator.of(context);
            if (v == 'archive') {
              _threads.setArchived(t, !t.archived);
              nav.pop();
            } else if (await _confirmDelete(context)) {
              _threads.delete(t);
              nav.pop();
            }
          },
        ),
      ],
      itemCount: t.entries.length,
      itemBuilder: (_, i) => ListenableBuilder(
        // Rebuild when the map data, position or settings change.
        listenable: Listenable.merge([
          widget.map ?? ValueNotifier(0),
          ?settings,
          // Source labels follow the attestations and publishers (#119).
          ?_labels?.attestations,
          ?_labels?.publishers,
        ]),
        builder: (_, _) => AnswerCard(
          answer: t.entries[i],
          labelOf: (s) => sourceLabelFor(t.entries[i], s, _labels),
          // Per answer, not whether guides are loaded now: an old answer
          // keeps its sources and warnings while they reload (#65).
          grounded: t.entries[i].fromGuides,
          done: !_busy || i < t.entries.length - 1,
          map: widget.map,
          onShowOnMap: widget.onShowOnMap,
          showStats: settings?.showStats ?? false,
        ),
      ),
      bar: QuestionBar(
        input: _threadInput,
        ready: ready,
        loading: _phase == AskPhase.loading,
        busy: _answering,
        onSend: () {
          final q = _threadInput.text.trim();
          if (q.isEmpty) return;
          _threadInput.clear();
          _current = t;
          unawaited(_ask(q));
        },
        onStop: _llm.stop,
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(c.l10n.conversationDeleteTitle),
          content: Text(c.l10n.conversationDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.l10n.delete),
            ),
          ],
        ),
      ) ??
      false;

  /// Home screen: every question starts a new conversation.
  void _sendNew() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    _startThread();
    unawaited(_ask(q));
  }
}
