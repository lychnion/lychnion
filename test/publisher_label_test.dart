// Labels from Lychnion's vouches, and the second look a link gets when its
// name looks official (lychnion/lychnion#119, part 3). Labels only:
// nothing here changes which keys are trusted.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/text_delegates.dart';
import 'package:lychnion/download/download_manager.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/lookalike.dart';
import 'package:lychnion/download/publisher_label.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/download/publishers_screen.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late SimpleKeyPair lychnion, sendai, fake;
  late String sendaiKey, fakeKey;
  late TrustedKeys trust;
  late Directory tmp;
  late DownloadStore store;
  late Vouch vouched, gone;

  Future<Vouch> vouch(
    String publisher,
    String key, {
    Map<String, String>? title,
    String signed = '2026-11-23T10:00:00+09:00',
    bool withdrawn = false,
  }) => Vouch.sign(
    publisher: publisher,
    key: key,
    title: title ?? {'ja': '仙台市', 'en': 'Sendai City'},
    checked: '2026-11-23',
    method: 'official-website',
    url: 'https://www.city.sendai.jp/',
    signed: signed,
    signer: lychnion,
    withdrawn: withdrawn,
  );

  setUpAll(() async {
    lychnion = await Ed25519().newKeyPair();
    sendai = await Ed25519().newKeyPair();
    fake = await Ed25519().newKeyPair();
    sendaiKey = await publicKeyOf(sendai);
    fakeKey = await publicKeyOf(fake);
    trust = TrustedKeys({
      'lychnion': [await publicKeyOf(lychnion)],
    });
    tmp = await Directory.systemTemp.createTemp('lychnion-labels');
    store = DownloadStore(Directory(tmp.path), trust: trust);
    vouched = await vouch('jp.city.sendai', sendaiKey);
    final old = await vouch(
      'jp.town.gone',
      sendaiKey,
      title: {'ja': '旧町', 'en': 'Old Town'},
      signed: '2026-11-01T00:00:00Z',
    );
    gone = await vouch(
      'jp.town.gone',
      sendaiKey,
      title: {'ja': '旧町', 'en': 'Old Town'},
      withdrawn: true,
    );
    await store.learnVouches([vouched, old, gone]);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  group('labelOf', () {
    test('built in, vouched, not checked, other key, withdrawn', () {
      expect(store.labelOf('lychnion', 'x').check, PublisherCheck.builtIn);
      final v = store.labelOf('jp.city.sendai', sendaiKey);
      expect(v.check, PublisherCheck.vouched);
      expect(v.titleIn('ja', 'link title'), '仙台市');
      expect(v.titleIn('en', 'link title'), 'Sendai City');
      expect(v.isProblem, isFalse);
      final other = store.labelOf('jp.city.sendai', fakeKey);
      expect(other.check, PublisherCheck.otherKey);
      expect(other.isProblem, isTrue);
      // Not vouched: the link's own title, never the vouch's.
      expect(other.titleIn('ja', 'Fake'), 'Fake');
      expect(
        store.labelOf('jp.town.gone', sendaiKey).check,
        PublisherCheck.withdrawn,
      );
      final none = store.labelOf('club.example', fakeKey);
      expect(none.check, PublisherCheck.notChecked);
      expect(none.vouch, isNull);
    });

    test(
      'a vouch whose signer the device no longer trusts: not checked',
      () async {
        final other = DownloadStore(
          Directory('${tmp.path}/other'),
          trust: TrustedKeys({
            'lychnion': [fakeKey],
          }),
        );
        await other.learnVouches([vouched]);
        expect(
          other.labelOf('jp.city.sendai', sendaiKey).check,
          PublisherCheck.notChecked,
        );
      },
    );
  });

  group('lookalikeOf', () {
    List<Vouch> vs() => [vouched, gone];

    test('a name or title like a vouched publisher', () {
      expect(lookalikeOf('jp.clty.sendai', null, vs()), Lookalike.vouched);
      expect(lookalikeOf('jp.city-sendai', null, vs()), Lookalike.vouched);
      expect(lookalikeOf('org.help', '仙台市 防災', vs()), Lookalike.vouched);
      expect(lookalikeOf('org.help', 'ＳＥＮＤＡＩ　ＣＩＴＹ', vs()), Lookalike.vouched);
      expect(lookalikeOf('org.help', 'Old Town', vs()), Lookalike.vouched);
      // The vouched name itself is decided by its vouch, not here.
      expect(
        lookalikeOf('jp.city.sendai', 'Sendai', vs()),
        isNot(Lookalike.vouched),
      );
    });

    test('a public body', () {
      for (final (name, title) in [
        ('jp.go.cao', null),
        ('jp.lg.example', null),
        ('jp.pref.miyagi', null),
        ('org.help', '宮城県'),
        ('org.help', '消防団'),
        ('org.help', '内閣府'),
        ('org.help', 'Ministry of Health'),
        ('org.help', 'Ｍｉｎｉｓｔｒｙ'),
        ('org.help', 'Kobe City Fire Department'),
      ]) {
        expect(
          lookalikeOf(name, title, const []),
          Lookalike.publicBody,
          reason: '$name $title',
        );
      }
    });

    test('an ordinary name', () {
      expect(lookalikeOf('club.example', 'Aoba Running Club', vs()), isNull);
      expect(lookalikeOf('jp.example', 'Electricity notes', vs()), isNull);
      expect(lookalikeOf('club.example', null, vs()), isNull);
    });
  });

  group('the add dialog', () {
    Future<void> open(WidgetTester t, PublisherLink link) async {
      final m = DownloadManager.forTest(store);
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appTextDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => addPublisher(c, m, link),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    FilledButton add(WidgetTester t) =>
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));

    testWidgets('vouched: the checked name, no tick', (t) async {
      await open(t, PublisherLink(name: 'jp.city.sendai', key: sendaiKey));
      expect(find.text('Sendai City'), findsOneWidget);
      expect(find.textContaining('Lychnion checked on'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(add(t).onPressed, isNotNull);
    });

    testWidgets('not checked, ordinary name: no tick', (t) async {
      await open(
        t,
        PublisherLink(name: 'club.example', key: fakeKey, title: 'Aoba Club'),
      );
      expect(
        find.text('Lychnion has not checked this publisher.'),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(add(t).onPressed, isNotNull);
    });

    testWidgets('looks like a public body: Add after the tick', (t) async {
      await open(
        t,
        PublisherLink(name: 'org.help', key: fakeKey, title: '宮城県防災'),
      );
      expect(find.textContaining('looks like a public body'), findsOneWidget);
      expect(add(t).onPressed, isNull);
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      expect(add(t).onPressed, isNotNull);
    });

    testWidgets('the vouched name with another key: warned, tick', (t) async {
      await open(
        t,
        PublisherLink(name: 'jp.city.sendai', key: fakeKey, title: '仙台市'),
      );
      expect(find.textContaining('may be fake'), findsOneWidget);
      expect(add(t).onPressed, isNull);
    });
  });
}
