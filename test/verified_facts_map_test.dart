// Only confirmed facts change the suggested evacuation site or route
// (lychnion/lychnion#69): a resident report or an "official" fact whose
// signature does not check out is shown, but not acted on.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/map/evac_sites.dart';
import 'package:lychnion/map/map_state.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20, 6);
  final site = EvacSite(
    'Central school',
    '兵庫県西宮市',
    const LatLng(34.73, 135.34),
    true,
    {Hazard.tsunami},
    uid: 'site-1',
  );
  late FactSigner city;

  setUpAll(() async => city = await FactSigner.generate());

  Fact fact(FactKind kind, String subject, String value, SourceType src) =>
      Fact(
        kind: kind,
        subject: subject,
        value: value,
        observedAt: now.subtract(const Duration(minutes: 5)),
        expiresAt: now.add(const Duration(hours: 3)),
        sourceType: src,
        sourceName: src == SourceType.official ? 'City' : '',
      );

  Future<MapState> mapWith(List<Fact> facts, {required bool trusted}) async {
    final trust = TrustList();
    if (trusted) await trust.add(city.publicKeyText, 'City');
    final store = FactStore(clock: () => now, trust: trust);
    await store.addAll(facts);
    return MapState(pmtilesPath: '', sitesAsset: '', facts: store);
  }

  group('a full or closed shelter', () {
    test('confirmed: the site is avoided', () async {
      final m = await mapWith([
        await city.sign(
          fact(FactKind.shelterStatus, 'site-1', 'full', SourceType.official),
        ),
      ], trusted: true);
      expect(m.statusOf(site)!.unconfirmed, isFalse);
      expect(m.avoid(site), isTrue);
    });

    test('a resident report: shown, but the site is still suggested', () async {
      final m = await mapWith([
        fact(FactKind.shelterStatus, 'site-1', 'full', SourceType.citizen),
      ], trusted: true);
      expect(m.statusOf(site)?.value, 'full');
      expect(m.avoid(site), isFalse);
    });

    test('"official" but not signed by a trusted key: not acted on', () async {
      final m = await mapWith([
        await city.sign(
          fact(FactKind.shelterStatus, 'site-1', 'closed', SourceType.official),
        ),
      ], trusted: false);
      expect(m.statusOf(site)!.unconfirmed, isTrue);
      expect(m.avoid(site), isFalse);
    });
  });

  test('a newer resident report does not hide a confirmed "full"', () async {
    final confirmed = await city.sign(
      fact(FactKind.shelterStatus, 'site-1', 'full', SourceType.official),
    );
    final later = Fact(
      kind: FactKind.shelterStatus,
      subject: 'site-1',
      value: 'open',
      observedAt: now,
      expiresAt: now.add(const Duration(hours: 3)),
      sourceType: SourceType.citizen,
    );
    final m = await mapWith([confirmed, later], trusted: true);
    // The confirmed fact wins its topic, so the site is still avoided.
    expect(m.statusOf(site)!.value, 'full');
    expect(m.avoid(site), isTrue);
  });

  group('a blocked road', () {
    test('confirmed: the route goes around it', () async {
      final m = await mapWith([
        await city.sign(
          fact(
            FactKind.roadBlocked,
            '34.7301,135.3401',
            'blocked',
            SourceType.official,
          ),
        ),
      ], trusted: true);
      expect(m.blockedPoints, hasLength(1));
    });

    test('a resident report: shown on the map, not routed around', () async {
      final m = await mapWith([
        fact(
          FactKind.roadBlocked,
          '34.7301,135.3401',
          'blocked',
          SourceType.citizen,
        ),
      ], trusted: true);
      expect(m.facts!.currentOf({FactKind.roadBlocked}), hasLength(1));
      expect(m.blockedPoints, isEmpty);
    });
  });

  group('a warning', () {
    test('confirmed: its hazard picks the site and route', () async {
      final m = await mapWith([
        await city.sign(
          fact(FactKind.warning, 'Nishinomiya', '津波警報', SourceType.official),
        ),
      ], trusted: true);
      expect(m.warningHazard, Hazard.tsunami);
    });

    test('unconfirmed: shown, but does not change the suggestion', () async {
      final m = await mapWith([
        fact(FactKind.warning, 'Nishinomiya', '津波警報', SourceType.citizen),
        await city.sign(
          fact(FactKind.warning, 'Nishinomiya', '津波警報', SourceType.official),
        ),
      ], trusted: false);
      expect(m.facts!.currentOf({FactKind.warning}), isNotEmpty);
      expect(m.warningHazard, isNull);
    });
  });
}
