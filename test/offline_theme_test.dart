import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/map/offline_theme.dart';

void main() {
  List<String> ids(bool contours) => offlineLightTheme(
    lang: 'ja',
    contours: contours,
  ).layers.map((l) => l.id).toList();

  test('without contours the theme has no contour layers', () {
    expect(ids(false).where((id) => id.startsWith('contours')), isEmpty);
  });

  test('contour lines go under the roads, labels under the other labels', () {
    final plain = ids(false), withC = ids(true);
    expect(withC.length, plain.length + 4);
    expect(withC.where((id) => !id.startsWith('contours')), plain);
    final roads = withC.indexOf('roads_tunnels_other_casing');
    for (final id in ['contours_low', 'contours_minor', 'contours_index']) {
      expect(withC.indexOf(id), lessThan(roads), reason: id);
    }
    final label = withC.indexOf('contours_label');
    final firstOtherSymbol = offlineLightTheme(lang: 'ja', contours: true)
        .layers
        .indexWhere((l) => l.type.name == 'symbol' && l.id != 'contours_label');
    expect(label, lessThan(firstOtherSymbol));
  });
}
