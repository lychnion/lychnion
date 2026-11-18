import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../download/download_store.dart';
import '../knowledge/regions.dart';
import '../map/map_state.dart';
import 'lang.dart';
import 'settings.dart';

/// The user's region for ranking local sources ('JP-30', 'JP'): set by hand
/// in Settings, else from the position, else Japan. The position and the
/// region stay on this device.
class UserRegion {
  static Future<RegionLookup>? _lookup;

  /// Boundaries from `assets/regions/` (copied out once per start).
  static Future<RegionLookup> lookup() => _lookup ??= DownloadStore.instance()
      .then((s) => s.copyBundled('regions', 'regions.sqlite'))
      .then(RegionLookup.open)
      .catchError((Object _) => RegionLookup.empty);

  /// The region at the user's position, or null when it is not known: the
  /// map's position (GPS or MOCK_LOCATION), else the phone's last known
  /// position when location is already allowed (no prompt just for this).
  static Future<String?> detect(MapState? map, {String? mockLocation}) async {
    double? lat = map?.here?.latitude, lon = map?.here?.longitude;
    // MOCK_LOCATION counts even before a map area is loaded.
    final mock = (mockLocation ?? map?.mockLocation)?.split(',');
    if (lat == null && mock != null && mock.length == 2) {
      lat = double.tryParse(mock[0]);
      lon = double.tryParse(mock[1]);
    }
    final phone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (lat == null && phone) {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final p = await Geolocator.getLastKnownPosition();
          lat = p?.latitude;
          lon = p?.longitude;
        }
      } on Object {
        // No location service.
      }
    }
    if (lat == null || lon == null) return null;
    return (await lookup()).codeAt(lat, lon);
  }

  /// What answers use: the manual choice, else the detected region, else
  /// 'JP'.
  static Future<String> current(
    AppSettings? settings,
    MapState? map, {
    String? mockLocation,
  }) async =>
      settings?.region ?? await detect(map, mockLocation: mockLocation) ?? 'JP';
}

/// Settings row: the region in use, and a picker to set it by hand.
class RegionTile extends StatefulWidget {
  const RegionTile({
    super.key,
    required this.settings,
    this.map,
    this.mockLocation,
  });

  final AppSettings settings;
  final MapState? map;

  /// MOCK_LOCATION, for tests without a map area.
  final String? mockLocation;

  @override
  State<RegionTile> createState() => _RegionTileState();
}

class _RegionTileState extends State<RegionTile> {
  RegionLookup? _lookup;
  String? _detected;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final lookup = await UserRegion.lookup();
    final detected = await UserRegion.detect(
      widget.map,
      mockLocation: widget.mockLocation,
    );
    if (!mounted) return;
    setState(() {
      _lookup = lookup;
      _detected = detected;
      _done = true;
    });
  }

  String _name(String code, String lang) {
    if (code == 'JP') return context.l10n.regionJapan;
    return _lookup?.nameOf(code, lang) ?? code;
  }

  Future<void> _pick() async {
    final lookup = _lookup;
    if (lookup == null) return;
    final l = context.l10n;
    final lang = context.lang;
    final options = [
      for (final r in lookup.regionsOf('JP')) (r, lookup.nameOf(r, lang) ?? r),
    ];
    // Returns '' for automatic, a code for a region, null when dismissed.
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => RadioGroup<String>(
          groupValue: widget.settings.region ?? '',
          onChanged: (v) => Navigator.pop(c, v),
          child: ListView(
            controller: scroll,
            children: [
              RadioListTile<String>(
                value: '',
                title: Text(l.regionAuto),
                subtitle: Text(
                  _detected == null ? l.regionUnknown : _name(_detected!, lang),
                ),
              ),
              const Divider(),
              RadioListTile<String>(value: 'JP', title: Text(l.regionJapan)),
              for (final (code, name) in options)
                RadioListTile<String>(value: code, title: Text(name)),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await widget.settings.setRegion(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final scheme = Theme.of(context).colorScheme;
    final manual = widget.settings.region;
    final String value;
    if (!_done) {
      value = '…';
    } else if (manual != null) {
      value = l.regionManual(_name(manual, lang));
    } else if (_detected != null) {
      value = l.regionAutoIs(_name(_detected!, lang));
    } else {
      value = l.regionUnknown;
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.place_outlined, size: 20),
      ),
      title: Text(value),
      subtitle: Text(l.regionHint),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _done ? _pick : null,
    );
  }
}
