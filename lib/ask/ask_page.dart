import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../app/dev_flags.dart';
import '../app/lang.dart';
import '../app/notices.dart';
import '../app/region.dart';
import '../app/settings.dart';
import '../download/catalog.dart';
import '../download/download_store.dart';
import '../facts/compact_codec.dart';
import '../facts/fact_store.dart';
import '../knowledge/app_help.dart';
import '../knowledge/bundled_packages.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/hybrid_retriever.dart';
import '../knowledge/knowledge_package.dart';
import '../llm/local_embedder.dart';
import '../llm/local_llm.dart';
import '../map/map_state.dart';
import '../shelter/base_discovery.dart';
import '../shelter/share_nearby.dart';
import '../shelter/shelter_client.dart';
import '../shelter/shelter_library.dart';
import '../shelter/shelter_panel.dart';
import '../shelter/shelter_server.dart';
import '../spike/bench_prompts.dart';
import '../spike/eval_questions.dart';
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

enum AskPageView { home, conversations }

/// Home and the conversations: asks the shelter base or the model on
/// this device, and shares this computer as a base.
class AskPage extends StatefulWidget {
  const AskPage({
    super.key,
    this.map,
    this.onShowOnMap,
    this.onDemoDone,
    this.onShelterCatalog,
    this.downloadChanges,
    this.facts,
    this.settings,
    this.onOpenDownloads,
    this.shelterUrls,
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

  /// Set by the shelter computer: its addresses, for the QR code.
  final ValueNotifier<List<String>>? shelterUrls;

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

  /// Connected to a shelter: its catalog address, for Downloads.
  final void Function(Uri catalog)? onShelterCatalog;

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  final _llm = LocalLlm();
  final _input = TextEditingController();
  final _threadInput = TextEditingController();
  final _url = TextEditingController(text: DevFlags.modelUrl);
  final _threads = ThreadStore();

  /// The guided tour starts by itself once, after the first steps.
  bool _tourStarted = false;

  void _startTour() {
    final keys = widget.tourKeys;
    final settings = widget.settings;
    if (keys == null || !mounted) return;
    _tourStarted = true;
    showGuidedTour(
      context,
      tourStops(context, keys),
      onEnd: () => unawaited(settings?.markFirstStep('tour')),
    );
  }

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

  /// Starts a conversation and shows it.
  Thread _startThread() {
    final t = _threads.create();
    _openThread(t);
    return t;
  }

  void _openThread(Thread t) {
    _current = t;
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
        });
  }

  GroundedAnswerer? _answerer;
  final _embedder = LocalEmbedder();
  String _status = 'No model loaded. / モデル未読み込み（「ダウンロード」から取得）';
  AskPhase _phase = AskPhase.noModel;

  /// What the last load used from Downloads (model, embedder, package).
  String? _loadedDownloads;

  /// The knowledge packages answers come from (shown on the home screen).
  List<PackageInfo> _packages = const [];

  /// Loading the phone's own model, and answering a question: separate,
  /// so the shelter can answer while the phone's model still loads.
  bool _loadingModel = false;
  bool _answering = false;
  bool get _busy => _loadingModel || _answering;

  /// A download change that came while busy, looked at again later.
  Timer? _reloadLater;

  /// Questions asked before anything could answer them, shown in their
  /// conversation, answered in order as soon as the shelter or the model
  /// is ready. A tap is never lost.
  final _waiting = <(Thread, String, GroundedAnswer)>[];

  bool get _canAnswer => _llm.isLoaded || _shelterReady;

  void _answerWaiting() {
    if (_waiting.isEmpty || _answering || !_canAnswer || !mounted) return;
    final (thread, question, placeholder) = _waiting.removeAt(0);
    thread.entries.remove(placeholder);
    unawaited(_ask(question, into: thread));
  }

