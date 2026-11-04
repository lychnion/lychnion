import 'package:fieldkit/map/evac_sites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
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
        '${n.site.name} ${n.meters.round()} m ${n.direction(false)}',
    ]);
  });

  test('shelters are never offered as emergency sites', () {
    final near = sites.nearest(cityHall, limit: 50);
    expect(near.every((n) => n.site.emergency), isTrue);
  });

  test('compass direction', () {
    final north = SiteDistance(sites.sites.first, 0, 0);
    final southWest = SiteDistance(sites.sites.first, 0, 225);
    expect(north.direction(true), 'N');
    expect(southWest.direction(false), '南西');
  });

  test('keeps the GSI usage notes for the app', () {
    expect(sites.notice, contains('ご利用上の注意'));
  });
}
