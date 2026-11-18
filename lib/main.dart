import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'app/brand.dart';
import 'app/dev_flags.dart';
import 'app/lang.dart';
import 'app/notices.dart';
import 'app/region.dart';
import 'app/settings.dart';
import 'app/settings_screen.dart';
import 'app/splash.dart';
import 'app/theme.dart';
import 'ask/ask_page.dart';
import 'download/catalogs_screen.dart';
import 'download/download_manager.dart';
import 'download/downloads_screen.dart';
import 'download/followed_catalogs.dart';
import 'download/publisher_list.dart';
import 'download/publishers_screen.dart';
import 'facts/demo_facts.dart';
import 'facts/fact_form.dart';
import 'facts/fact_store.dart';
import 'facts/signing.dart';
import 'knowledge/bundled_packages.dart';
import 'knowledge/grounded_answer.dart';
import 'l10n/app_localizations.dart';
import 'llm/local_llm.dart';
import 'map/hazard_detect.dart';
import 'map/map_screen.dart';
import 'map/map_state.dart';
import 'shelter/share_nearby.dart';
import 'shelter/shelter_link.dart';
import 'shelter/shelter_panel.dart';
import 'ui/ask_view.dart';
import 'ui/guided_tour.dart';
import 'util/paths.dart';

const _mapSitesAsset = 'jp.map.nishinomiya.sites.sqlite';

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
    packages: builtInPackageInfo,
    child: child,
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
  int _tab = DevFlags.startTab;

  /// Shared by Home and the bottom bar: the parts the guided tour shows.
  final _tourKeys = TourKeys();

  /// Current facts (shelter status, blocked roads, warnings), kept apart
  /// from the model and the knowledge packages.
  final _trust = TrustList();
  late final _facts = FactStore(trust: _trust);

  /// Map data and position, shared by the answers and the map tab.
  /// From MAP_PMTILES_PATH, else from a downloaded map area.
  late MapState? _map = DevFlags.mapPmtiles.isEmpty
      ? null
      : MapState(
          pmtilesPath: DevFlags.mapPmtiles,
          sitesAsset: _mapSitesAsset,
          mockLocation: DevFlags.mockLocation,
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
    // Already connected, and nothing new: a QR code with the key of a base
    // connected by address or found on the Wi-Fi pins that key.
    if (link.url == widget.settings.shelterUrl &&
        (link.key == null || link.key == widget.settings.shelterKey)) {
      return;
    }
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
    if (DevFlags.mapPmtiles.isNotEmpty) return;
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
              mockLocation: DevFlags.mockLocation,
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
    if (!DevFlags.shelterServer) {
      // Phones only: links come from the QR code at a shelter.
      _links = AppLinks().uriLinkStream.listen((u) => unawaited(_openLink(u)));
    }
    if (DevFlags.screenshotAfter > 0) {
      Timer(const Duration(seconds: DevFlags.screenshotAfter), _saveScreenshot);
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
    if (isDesktop ||
        DevFlags.shelterServer ||
        DevFlags.factsEdit ||
        DevFlags.demoFacts) {
      final signer = await FactSigner.loadOrCreate(
        File('${dir.path}/signing_key'),
      );
      _facts.signer = signer;
      await _trust.add(signer.publicKeyText, sharingName(widget.settings));
    }
    await _facts.load();
    if (!DevFlags.demoFacts) return;
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
        onShareNearby: isDesktop ? null : _openShareNearby,
        region: RegionTile(
          settings: widget.settings,
          map: _map,
          mockLocation: DevFlags.mockLocation,
        ),
        bundledPackages: builtInPackageInfo,
        userRegion: () => UserRegion.current(
          widget.settings,
          _map,
          mockLocation: DevFlags.mockLocation,
        ),
        shelter: isDesktop
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
            mockLocation: DevFlags.mockLocation,
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
            AskPage(
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
                        editor: sharingOn(widget.settings) || DevFlags.factsEdit
                            ? FactEditor(
                                sourceName: sharingName(widget.settings),
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
