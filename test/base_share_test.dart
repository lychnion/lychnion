import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/base/base_panel.dart';
import 'package:lychnion/ui/ask_view.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  Widget app(AppSettings settings, ValueNotifier<List<String>> urls) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: settings,
              builder: (_, _) =>
                  BaseShareSection(settings: settings, urls: urls),
            ),
          ),
        ),
      );

  testWidgets('turning sharing on asks for a name first', (t) async {
    final settings = AppSettings();
    final urls = ValueNotifier<List<String>>(const []);
    await t.pumpWidget(app(settings, urls));

    // Cancelling the name leaves sharing off.
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Base name'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(settings.sharing, isFalse);

    // With a name: on, and the codes show once the server has addresses.
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '  Minami shelter ');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(settings.sharing, isTrue);
    expect(settings.sharingName, 'Minami shelter');
    expect(find.text('Starts as soon as the app is ready.'), findsOneWidget);

    urls.value = ['http://192.168.1.20:8642'];
    await t.pumpAndSettle();
    expect(find.byType(BaseQrCard), findsOneWidget);
    expect(find.text('Show large'), findsOneWidget);

    // One code at a time: the browser page first, the app on request.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('without the app'), findsOneWidget);
    await t.tap(find.byIcon(Icons.phone_iphone_rounded));
    await t.pumpAndSettle();
    expect(find.textContaining('Minami shelter'), findsWidgets);
    expect(find.textContaining('without the app'), findsNothing);

    // Full screen for the entrance.
    await t.tap(find.text('Show large'));
    await t.pumpAndSettle();
    expect(find.text('Show large'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    // Off again: the name is kept for next time.
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(settings.sharing, isFalse);
    expect(settings.sharingName, 'Minami shelter');
    expect(find.byType(BaseQrCard), findsNothing);
  });

  testWidgets('a phone connects to a base by its address', (t) async {
    final settings = AppSettings();
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => BaseSettingsTile(settings: settings),
          ),
        ),
      ),
    );
    // Cancel, then connect: the dialog closes without errors both times.
    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(settings.baseUrl, isNull);

    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '192.168.1.20');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    expect(settings.baseUrl, 'http://192.168.1.20:8642');
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('share texts count in words people use', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.shareNearbyItems(1), 'Sharing 1 item');
    expect(en.shareNearbyItems(3), 'Sharing 3 items');
    expect(en.shareReceiveFound(1), '1 item available');
    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(ja.shareNearbyItems(3), '共有中：3件');
  });

  testWidgets('the menu offers sharing only when the app passes it', (t) async {
    var opened = 0;
    Widget menu({VoidCallback? share}) => MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: AppBar(
          actions: [AppMenu(onOpenSettings: () {}, onShareNearby: share)],
        ),
      ),
    );
    await t.pumpWidget(menu(share: () => opened++));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('近くの人に共有'));
    await t.pumpAndSettle();
    expect(opened, 1);

    // Computers share as a base: no entry.
    await t.pumpWidget(menu());
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('近くの人に共有'), findsNothing);
  });
}
