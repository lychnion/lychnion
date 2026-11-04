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
    if (f != null && _mapReady) {
      _map.move(f, 16);
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
    if (f != null) await s.facts!.addAll([f]);
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

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              for (final h in Hazard.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(en ? h.en : h.ja),
                    selected: hazard == h,
                    onSelected: (_) => s.selectHazard(h),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: s.focus ?? from,
              initialZoom: 15,
              minZoom: 10,
              maxZoom: 18,
              onMapReady: () {
                _mapReady = true;
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
                    if (_point(f.subject) case final p?)
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
                ],
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      en
                          ? 'Nearest emergency evacuation sites for ${hazard?.en ?? 'any hazard'}'
                          : '${hazard?.ja ?? 'すべて'}の指定緊急避難場所（近い順）',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(_locationStatus, style: theme.textTheme.bodySmall),
                  IconButton(
                    onPressed: s.locate,
                    icon: const Icon(Icons.my_location),
                  ),
                ],
              ),
              if (s.cityWithoutSiteFor(hazard) case final city?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          noSiteWarning(city, hazard!, en),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
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
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    en
                        ? 'Shelter computer: tap ✎ to set a site\'s status; long-press the map to report a blocked road or water point. Phones connected to this computer get the update within a minute.'
                        : '避難所の端末：✎で避難場所の状況を入力。地図を長押しで通行止め・給水を登録。接続中のスマホには1分以内に届きます。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final n in nearest)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    '${formatDistance(n.meters)}\n${n.direction(en)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  title: Text(n.site.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.site.address),
                      if (s.statusOf(n.site) case final f?)
                        Text(
                          factLine(f, s.facts!.now, en: en),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: factColor(f, theme.colorScheme),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  onTap: () => _map.move(n.site.point, 16),
                  trailing: _editor == null
                      ? null
                      : IconButton(
                          tooltip: en ? 'Set status' : '状況を入力',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editSite(n.site),
                        ),
                ),
              const SizedBox(height: 8),
              Text(
                en
                    ? 'Straight-line distance, not a route. Emergency evacuation sites are designated per hazard; '
                          'shelters (指定避難所) are for staying after the danger has passed. The data may be out of '
                          'date or incomplete: check with your city for the latest information.'
                    : '直線距離です（道のりではありません）。指定緊急避難場所は災害の種類ごとに指定されています。'
                          '指定避難所は危険が去った後に滞在する施設です。データは最新でない場合や未掲載の場合があるため、'
                          '最新の状況は市町村に確認してください。',
                style: theme.textTheme.bodySmall,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  en ? 'GSI usage notes (Japanese)' : '国土地理院 ご利用上の注意',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  SelectableText(
                    '${sites.notice}\n\n${sites.attribution}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when the user's city has no emergency site for [hazard] in the
/// GSI data, so the nearest one may be in another city.
String noSiteWarning(String city, Hazard hazard, bool en) => en
    ? 'The GSI data lists no ${hazard.en.toLowerCase()} evacuation site in $city. '
          'The nearest site may be in another city. Check $city\'s own hazard map '
          'and evacuation guidance.'
    : '国土地理院のデータでは、$cityに${hazard.ja}の指定緊急避難場所が登録されていません。'
          '最寄りの場所は別の市町村の可能性があります。$cityのハザードマップや避難情報を確認してください。';

LatLng? _point(String subject) {
  final p = subject.split(',');
  if (p.length != 2) return null;
  final lat = double.tryParse(p[0]), lon = double.tryParse(p[1]);
  return lat == null || lon == null ? null : LatLng(lat, lon);
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
