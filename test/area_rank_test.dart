import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion_format/lychnion_format.dart';

CatalogItem _item(String id, [PackageRecord? record]) => CatalogItem(
  id: id,
  kind: ItemKind.map,
  titles: const {},
  version: '1',
  licence: '',
  files: const [],
  record: record,
);

Future<PackageRecord> _signed(String id, List<String>? area) async =>
    PackageRecord.sign({
      'format': 1,
      'id': id,
      'kind': 'map',
      'version': '2026.11.1',
      'publisher': 'test',
      'signed': '2026-11-18',
      'area': ?area,
      'files': [
        {'name': '$id.pmtiles', 'size': 1, 'sha256': 'a' * 64},
      ],
    }, await keyPairFromSeed((await newKeyPair()).seed));

void main() {
  test('areaRank: own region, country, anywhere, elsewhere', () {
    expect(areaRank(['JP-30'], 'JP-30'), 3);
    expect(areaRank(['JP-27', 'JP-28'], 'JP-28'), 3);
    expect(areaRank(['JP'], 'JP-30'), 2);
    expect(areaRank([], 'JP-30'), 1);
    expect(areaRank(['JP-28'], 'JP-30'), 0);
    expect(areaRank(['US-CA'], 'JP-30'), 0);
  });

  test('areaRank: only the country known', () {
    expect(areaRank(['JP-30'], 'JP'), 2);
    expect(areaRank(['JP'], 'JP'), 3);
    expect(areaRank(['US'], 'JP'), 0);
  });

  test('byArea keeps catalog order without a region and for ties', () {
    final items = [_item('a'), _item('b'), _item('c')];
    expect(byArea(items, null).map((i) => i.id), ['a', 'b', 'c']);
    expect(byArea(items, 'JP-30').map((i) => i.id), ['a', 'b', 'c']);
  });

  test('byArea: own region first, then the country, then others', () async {
    final items = [
      _item('osaka', await _signed('osaka', ['JP-27', 'JP-28'])),
      _item('world', await _signed('world', null)),
      _item('japan', await _signed('japan', ['JP'])),
      _item('kushimoto', await _signed('kushimoto', ['JP-30'])),
    ];
    expect(byArea(items, 'JP-30').map((i) => i.id), [
      'kushimoto',
      'japan',
      'world',
      'osaka',
    ]);
  });
}
