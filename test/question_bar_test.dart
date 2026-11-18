import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/ask_view.dart';

void main() {
  Widget bar({required bool ready, bool loading = false, bool busy = false}) =>
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QuestionBar(
            input: TextEditingController(),
            ready: ready,
            busy: busy,
            loading: loading,
            onSend: () {},
            onStop: () {},
          ),
        ),
      );

  testWidgets('while loading the bar says so and still takes a question', (
    t,
  ) async {
    await t.pumpWidget(bar(ready: true, loading: true));
    expect(find.text('準備中…'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    final send = t.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(send.onPressed, isNotNull);
  });

  testWidgets('while an answer is written, stop replaces send', (t) async {
    await t.pumpWidget(bar(ready: true, busy: true));
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });

  testWidgets('when ready the bar asks for a question', (t) async {
    await t.pumpWidget(bar(ready: true));
    expect(find.text('質問を入力'), findsOneWidget);
  });
}
