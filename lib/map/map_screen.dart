import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'evac_sites.dart';

/// Offline map: base map from a local PMTiles file, emergency evacuation
/// sites for the chosen hazard, and the nearest ones from the current position.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.pmtilesPath,
    required this.sitesAsset,
    this.mockLocation,
    this.english = false,
  });

  final String pmtilesPath;
  final String sitesAsset;

  /// "lat,lon" for testing without a GPS fix.
  final String? mockLocation;
  final bool english;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  EvacSites? _sites;
  PmTilesVectorTileProvider? _tiles;
  LatLng? _here;
  String _locationStatus = '';
  Hazard? _hazard = Hazard.tsunami;
  String? _error;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final sites = await EvacSites.fromAsset(widget.sitesAsset);
      final tiles = await PmTilesVectorTileProvider.fromSource(
        widget.pmtilesPath,
      );
      setState(() {
        _sites = sites;
        _tiles = tiles;
      });
      await _locate();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _locate() async {
    final mock = widget.mockLocation;
    if (mock != null && mock.isNotEmpty) {
      final p = mock.split(',').map(double.parse).toList();
      setState(() {
        _here = LatLng(p[0], p[1]);
        _locationStatus = en ? 'Test location' : 'テスト用の位置';
      });
      return;
    }
    try {
      // GPS works without a network; only the satellite fix takes time.
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(
          () =>
              _locationStatus = en ? 'No location permission' : '位置情報の許可がありません',
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      setState(() {
        _here = LatLng(pos.latitude, pos.longitude);
        _locationStatus = en
            ? 'Location ±${pos.accuracy.round()} m'
            : '現在地 ±${pos.accuracy.round()} m';
      });
      _map.move(_here!, 15);
    } catch (e) {
      setState(
        () => _locationStatus = en ? 'Location not available' : '現在地を取得できません',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final sites = _sites, tiles = _tiles;
    if (sites == null || tiles == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final from = _here ?? sites.center;
    final nearest = sites.nearest(from, hazard: _hazard);
    final shown = [
      for (final s in sites.sites)
        if (s.emergency && (_hazard == null || s.hazards.contains(_hazard))) s,
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
                    selected: _hazard == h,
                    onSelected: (_) => setState(() => _hazard = h),
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
              initialCenter: from,
              initialZoom: 14,
              minZoom: 10,
              maxZoom: 18,
            ),
            children: [
              VectorTileLayer(
                theme: ProtomapsThemes.lightV4(),
                tileProviders: TileProviders({'protomaps': tiles}),
                maximumZoom: 18,
              ),
              MarkerLayer(
                markers: [
                  for (final s in shown)
                    Marker(
                      point: s.point,
                      width: 14,
                      height: 14,
                      child: Tooltip(
                        message: s.name,
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
                  if (_here != null)
                    Marker(
                      point: _here!,
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
                          ? 'Nearest emergency evacuation sites for ${_hazard?.en ?? 'any hazard'}'
                          : '${_hazard?.ja ?? 'すべて'}の指定緊急避難場所（近い順）',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(_locationStatus, style: theme.textTheme.bodySmall),
                  IconButton(
                    onPressed: _locate,
                    icon: const Icon(Icons.my_location),
                  ),
                ],
              ),
              for (final n in nearest)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    '${(n.meters / 1000).toStringAsFixed(n.meters < 1000 ? 2 : 1)} km\n${n.direction(en)}',
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
