import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/answer_card.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ja'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Hit _hit(int id, String sourceId, String title) => Hit(
  Passage(
    id,
    Source(sourceId, title, '首相官邸', 'https://example.org', 'PDL1.0', ''),
    '',
    'text',
  ),
  1,
);

void main() {
  testWidgets('searching: the plain line', (t) async {
    final a = GroundedAnswer('津波は一回だけですか？', lang: 'ja');
    await t.pumpWidget(_app(AnswerWaiting(answer: a)));
    expect(find.text('資料を確認しています…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'reading: sources once each, time left, and on a slow '
    'phone a base hint',
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    (t) async {
      final a = GroundedAnswer('津波は一回だけですか？', lang: 'ja')
        ..hits = [
          _hit(1, 'kantei-tsunami', '津波から身を守る'),
          _hit(2, 'kantei-tsunami', '津波から身を守る'),
          _hit(3, 'kantei-jishin', '地震に備えて'),
        ];
      await t.pumpWidget(
        _app(AnswerWaiting(answer: a, expected: const Duration(seconds: 40))),
      );
      // Three passages from two pages: two sources.
      expect(find.text('資料2件を読んでいます…'), findsOneWidget);
      expect(find.text('首相官邸「津波から身を守る」'), findsOneWidget);
      expect(find.text('首相官邸「地震に備えて」'), findsOneWidget);
      expect(find.textContaining('あと約'), findsOneWidget);
      expect(find.text('ベースにつなぐと、数秒で答えます'), findsOneWidget);
    },
  );

  // The note after 10 s is not tested: AnswerWaiting times itself with a
  // real Stopwatch, which t.pump() does not move.
  testWidgets('first answer: no estimate, the bar just moves', (t) async {
    final a = GroundedAnswer('津波は一回だけですか？', lang: 'ja')
      ..hits = [_hit(1, 'kantei-tsunami', '津波から身を守る')];
    await t.pumpWidget(_app(AnswerWaiting(answer: a)));
    expect(find.textContaining('あと約'), findsNothing);
    final bar = t.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });
}
