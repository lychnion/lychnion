import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app/settings.dart';
import 'app/settings_screen.dart';
import 'app/theme.dart';
import 'download/catalog.dart';
import 'download/download_manager.dart';
import 'download/download_store.dart';
import 'download/downloads_screen.dart';
import 'ui/ask_view.dart';
import 'knowledge/grounded_answer.dart';
import 'knowledge/hybrid_retriever.dart';
import 'knowledge/knowledge_package.dart';
import 'llm/local_embedder.dart';
import 'map/map_screen.dart';
import 'facts/compact_codec.dart';
import 'facts/demo_facts.dart';
import 'facts/fact_form.dart';
import 'facts/fact_store.dart';
import 'map/hazard_detect.dart';
import 'map/map_state.dart';
import 'package:app_links/app_links.dart';

import 'shelter/shelter_client.dart';
import 'shelter/shelter_link.dart';
import 'shelter/shelter_panel.dart';
import 'shelter/shelter_server.dart';
import 'llm/local_llm.dart';
import 'spike/bench_prompts.dart';
import 'spike/eval_questions.dart';
import 'ui/answer_card.dart';
import 'util/paths.dart';

/// Spike app: load a GGUF model, chat with it, and time a fixed question set.
///
/// Dev flags (all optional):
///   --dart-define=GGUF_MODEL_PATH=/path/in/app/storage.gguf  load on start (docs:… = in Documents)
///   --dart-define=GGUF_MODEL_URL=https://...gguf             download on start
///   --dart-define=AUTO_BENCH=true                            run the questions after loading
///   --dart-define=BARE=true                                  no package: the model answers alone (spike 1)
///   --dart-define=EMBED_MODEL_PATH=/path/in/app/storage.gguf  vector search (spike 3)
///   --dart-define=MIN_COS=0.5                                relevance cut-off for vector search (default 0.70)
///   --dart-define=CATALOG_URL=https://…/catalog.json         download catalog (Downloads tab)
///   --dart-define=DOWNLOAD_BASE_URL=http://host:port/        base for relative catalog URLs
///   --dart-define=MAP_PMTILES_PATH=/path/area.pmtiles        offline base map
///   --dart-define=MOCK_LOCATION=34.7376,135.3417             fixed position for testing
///   --dart-define=START_TAB=1                                open on the map
///   --dart-define=SCREENSHOT_AFTER_S=20                      save a PNG of the app to Documents
///   --dart-define=SHELTER_SERVER=true                        answer phones on the local network (desktop)
///   --dart-define=SHELTER_NAME=…                             shown on phones
///   --dart-define=SHELTER_URL=http://192.168.1.20:8642       ask this shelter first (phone)
///   --dart-define=FACTS_EDIT=true                            enter facts on the map (on with SHELTER_SERVER)
///   --dart-define=DEMO_FACTS=true                            add made-up current facts (test data)
///   --dart-define=TOP_K=2                                    passages per answer (default 4)
///   --dart-define=RELEVANCE_CHECK=true                       yes/no check before answering (spike 4)
///   --dart-define=ASK='q1|q2'                                ask these after loading, then save
///                                                            screenshots of the answers and the map
const _modelPath = String.fromEnvironment('GGUF_MODEL_PATH');
const _modelUrl = String.fromEnvironment(
  'GGUF_MODEL_URL',
  defaultValue:
      'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf',
);
const _autoBench = bool.fromEnvironment('AUTO_BENCH');
const _bare = bool.fromEnvironment('BARE');
const _packageAsset = 'jp.bousai.core.sqlite';
const _packageId = 'jp.bousai.core';
const _embedPath = String.fromEnvironment('EMBED_MODEL_PATH');
const _minCos = String.fromEnvironment('MIN_COS', defaultValue: '0.70');
const _mapPmtiles = String.fromEnvironment('MAP_PMTILES_PATH');
const _mockLocation = String.fromEnvironment('MOCK_LOCATION');
const _mapSitesAsset = 'jp.map.nishinomiya.sites.sqlite';
const _startTab = int.fromEnvironment('START_TAB');
const _screenshotAfter = int.fromEnvironment('SCREENSHOT_AFTER_S');
const _demoQuestions = String.fromEnvironment('ASK');
const _relevanceCheck = bool.fromEnvironment('RELEVANCE_CHECK');
const _topK = int.fromEnvironment('TOP_K', defaultValue: 4);
const _shelterServer = bool.fromEnvironment('SHELTER_SERVER');
const _shelterName = String.fromEnvironment(
  'SHELTER_NAME',
  defaultValue: 'fieldkit shelter',
);
const _shelterUrl = String.fromEnvironment('SHELTER_URL');
const _demoFactsFlag = bool.fromEnvironment('DEMO_FACTS');
const _factsEdit = bool.fromEnvironment('FACTS_EDIT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalLlm.init();
  final settings = AppSettings();
  await settings.load();
  runApp(FieldkitApp(settings: settings));
}

