import 'package:material_ui/material_ui.dart';

import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/notices.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/app/settings_screen.dart';
import 'package:lychnion/app/theme.dart';
import 'package:lychnion/knowledge/app_help.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/answer_card.dart';
import 'package:lychnion/ui/ask_view.dart';
import 'package:lychnion/ui/first_steps.dart';
import 'package:lychnion/ui/help_screen.dart';
import 'package:lychnion/app/splash.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_view.dart';
import 'package:lychnion/base/base_panel.dart';
import 'package:lychnion/ui/guided_tour.dart';
import 'package:lychnion/ui/source_link.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lychnion/app/text_delegates.dart';

/// Screens checked with Flutter's accessibility guidelines, in light and
/// dark, Japanese and English, and with text at twice the size.
void main() {
  final book = HelpBook.open('assets/help/app.help.sqlite');
  final infos = [
    for (final id in ['jp.bousai.core', 'jp.outdoor.hiking'])
      KnowledgePackage.readInfo('assets/packages/$id.sqlite'),
  ];
  final src = Source(
    'kantei-tsunami',
    '津波から身を守る',
    '首相官邸',
    'https://example.org',
    'PDL1.0',
    '',
  );
  GroundedAnswer answer() => GroundedAnswer('津波は一回だけですか？', lang: 'ja')
    ..hits = [Hit(Passage(1, src, '津波', '津波は何度も来ます。'), 1)]
    ..alerts = [Alert('a', src, '強い揺れを感じたら、すぐに高い所へ避難してください。')]
    ..text = '津波は一回だけではありません。何度も来ます[1]。';

  final screens = <String, Widget Function()>{
    'home (empty)': () => AskView(
      phase: AskPhase.ready,
      detail: '',
      ready: true,
      busy: false,
      input: TextEditingController(),
      onSend: () {},
      onAsk: (_) {},
      onStop: () {},
      onOpenSettings: () {},
      packageInfos: infos,
      firstSteps: FirstStepsCard(
        steps: const FirstSteps(
          aiReady: true,
          mapReady: false,
          siteSeen: false,
          asked: false,
        ),
        onDownloads: () {},
        onMap: () {},
        onAsk: () {},
        onHide: () {},
      ),
    ),
    'answer': () => Scaffold(
      body: ListView(
        children: [AnswerCard(answer: answer(), grounded: true, done: true)],
      ),
    ),
    'help list': () => HelpScreen(book: book),
    'help topic': () => HelpScreen(book: book, topic: 'help-05-base'),
    'notice': () => NoticeScreen(packages: infos, onAccept: () {}),
    'settings': () => SettingsScreen(settings: AppSettings(), downloads: null),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final lang in ['ja', 'en']) {
      for (final b in Brightness.values) {
        testWidgets('$name, $lang, ${b.name}: guidelines', (t) async {
          final handle = t.ensureSemantics();
          await _pump(t, build(), lang, b, 1);
          final problems = <String>[];
          for (final g in [
            androidTapTargetGuideline,
            iOSTapTargetGuideline,
            labeledTapTargetGuideline,
            textContrastGuideline,
          ]) {
            final e = await g.evaluate(t);
            if (!e.passed) problems.add('${g.description}:\n${e.reason}');
          }
          handle.dispose();
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
      testWidgets('$name, $lang: text at 2.0 fits', (t) async {
        await _pump(t, build(), lang, Brightness.light, 2);
        expect(t.takeException(), isNull);
      });
    }
  }
  group('screen readers', () {
    test('a finished answer is announced with its safety line', () {
      // AskPage says this when an answer completes (not the card, which
      // may be off screen, or "done" early when a question is queued).
      expect(
        answerReadyMessage(answer()),
        '回答が出ました。 強い揺れを感じたら、すぐに高い所へ避難してください。',
      );
      final en = GroundedAnswer('Does a tsunami come only once?', lang: 'en')
        ..text = 'No.';
      expect(answerReadyMessage(en), 'The answer is ready.');
      expect(answerFailedMessage(en), 'No answer this time.');
      expect(answerFailedMessage(answer()), '今回は回答できませんでした。');
    });

    testWidgets('an answer from a base without a QR check says so', (t) async {
      Widget card(bool unchecked) => Scaffold(
        body: ListView(
          children: [
            AnswerCard(
              answer: answer()
                ..answeredBy = 'Hall'
                ..baseUnchecked = unchecked,
              grounded: true,
              done: true,
            ),
          ],
        ),
      );
      // The card speaks the answer's language (Japanese here).
      await _pump(t, card(true), 'en', Brightness.light, 1);
      expect(find.textContaining('確認されていないベース'), findsOneWidget);
      await _pump(t, card(false), 'en', Brightness.light, 1);
      expect(find.textContaining('確認されていないベース'), findsNothing);
      expect(find.textContaining('署名していません'), findsNothing);
    });

    testWidgets('a checked base that did not sign its answer says so', (
      t,
    ) async {
      Widget card({required bool unchecked}) => Scaffold(
        body: ListView(
          children: [
            AnswerCard(
              answer: answer()
                ..answeredBy = 'Hall'
                ..baseUnchecked = unchecked
                ..baseUnsigned = true,
              grounded: true,
              done: true,
            ),
          ],
        ),
      );
      await _pump(t, card(unchecked: false), 'en', Brightness.light, 1);
      expect(find.textContaining('署名していません'), findsOneWidget);
      expect(find.textContaining('確認されていないベース'), findsNothing);
      // Not checked at all says that instead: only one note.
      await _pump(t, card(unchecked: true), 'en', Brightness.light, 1);
      expect(find.textContaining('署名していません'), findsNothing);
      expect(find.textContaining('確認されていないベース'), findsOneWidget);
    });

    testWidgets('the phone\'s own answer says when the base\'s was refused', (
      t,
    ) async {
      Widget card({required bool refused}) => Scaffold(
        body: ListView(
          children: [
            AnswerCard(
              answer: answer()..baseRefused = refused,
              grounded: true,
              done: true,
            ),
          ],
        ),
      );
      await _pump(t, card(refused: true), 'en', Brightness.light, 1);
      expect(find.textContaining('QR コードで確かめられなかった'), findsOneWidget);
      await _pump(t, card(refused: false), 'en', Brightness.light, 1);
      expect(find.textContaining('QR コードで確かめられなかった'), findsNothing);
    });

    testWidgets('the answer card itself announces nothing', (t) async {
      final said = <Object?>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (m) async {
          said.add(m);
          return null;
        },
      );
      final a = answer();
      Widget card(bool done) => Scaffold(
        body: ListView(
          children: [AnswerCard(answer: a, grounded: true, done: done)],
        ),
      );
      await _pump(t, card(false), 'ja', Brightness.light, 1);
      await _pump(t, card(true), 'ja', Brightness.light, 1);
      expect(said, isEmpty);
    });

    testWidgets('safety line, answer text and sources read well', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, screens['answer']!(), 'ja', Brightness.light, 1);
      // Said as a warning, in one piece.
      final labels = _labels(t);
      expect(labels, contains(startsWith('安全のための注意\n強い揺れを感じたら')));
      // Plain text, not a read-only text field.
      expect(labels, contains('津波は一回だけではありません。何度も来ます。'));
      // The app name once, not logo + name.
      expect(labels, isNot(contains('Lychnion')));
      handle.dispose();
    });

    testWidgets('first steps say "1 of 4 done" and the title once', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, screens['home (empty)']!(), 'en', Brightness.light, 1);
      final labels = _labels(t).join('\n').split('\n');
      expect(labels, contains('1 of 4 done'));
      expect(labels.where((l) => l == 'First steps'), hasLength(1));
      handle.dispose();
    });

    testWidgets('the menu says how many updates its dot stands for', (t) async {
      final updates = ValueNotifier(2);
      await _pump(
        t,
        Scaffold(
          appBar: AppBar(
            actions: [AppMenu(onOpenSettings: () {}, updates: updates)],
          ),
        ),
        'en',
        Brightness.light,
        1,
      );
      expect(find.byTooltip('Show menu (2 updates)'), findsOneWidget);
      updates.value = 0;
      await t.pump();
      expect(find.byTooltip('Show menu'), findsOneWidget);
    });

    testWidgets('a source link is a link, 48 dp tall', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        Scaffold(
          body: SourceLink(
            source: Source('s', 't', 'p', 'https://example.org', '', '出典：首相官邸'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        'ja',
        Brightness.light,
        1,
      );
      final link = find.byType(InkWell);
      expect(t.getSize(link).height, greaterThanOrEqualTo(48));
      expect(t.getSemantics(link).flagsCollection.isLink, isTrue);
      handle.dispose();
    });

    testWidgets('QR codes say what they are for, in the app language', (
      t,
    ) async {
      await _pump(
        t,
        Scaffold(
          body: BaseQrCard(
            urls: const ['http://192.168.1.20:8642'],
            name: '南小学校',
          ),
        ),
        'ja',
        Brightness.light,
        1,
      );
      final qr = t.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.semanticsLabel, '南小学校につなぐためのQRコード');
    });
  });

  group('guided tour', () {
    final keys = TourKeys();
    Widget page() => Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            SizedBox(key: keys.status, height: 40, child: const Text('S')),
            SizedBox(key: keys.bar, height: 40, child: const Text('B')),
            TextButton(
              onPressed: () => showGuidedTour(
                context,
                tourStops(context, keys),
                onEnd: () {},
              ),
              child: const Text('start'),
            ),
          ],
        ),
      ),
    );

    testWidgets('screen readers reach only the card', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, page(), 'ja', Brightness.light, 1);
      expect(_labels(t), contains('start'));
      await t.tap(find.text('start'));
      await t.pumpAndSettle();
      expect(_labels(t), isNot(contains('start')));
      expect(_labels(t), contains('次へ'));
      handle.dispose();
    });

    testWidgets('at text 2.0 the buttons stay on screen', (t) async {
      await _pump(t, page(), 'en', Brightness.light, 2);
      await t.tap(find.text('start'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Next'));
      final next = t.getRect(find.text('Next'));
      expect(next.bottom, lessThanOrEqualTo(780));
      expect(next.top, greaterThanOrEqualTo(0));
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('with a screen reader on, the splash is skipped', (t) async {
    await t.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(accessibleNavigation: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SplashOverlay(child: Text('app')),
        ),
      ),
    );
    expect(find.byType(FadeTransition), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  test('fact text and status chips are readable in light and dark', () {
    final now = DateTime(2026, 11, 19);
    Fact fact(FactKind kind, String value, SourceType src) => Fact(
      kind: kind,
      subject: 'x',
      value: value,
      observedAt: now,
      expiresAt: now.add(const Duration(hours: 6)),
      sourceType: src,
    );
    final facts = {
      'unconfirmed road': fact(
        FactKind.roadBlocked,
        '通行止め',
        SourceType.citizen,
      ),
      'open, official': fact(
        FactKind.shelterStatus,
        'open',
        SourceType.official,
      ),
      'crowded, unconfirmed': fact(
        FactKind.shelterStatus,
        'crowded',
        SourceType.citizen,
      ),
      'full, official': fact(
        FactKind.shelterStatus,
        'full',
        SourceType.official,
      ),
    };
    final low = <String>[];
    for (final b in Brightness.values) {
      final c = buildTheme(b).colorScheme;
      // Where facts are shown: plain screens, cards, Home's nearest-site
      // card (secondaryContainer) and the map sheet.
      final grounds = [
        c.surface,
        c.surfaceContainerLowest,
        c.surfaceContainer,
        c.secondaryContainer,
      ];
      for (final MapEntry(key: name, value: f) in facts.entries) {
        final (fg, chip) = statusChipColors(f, c);
        for (final g in grounds) {
          final text = _contrast(factColor(f, c), g);
          final onChip = _contrast(fg, Color.alphaBlend(chip, g));
          if (text < 4.5) low.add('$name text, ${b.name}, on $g: $text');
          if (onChip < 4.5) low.add('$name chip, ${b.name}, on $g: $onChip');
        }
      }
    }
    expect(low, isEmpty);
  });
}

/// Labels of the semantics nodes screen readers visit, in reading order.
List<String> _labels(WidgetTester t) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    if (n.getSemanticsData().label case final l when l.isNotEmpty) out.add(l);
    n
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
        .forEach(walk);
  }

  walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return out;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

Future<void> _pump(
  WidgetTester t,
  Widget screen,
  String lang,
  Brightness b,
  double scale,
) async {
  // A small phone (Pixel 5a-like width).
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: appTextDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(b),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await t.pump(const Duration(milliseconds: 500));
}
