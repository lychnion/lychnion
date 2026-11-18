import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/guided_tour.dart';
import 'package:lychnion/app/text_delegates.dart';

void main() {
  late TourKeys keys;
  var ended = 0;

  Widget app() => MaterialApp(
    locale: const Locale('ja'),
    localizationsDelegates: appTextDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            // Only three of the seven parts are on screen.
            SizedBox(key: keys.status, height: 40, child: const Text('S')),
            SizedBox(key: keys.bar, height: 40, child: const Text('B')),
            SizedBox(key: keys.menu, height: 40, child: const Text('M')),
            TextButton(
              onPressed: () => showGuidedTour(
                context,
                tourStops(context, keys),
                onEnd: () => ended++,
              ),
              child: const Text('start'),
            ),
          ],
        ),
      ),
    ),
  );

  setUp(() {
    keys = TourKeys();
    ended = 0;
  });

  testWidgets('parts not on screen are skipped; next, back, done', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    expect(find.text('使い方 1 / 3'), findsOneWidget);
    expect(find.text('準備の状態'), findsOneWidget);
    expect(find.text('戻る'), findsNothing);

    await t.tap(find.text('次へ'));
    await t.pumpAndSettle();
    expect(find.text('使い方 2 / 3'), findsOneWidget);
    expect(find.text('質問する'), findsOneWidget);

    await t.tap(find.text('戻る'));
    await t.pumpAndSettle();
    expect(find.text('使い方 1 / 3'), findsOneWidget);

    await t.tap(find.text('次へ'));
    await t.pumpAndSettle();
    await t.tap(find.text('次へ'));
    await t.pumpAndSettle();
    expect(find.text('メニュー'), findsOneWidget);
    await t.tap(find.text('はじめる'));
    await t.pumpAndSettle();
    expect(find.textContaining('使い方'), findsNothing);
    expect(ended, 1);
  });

  testWidgets('skip ends the tour at once', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    await t.tap(find.text('スキップ'));
    await t.pumpAndSettle();
    expect(find.textContaining('使い方'), findsNothing);
    expect(ended, 1);
  });
}
