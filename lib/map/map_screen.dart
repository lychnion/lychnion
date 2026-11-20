import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../facts/fact.dart';
import '../facts/fact_form.dart';
import '../facts/fact_view.dart';
import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import 'evac_sites.dart';
import 'inundation_tiles.dart';
import 'map_labels.dart';
import 'map_state.dart';
import 'route_graph.dart';
import 'offline_theme.dart';
import '../ui/breathing_light.dart';

/// Offline map: base map from a local PMTiles file, emergency evacuation
/// sites for the chosen hazard, and the nearest ones from the current position.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.state, this.editor});

  final MapState state;

  /// Set on the base computer: lets staff enter current facts.
  final FactEditor? editor;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  bool _mapReady = false;

  /// The theme is parsed once per language and contours on/off.
  vtr.Theme? _theme;
  (String, bool)? _themeKey;
  vtr.Theme _themeFor(String lang, bool contours) {
    if (_themeKey != (lang, contours)) {
      _theme = offlineLightTheme(lang: lang, contours: contours);
      _themeKey = (lang, contours);
    }
    return _theme!;
  }

  /// Site opened in the list (shows its address).
  String? _selected;

  /// Centres [p] in the part of the map above the panel.
  void _moveTo(LatLng p, [double zoom = 16]) {
    final h = MediaQuery.sizeOf(context).height;
    _map.move(p, zoom, offset: Offset(0, -h * 0.18));
  }

  MapState get s => widget.state;
  AppLocalizations get l => context.l10n;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final f = s.focus;
    if (f != null) {
      // "Show on map" from an answer or the home card: route to that site.
      _selected = s
          .nearest(s.hazard)
          .where((n) => n.site.point == f)
          .firstOrNull
          ?.site
          .uid;
    }
    if (f != null && _mapReady) {
      _moveTo(f);
      s.focus = null;
    }
    setState(() {});
  }

  FactEditor? get _editor => s.facts == null ? null : widget.editor;

  Future<void> _enter({
    required FactKind kind,
    required String subject,
    required String title,
    List<FactChoice>? choices,
    Fact? current,
  }) async {
    final f = await showFactForm(
      context,
      editor: _editor!,
      kind: kind,
      subject: subject,
      title: title,
      choices: choices,
      current: current,
    );
    if (f != null) await s.facts!.addOwn([f]);
  }

  Future<void> _editSite(EvacSite site) => _enter(
    kind: FactKind.shelterStatus,
    subject: site.uid,
    title: site.name,
    choices: shelterChoices(l),
    current: s.statusOf(site),
  );

  Future<void> _editPoint(Fact f) => _enter(
    kind: f.kind,
    subject: f.subject,
    title: factLine(l, f, s.facts!.now),
    choices: [_pointChoice(f.kind, f.value)],
    current: f,
  );

  Future<void> _editWarning(Fact? f, String city) => _enter(
    kind: FactKind.warning,
    subject: f?.subject ?? city,
    title: f == null ? l.mapWarningFor(city) : factLine(l, f, s.facts!.now),
    choices: f == null ? null : [_pointChoice(f.kind, f.value)],
    current: f,
  );

  /// Long press on the map: report a blocked road or a water point there.
  Future<void> _addPoint(LatLng p) async {
    final kind = await showModalBottomSheet<FactKind>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.do_not_disturb_on,
                color: Colors.deepOrange,
              ),
              title: Text(l.mapRoadBlockedHere),
              onTap: () => Navigator.pop(c, FactKind.roadBlocked),
            ),
            ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.blue),
              title: Text(l.mapWaterHere),
              onTap: () => Navigator.pop(c, FactKind.waterPoint),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _enter(
      kind: kind,
      subject:
          '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
      title: kind == FactKind.roadBlocked ? l.mapRoadBlocked : l.mapWaterPoint,
      choices: kind == FactKind.roadBlocked
          ? [_pointChoice(kind, 'blocked')]
          : [
              // Stored values stay Japanese (as on the radio); labels follow
              // the app language.
              (value: '給水車', label: l.mapWaterTruck),
              (value: '給水所', label: l.mapWaterStation),
            ],
    );
  }

  FactChoice _pointChoice(FactKind kind, String value) =>
      kind == FactKind.roadBlocked
      ? (value: value, label: l.factRoadBlocked)
      : (value: value, label: value);

  /// Phones: the list of hazards, as a bottom sheet.
  Future<void> _pickHazard() async {
    final h = await showModalBottomSheet<Hazard>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  l.mapWhichHazard,
                  style: Theme.of(c).textTheme.titleLarge,
                ),
              ),
              for (final h in Hazard.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(hazardName(l, h)),
                  trailing: s.hazard == h
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(c).colorScheme.primary,
                        )
                      : null,
                  selected: s.hazard == h,
                  onTap: () => Navigator.pop(c, h),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (h != null) s.selectHazard(h);
  }

  String get _locationStatus {
    if (s.hereIsMock) return l.mapTestLocation;
    if (s.here != null) {
      final acc = s.accuracy?.round();
      return l.mapLocationAccuracy('$acc');
    }
    return switch (s.error) {
      'no-permission' => l.mapNoLocationPermission,
      'no-location' => l.mapNoLocation,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final sites = s.sites, tiles = s.tiles;
    if (sites == null || tiles == null) {
      final e = s.error;
      return Center(
        child: e != null && e.length > 20
            ? Text(e)
            : BreathingLight(size: 56, label: l.mapLoadingSpoken),
      );
    }
    final from = s.from!;
    final hazard = s.hazard;
    final nearest = s.nearest(hazard);
    final shown = [
      for (final site in sites.sites)
        if (site.emergency && (hazard == null || site.hazards.contains(hazard)))
          site,
    ];
    final theme = Theme.of(context);
    // Route to the site opened in the list, else to the nearest site that
    // can take people.
    final target =
        nearest.where((n) => n.site.uid == _selected).firstOrNull ??
        nearest.where((n) => !s.avoid(n.site)).firstOrNull;
    final out = s.wayOut(hazard);
    final route = _selected == _wayOutId ? out?.path : target?.path;
    final walking = s.routes != null;

    Widget chip(Hazard h) => ChoiceChip(
      label: Text(hazardName(l, h)),
      selected: hazard == h,
      showCheckmark: false,
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: hazard == h
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      elevation: 2,
      shadowColor: Colors.black26,
      side: BorderSide.none,
      onSelected: (_) => s.selectHazard(h),
    );

    // Wide screens show all eight hazards; phones show the chosen one as a
    // button that opens the full list (a scrolling row hid half of them).
    final chips = LayoutBuilder(
      builder: (context, c) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: c.maxWidth >= 700
            ? Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final h in Hazard.values) chip(h)],
              )
            : Align(
                alignment: Alignment.topLeft,
                child: ActionChip(
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.onPrimary,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hazard == null ? l.mapHazard : hazardName(l, hazard),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ],
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 2,
                  shadowColor: Colors.black26,
                  side: BorderSide.none,
                  tooltip: l.mapChooseHazard,
                  onPressed: _pickHazard,
                ),
              ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          // Screen readers skip the map itself (hundreds of markers, no
          // order) and hear the nearest site; the list in the sheet below
          // is the full, readable version.
          child: Semantics(
            container: true,
            label: nearest.isEmpty
                ? null
                : l.mapNearestSiteSpoken(nearest.first.site.name),
            // Staff: the long press that adds a blocked road or water
            // point, at the map centre (screen readers can't long-press
            // a spot on the map).
            hint: _editor == null ? null : l.mapAddPointAtCentre,
            onLongPress: _editor == null
                ? null
                : () => _addPoint(_mapReady ? _map.camera.center : from),
            child: ExcludeSemantics(
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: s.focus ?? from,
                  initialZoom: 15,
                  minZoom: 10,
                  maxZoom: 18,
                  onMapReady: () {
                    _mapReady = true;
                    _moveTo(s.focus ?? from, 15);
                    s.focus = null;
                  },
                  onLongPress: _editor == null ? null : (_, p) => _addPoint(p),
                ),
                children: [
                  VectorTileLayer(
                    theme: _themeFor(context.lang, s.contourTiles != null),
                    tileProviders: TileProviders({
                      'protomaps': tiles,
                      if (s.contourTiles != null) 'contours': s.contourTiles!,
                    }),
                    // Vector mode draws the labels; raster mode dropped them.
                    layerMode: VectorTileLayerMode.vector,
                    fileCacheTtl: Duration.zero,
                    maximumZoom: 18,
                  ),
                  if (hazard == Hazard.tsunami && s.inundationTiles != null)
                    TileLayer(
                      tileProvider: s.inundationTiles!,
                      minNativeZoom: InundationTiles.minZoom,
                      maxNativeZoom: InundationTiles.maxZoom,
                      maxZoom: 18,
                    ),
                  if (route != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 6,
                          color: _selected == _wayOutId
                              ? Colors.teal.shade700
                              : theme.colorScheme.primary,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final site in shown)
                        Marker(
                          point: site.point,
                          width: 14,
                          height: 14,
                          child: Tooltip(
                            message: site.name,
                            child: Icon(
                              Icons.place,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      for (final n in nearest)
                        Marker(
                          point: n.site.point,
                          width: 22,
                          height: 22,
                          child: Icon(
                            s.avoid(n.site) ? Icons.block : Icons.place,
                            size: 22,
                            // Full or closed: grey, so it does not look like a target.
                            color: s.avoid(n.site)
                                ? Colors.grey
                                : theme.colorScheme.error,
                          ),
                        ),
                      for (final f
                          in s.facts?.currentOf({
                                FactKind.roadBlocked,
                                FactKind.waterPoint,
                              }) ??
                              const <Fact>[])
                        if (pointOf(f.subject) case final p?)
                          Marker(
                            point: p,
                            // 48 dp to tap (editor), the icon stays 22.
                            width: 48,
                            height: 48,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _editor == null
                                  ? null
                                  : () => _editPoint(f),
                              child: Tooltip(
                                message: factLine(l, f, s.facts!.now),
                                child: f.kind == FactKind.roadBlocked
                                    ? const Icon(
                                        Icons.do_not_disturb_on,
                                        size: 22,
                                        color: Colors.deepOrange,
                                      )
                                    : const Icon(
                                        Icons.water_drop,
                                        size: 22,
                                        color: Colors.blue,
                                      ),
                              ),
                            ),
                          ),
                      if (_selected == _wayOutId && out != null)
                        Marker(
                          point: out.path.last,
                          width: 26,
                          height: 26,
                          child: Icon(
                            Icons.flag_rounded,
                            size: 26,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      if (s.here != null)
                        Marker(
                          point: s.here!,
                          width: 18,
                          height: 18,
                          child: const Icon(
                            Icons.my_location,
                            size: 18,
                            color: Colors.blue,
                          ),
                        ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(sites.basemapAttribution),
                      TextSourceAttribution(l.mapAttributionSites),
                      if (s.routes?.hasHeights ?? false)
                        TextSourceAttribution(l.mapAttributionHeights),
                      if (s.routes?.hasFlood ?? false)
                        TextSourceAttribution(l.mapAttributionFlood),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(child: chips),
        DraggableScrollableSheet(
          initialChildSize: 0.36,
          minChildSize: 0.14,
          maxChildSize: 0.9,
          snap: true,
          builder: (context, scroll) => Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: const [
                BoxShadow(blurRadius: 16, color: Colors.black26),
              ],
            ),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.mapNearbySites,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              hazard == null
                                  ? l.mapAnyHazard
                                  : hazardName(l, hazard),
                              walking
                                  ? l.mapWalkingDistance
                                  : l.mapStraightLine,
                              if (s.prefersHigh(hazard)) l.mapKeepsHigh,
                              if (s.avoidsBlocked) l.mapBlockedConsidered,
                              if (_locationStatus.isNotEmpty) _locationStatus,
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.mapAboutData,
                      onPressed: () =>
                          _showAbout(context, sites.notice, sites.attribution),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: l.mapMyLocation,
                      onPressed: s.locate,
                      icon: const Icon(Icons.my_location_rounded),
                    ),
                  ],
                ),
                if (s.cityWithoutSiteFor(hazard) case final city?)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            noSiteWarning(l, city, hazard!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (hazard == Hazard.tsunami && s.floodHere != null)
                  _floodCard(theme, s.floodHere!, out),
                if (hazard == Hazard.tsunami && s.inundationTiles != null)
                  _floodLegend(theme),
                for (final n in nearest) _siteRow(theme, n),
                if (s.facts?.currentOf({
                      FactKind.warning,
                      FactKind.roadBlocked,
                      FactKind.waterPoint,
                    })
                    case final cur? when cur.isNotEmpty || _editor != null)
                  CurrentFactsBox(
                    facts: cur,
                    now: s.facts!.now,
                    onTap: _editor == null
                        ? null
                        : (f) => f.kind == FactKind.warning
                              ? _editWarning(f, f.subject)
                              : _editPoint(f),
                    onAdd: _editor == null
                        ? null
                        : () => _editWarning(null, sites.cityAt(from)),
                  ),
                if (_editor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l.mapBaseHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _wayOutId = '__way_out__';

  /// Tsunami: whether the current position is in the official inundation
  /// area, and the way out of it (tap to draw it).
  Widget _floodCard(ThemeData theme, int flood, RouteInfo? out) {
    final scheme = theme.colorScheme;
    final inside = flood >= 2;
    final d = s.depthHere;
    final depth = d == null ? '' : depthLabel(l, d);
    final title = inside
        ? l.mapInFloodArea(depth)
        : flood == 1
        ? l.mapNearFloodArea
        : l.mapOutsideFloodArea;
    final minutes = out == null ? null : max(1, (out.meters / 60).round());
    final bg = inside ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = inside ? scheme.onErrorContainer : scheme.onSurface;
    final selected = _selected == _wayOutId;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      // The way out is shown on the map when selected.
      child: Semantics(
        container: true,
        button: out != null,
        selected: out != null && selected,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: out == null
                ? null
                : () {
                    setState(() => _selected = selected ? null : _wayOutId);
                    if (!selected) _moveTo(out.path.last, 15);
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    inside ? Icons.waves_rounded : Icons.check_circle_outline,
                    color: fg,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          out != null
                              ? l.mapWayOut(
                                  formatDistance(out.meters),
                                  '$minutes',
                                )
                              : l.mapFloodBasis,
                          style: theme.textTheme.bodySmall?.copyWith(color: fg),
                        ),
                      ],
                    ),
                  ),
                  if (out != null)
                    Icon(
                      selected ? Icons.flag_rounded : Icons.flag_outlined,
                      color: fg,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Colours of the inundation layer by expected depth.
  Widget _floodLegend(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 6),
    child: Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l.mapExpectedDepth,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final e in InundationTiles.colours.entries)
          if (e.key <= max(s.routes?.deepest ?? 6, 0))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: e.value,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  depthFromLabel(l, e.key),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
      ],
    ),
  );

  /// One site: distance, name, status; tap to see it on the map and open
  /// its address.
  Widget _siteRow(ThemeData theme, SiteDistance n) {
    final avoid = s.avoid(n.site);
    final status = s.statusOf(n.site);
    final open = _selected == n.site.uid;
    // Open: the address shows and the map moves to the site.
    return Semantics(
      container: true,
      button: true,
      expanded: open,
      child: _siteInk(theme, n, avoid, status, open),
    );
  }

  Widget _siteInk(
    ThemeData theme,
    SiteDistance n,
    bool avoid,
    Fact? status,
    bool open,
  ) {
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() => _selected = open ? null : n.site.uid);
        _moveTo(n.site.point);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              // Grows with large text instead of breaking the words.
              constraints: const BoxConstraints(minWidth: 58),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: avoid
                    ? scheme.surfaceContainerHighest
                    : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    formatDistance(n.walk ?? n.meters),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: avoid
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    n.minutes != null
                        ? l.mapMinutes('${n.minutes}')
                        : siteDirection(l, n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: avoid
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.site.name,
                    maxLines: open ? null : 1,
                    overflow: open ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: avoid ? scheme.onSurfaceVariant : null,
                      decoration: avoid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (s.prefersHigh(s.hazard) &&
                      siteHeightLabel(l, n).isNotEmpty)
                    Text(
                      siteHeightLabel(l, n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: (n.route?.dip ?? 0) >= SiteDistance.minDip
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: StatusChip(fact: status, now: s.facts!.now),
                    ),
                  if (open) ...[
                    const SizedBox(height: 6),
                    Text(n.site.address, style: theme.textTheme.bodySmall),
                    if (status != null)
                      Text(
                        factLine(l, status, s.facts!.now),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      [for (final h in n.site.hazards) hazardName(l, h)]
                          .join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_editor != null)
              IconButton(
                tooltip: l.mapSetStatus,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editSite(n.site),
              ),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context, String notice, String attribution) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (c, scroll) {
            final theme = Theme.of(c);
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                Text(
                  l.mapAboutData,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  (s.routes != null ? l.mapAboutRoutes : '') +
                      (s.routes?.hasHeights ?? false ? l.mapAboutHeights : '') +
                      (s.routes != null ? '' : l.mapAboutStraight) +
                      l.mapAboutSites,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(l.mapGsiNotes, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                SelectableText(
                  '$notice\n\n$attribution',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      );
}

/// Shown when the user's city has no emergency site for [hazard] in the
/// GSI data, so the nearest one may be in another city.
String noSiteWarning(AppLocalizations l, String city, Hazard hazard) =>
    l.mapNoSiteWarning(hazardInSentence(l, hazard), city);
