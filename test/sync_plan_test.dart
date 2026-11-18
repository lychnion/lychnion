// What the app fetches by itself (docs/distribution.md, step 5).
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/catalog.dart';
import 'package:lychnion/download/download_manager.dart' show ItemStatus;
import 'package:lychnion/download/sync_plan.dart';
import 'package:lychnion_format/lychnion_format.dart';

void main() {
  late Catalog c;

  setUpAll(() async {
    final key = await Ed25519().newKeyPair();
    final trust = TrustedKeys({
      'lychnion': [await publicKeyOf(key)],
    });
    Future<Map<String, Object?>> rec(String id, String kind) async =>
        (await PackageRecord.sign({
          'format': 1,
          'id': id,
          'kind': kind,
          'version': '1',
          'publisher': 'lychnion',
          'title': {'en': id},
          'files': [
            {'name': '$id.bin', 'size': 10, 'sha256': 'a' * 64},
          ],
          'signed': '2026-11-18T09:00:00+09:00',
        }, key)).json;
    c = await Catalog.parse(
      jsonEncode({
        'format': 2,
        'records': [
          await rec('guide', 'package'),
          await rec('map', 'map'),
          await rec('model', 'model'),
          await rec('updated', 'package'),
          await rec('broken', 'package'),
        ],
      }),
      trust: trust,
    );
  });

  List<String> plan({
    bool updates = false,
    bool keepAll = false,
    bool keepModels = false,
  }) => [
    for (final i in itemsToSync(
      c,
      status: (i) => switch (i.id) {
        'updated' => ItemStatus.update,
        _ => ItemStatus.absent,
      },
      error: (i) => i.id == 'broken' ? 'signature' : null,
      updates: updates,
      keepAll: keepAll,
      keepModels: keepModels,
    ))
      i.id,
  ];

  test('automatic updates: only new versions of what is installed', () {
    expect(plan(updates: true), ['updated']);
    expect(plan(), isEmpty);
  });

  test('keeping everything: every guide and map, models on request', () {
    expect(plan(keepAll: true), ['guide', 'map', 'updated']);
    expect(plan(keepAll: true, keepModels: true), [
      'guide',
      'map',
      'model',
      'updated',
    ]);
  });

  test('an item that failed for good is not tried again by itself', () {
    expect(plan(keepAll: true, updates: true), isNot(contains('broken')));
  });

  test('connections: never offline; computers on any, phones on Wi-Fi', () {
    const none = [ConnectivityResult.none];
    const mobile = [ConnectivityResult.mobile];
    const wifi = [ConnectivityResult.wifi];
    expect(syncAllowed(none, desktop: true), isFalse);
    expect(syncAllowed(const [], desktop: false), isFalse);
    expect(syncAllowed(mobile, desktop: false), isFalse);
    expect(syncAllowed(mobile, desktop: true), isTrue);
    expect(syncAllowed(wifi, desktop: false), isTrue);
    expect(
      syncAllowed(const [ConnectivityResult.other], desktop: true),
      isTrue,
    );
    expect(isOnline(none), isFalse);
    expect(isOnline(mobile), isTrue);
  });
}
