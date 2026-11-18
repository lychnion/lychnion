import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'app/settings.dart';
import 'app/settings_screen.dart';
import 'app/theme.dart';
import 'download/catalog.dart';
import 'download/download_manager.dart';
import 'download/download_store.dart';
import 'download/catalogs_screen.dart';
import 'download/downloads_screen.dart';
import 'download/followed_catalogs.dart';
import 'download/publisher_list.dart';
import 'download/publishers_screen.dart';
import 'ui/ask_view.dart';
import 'ui/first_steps.dart';
import 'ui/guided_tour.dart';
import 'ui/suggestions.dart';
import 'knowledge/app_help.dart';
import 'knowledge/grounded_answer.dart';
import 'knowledge/hybrid_retriever.dart';
import 'knowledge/knowledge_package.dart';
import 'app/region.dart';
import 'ui/package_row.dart';
import 'llm/local_embedder.dart';
import 'map/map_screen.dart';
import 'facts/compact_codec.dart';
import 'facts/demo_facts.dart';
import 'facts/fact_form.dart';
import 'facts/fact_store.dart';
import 'facts/signing.dart';
import 'map/hazard_detect.dart';
import 'map/map_state.dart';
import 'package:app_links/app_links.dart';

import 'shelter/share_nearby.dart';
import 'shelter/shelter_client.dart';
import 'shelter/shelter_link.dart';
import 'shelter/shelter_panel.dart';
import 'shelter/shelter_server.dart';
import 'shelter/shelter_library.dart';
import 'llm/local_llm.dart';
import 'spike/bench_prompts.dart';
import 'spike/eval_questions.dart';
import 'ui/answer_card.dart';
import 'ui/conversation_page.dart';
import 'ui/thread_list.dart';
import 'ui/threads.dart';
import 'ui/nearest_card.dart';
import 'util/paths.dart';
import 'app/brand.dart';
import 'app/splash.dart';
import 'app/notices.dart';
import 'app/lang.dart';
import 'l10n/app_localizations.dart';

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
///   --dart-define=START_TAB=2                                open on the map (1: conversations)
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

/// Knowledge packages built into the app (`assets/packages/<id>.sqlite`).
/// A newer download from the catalog replaces the built-in copy.
const _bundledPackages = [
  'jp.bousai.core',
  'jp.outdoor.hiking',
  'intl.firstaid.basics',
];
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
const _shelterNameFlag = String.fromEnvironment(
  'SHELTER_NAME',
  defaultValue: 'Lychnion shelter',
);

/// Computers can share on the local network (phones: later).
bool get _isDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Sharing on the local network: the switch in Settings, or the
/// SHELTER_SERVER flag for development.
bool _sharingOn(AppSettings? s) =>
    _shelterServer || (_isDesktop && (s?.sharing ?? false));
String _sharingName(AppSettings? s) => s?.sharingName ?? _shelterNameFlag;
const _shelterUrl = String.fromEnvironment('SHELTER_URL');
const _demoFactsFlag = bool.fromEnvironment('DEMO_FACTS');
const _factsEdit = bool.fromEnvironment('FACTS_EDIT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  addLicenses();
  await LocalLlm.init();
  final settings = AppSettings();
  await settings.load();
  runApp(LychnionApp(settings: settings));
}

final _appShotKey = GlobalKey();

class LychnionApp extends StatelessWidget {
  const LychnionApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: HomePage(settings: settings),
      // Dev screenshots include pages pushed on top (conversations).
      // Headings in Latin-script languages use Lexend; the language is
      // known only here (it may follow the device).
      builder: (context, child) {
        final latin = usesLatinScript(context.lang);
        final shot = RepaintBoundary(key: _appShotKey, child: child);
        // The splash stays at the top, so a language change keeps its state.
        return SplashOverlay(
          child: latin
              ? Theme(
                  data: withLatinHeadings(Theme.of(context)),
                  child: _gate(shot),
                )
              : _gate(shot),
        );
      },
    ),
  );

  /// First start: what the app can and cannot do, over the home page.
  Widget _gate(Widget child) => NoticeGate(
    settings: settings,
    packages: _builtInPackageInfo,
    child: child,
  );
}

