import 'package:lychnion/map/evac_sites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:lychnion/map/map_labels.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  final en = lookupAppLocalizations(const Locale('en'));
  final sites = EvacSites.open('assets/maps/jp.map.nishinomiya.sites.sqlite');
  const cityHall = LatLng(34.7376, 135.3417); // 西宮市役所

  test('nearest tsunami sites are sorted and all designated for tsunami', () {
    final near = sites.nearest(cityHall, hazard: Hazard.tsunami);
    expect(near, hasLength(5));
    for (var i = 0; i < near.length; i++) {
      expect(near[i].site.hazards, contains(Hazard.tsunami));
      expect(near[i].site.emergency, isTrue);
      if (i > 0) {
        expect(near[i].meters, greaterThanOrEqualTo(near[i - 1].meters));
      }
    }
    // ignore: avoid_print
    print([
      for (final n in near)
        '${n.site.name} ${n.meters.round()} m ${siteDirection(ja, n)}',
    ]);
  });

  test('shelters are never offered as emergency sites', () {
    final near = sites.nearest(cityHall, limit: 50);
    expect(near.every((n) => n.site.emergency), isTrue);
  });

  test('compass direction', () {
    final north = SiteDistance(sites.sites.first, 0, 0);
    final southWest = SiteDistance(sites.sites.first, 0, 225);
    expect(siteDirection(en, north), 'N');
    expect(siteDirection(ja, southWest), '南西');
  });

  test('keeps the GSI usage notes for the app', () {
    expect(sites.notice, contains('ご利用上の注意'));
  });

  test('city from the address and missing hazard designations', () {
    expect(sites.cityAt(cityHall), '西宮市');
    // GSI data: Nishinomiya marks no site for earthquakes, Kobe marks all.
    expect(sites.cityHasSiteFor('西宮市', Hazard.earthquake), isFalse);
    expect(sites.cityHasSiteFor('西宮市', Hazard.tsunami), isTrue);
    expect(sites.cityHasSiteFor('神戸市', Hazard.earthquake), isTrue);
    final near = sites.nearest(cityHall, hazard: Hazard.earthquake, limit: 1);
    expect(near.single.site.city, isNot('西宮市'));
  });

  test('the map area covers Nishinomiya, not Kushimoto', () {
    expect(sites.covers(const LatLng(34.7376, 135.3417)), isTrue);
    // Kushimoto (Wakayama), about 130 km south: another map's area.
    expect(sites.covers(const LatLng(33.4774, 135.7783)), isFalse);
  });
}
