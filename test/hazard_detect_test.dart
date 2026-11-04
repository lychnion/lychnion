import 'package:fieldkit/map/evac_sites.dart';
import 'package:fieldkit/map/hazard_detect.dart';
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
}