class FieldkitApp extends StatelessWidget {
  const FieldkitApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'fieldkit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: settings.language.locale,
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomePage(settings: settings),
    ),
  );
}

/// Three tabs: ask, the offline map and settings (with downloads).
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = _startTab;
  final _shotKey = GlobalKey();

  /// Current facts (shelter status, blocked roads, warnings), kept apart
  /// from the model and the knowledge packages.
  final _facts = FactStore();

  /// Map data and position, shared by the answers and the map tab.
  /// From MAP_PMTILES_PATH, else from a downloaded map area.
  late MapState? _map = _mapPmtiles.isEmpty
      ? null
      : MapState(
          pmtilesPath: _mapPmtiles,
          sitesAsset: _mapSitesAsset,
          mockLocation: _mockLocation,
          facts: _facts,
        );

  DownloadManager? _downloads;

  /// Shelter computer: its addresses for phones (empty when not serving).
  final _shelterUrls = ValueNotifier<List<String>>(const []);

  StreamSubscription<Uri>? _links;

  bool _asking = false;

  /// A scanned fieldkit://shelter link: ask, then connect. The same link can
  /// arrive twice (at launch and from the stream): ask only once.
  Future<void> _openLink(Uri uri) async {
    final link = ShelterLink.fromUri(uri);
    if (link == null || !mounted || _asking) return;
    if (link.url == widget.settings.shelterUrl) return; // already connected
    _asking = true;
    try {
      final en = Localizations.localeOf(context).languageCode != 'ja';
      if (await confirmShelter(context, link, en: en)) {
        await widget.settings.setShelter(link.url, name: link.name);
        setState(() => _tab = 0);
      }
    } finally {
      _asking = false;
    }
  }

  /// Bumped when a download is installed or deleted.
  final _downloadChanges = ValueNotifier<int>(0);

  Future<void> _initDownloads() async {
    final dm = await DownloadManager.create();
    dm.changes.addListener(() {
      _useDownloadedMap();
      _downloadChanges.value++;
    });
    setState(() => _downloads = dm);
    _useDownloadedMap();
  }

  /// (Re)opens the downloaded map area unless MAP_PMTILES_PATH is set.
  void _useDownloadedMap() {
    if (_mapPmtiles.isNotEmpty) return;
    final p = _downloads!.store.mapPaths();
    final old = _map;
    setState(
      () => _map = p == null
          ? null
          : MapState(
              pmtilesPath: p.pmtiles,
              sitesAsset: _mapSitesAsset,
              sitesPath: p.sites,
              mockLocation: _mockLocation,
              facts: _facts,
            ),
    );
    old?.dispose();
    unawaited(_map?.load());
  }

  @override
  void initState() {
    super.initState();
    unawaited(_map?.load());
    unawaited(_initFacts());
    unawaited(_initDownloads());
    if (!_shelterServer) {
      // Phones only: links come from the QR code at a shelter.
      _links = AppLinks().uriLinkStream.listen((u) => unawaited(_openLink(u)));
    }
    if (_screenshotAfter > 0) {
      Timer(const Duration(seconds: _screenshotAfter), _saveScreenshot);
    }
  }

  @override
  void dispose() {
    unawaited(_links?.cancel());
    super.dispose();
  }

  Future<void> _initFacts() async {
    await _facts.load();
    if (!_demoFactsFlag) return;
    // Demo facts refer to evacuation sites: wait for the map area.
    for (var i = 0; i < 300; i++) {
      final sites = _map?.sites;
      if (sites != null) {
        await _facts.addAll(demoFacts(sites, DateTime.now()));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Demo run: screenshot the answers, then the map at the suggested site.
  Future<void> _demoDone(List<GroundedAnswer> answers) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await _saveScreenshot();
    final map = _map;
    if (map == null) return;
    for (final a in answers) {
      final h = hazardFor(a.question, a.alerts);
      final near = map.nearest(h, limit: 1, skipAvoided: true);
      if (h == null || near.isEmpty) continue;
      map.showOnMap(h, near.first.site.point);
      setState(() => _tab = 1);
      await Future<void>.delayed(const Duration(seconds: 10));
      await _saveScreenshot();
      return;
    }
  }

  // Dev aid: lets scripts see the app without screen-recording rights.
  Future<void> _saveScreenshot() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await exchangeDirectory();
    final file = File(
      '${dir.path}/fieldkit-screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint(
      'FIELDKIT ${jsonEncode({'event': 'screenshot', 'file': file.path})}',
    );
  }

  void _openDownloads(bool en) {
    final dm = _downloads;
    if (dm == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadsScreen(manager: dm, english: en),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context).languageCode != 'ja';
    return RepaintBoundary(
      key: _shotKey,
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            SpikePage(
              map: _map,
              facts: _facts,
              settings: widget.settings,
              shelterUrls: _shelterUrls,
              downloadChanges: _downloadChanges,
              onShowOnMap: () => setState(() => _tab = 1),
              onOpenDownloads: () => _openDownloads(en),
              onDemoDone: _demoDone,
            ),
            Scaffold(
              body: _map == null
                  ? EmptyHint(
                      icon: Icons.map_outlined,
                      title: en ? 'No map yet' : '地図がありません',
                      text: en
                          ? 'Download your area to see evacuation sites without internet.'
                          : 'お住まいの地域をダウンロードすると、インターネットなしで避難場所を確認できます。',
                      action: en ? 'Download a map' : '地図をダウンロード',
                      onAction: () => _openDownloads(en),
                    )
                  : MapScreen(
                      key: ObjectKey(_map),
                      state: _map!,
                      english: en,
                      editor: _shelterServer || _factsEdit
                          ? const FactEditor(sourceName: _shelterName)
                          : null,
                    ),
            ),
            SettingsScreen(
              settings: widget.settings,
              downloads: _downloads,
              en: en,
              shelter: ValueListenableBuilder(
                valueListenable: _shelterUrls,
                builder: (_, urls, _) => _shelterServer
                    ? ShelterQrCard(urls: urls, name: _shelterName, en: en)
                    : ShelterSettingsTile(settings: widget.settings, en: en),
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: const Icon(Icons.chat_bubble_rounded),
              label: en ? 'Ask' : '質問',
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map_rounded),
              label: en ? 'Map' : '地図',
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: en ? 'Settings' : '設定',
            ),
          ],
        ),
      ),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({
    super.key,
    this.map,
    this.onShowOnMap,
    this.onDemoDone,
    this.downloadChanges,
    this.facts,
    this.settings,
    this.onOpenDownloads,
    this.shelterUrls,
  });

  /// Set by the shelter computer: its addresses, for the QR code.
  final ValueNotifier<List<String>>? shelterUrls;

  final MapState? map;
  final FactStore? facts;
  final AppSettings? settings;
  final VoidCallback? onOpenDownloads;

  /// Fires when downloads change; the downloaded model is (re)loaded.
  final Listenable? downloadChanges;
  final void Function()? onShowOnMap;
  final Future<void> Function(List<GroundedAnswer>)? onDemoDone;

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _llm = LocalLlm();
  final _input = TextEditingController();
  final _url = TextEditingController(text: _modelUrl);
  final _entries = <GroundedAnswer>[];
  GroundedAnswerer? _answerer;
  final _embedder = LocalEmbedder();
  String _status = 'No model loaded. / モデル未読み込み（「ダウンロード」から取得）';
  AskPhase _phase = AskPhase.noModel;

  /// What the last load used from Downloads (model, embedder, package).
  String? _loadedDownloads;
  bool _busy = false;

  /// Phone side: the shelter computer to ask first (SHELTER_URL, or the
  /// one saved in settings from a QR code or a typed address).
  ShelterClient? _shelter;
  bool _shelterReady = false;
  Timer? _retry;

  String? get _wantedShelter =>
      _shelterUrl.isNotEmpty ? _shelterUrl : widget.settings?.shelterUrl;

  /// Connects, switches or disconnects when the saved shelter changes.
  void _shelterChanged() {
    final want = _wantedShelter;
    if (want == _shelter?.baseUrl) return;
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

  /// Desktop side: answers phones on the local network.
  ShelterServer? _server;

  bool get _usesDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    widget.settings?.addListener(_shelterChanged);
    _shelterChanged();
    if (_modelPath.isNotEmpty) {
      unawaited(
        _run(
          () async => _llm.loadFile(await resolvePath(_modelPath)),
          afterLoad: true,
        ),
      );
    } else if (_autoBench && _usesDownload) {
      unawaited(_download());
    } else {
      widget.downloadChanges?.addListener(_loadDownloaded);
      unawaited(_loadDownloaded());
    }
  }

  @override
  void dispose() {
    widget.downloadChanges?.removeListener(_loadDownloaded);
    widget.settings?.removeListener(_shelterChanged);
    _factsTimer?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  /// Loads the chat model from the Downloads tab, and loads again when the
  /// model, the search model or the package there changes.
  Future<void> _loadDownloaded() async {
    if (_busy) return;
    final store = await DownloadStore.instance();
    final chat = store.chatModelPath();
    if (chat == null) return;
    final sig = [
      chat,
      store.embedModelPath(),
      store.installed(ItemKind.package, _packageId)?.version,
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
      _busy = true;
      _status = 'Loading model…';
      _phase = AskPhase.loading;
    });
    try {
      await load();
      await _llm.newChat(systemInstruction: benchSystemInstruction);
      if (!_bare) {
        final store = await DownloadStore.instance();
        final pkg = KnowledgePackage.open(
          await store.packagePath(_packageId, _packageAsset),
        );
        HybridRetriever? hybrid;
        final embedPath = _embedPath.isNotEmpty
            ? await resolvePath(_embedPath)
            : store.embedModelPath();
        if (embedPath != null) {
          final sw = Stopwatch()..start();
          await _embedder.loadFile(embedPath);
          hybrid = HybridRetriever(
            pkg,
            _embedder,
            minCosine: double.parse(_minCos),
          );
          await hybrid.index();
          _log({
            'event': 'indexed',
            'ms': sw.elapsedMilliseconds,
            'model': _embedder.modelName,
          });
        }
        _answerer = GroundedAnswerer(
          _llm,
          pkg,
          hybrid: hybrid,
          checkRelevance: _relevanceCheck,
          topK: _topK,
        );
        _log({
          'event': 'package',
          'id': pkg.id,
          'version': pkg.version,
          'passages': pkg.passages.length,
        });
      }
      _log({
        'event': 'loaded',
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'backend': _llm.backend,
      });
      final answerer = _answerer;
      if (_shelterServer && answerer != null) {
        _server = ShelterServer(
          answerer: answerer,
          name: _shelterName,
          modelName: _modelPath.split('/').last,
          facts: widget.facts,
          codec: widget.map?.sites == null
              ? null
              : CompactCodec(widget.map!.sites!.siteIds),
        );
        await _server!.start();
        final addrs = await ShelterServer.localAddresses();
        widget.shelterUrls?.value = [
          for (final a in addrs) 'http://$a:${ShelterServer.defaultPort}',
        ];
        _log({
          'event': 'shelter_started',
          'name': _shelterName,
          'urls': [
            for (final a in addrs) 'http://$a:${ShelterServer.defaultPort}',
          ],
        });
      }
      setState(() {
        _status =
            'Ready · ${_llm.backend} · loaded in ${_llm.lastLoadTime!.inMilliseconds} ms'
            '${_server != null ? ' · shelter server on port ${ShelterServer.defaultPort}' : ''}';
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
      setState(() => _busy = false);
    }
    if (afterLoad && _autoBench) await _bench();
    if (afterLoad && _demoQuestions.isNotEmpty) {
      for (final q in _demoQuestions.split('|')) {
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

  Future<void> _connectShelter() async {
    final shelter = _shelter;
    if (shelter == null) return;
    try {
      final info = await shelter.info();
      if (!identical(shelter, _shelter)) return; // switched meanwhile
      _log({'event': 'shelter_connected', ...info});
      await _pullFacts();
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
      if (_modelPath.isEmpty && _demoQuestions.isNotEmpty) {
        for (final q in _demoQuestions.split('|')) {
          await _ask(q.trim());
        }
        await widget.onDemoDone?.call(_entries);
      }
    } catch (e) {
      _log({'event': 'shelter_unreachable', 'error': '$e'});
      if (!mounted || !identical(shelter, _shelter)) return;
      setState(() => _status = 'Shelter not reachable: $e');
      // The phone may join the shelter Wi-Fi later: try again.
      _retry = Timer(const Duration(seconds: 30), () {
        if (identical(shelter, _shelter)) unawaited(_connectShelter());
      });
    }
  }

  Future<void> _ask(String question) async {
    // A shelter computer answers first: faster and better than a phone.
    final shelter = _shelter;
    if (shelter != null && _shelterReady) {
      final placeholder = GroundedAnswer(question)..answeredBy = shelter.name;
      setState(() {
        _busy = true;
        _entries.add(placeholder);
      });
      try {
        final remote = await shelter.ask(question)
          ..answeredBy = shelter.name;
        setState(() => _entries[_entries.indexOf(placeholder)] = remote);
        _log({'event': 'answer', ...remote.toJson()});
        setState(() => _busy = false);
        return;
      } catch (e) {
        _log({'event': 'shelter_failed', 'error': '$e'});
        setState(() => _entries.remove(placeholder));
        if (!_llm.isLoaded) {
          final failed = GroundedAnswer(question)
            ..text = 'Shelter not reachable and no model on this device: $e';
          setState(() {
            _entries.add(failed);
            _busy = false;
          });
          return;
        }
      }
    }
    final entry = GroundedAnswer(question);
    setState(() {
      _busy = true;
      _entries.add(entry);
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
      setState(() => _busy = false);
    }
  }

  Future<void> _bench() async {
    final results = <Map<String, Object?>>[];
    final hybrid = _answerer?.hybrid;
    if (hybrid != null) await _logRetrieval(hybrid);
    final questions = hybrid != null
        ? [for (final e in evalQuestions) e.text]
        : benchPrompts;
    for (final q in questions) {
      // A fresh chat per question, so answers do not depend on each other.
      if (_bare) await _llm.newChat(systemInstruction: benchSystemInstruction);
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await exchangeDirectory();
    final out = File(
      '${dir.path}/fieldkit-bench-${_bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': defaultTargetPlatform.name,
        'mode': _bare ? 'bare' : 'grounded',
        'relevance_check': _relevanceCheck,
        'top_k': _topK,
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
      debugPrint('FIELDKIT ${jsonEncode(data)}');

  @override
  Widget build(BuildContext context) {
    final ready = (_llm.isLoaded || _shelterReady) && !_busy;
    final en = Localizations.localeOf(context).languageCode != 'ja';
    final settings = widget.settings;
    return AskView(
      en: en,
      phase: _phase,
      detail: _status,
      shelterName: _shelter?.name,
      detailExtra: _server == null
          ? null
          : ShelterQrCard(
              urls: widget.shelterUrls?.value ?? const [],
              name: _shelterName,
              en: en,
            ),
      ready: ready,
      busy: _busy,
      input: _input,
      onSend: _send,
      onAsk: (q) => unawaited(_ask(q)),
      onStop: _llm.stop,
      onOpenDownloads: widget.onOpenDownloads,
      devActions: [
        if (_usesDownload)
          DevAction('Download model (URL)', _busy ? null : _download)
        else
          DevAction('Load GGUF file…', _busy ? null : _pickFile),
        DevAction('Run test questions', ready ? _bench : null),
      ],
      itemCount: _entries.length,
      itemBuilder: (_, i) => ListenableBuilder(
        // Rebuild when the map data, position or settings change.
        listenable: Listenable.merge([
          widget.map ?? ValueNotifier(0),
          ?settings,
        ]),
        builder: (_, _) => AnswerCard(
          answer: _entries[i],
          grounded: _answerer != null || _entries[i].answeredBy != null,
          done: !_busy || i < _entries.length - 1,
          map: widget.map,
          onShowOnMap: widget.onShowOnMap,
          showStats: settings?.showStats ?? false,
        ),
      ),
    );
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    unawaited(_ask(q));
  }
}
