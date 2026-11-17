import '../map/evac_sites.dart';
import 'fact.dart';

/// Made-up facts around 西宮市役所 for demos and tests (dev flag DEMO_FACTS).
/// Clearly marked as test data in their source name. In another area (no
/// such sites) the shelter facts are left out; the warning still shows.
List<Fact> demoFacts(EvacSites sites, DateTime now) {
  String? site(String name, Hazard h) => sites.sites
      .where((s) => s.emergency && s.name == name && s.hazards.contains(h))
      .firstOrNull
      ?.uid;
  Fact f(
    FactKind kind,
    String subject,
    String value,
    SourceType src,
    String name, {
    required int minutesAgo,
    int ttlMinutes = 180,
    String note = '',
  }) => Fact(
    kind: kind,
    subject: subject,
    value: value,
    observedAt: now.subtract(Duration(minutes: minutesAgo)),
    expiresAt: now.add(Duration(minutes: ttlMinutes - minutesAgo)),
    sourceType: src,
    sourceName: name,
    note: note,
  );
  final cityHall = site('市役所', Hazard.tsunami);
  final hall = site('市民会館', Hazard.tsunami);
  return [
    if (cityHall != null) ...[
      f(
        FactKind.shelterStatus,
        cityHall,
        'open',
        SourceType.official,
        '西宮市（テスト）',
        minutesAgo: 95,
      ),
      f(
        FactKind.shelterStatus,
        cityHall,
        'full',
        SourceType.official,
        '西宮市（テスト）',
        minutesAgo: 20,
        note: '受け入れ停止',
      ),
    ],
    if (hall != null)
      f(
        FactKind.shelterStatus,
        hall,
        'crowded',
        SourceType.citizen,
        '住民（テスト）',
        minutesAgo: 8,
      ),
    f(
      FactKind.roadBlocked,
      '34.7349,135.3420',
      'blocked',
      SourceType.citizen,
      '住民（テスト）',
      minutesAgo: 35,
      note: '倒壊家屋で通行止め',
    ),
    f(
      FactKind.warning,
      '西宮市',
      '津波警報',
      SourceType.official,
      '気象庁（テスト）',
      minutesAgo: 12,
      ttlMinutes: 360,
    ),
    // Expired: must never be shown.
    f(
      FactKind.waterPoint,
      '34.7390,135.3440',
      '給水車',
      SourceType.official,
      '西宮市（テスト）',
      minutesAgo: 400,
      ttlMinutes: 120,
    ),
  ];
}
