import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../facts/fact.dart';
import '../facts/fact_form.dart';
import '../facts/fact_view.dart';
import 'evac_sites.dart';
import 'map_state.dart';
import 'offline_theme.dart';

/// Offline map: base map from a local PMTiles file, emergency evacuation
/// sites for the chosen hazard, and the nearest ones from the current position.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.state,
    this.english = false,
    this.editor,
  });

  final MapState state;
  final bool english;

  /// Set on the shelter computer: lets staff enter current facts.
  final FactEditor? editor;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  bool _mapReady = false;

  /// Site opened in the list (shows its address).
  String? _selected;

  /// Centres [p] in the part of the map above the panel.
  void _moveTo(LatLng p, [double zoom = 16]) {
    final h = MediaQuery.sizeOf(context).height;
    _map.move(p, zoom, offset: Offset(0, -h * 0.18));
  }

  MapState get s => widget.state;
  bool get en => widget.english;

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
      en: en,
      choices: choices,
      current: current,
    );
    if (f != null) await s.facts!.addOwn([f]);
  }

  Future<void> _editSite(EvacSite site) => _enter(
    kind: FactKind.shelterStatus,
    subject: site.uid,
    title: site.name,
    choices: shelterChoices,
    current: s.statusOf(site),
  );

  Future<void> _editPoint(Fact f) => _enter(
    kind: f.kind,
    subject: f.subject,
    title: factLine(f, s.facts!.now, en: en),
    choices: [_pointChoice(f.kind, f.value)],
    current: f,
  );

  Future<void> _editWarning(Fact? f, String city) => _enter(
    kind: FactKind.warning,
    subject: f?.subject ?? city,
    title: f == null
        ? (en ? 'Warning for $city' : '$cityの警報・注意報')
        : factLine(f, s.facts!.now, en: en),
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
              title: Text(en ? 'Road blocked here' : 'ここが通行止め'),
              onTap: () => Navigator.pop(c, FactKind.roadBlocked),
            ),
            ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.blue),
              title: Text(en ? 'Water handed out here' : 'ここで給水'),
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
      title: kind == FactKind.roadBlocked
          ? (en ? 'Road blocked' : '通行止め')
          : (en ? 'Water point' : '給水'),
      choices: kind == FactKind.roadBlocked
          ? [_pointChoice(kind, 'blocked')]
          : const [
              (value: '給水車', ja: '給水車', en: 'water truck'),
              (value: '給水所', ja: '給水所', en: 'water station'),
            ],
    );
  }

  static FactChoice _pointChoice(FactKind kind, String value) =>
      kind == FactKind.roadBlocked
      ? (value: value, ja: '通行止め', en: 'road blocked')
      : (value: value, ja: value, en: value);

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
                  en ? 'Which hazard?' : 'どの災害ですか？',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
              ),
              for (final h in Hazard.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(en ? h.en : h.ja),
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
    if (s.hereIsMock) return en ? 'Test location' : 'テスト用の位置';
    if (s.here != null) {
      final acc = s.accuracy?.round();
      return en ? 'Location ±$acc m' : '現在地 ±$acc m';
    }
    return switch (s.error) {
      'no-permission' => en ? 'No location permission' : '位置情報の許可がありません',
      'no-location' => en ? 'Location not available' : '現在地を取得できません',
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
            : const CircularProgressIndicator(),
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
    final route = target?.path;
    final walking = s.routes != null;

    Widget chip(Hazard h) => ChoiceChip(
      label: Text(en ? h.en : h.ja),
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
                        hazard == null
                            ? (en ? 'Hazard' : '災害の種類')
                            : (en ? hazard.en : hazard.ja),
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
                  tooltip: en ? 'Choose the hazard' : '災害の種類を選ぶ',
                  onPressed: _pickHazard,
                ),
              ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
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
                theme: offlineLightTheme(english: en),
                tileProviders: TileProviders({'protomaps': tiles}),
                // Vector mode draws the labels; raster mode dropped them.
                layerMode: VectorTileLayerMode.vector,
                fileCacheTtl: Duration.zero,
                maximumZoom: 18,
              ),
              if (route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      strokeWidth: 6,
                      color: theme.colorScheme.primary,
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
                        width: 22,
                        height: 22,
                        child: GestureDetector(
                          onTap: _editor == null ? null : () => _editPoint(f),
                          child: Tooltip(
                            message: factLine(f, s.facts!.now, en: en),
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
                  TextSourceAttribution(
                    en ? 'Evacuation sites: GSI Japan' : '避難場所：国土地理院',
                  ),
                  if (s.routes?.hasHeights ?? false)
                    TextSourceAttribution(
                      en ? 'Heights: GSI elevation tiles' : '標高：国土地理院 標高タイル',
                    ),
                ],
              ),
            ],
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
                            en ? 'Nearby evacuation sites' : '近くの避難場所',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              en
                                  ? '${hazard?.en ?? 'Any hazard'} · ${walking ? 'walking distance' : 'straight line'}'
                                  : '${hazard?.ja ?? 'すべての災害'} · ${walking ? '徒歩の道のり' : '直線距離'}',
                              if (s.prefersHigh(hazard))
                                en ? 'keeps to higher ground' : '高い道を優先',
                              if (s.avoidsBlocked)
                                en ? 'blocked roads considered' : '通行止めを考慮',
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
                      tooltip: en ? 'About this data' : 'データについて',
                      onPressed: () =>
                          _showAbout(context, sites.notice, sites.attribution),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: en ? 'My location' : '現在地',
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
                            noSiteWarning(city, hazard!, en),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
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
                    en: en,
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
                      en
                          ? 'Shelter computer: ✎ sets a site\'s status; long-press the map for a blocked road or water point.'
                          : '避難所の端末：✎で状況を入力。地図を長押しで通行止め・給水を登録。',
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

  /// One site: distance, name, status; tap to see it on the map and open
  /// its address.
  Widget _siteRow(ThemeData theme, SiteDistance n) {
    final scheme = theme.colorScheme;
    final avoid = s.avoid(n.site);
    final status = s.statusOf(n.site);
    final open = _selected == n.site.uid;
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
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                        ? (en ? '${n.minutes} min' : '約${n.minutes}分')
                        : n.direction(en),
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
                  if (s.prefersHigh(s.hazard) && n.heightLabel(en).isNotEmpty)
                    Text(
                      n.heightLabel(en),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: (n.route?.dip ?? 0) >= SiteDistance.minDip
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: StatusChip(
                        fact: status,
                        now: s.facts!.now,
                        en: en,
                      ),
                    ),
                  if (open) ...[
                    const SizedBox(height: 6),
                    Text(n.site.address, style: theme.textTheme.bodySmall),
                    if (status != null)
                      Text(
                        factLine(status, s.facts!.now, en: en),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      [
                        for (final h in n.site.hazards) en ? h.en : h.ja,
                      ].join(' · '),
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
                tooltip: en ? 'Set status' : '状況を入力',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editSite(n.site),
              ),
          ],
        ),
      ),
    );
  }

  void _showAbout(
    BuildContext context,
    String notice,
    String attribution,
  ) => showModalBottomSheet<void>(
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
              en ? 'About this data' : 'データについて',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (s.routes != null
                      ? (en
                            ? 'Distances are walking routes on OpenStreetMap roads and paths, '
                                  'at 60 m a minute. The route does not know about damage, '
                                  'crowds or tsunami height: follow official guidance and what you see. '
                            : '距離は OpenStreetMap の道路・歩道に沿った徒歩の道のりです（分速60 m で計算）。'
                                  '被害や混雑、津波の高さは考慮していません。公式の情報と現地の状況に従ってください。')
                      : '') +
                  (s.routes?.hasHeights ?? false
                      ? (en
                            ? 'For tsunami the route keeps to higher ground and avoids going down, even if '
                                  'it is a little longer. Heights are ground heights (GSI elevation tiles): at a '
                                  'tsunami evacuation building, go up to the upper floors. '
                            : '津波の場合は、少し遠回りでも高い道を通り、下り坂を避ける経路を選びます。高さは地面の標高'
                                  '（国土地理院 標高タイル）です。津波避難ビルでは上の階へ上がってください。')
                      : '') +
                  (s.routes != null
                      ? ''
                      : (en
                            ? 'Distances are straight lines, not routes. '
                            : '距離は直線距離です（道のりではありません）。')) +
                  (en
                      ? 'Emergency evacuation sites (指定緊急避難場所) '
                            'are designated per hazard; shelters (指定避難所) are for staying after the danger has '
                            'passed. The data may be out of date or incomplete: check with your city.'
                      : '指定緊急避難場所は災害の種類ごとに指定されています。'
                            '指定避難所は危険が去った後に滞在する施設です。データは最新でない場合や未掲載の場合があるため、'
                            '最新の状況は市町村に確認してください。'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              en ? 'GSI usage notes (Japanese)' : '国土地理院 ご利用上の注意',
              style: theme.textTheme.titleSmall,
            ),
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
String noSiteWarning(String city, Hazard hazard, bool en) => en
    ? 'The GSI data lists no ${hazard.en.toLowerCase()} evacuation site in $city. '
          'The nearest site may be in another city. Check $city\'s own hazard map '
          'and evacuation guidance.'
    : '国土地理院のデータでは、$cityに${hazard.ja}の指定緊急避難場所が登録されていません。'
          '最寄りの場所は別の市町村の可能性があります。$cityのハザードマップや避難情報を確認してください。';

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
