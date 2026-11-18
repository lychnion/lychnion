import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../ask/ask_page.dart';
import '../download/catalogs_screen.dart';
import '../download/download_manager.dart';
import '../download/downloads_screen.dart';
import '../download/followed_catalogs.dart';
import '../download/publisher_list.dart';
import '../download/publishers_screen.dart';
import '../facts/demo_facts.dart';
import '../facts/fact_form.dart';
import '../facts/fact_store.dart';
import '../facts/signing.dart';
import '../knowledge/bundled_packages.dart';
import '../knowledge/grounded_answer.dart';
import '../map/hazard_detect.dart';
import '../map/map_screen.dart';
import '../map/map_state.dart';
import '../shelter/share_nearby.dart';
import '../shelter/shelter_link.dart';
import '../shelter/shelter_panel.dart';
import '../ui/ask_view.dart';
import '../ui/guided_tour.dart';
import '../util/paths.dart';
import 'dev_flags.dart';
import 'lang.dart';
import 'region.dart';
import 'settings.dart';
import 'settings_screen.dart';

part 'incoming_links.dart';

const _mapSitesAsset = 'jp.map.nishinomiya.sites.sqlite';

/// The app's screenshot area (dev screenshots, SCREENSHOT_AFTER_S and ASK).
final appShotKey = GlobalKey();

/// Three tabs: ask, the offline map and settings (with downloads).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with _IncomingLinks {
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

  @override
  DownloadManager? _downloads;

  /// Shelter computer: its addresses for phones (empty when not serving).
  final _shelterUrls = ValueNotifier<List<String>>(const []);

  StreamSubscription<Uri>? _links;

  /// Bumped when a download is installed or deleted.
  final _downloadChanges = ValueNotifier<int>(0);

  /// New versions of installed downloads, for the ⋮ menu badge.
  final _updates = ValueNotifier<int>(0);

  /// A shelter's catalog that arrived before Downloads was ready.
  Uri? _pendingShelterCatalog;

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
        appShotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
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

  @override
  void _openDownloads() {
    final dm = _downloads;
    if (dm == null) return;
    unawaited(
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
