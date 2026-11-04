import 'package:fieldkit/facts/fact.dart';
import 'package:fieldkit/facts/fact_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Fact?> fill(
    WidgetTester tester,
    Future<void> Function() steps, {
    List<FactChoice>? choices,
    Fact? current,
    FactKind kind = FactKind.shelterStatus,
  }) async {
    Fact? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showFactForm(
              context,
              editor: const FactEditor(sourceName: 'テスト避難所'),
              kind: kind,
              subject: 'E1',
              title: '市役所',
              en: false,
              choices: choices,
              current: current,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await steps();
    await tester.tap(
      find.text('保存').hitTestable().evaluate().isEmpty
          ? find.text('解除する')
          : find.text('保存'),
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('staff set a shelter to full', (tester) async {
    final f = await fill(tester, () async {
      await tester.tap(find.text('満員'));
      await tester.tap(find.text('6時間'));
      await tester.enterText(find.byType(TextField).last, '受け入れ停止');
      await tester.pump();
    }, choices: shelterChoices);
    expect(f!.value, 'full');
    expect(f.sourceType, SourceType.official);
    expect(f.sourceName, 'テスト避難所');
    expect(f.note, '受け入れ停止');
    expect(f.expiresAt.difference(f.observedAt), const Duration(hours: 6));
  });

  testWidgets('a typed warning drops radio separators', (tester) async {
    final f = await fill(tester, () async {
      await tester.enterText(find.byType(TextField).first, '津波警報|解除;');
      await tester.tap(find.text('住民の報告'));
      await tester.pump();
    }, kind: FactKind.warning);
    expect(f!.value, '津波警報 解除');
    expect(f.sourceType, SourceType.citizen);
  });
}
