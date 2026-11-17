import 'package:lychnion/map/evac_sites.dart';
import 'package:lychnion/map/hazard_detect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds the hazard in Japanese and English questions', () {
    expect(hazardFor('海の近くで強い揺れを感じました。津波警報はまだ出ていません。', []), Hazard.tsunami);
    expect(
      hazardFor('大きな地震で揺れているとき、家の中ではまず何をすればいいですか？', []),
      Hazard.earthquake,
    );
    expect(hazardFor('大雨で川が氾濫しそうです', []), Hazard.flood);
    expect(
      hazardFor('What should I do indoors during a strong earthquake?', []),
      Hazard.earthquake,
    );
    expect(
      hazardFor('Is a tsunami coming after the quake?', []),
      Hazard.tsunami,
    );
  });

  test('no hazard, no evacuation site', () {
    expect(hazardFor('腕から血がたくさん出ています。', []), isNull);
    expect(hazardFor('What should I pack for a day hike?', []), isNull);
  });

  test('warnings: the most urgent hazard wins, lifted ones are ignored', () {
    expect(hazardForWarnings([]), isNull);
    expect(hazardForWarnings(['大津波警報', '串本町']), Hazard.tsunami);
    // Tsunami wins over the earthquake that caused it.
    expect(hazardForWarnings(['緊急地震速報 和歌山県南部', '津波警報 和歌山県']), Hazard.tsunami);
    expect(hazardForWarnings(['大雨警報 西宮市']), Hazard.flood);
    // A lifted tsunami warning no longer counts.
    expect(hazardForWarnings(['津波注意報解除']), isNull);
    expect(hazardForWarnings(['津波警報解除', '大雨警報']), Hazard.flood);
    expect(hazardForWarnings(['Tsunami warning lifted']), isNull);
    expect(
      hazardForWarnings(['Tsunami warning: Wakayama coast']),
      Hazard.tsunami,
    );
    // A warning without a known hazard: no special site.
    expect(hazardForWarnings(['停電のお知らせ']), isNull);
  });
}
