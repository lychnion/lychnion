import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/notices.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';

void main() {
  const ids = ['jp.bousai.core', 'jp.outdoor.hiking', 'intl.firstaid.basics'];
  final infos = [
    for (final id in ids)
      KnowledgePackage.readInfo('assets/packages/$id.sqlite'),
  ];

  test('every built-in package says what it is not for, in both languages', () {
    for (final p in infos) {
      expect(p.noticeIn(en: false), isNotEmpty, reason: p.id);
      expect(p.noticeIn(en: true), isNotEmpty, reason: p.id);
    }
    final hiking = infos[1];
    expect(hiking.noticeIn(en: false).join(), contains('雪崩の危険度の判断には使えません'));
    expect(infos[2].noticeIn(en: false).join(), contains('医師'));
  });

  test('the notice key is stable and changes with the text', () {
    final p = infos[0];
    expect(
      p.noticeKey,
      KnowledgePackage.readInfo(
        'assets/packages/jp.bousai.core.sqlite',
      ).noticeKey,
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
      appNotice(en: false).map((l) => l.$2).join(),
      allOf(contains('119'), contains('110')),
    );
    expect(
      appNotice(en: true).map((l) => l.$2).join(),
      allOf(contains('119'), contains('110')),
    );
  });

  testWidgets('first start: notice, package notices, one button', (t) async {
    var accepted = false;
    await t.pumpWidget(
      MaterialApp(
        home: NoticeScreen(
          en: false,
          packages: infos,
          onAccept: () => accepted = true,
        ),
      ),
    );
    expect(find.text('ご利用の前に'), findsOneWidget);
    expect(find.text('入っている資料について'), findsOneWidget);
    await t.tap(find.text('わかりました'));
    expect(accepted, isTrue);
  });
}
