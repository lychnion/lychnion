import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/app_help.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/help_screen.dart';

void main() {
  // Built by tool/build_help.py from help/.
  final book = HelpBook.open('assets/help/app.help.sqlite');

  Widget app(Widget child, {String locale = 'ja'}) => MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  test('every topic has its title and sections in both languages', () {
    expect(book.topics, hasLength(9));
    for (final t in book.topics) {
      expect(t.titles.keys, containsAll(['ja', 'en']), reason: t.id);
      expect(t.sections, isNotEmpty, reason: t.id);
      for (final s in t.sections) {
        expect(s.texts.keys, containsAll(['ja', 'en']), reason: t.id);
      }
    }
  });

  test('search works without the AI, in both languages', () {
    expect(book.search('共有するには', 'ja').first.$1.id, 'help-06-share-nearby');
    expect(book.search('ベース 名前', 'ja').first.$1.id, 'help-05-base');
    expect(
      book.search('give maps to another phone', 'en').first.$1.id,
      'help-06-share-nearby',
    );
    expect(book.search('xyzzy', 'en'), isEmpty);
  });

  testWidgets('the list, a search, and a topic', (t) async {
    await t.pumpWidget(app(HelpScreen(book: book)));
    expect(find.text('ヘルプ'), findsOneWidget);
    expect(find.text('はじめに'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'テザリング');
    await t.pumpAndSettle();
    expect(find.textContaining('テザリング'), findsWidgets);

    await t.pumpWidget(
      app(
        HelpScreen(book: book, topic: 'help-05-base'),
        locale: 'en',
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('What is a base?'), findsOneWidget);
    expect(find.text('All help'), findsOneWidget);
  });
}