  /// Phone side: the shelter computer to ask first (SHELTER_URL, or the
  /// one saved in settings from a QR code or a typed address).
  ShelterClient? _shelter;
  bool _shelterReady = false;
  Timer? _retry;

  String? get _wantedShelter => DevFlags.shelterUrl.isNotEmpty
      ? DevFlags.shelterUrl
      : widget.settings?.shelterUrl;

  /// Connects, switches or disconnects when the saved shelter changes.
  void _shelterChanged() {
    final want = _wantedShelter;
    final key = widget.settings?.shelterKey;
    // A key pinned for the same address connects again, to check it.
    if (want == _shelter?.baseUrl && key == _shelterKeyUsed) return;
    _shelterKeyUsed = key;
    _factsTimer?.cancel();
    _retry?.cancel();
    _shelter?.close();
    _shelter = want == null ? null : ShelterClient(want);
    setState(() {
      _shelterReady = false;
      if (_phase == AskPhase.shelter) {
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      }
    });
    if (_shelter != null) unawaited(_connectShelter());
  }

  /// The pinned key the current connection was checked against.
  String? _shelterKeyUsed;

  /// Desktop side: answers phones on the local network.
  ShelterServer? _server;

  /// Server changes run one after the other.
  Future<void> _serverOps = Future.value();

  void _sharingChanged() {
    final want = sharingOn(widget.settings) && _answerer != null;
    final name = sharingName(widget.settings);
    if (want == (_server != null) && (!want || _server!.name == name)) return;
    _serverOps = _serverOps.then((_) => _syncServer()).then((_) {
      if (!mounted) return;
      setState(() {
        if (_phase == AskPhase.serving ||
            _phase == AskPhase.ready ||
            _phase == AskPhase.shelter) {
          _phase = _server != null
              ? AskPhase.serving
              : (_shelterReady ? AskPhase.shelter : AskPhase.ready);
        }
      });
    });
  }

  /// Starts, stops or renames the server to match the settings. Answering
  /// needs the loaded model, so it starts once the model is ready.
  Future<void> _syncServer() async {
    final answerer = _answerer;
    final want = sharingOn(widget.settings) && answerer != null;
    final name = sharingName(widget.settings);
    // A new answerer (other packages, or a publisher removed) restarts the
    // server: it must not keep answering from what was unloaded.
    if (_server case final s?
        when !want || s.name != name || s.answerer != answerer) {
      await s.stop();
      await _announcer.stop().catchError((Object _) {});
      _server = null;
      widget.shelterUrls?.value = const [];
      _log({'event': 'shelter_stopped'});
    }
    if (!want || _server != null) return;
    final server = ShelterServer(
      answerer: answerer,
      name: name,
      modelName: DevFlags.modelPath.split('/').last,
      facts: widget.facts,
      codec: widget.map?.sites == null
          ? null
          : CompactCodec(widget.map!.sites!.siteIds),
      // Pass on what this computer has installed (packages, maps,
      // models), so phones can update here without internet.
      library: ShelterLibrary(await DownloadStore.instance()),
      page: await rootBundle.loadString('assets/web/shelter.html'),
      placeName: (id) => widget.map?.sites?.byUid(id)?.name,
    );
    try {
      await server.start();
    } on SocketException catch (e) {
      _log({'event': 'shelter_failed', 'error': '$e'});
      return;
    }
    _server = server;
    final urls = [
      for (final a in await ShelterServer.localAddresses())
        'http://$a:${ShelterServer.defaultPort}',
    ];
    widget.shelterUrls?.value = urls;
    _log({'event': 'shelter_started', 'name': name, 'urls': urls});
    // Phones on this Wi-Fi find the base without its QR code (step 5e).
    // Serving goes on if announcing is not possible here.
    try {
      await _announcer.start(
        name: name,
        port: ShelterServer.defaultPort,
        key: widget.facts?.signer?.publicKeyText,
      );
    } on Object catch (e) {
      _log({'event': 'shelter_announce_failed', 'error': '$e'});
    }
  }

