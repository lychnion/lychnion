import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/notices.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/app/text_delegates.dart';

void main() {
  const ids = ['jp.bousai.core', 'jp.outdoor.hiking', 'intl.firstaid.basics'];
  final infos = [
    for (final id in ids)
      KnowledgePackage.readInfo('assets/packages/$id.sqlite'),
  ];

  test('every built-in package says what it is not for, in both languages', () {
    for (final p in infos) {
      expect(p.noticeIn('ja'), isNotEmpty, reason: p.id);
      expect(p.noticeIn('en'), isNotEmpty, reason: p.id);
    }
    final hiking = infos[1];
    expect(hiking.noticeIn('ja').join(), contains('雪崩の危険度の判断には使えません'));
    expect(infos[2].noticeIn('ja').join(), contains('医師'));
  });

  test('the notice key is stable and changes with the text', () {
    final p = infos[0];
    expect(
      p.noticeKey,
      KnowledgePackage.readInfo('assets/packages/jp.bousai.core.sqlite')
          .noticeKey,
    );
    final changed = PackageInfo(
      p.id,
      p.title,
      p.version,
      0,
      notice: {
        'ja': ['別の文'],
      },
    );
    expect(changed.noticeKey, isNot(p.noticeKey));
    expect(changed.noticeKey, startsWith('pkg:jp.bousai.core:'));
  });

  test('the app notice names the emergency numbers', () {
    expect(
      appNotice(lookupAppLocalizations(const Locale('ja')))
          .map((l) => l.$2)
          .join(),
      allOf(contains('119'), contains('110')),
    );
    expect(
      appNotice(lookupAppLocalizations(const Locale('en')))
          .map((l) => l.$2)
          .join(),
      allOf(contains('119'), contains('110')),
    );
  });

  testWidgets('first start: notice, package notices, one button', (t) async {
    var accepted = false;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: appTextDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoticeScreen(packages: infos, onAccept: () => accepted = true),
      ),
    );
    expect(find.text('ご利用の前に'), findsOneWidget);
    expect(find.text('入っている資料について'), findsOneWidget);
    await t.tap(find.text('わかりました'));
    expect(accepted, isTrue);
  });
}