Future<List<PackageInfo>> _builtInPackageInfo() async {
  final store = await DownloadStore.instance();
  return [
    for (final id in _bundledPackages)
      KnowledgePackage.readInfo(await store.packagePath(id, '$id.sqlite')),
  ];
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

  /// Shared by Home and the bottom bar: the parts the guided tour shows.
  final _tourKeys = TourKeys();

  /// Current facts (shelter status, blocked roads, warnings), kept apart
  /// from the model and the knowledge packages.
  final _trust = TrustList();
  late final _facts = FactStore(trust: _trust);

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

  /// A scanned lychnion://shelter link: ask, then connect. The same link can
  /// arrive twice (at launch and from the stream): ask only once.
  Future<void> _openLink(Uri uri) async {
    if (ShareLink.fromUri(uri) case final share?) {
      await _receiveShare(share);
      return;
    }
    if (CatalogLink.fromUri(uri) case final catalog?) {
      final dm = _downloads;
      // At a cold start Downloads may not be ready yet: ask once it is.
      if (dm == null) {
        _pendingCatalog = catalog;
        return;
      }
      if (!mounted || _asking) return;
      _asking = true;
      try {
        await followCatalog(context, dm, catalog);
      } finally {
        _asking = false;
      }
      return;
    }
    if (PublisherLink.fromUri(uri) case final publisher?) {
      final dm = _downloads;
      // At a cold start Downloads may not be ready yet: ask once it is.
      if (dm == null) {
        _pendingPublisher = publisher;
        return;
      }
      if (!mounted || _asking) return;
      _asking = true;
      try {
        await addPublisher(context, dm, publisher);
      } finally {
        _asking = false;
      }
      return;
    }
    final link = ShelterLink.fromUri(uri);
    if (link == null || !mounted || _asking) return;
    if (link.url == widget.settings.shelterUrl) return; // already connected
    _asking = true;
    try {
      if (await confirmShelter(context, link)) {
        await widget.settings.setShelter(
          link.url,
          name: link.name,
          key: link.key,
        );
        setState(() => _tab = 0);
      }
    } finally {
      _asking = false;
    }
  }

  /// Bumped when a download is installed or deleted.
  final _downloadChanges = ValueNotifier<int>(0);

  /// New versions of installed downloads, for the ⋮ menu badge.
  final _updates = ValueNotifier<int>(0);

  /// A shelter's catalog that arrived before Downloads was ready.
  Uri? _pendingShelterCatalog;

  /// A publisher link that arrived before Downloads was ready.
  PublisherLink? _pendingPublisher;

  /// A catalog link that arrived before Downloads was ready.
  CatalogLink? _pendingCatalog;

  /// A phone nearby shares its downloads: ask, then show what it offers in
  /// Downloads. Records and files are checked as for any download.
  Future<void> _receiveShare(ShareLink link) async {
    final dm = _downloads;
    if (dm == null || !mounted || _asking) return;
    _asking = true;
    try {
      final l = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.share_rounded),
          title: Text(l.shareReceiveTitle),
          content: Text(
            l.shareReceiveBody(link.url.replaceFirst('http://', '')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l.shareReceiveShow),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final url = Uri.parse(link.url).resolve('/catalog.json');
      final offered = await dm.addCatalogFrom(url);
      if (!mounted) return;
      // Count only what this phone does not have yet.
      final n = offered == null ? 0 : dm.newItemsAt(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offered == null
                ? l.shareReceiveNone
                : n == 0
                ? l.shareReceiveNothingNew
                : l.shareReceiveFound(n),
          ),
        ),
      );
      if (offered != null) _openDownloads();
    } finally {
      _asking = false;
    }
  }

  void _addShelterCatalog(Uri url) {
    final dm = _downloads;
    if (dm == null) {
      _pendingShelterCatalog = url;
    } else {
      unawaited(dm.addCatalogFrom(url));
    }
  }

  Future<void> _initDownloads() async {
    final dm = await DownloadManager.create();
    dm.changes.addListener(() {
      _useDownloadedMap();
      _downloadChanges.value++;
    });
    dm.updates.addListener(() => _updates.value = dm.updates.value);
    setState(() => _downloads = dm);
    _useDownloadedMap();
    if (_pendingShelterCatalog case final u?) {
      _pendingShelterCatalog = null;
      unawaited(dm.addCatalogFrom(u));
    }
    if (_pendingPublisher case final p?) {
      _pendingPublisher = null;
      await _openLink(p.toUri());
    }
    if (_pendingCatalog case final c?) {
      _pendingCatalog = null;
      await _openLink(c.toUri());
    }
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
              routesPath: p.routes,
              inundationPath: p.inundation,
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
    final dir = await getApplicationSupportDirectory();
    await _trust.load(File('${dir.path}/trusted_keys.json'));
    // Devices that enter official facts (shelter computer, demo) sign them.
    if (_isDesktop || _shelterServer || _factsEdit || _demoFactsFlag) {
      final signer = await FactSigner.loadOrCreate(
        File('${dir.path}/signing_key'),
      );
      _facts.signer = signer;
      await _trust.add(signer.publicKeyText, _sharingName(widget.settings));
    }
    await _facts.load();
    if (!_demoFactsFlag) return;
    // Demo facts refer to evacuation sites: wait for the map area.
    for (var i = 0; i < 300; i++) {
      final sites = _map?.sites;
      if (sites != null) {
        await _facts.addOwn(demoFacts(sites, DateTime.now()));
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
      setState(() => _tab = 2);
      await Future<void>.delayed(const Duration(seconds: 10));
      await _saveScreenshot();
      return;
    }
  }

  // Dev aid: lets scripts see the app without screen-recording rights.
  Future<void> _saveScreenshot() async {
    final boundary =
        _appShotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await exchangeDirectory();
    final file = File(
      '${dir.path}/lychnion-screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint(
      'LYCHNION ${jsonEncode({'event': 'screenshot', 'file': file.path})}',
    );
  }

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => SettingsScreen(
        settings: widget.settings,
        downloads: _downloads,
        onShareNearby: _isDesktop ? null : _openShareNearby,
        region: RegionTile(
          settings: widget.settings,
          map: _map,
          mockLocation: _mockLocation,
        ),
        bundledPackages: _builtInPackageInfo,
        userRegion: () => UserRegion.current(
          widget.settings,
          _map,
          mockLocation: _mockLocation,
        ),
        shelter: _isDesktop
            ? ShelterShareSection(
                settings: widget.settings,
                urls: _shelterUrls,
                keyText: _facts.signer?.publicKeyText,
              )
            : ShelterSettingsTile(settings: widget.settings),
      ),
    ),
  );

  /// Phones pass on their downloads to phones nearby (computers do it as
  /// a base).
  void _openShareNearby() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ShareNearbyScreen()));

  void _openDownloads() {
    final dm = _downloads;
    if (dm == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadsScreen(
          manager: dm,
          userRegion: () => UserRegion.current(
            widget.settings,
            _map,
            mockLocation: _mockLocation,
          ),
        ),
      ),
    );
  }

  /// Opening the map with an area counts as the first step "look at the
  /// nearest site".
  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 2 && _map != null) {
      unawaited(widget.settings.markFirstStep('site'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RepaintBoundary(
      child: Scaffold(
        body: IndexedStack(
          index: _tab == 2 ? 1 : 0,
          children: [
            SpikePage(
              tourKeys: _tourKeys,
              onScreen: _tab == 0,
              onShelterCatalog: _addShelterCatalog,
              view: _tab == 1 ? AskPageView.conversations : AskPageView.home,
              onOpenSettings: _openSettings,
              onShowAsk: () => setState(() => _tab = 1),
              map: _map,
              facts: _facts,
              settings: widget.settings,
              shelterUrls: _shelterUrls,
              updates: _updates,
              downloadChanges: _downloadChanges,
              onShowOnMap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                _selectTab(2);
              },
              onOpenDownloads: _openDownloads,
              onDemoDone: _demoDone,
            ),
            Scaffold(
              body: _map == null
                  ? EmptyHint(
                      icon: Icons.map_outlined,
                      title: l.mapNoMap,
                      text: l.mapNoMapText,
                      action: l.mapDownloadMap,
                      onAction: _openDownloads,
                    )
                  : ListenableBuilder(
                      listenable: widget.settings,
                      builder: (_, _) => MapScreen(
                        key: ObjectKey(_map),
                        state: _map!,
                        editor: _sharingOn(widget.settings) || _factsEdit
                            ? FactEditor(
                                sourceName: _sharingName(widget.settings),
                              )
                            : null,
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l.navHome,
            ),
            NavigationDestination(
              key: _tourKeys.ask,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: const Icon(Icons.chat_bubble_rounded),
              label: l.navAsk,
            ),
            NavigationDestination(
              key: _tourKeys.map,
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map_rounded),
              label: l.navMap,
            ),
          ],
        ),
      ),
    );
  }
}

enum AskPageView { home, conversations }

class SpikePage extends StatefulWidget {
  const SpikePage({
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
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _llm = LocalLlm();
  final _input = TextEditingController();
  final _threadInput = TextEditingController();
  final _url = TextEditingController(text: _modelUrl);
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

  /// Server changes run one after the other.
  Future<void> _serverOps = Future.value();

  void _sharingChanged() {
    final want = _sharingOn(widget.settings) && _answerer != null;
    final name = _sharingName(widget.settings);
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
    final want = _sharingOn(widget.settings) && answerer != null;
    final name = _sharingName(widget.settings);
    // A new answerer (other packages, or a publisher removed) restarts the
    // server: it must not keep answering from what was unloaded.
    if (_server case final s?
        when !want || s.name != name || s.answerer != answerer) {
      await s.stop();
      _server = null;
      widget.shelterUrls?.value = const [];
      _log({'event': 'shelter_stopped'});
    }
    if (!want || _server != null) return;
    final server = ShelterServer(
      answerer: answerer,
      name: name,
      modelName: _modelPath.split('/').last,
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
  }

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
      _builtInPackageInfo()
          .then((p) {
            if (mounted && _packages.isEmpty) setState(() => _packages = p);
          })
          .catchError((Object _) {}),
    );
    widget.settings?.addListener(_shelterChanged);
    widget.settings?.addListener(_sharingChanged);
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
    _reloadLater?.cancel();
    widget.settings?.removeListener(_shelterChanged);
    widget.settings?.removeListener(_sharingChanged);
    unawaited(_server?.stop());
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
      if (!_bare) {
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
          for (final id in _bundledPackages)
            ?openOrSkip(id, await store.packagePath(id, '$id.sqlite')),
          for (final i in store.allInstalled(ItemKind.package))
            if (!_bundledPackages.contains(i.id) &&
                i.fileEnding('.sqlite') != null)
              ?openOrSkip(i.id, store.path(i, i.fileEnding('.sqlite')!)),
        ]);
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
              minCosine: double.parse(_minCos),
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
          checkRelevance: _relevanceCheck,
          topK: _topK,
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
    if (afterLoad && _autoBench) await _bench();
    if (afterLoad && _demoQuestions.isNotEmpty) {
      _startThread();
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

  /// Trusts the shelter's signing key. With a key from the QR code, a
  /// computer with another key is refused (someone else at that address).
  Future<bool> _trustShelterKey(Map<String, dynamic> info) async {
    final key = info['key'] as String?;
    final expected = widget.settings?.shelterKey;
    final trust = widget.facts?.trust;
    if (expected != null && key != expected) {
      _log({'event': 'shelter_key_mismatch'});
      setState(() {
        _status = 'Base key does not match the QR code: not connected.';
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      });
      return false;
    }
    if (key != null && trust != null) {
      await trust.add(key, info['name'] as String? ?? 'shelter');
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
      if (_modelPath.isEmpty && _demoQuestions.isNotEmpty) {
        _startThread();
        for (final q in _demoQuestions.split('|')) {
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
      mockLocation: _mockLocation,
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
      if (_bare) await _llm.newChat(systemInstruction: benchSystemInstruction);
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await exchangeDirectory();
    final out = File(
      '${dir.path}/lychnion-bench-${_bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
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
          ? _sharingName(widget.settings)
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
              name: _sharingName(widget.settings),
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