  final _announcer = BaseAnnouncer();

  bool get _usesDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(_threads.load());
    // Until packages load here (or when a shelter answers instead), show
    // the built-in packages' names and suggestions.
    unawaited(
      builtInPackageInfo()
          .then((p) {
            if (mounted && _packages.isEmpty) setState(() => _packages = p);
          })
          .catchError((Object _) {}),
    );
    widget.settings?.addListener(_shelterChanged);
    widget.settings?.addListener(_sharingChanged);
    _shelterChanged();
    if (DevFlags.modelPath.isNotEmpty) {
      unawaited(
        _run(
          () async => _llm.loadFile(await resolvePath(DevFlags.modelPath)),
          afterLoad: true,
        ),
      );
    } else if (DevFlags.autoBench && _usesDownload) {
      unawaited(_download());
    } else {
      widget.downloadChanges?.addListener(_loadDownloaded);
      unawaited(_loadDownloaded());
    }
  }

  @override
  void dispose() {
    widget.downloadChanges?.removeListener(_loadDownloaded);
    _reloadLater?.cancel();
    widget.settings?.removeListener(_shelterChanged);
    widget.settings?.removeListener(_sharingChanged);
    unawaited(_server?.stop());
    unawaited(_announcer.dispose().catchError((Object _) {}));
    _factsTimer?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  /// Loads the chat model from the Downloads tab, and loads again when the
  /// model, the search model or the package there changes.
  Future<void> _loadDownloaded() async {
    // Busy (loading or answering): look again shortly, so a change (a
    // removed publisher, say) is never skipped.
    if (_busy) {
      _reloadLater?.cancel();
      _reloadLater = Timer(const Duration(seconds: 1), _loadDownloaded);
      return;
    }
    final store = await DownloadStore.instance();
    final chat = store.chatModelPath();
    if (chat == null) {
      // The model is gone (deleted, or its publisher removed): stop using
      // what was loaded from Downloads, also on the base server.
      if (_loadedDownloads != null && mounted) {
        _loadedDownloads = null;
        setState(() {
          _answerer = null;
          _phase = AskPhase.noModel;
          _status = '';
        });
        await _syncServer();
      }
      return;
    }
    final sig = [
      chat,
      store.embedModelPath(),
      for (final i in store.allInstalled(ItemKind.package))
        '${i.id}@${i.version}',
    ].join('|');
    if (sig == _loadedDownloads) return;
    _loadedDownloads = sig;
    await _run(() => _llm.loadFile(chat), afterLoad: true);
  }

  Future<void> _run(
    Future<void> Function() load, {
    bool afterLoad = false,
  }) async {
    setState(() {
      _loadingModel = true;
      _status = 'Loading model…';
      _phase = AskPhase.loading;
    });
    try {
      await load();
      await _llm.newChat(systemInstruction: benchSystemInstruction);
      if (!DevFlags.bare) {
        final store = await DownloadStore.instance();
        // The built-in packages (or newer downloads of them) plus every
        // other package installed from Downloads, searched together.
        // One broken or foreign file must not stop the app from answering
        // with the others: it is left out and logged.
        KnowledgePackage? openOrSkip(String id, String path) {
          try {
            return KnowledgePackage.open(path);
          } on Object catch (e) {
            _log({'event': 'package_skipped', 'id': id, 'error': '$e'});
            return null;
          }
        }

        final pkg = KnowledgePackage.merge([
          for (final id in bundledPackages)
            ?openOrSkip(id, await store.packagePath(id, '$id.sqlite')),
          for (final i in store.allInstalled(ItemKind.package))
            if (!bundledPackages.contains(i.id) &&
                i.fileEnding('.sqlite') != null)
              ?openOrSkip(i.id, store.path(i, i.fileEnding('.sqlite')!)),
        ]);
        HybridRetriever? hybrid;
        final embedPath = DevFlags.embedPath.isNotEmpty
            ? await resolvePath(DevFlags.embedPath)
            : store.embedModelPath();
        if (embedPath != null) {
          final sw = Stopwatch()..start();
          await _embedder.loadFile(embedPath);
          hybrid = HybridRetriever(
            pkg,
            _embedder,
            minCosine: double.parse(DevFlags.minCos),
          );
          await hybrid.index();
          _log({
            'event': 'indexed',
            'ms': sw.elapsedMilliseconds,
            'model': _embedder.modelName,
          });
        }
        // The app's own help, for questions about the app (lychnion#9).
        // Answers about hazards work without it.
        KnowledgePackage? help;
        HybridRetriever? helpHybrid;
        try {
          help = await AppHelp.load();
          if (hybrid != null) {
            helpHybrid = HybridRetriever(
              help,
              _embedder,
              minCosine: double.parse(DevFlags.minCos),
            );
            await helpHybrid.index();
          }
        } on Object catch (e) {
          _log({'event': 'help', 'error': '$e'});
        }
        _answerer = GroundedAnswerer(
          _llm,
          pkg,
          hybrid: hybrid,
          checkRelevance: DevFlags.relevanceCheck,
          topK: DevFlags.topK,
          help: help,
          helpHybrid: helpHybrid,
        );
        _log({
          'event': 'package',
          'id': pkg.id,
          'version': pkg.version,
          'passages': pkg.passages.length,
        });
        _packages = pkg.parts;
        if (mounted && widget.settings != null) {
          unawaited(showPackageNotices(context, widget.settings!, _packages));
        }
      }
      _log({
        'event': 'loaded',
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'backend': _llm.backend,
      });
      await _syncServer();
      setState(() {
        _status =
            'Ready · ${_llm.backend} · loaded in ${_llm.lastLoadTime!.inMilliseconds} ms'
            '${_server != null ? ' · base server on port ${ShelterServer.defaultPort}' : ''}';
        // A connected shelter still answers first.
        _phase = _server != null
            ? AskPhase.serving
            : (_shelterReady ? AskPhase.shelter : AskPhase.ready);
      });
    } catch (e) {
      setState(() {
        _status = 'Load failed: $e';
        _phase = AskPhase.failed;
      });
      _log({'event': 'load_failed', 'error': '$e'});
      return;
    } finally {
      setState(() => _loadingModel = false);
      _answerWaiting();
    }
    if (afterLoad && DevFlags.autoBench) await _bench();
    if (afterLoad && DevFlags.demoQuestions.isNotEmpty) {
      _startThread();
      for (final q in DevFlags.demoQuestions.split('|')) {
        await _ask(q.trim());
      }
      await widget.onDemoDone?.call(_entries);
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'GGUF models', extensions: ['gguf']),
      ],
    );
    if (file == null) return;
    // Copy into app storage so the sandboxed app can reopen it after restart.
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/models',
    );
    await dir.create(recursive: true);
    final target = File('${dir.path}/${file.name}');
    if (!await target.exists() ||
        await target.length() != await file.length()) {
      setState(() => _status = 'Copying model into app storage…');
      await File(file.path).copy(target.path);
    }
    await _run(() => _llm.loadFile(target.path));
  }

  Future<void> _download() => _run(
    () => _llm.loadUrl(
      _url.text.trim(),
      onProgress: (p) => setState(() => _status = 'Downloading model… $p%'),
    ),
    afterLoad: true,
  );

  Timer? _factsTimer;

  Future<void> _pullFacts() async {
    final store = widget.facts;
    if (store == null) return;
    try {
      final shelter = _shelter;
      if (shelter == null) return;
      final added = await store.addAll(await shelter.facts());
      _log({'event': 'facts_pulled', 'new': added});
    } catch (e) {
      _log({'event': 'facts_failed', 'error': '$e'});
    }
  }

  /// Trusts the shelter's signing key, only when it came from its QR code
  /// (checked in person): a computer with another key is refused (someone
  /// else at that address). A base connected by its address or found on
  /// the Wi-Fi gives answers and downloads (checked by signature anyway),
  /// but its facts stay unverified until its QR code is scanned.
  Future<bool> _trustShelterKey(Map<String, dynamic> info) async {
    final key = info['key'] as String?;
    final expected = widget.settings?.shelterKey;
    final trust = widget.facts?.trust;
    if (expected == null) {
      _log({'event': 'shelter_key_not_pinned'});
      return true;
    }
    if (key != expected) {
      _log({'event': 'shelter_key_mismatch'});
      setState(() {
        _status = 'Base key does not match the QR code: not connected.';
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      });
      return false;
    }
    if (trust != null) {
      await trust.add(expected, info['name'] as String? ?? 'shelter');
      // Facts pulled before the QR code was scanned.
      await widget.facts?.reverify();
    }
    return true;
  }

  Future<void> _connectShelter() async {
    final shelter = _shelter;
    if (shelter == null) return;
    try {
      final info = await shelter.info();
      if (!identical(shelter, _shelter)) return; // switched meanwhile
      if (!await _trustShelterKey(info)) return;
      _log({'event': 'shelter_connected', ...info});
      await _pullFacts();
      // Packages, maps and models the shelter can pass on (signed records).
      widget.onShelterCatalog?.call(
        Uri.parse(shelter.baseUrl).resolve('/catalog.json'),
      );
      // Keep current facts in step with the shelter while connected.
      _factsTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_pullFacts()),
      );
      setState(() {
        _shelterReady = true;
        _status = 'Connected to shelter: ${info['name']} (${info['model']})';
        _phase = AskPhase.shelter;
      });
      _answerWaiting();
      if (DevFlags.modelPath.isEmpty && DevFlags.demoQuestions.isNotEmpty) {
        _startThread();
        for (final q in DevFlags.demoQuestions.split('|')) {
          await _ask(q.trim());
        }
        await widget.onDemoDone?.call(_entries);
      }
    } catch (e) {
      _log({'event': 'shelter_unreachable', 'error': '$e'});
      if (!mounted || !identical(shelter, _shelter)) return;
      setState(() => _status = 'Base not reachable: $e');
      // The phone may join the shelter Wi-Fi later: try again.
      _retry = Timer(const Duration(seconds: 30), () {
        if (identical(shelter, _shelter)) unawaited(_connectShelter());
      });
    }
  }

  Future<void> _ask(String question, {Thread? into}) async {
    final thread = into ?? (_current ??= _threads.create());
    final lang = appLang(context);
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
    // A shelter computer answers first: faster and better than a phone.
    final shelter = _shelter;
    if (shelter != null && _shelterReady) {
      final placeholder = GroundedAnswer(question, appLang: lang)
        ..answeredBy = shelter.name;
      setState(() {
        _answering = true;
        thread.entries.add(placeholder);
      });
      try {
        final remote = await shelter.ask(question)
          ..answeredBy = shelter.name;
        setState(
          () => thread.entries[thread.entries.indexOf(placeholder)] = remote,
        );
        unawaited(_threads.save());
        _log({'event': 'answer', ...remote.toJson()});
        setState(() => _answering = false);
        _answerWaiting();
        return;
      } catch (e) {
        _log({'event': 'shelter_failed', 'error': '$e'});
        setState(() {
          thread.entries.remove(placeholder);
          _answering = false;
        });
        // The phone's own model is still loading: answer with it then.
        if (!_llm.isLoaded && _loadingModel) {
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
            ..text = context.l10n.answerBaseUnreachable;
          setState(() {
            thread.entries.add(failed);
            _answering = false;
          });
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
    final entry = GroundedAnswer(question, appLang: lang);
    setState(() {
      _answering = true;
      thread.entries.add(entry);
    });
    try {
      final answerer = _answerer;
      if (answerer != null) {
        await answerer.answer(entry, () => setState(() {}));
      } else {
        await for (final t in _llm.ask(
          question,
          onDone: (s) => entry.stats = s,
        )) {
          entry.text += t;
          setState(() {});
        }
      }
      _log({'event': 'answer', ...entry.toJson()});
    } catch (e) {
      entry.text += '\n[error: $e]';
    } finally {
      setState(() => _answering = false);
      unawaited(_threads.save());
      _answerWaiting();
    }
  }

  Future<void> _bench() async {
    _current = _threads.create(); // results land in their own thread
    final results = <Map<String, Object?>>[];
    final hybrid = _answerer?.hybrid;
    if (hybrid != null) await _logRetrieval(hybrid);
    final questions = hybrid != null
        ? [for (final e in evalQuestions) e.text]
        : benchPrompts;
    for (final q in questions) {
      // A fresh chat per question, so answers do not depend on each other.
      if (DevFlags.bare) {
        await _llm.newChat(systemInstruction: benchSystemInstruction);
      }
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await exchangeDirectory();
    final out = File(
      '${dir.path}/lychnion-bench-${DevFlags.bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': defaultTargetPlatform.name,
        'mode': DevFlags.bare ? 'bare' : 'grounded',
        'relevance_check': DevFlags.relevanceCheck,
        'top_k': DevFlags.topK,
        'package': _answerer?.package.version,
        'backend': _llm.backend,
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'results': results,
      }),
    );
    _log({'event': 'bench_done', 'file': out.path});
    setState(() => _status = 'Benchmark saved: ${out.path}');
  }

  /// Logs the ranking for every eval question, so the cut-off can be tuned.
  Future<void> _logRetrieval(HybridRetriever hybrid) async {
    for (final e in evalQuestions) {
      final ranked = await hybrid.rankAll(e.text);
      _log({
        'event': 'rank',
        'q': e.text,
        'lang': e.lang,
        'expected': e.expected,
        'top': [
          for (final h in ranked.take(6))
            {
              'source': h.passage.source.id,
              'id': h.passage.id,
              'cos': double.parse(h.cosine.toStringAsFixed(3)),
              'kw': double.parse(h.keyword.toStringAsFixed(1)),
            },
        ],
      });
    }
  }

  void _log(Map<String, Object?> data) =>
      debugPrint('LYCHNION ${jsonEncode(data)}');

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

  /// Where the user stands on the first steps (lychnion#7).
  FirstSteps _firstSteps(AppSettings? settings) => FirstSteps(
    aiReady: const {
      AskPhase.loading,
      AskPhase.ready,
      AskPhase.shelter,
      AskPhase.serving,
    }.contains(_phase),
    mapReady: widget.map != null,
    siteSeen: settings?.firstSteps.contains('site') ?? false,
    asked: _threads.recent.isNotEmpty,
  );

  Widget _home(BuildContext context, bool ready, AppSettings? settings) {
    final steps = _firstSteps(settings);
    final hidden = settings?.firstSteps.contains('hidden') ?? false;
    final showSteps = settings != null && !steps.allDone && !hidden;
    // Once the first steps are done, the tour shows the screen once.
    if (widget.onScreen &&
        widget.view == AskPageView.home &&
        steps.allDone &&
        settings != null &&
        !settings.firstSteps.contains('tour') &&
        !_tourStarted) {
      _tourStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
    }
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
      // Sharing: this computer's name; connected: the shelter's.
      shelterName: _server != null
          ? sharingName(widget.settings)
          : _shelter?.name,
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
          : ShelterQrCard(
              urls: widget.shelterUrls?.value ?? const [],
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
        ]),
        builder: (_, _) => AnswerCard(
          answer: t.entries[i],
          grounded: _answerer != null || t.entries[i].answeredBy != null,
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
