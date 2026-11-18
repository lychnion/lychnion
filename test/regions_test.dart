import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/region.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/regions.dart';

void main() {
  final regions = RegionLookup.open('assets/regions/regions.sqlite');

  test('finds the prefecture or state at a position', () {
    expect(regions.length, greaterThan(4000));
    expect(regions.codeAt(34.7376, 135.3416), 'JP-28'); // 西宮市役所
    expect(regions.codeAt(33.4720, 135.7790), 'JP-30'); // 串本町
    expect(regions.codeAt(35.6812, 139.7671), 'JP-13'); // 東京駅
    expect(regions.codeAt(43.0687, 141.3508), 'JP-01'); // 札幌駅
    expect(regions.codeAt(47.3769, 8.5417), 'CH-ZH'); // Zürich
    expect(regions.codeAt(30.0, 140.0), isNull); // Pacific
  });

  test('names in Japanese, English as fallback', () {
    expect(regions.nameOf('JP-28', 'ja'), '兵庫県');
    expect(regions.nameOf('JP-28', 'en'), contains('Hy'));
    expect(regions.nameOf('CH-ZH', 'ja'), isNotNull);
  });

  test('a source for the prefecture ranks above a national one', () {
    final user = regions.codeAt(34.7376, 135.3416)!;
    expect(
      localityBoost('JP-28', user),
      greaterThan(localityBoost('JP', user)),
    );
    expect(localityBoost('JP-13', user), localityBoost('JP', user));
  });

  test('the picker lists all 47 prefectures in order', () {
    final jp = regions.regionsOf('JP');
    expect(jp, hasLength(47));
    expect(jp.first, 'JP-01');
    expect(jp.last, 'JP-47');
  });

  test('a region set by hand wins over the position', () async {
    final settings = AppSettings()..region = 'JP-13';
    expect(await UserRegion.current(settings, null), 'JP-13');
  });
}
