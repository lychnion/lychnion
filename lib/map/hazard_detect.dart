import '../knowledge/knowledge_package.dart';
import 'evac_sites.dart';

/// Which hazard a question is about, so the answer can show where to go.
///
/// Fixed safety lines win (the tsunami line means tsunami sites). Otherwise
/// simple Japanese and English keywords; the first match in this order wins,
/// because "tsunami after an earthquake" is about the tsunami.
Hazard? hazardFor(String question, List<Alert> alerts) {
  if (alerts.any((a) => a.id.startsWith('tsunami'))) return Hazard.tsunami;
  final q = question.toLowerCase();
  for (final (hazard, words) in _keywords) {
    if (words.any(q.contains)) return hazard;
  }
  return null;
}

const _keywords = <(Hazard, List<String>)>[
  (Hazard.tsunami, ['津波', 'tsunami']),
  (Hazard.volcano, ['噴火', '火山', 'eruption', 'volcan']),
  (Hazard.stormSurge, ['高潮', 'storm surge']),
  (
    Hazard.landslide,
    ['土砂', '崖崩れ', 'がけ崩れ', '土石流', '地滑り', '地すべり', 'landslide', 'mudslide'],
  ),
  (Hazard.flood, ['洪水', '氾濫', '浸水', '大雨', 'flood', 'heavy rain']),
  (Hazard.fire, ['火事', '火災', 'fire']),
  (Hazard.earthquake, ['地震', '揺れ', 'earthquake', 'quake', 'shaking']),
];
