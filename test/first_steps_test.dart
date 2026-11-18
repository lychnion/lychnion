import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/first_steps.dart';
import 'package:lychnion/ui/suggestions.dart';
import 'package:lychnion/app/text_delegates.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ja'),
  localizationsDelegates: appTextDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

FirstSteps _steps({
  bool ai = false,
  bool map = false,
  bool site = false,
  bool asked = false,
}) => FirstSteps(aiReady: ai, mapReady: map, siteSeen: site, asked: asked);

void main() {
  test('progress, current step and ready offline', () {
    expect(_steps().done, 0);
    expect(_steps().current, 0);
    expect(_steps(ai: true).current, 1);
    expect(_steps(ai: true, map: true).readyOffline, isTrue);
    expect(_steps(ai: true, map: true).current, 2);
    final all = _steps(ai: true, map: true, site: true, asked: true);
    expect(all.allDone, isTrue);
    expect(all.current, isNull);
  });

  testWidgets('the current step has the button; Later hides', (t) async {
    var downloads = 0, hidden = 0;
    await t.pumpWidget(
      _app(
        FirstStepsCard(
          steps: _steps(),
          onDownloads: () => downloads++,
          onMap: () {},
          onAsk: () {},
          onHide: () => hidden++,
        ),
      ),
    );
    expect(find.text('はじめの準備'), findsOneWidget);
    expect(find.text('0 / 4'), findsOneWidget);
    // Only the first open step offers its action.
    expect(find.text('ダウンロードへ'), findsOneWidget);
    expect(find.text('地図を開く'), findsNothing);
    await t.tap(find.text('ダウンロードへ'));
    await t.tap(find.text('あとで'));
    expect(downloads, 1);
    expect(hidden, 1);
  });

  testWidgets('done steps are ticked, the next one leads', (t) async {
    var map = 0;
    await t.pumpWidget(
      _app(
        FirstStepsCard(
          steps: _steps(ai: true, map: true),
          onDownloads: () {},
          onMap: () => map++,
          onAsk: () {},
          onHide: () {},
        ),
      ),
    );
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    await t.tap(find.text('地図を開く'));
    expect(map, 1);
  });

  testWidgets('suggestions are grouped under their package', (t) async {
    final pkg = PackageInfo(
      'jp.bousai.core',
      '防災（基本）',
      '1',
      1,
      name: {'ja': '防災'},
      suggestions: {
        'ja': [(icon: 'water', text: '非常用の水はどれくらい必要？')],
      },
    );
    final asked = <String>[];
    await t.pumpWidget(
      _app(SuggestionGroups(packages: [pkg], onAsk: asked.add)),
    );
    expect(find.text('防災'), findsOneWidget);
    await t.tap(find.text('非常用の水はどれくらい必要？'));
    expect(asked, ['非常用の水はどれくらい必要？']);

    // Before questions can be asked, the suggestions do nothing.
    await t.pumpWidget(_app(SuggestionGroups(packages: [pkg], onAsk: null)));
    await t.tap(find.text('非常用の水はどれくらい必要？'));
    expect(asked, hasLength(1));
  });
}
