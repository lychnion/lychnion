// Finding bases on the local Wi-Fi (docs/distribution.md, step 5e).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/base/base_discovery.dart';
import 'package:lychnion/base/base_link.dart';
import 'package:lychnion/base/base_panel.dart';

/// Lists [bases] at once, without the network.
class _FakeFinder extends BaseFinder {
  _FakeFinder(this.bases);
  final List<BaseLink> bases;
  @override
  Future<void> start() async => found.value = bases;
  @override
  Future<void> stop() async {}
}

void main() {
  final key = 'A' * 43;

  group('an announcement', () {
    BaseLink? link(
      List<String> addresses, {
      int port = 8642,
      Map<String, String> attributes = const {},
    }) => baseLinkFrom(
      addresses: addresses,
      port: port,
      attributes: attributes,
      serviceName: 'Base',
    );

    test('gives the first private IPv4 address and the name', () {
      final l = link(
        [
          'fe80::1',
          '127.0.0.1',
          '169.254.3.4',
          '8.8.8.8',
          '192.168.1.20',
          '10.0.0.2',
        ],
        attributes: {'name': '中央小学校', 'key': key},
      )!;
      expect(l.url, 'http://192.168.1.20:8642');
      expect(l.name, '中央小学校');
      // An announced key is not checked in person: not kept.
      expect(l.key, isNull);
      expect(link(['172.20.10.2'])!.url, 'http://172.20.10.2:8642');
      expect(link(['100.64.0.5'])!.url, 'http://100.64.0.5:8642');
    });

    test('without a usable address or port it is left out', () {
      expect(link(['fe80::1', '2001:db8::1']), isNull);
      expect(link(['8.8.8.8', '0.0.0.0', '255.255.255.255']), isNull);
      expect(link(['172.32.0.1', '192.169.0.1']), isNull);
      expect(link(['not an address']), isNull);
      expect(link(['192.168.1.20'], port: 0), isNull);
      expect(link(['192.168.1.20'], port: 70000), isNull);
    });

    test('the name is cleaned', () {
      final l = link(
        ['192.168.1.20'],
        attributes: {'name': '\u202eevil\u0000 base'},
      )!;
      expect(l.name, 'evil base');
      // No name in the announcement: the service name.
      expect(link(['192.168.1.20'])!.name, 'Base');
    });
  });

  test('what a base announces fits the DNS limits', () {
    final long = '避難所' * 30;
    expect(utf8.encode(instanceName(long)).length, lessThanOrEqualTo(63));
    expect(instanceName('  '), 'Lychnion');
    final a = baseAttributes(name: long, key: key);
    expect(a['name']!.runes.length, 60);
    expect(a['key'], key);
    expect(baseAttributes(name: 'x', key: 'bad').containsKey('key'), isFalse);
  });

  testWidgets('a phone picks a base found on the Wi-Fi, after a question', (
    t,
  ) async {
    final settings = AppSettings();
    const base = BaseLink('http://192.168.1.20:8642', name: 'Central school');
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => BaseSettingsTile(
              settings: settings,
              newFinder: () => _FakeFinder([base]),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    expect(find.text('Bases on this Wi-Fi'), findsOneWidget);
    await t.tap(find.text('Central school'));
    await t.pumpAndSettle();
    // The same question as for a QR code.
    expect(find.textContaining('Central school'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    expect(settings.baseUrl, base.url);
    expect(settings.baseName, 'Central school');
    // Its facts are trusted only after its QR code is scanned.
    expect(settings.baseKey, isNull);
    expect(find.textContaining('QR code to trust'), findsOneWidget);
  });
}
