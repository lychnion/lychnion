// Trusting a base's notices in person (lychnion/lychnion#63): a link only
// connects, the user compares the key's code to trust its notices, and
// trusted bases are listed in Settings, where they can be removed.
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/settings.dart';
import 'package:lychnion/app/text_delegates.dart';
import 'package:lychnion/base/base_checks.dart';
import 'package:lychnion/base/base_key_code.dart';
import 'package:lychnion/base/base_link.dart';
import 'package:lychnion/base/base_panel.dart';
import 'package:lychnion/facts/fact.dart';
import 'package:lychnion/facts/fact_store.dart';
import 'package:lychnion/facts/signing.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

const _url = 'http://192.168.1.20:8642';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: appTextDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// A button that opens [confirmBase] for [link] and keeps the answer.
class _Asker extends StatelessWidget {
  const _Asker(this.link, this.onAnswer);

  final BaseLink link;
  final void Function(BaseConsent?) onAnswer;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () async => onAnswer(await confirmBase(context, link)),
    child: const Text('open'),
  );
}

void main() {
  late FactSigner base;
  final now = DateTime.utc(2026, 11, 20, 6);

  setUpAll(() async => base = await FactSigner.generate());

  Fact status(String value) => Fact(
    kind: FactKind.shelterStatus,
    subject: '34.73,135.34',
    value: value,
    observedAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(hours: 3)),
    sourceType: SourceType.official,
  );

  group('the connect dialog', () {
    Future<List<BaseConsent?>> ask(
      WidgetTester t,
      BaseLink link,
      Future<void> Function() act,
    ) async {
      final answers = <BaseConsent?>[];
      await t.pumpWidget(_app(_Asker(link, answers.add)));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await act();
      await t.pumpAndSettle();
      return answers;
    }

    testWidgets('a link with a key shows its code; connecting alone does '
        'not trust it', (t) async {
      final link = BaseLink(_url, name: 'Hall', key: base.publicKeyText);
      final answers = await ask(t, link, () async {
        expect(find.text(baseKeyCode(base.publicKeyText)!), findsOneWidget);
        await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      });
      expect(answers.single, (trust: false));
    });

    testWidgets('ticking that the code matches trusts it', (t) async {
      final link = BaseLink(_url, name: 'Hall', key: base.publicKeyText);
      final answers = await ask(t, link, () async {
        await t.tap(find.byType(Checkbox));
        await t.pump();
        await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      });
      expect(answers.single, (trust: true));
    });

    testWidgets('cancel answers null', (t) async {
      final link = BaseLink(_url, name: 'Hall', key: base.publicKeyText);
      final answers = await ask(
        t,
        link,
        () => t.tap(find.widgetWithText(TextButton, 'Cancel')),
      );
      expect(answers.single, isNull);
    });

    testWidgets('a link without a key has nothing to compare', (t) async {
      const link = BaseLink(_url, name: 'Hall');
      final answers = await ask(t, link, () async {
        expect(find.byType(Checkbox), findsNothing);
        await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      });
      expect(answers.single, (trust: false));
    });
  });

  testWidgets('a pinned key that is not trusted can be compared in '
      'Settings', (t) async {
    final settings = AppSettings();
    final facts = FactStore(clock: () => now, trust: TrustList());
    await t.runAsync(() async {
      await settings.setBase(_url, name: 'Hall', key: base.publicKeyText);
      await facts.addAll([await base.sign(status('full'))]);
    });
    await t.pumpWidget(
      _app(
        ListenableBuilder(
          listenable: settings,
          builder: (_, _) => BaseSettingsTile(settings: settings, facts: facts),
        ),
      ),
    );
    expect(find.textContaining('compare its code'), findsOneWidget);

    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    expect(find.text(baseKeyCode(base.publicKeyText)!), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'Same code'));
      // Trusting checks the facts again (real crypto, not fake time).
      for (var i = 0; i < 50 && !facts.all.single.verified; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pumpAndSettle();
    expect(facts.trust!.trustsKey(base.publicKeyText), isTrue);
    expect(facts.all.single.verified, isTrue);
    expect(find.textContaining('compare its code'), findsNothing);
  });

  testWidgets('trusted bases are listed and can be removed; the own key is '
      'not listed', (t) async {
    final trust = TrustList();
    final facts = FactStore(clock: () => now, trust: trust);
    await t.runAsync(() async {
      final own = await FactSigner.generate();
      await trust.add(
        own.publicKeyText,
        'This computer',
        kind: TrustedKeyKind.own,
      );
      await trustBaseKey(base.publicKeyText, name: 'Hall', facts: facts);
      await facts.addAll([await base.sign(status('full'))]);
    });
    expect(facts.all.single.verified, isTrue);

    await t.pumpWidget(_app(TrustedBasesList(facts: facts)));
    expect(find.text('Hall'), findsOneWidget);
    expect(find.text('This computer'), findsNothing);
    expect(find.text(baseKeyCode(base.publicKeyText)!), findsOneWidget);

    // Cancel keeps it.
    await t.tap(find.byTooltip('Stop trusting'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();
    expect(trust.trustsKey(base.publicKeyText), isTrue);

    await t.tap(find.byTooltip('Stop trusting'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Stop trusting'));
    await t.pumpAndSettle();
    expect(trust.trustsKey(base.publicKeyText), isFalse);
    expect(facts.all.single.verified, isFalse);
    // The list is empty now and shows nothing.
    expect(find.text('Trusted bases'), findsNothing);
  });
}
