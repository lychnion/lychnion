import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'evac_sites.dart';
import 'map_state.dart';
import 'offline_theme.dart';

/// Offline map: base map from a local PMTiles file, emergency evacuation
/// sites for the chosen hazard, and the nearest ones from the current position.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.state, this.english = false});

  final MapState state;
  final bool english;

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
                        Icons.place,
                        size: 22,
                        color: theme.colorScheme.error,
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
                  subtitle: Text(n.site.address),
                  onTap: () => _map.move(n.site.point, 16),
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

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
