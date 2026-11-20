import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/map/map_screen.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));
  const basemap = '© OpenStreetMap contributors, Protomaps';

  test('the base map and the sites are always credited', () {
    expect(mapCredits(en, basemap: basemap), [basemap, en.mapAttributionSites]);
  });

  test('heights, flood and contours are credited only when shown', () {
    expect(
      mapCredits(
        ja,
        basemap: basemap,
        heights: true,
        flood: true,
        contours: true,
      ),
      [
        basemap,
        ja.mapAttributionSites,
        ja.mapAttributionHeights,
        ja.mapAttributionFlood,
        ja.mapAttributionContours,
      ],
    );
    expect(
      mapCredits(ja, basemap: basemap, contours: false),
      isNot(contains(ja.mapAttributionContours)),
    );
  });

  test('a map file without a base map credit leaves no empty line', () {
    expect(mapCredits(en, basemap: ''), [en.mapAttributionSites]);
  });
}
