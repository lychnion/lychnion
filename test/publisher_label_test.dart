// Labels from Lychnion's attestations, and the second look a link gets when its
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
  late Attestation attested, gone;

  Future<Attestation> attestation(
    String publisher,
    String key, {
    Map<String, String>? title,
    String signed = '2026-11-23T10:00:00+09:00',
    bool withdrawn = false,
  }) => Attestation.sign(
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
    attested = await attestation('jp.city.sendai', sendaiKey);
    final old = await attestation(
      'jp.town.gone',
      sendaiKey,
      title: {'ja': '旧町', 'en': 'Old Town'},
      signed: '2026-11-01T00:00:00Z',
    );
    gone = await attestation(
      'jp.town.gone',
      sendaiKey,
      title: {'ja': '旧町', 'en': 'Old Town'},
      withdrawn: true,
    );
    await store.learnAttestations([attested, old, gone]);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  group('labelOf', () {
    test('built in, attested, not checked, other key, withdrawn', () {
      expect(store.labelOf('lychnion', 'x').check, PublisherCheck.builtIn);
      final v = store.labelOf('jp.city.sendai', sendaiKey);
      expect(v.check, PublisherCheck.attested);
      expect(v.titleIn('ja', 'link title'), '仙台市');
      expect(v.titleIn('en', 'link title'), 'Sendai City');
      expect(v.isProblem, isFalse);
      final other = store.labelOf('jp.city.sendai', fakeKey);
      expect(other.check, PublisherCheck.otherKey);
      expect(other.isProblem, isTrue);
      // Not attested: the link's own title, never the attestation's.
      expect(other.titleIn('ja', 'Fake'), 'Fake');
      expect(
        store.labelOf('jp.town.gone', sendaiKey).check,
        PublisherCheck.withdrawn,
      );
      final none = store.labelOf('club.example', fakeKey);
      expect(none.check, PublisherCheck.notChecked);
      expect(none.attestation, isNull);
    });

    test(
      'an attestation whose signer the device no longer trusts: not checked',
      () async {
        final other = DownloadStore(
          Directory('${tmp.path}/other'),
          trust: TrustedKeys({
            'lychnion': [fakeKey],
          }),
        );
        await other.learnAttestations([attested]);
        expect(
          other.labelOf('jp.city.sendai', sendaiKey).check,
          PublisherCheck.notChecked,
        );
      },
    );
  });

  group('a store where the attested publisher was added', () {
    late DownloadStore added;
    setUp(() async {
      final dir = Directory(
        '${tmp.path}/added-${DateTime.now().microsecondsSinceEpoch}',
      );
      // Trust from its own publisher list, as on a phone: Lychnion built
      // in, Sendai added.
      added = DownloadStore(
        dir,
        publishers: PublisherList(
          File('${dir.path}/publishers.json'),
          builtIn: trust,
        ),
      );
      await added.learnAttestations([attested]);
      await added.publishers.add(
        PublisherLink(name: 'jp.city.sendai', key: sendaiKey),
      );
    });

    Future<PackageRecord> record(SimpleKeyPair by) => PackageRecord.sign({
      'format': 1,
      'id': 'jp.sendai.guide',
      'kind': 'package',
      'version': '1',
      'publisher': 'jp.city.sendai',
      'title': {'en': 'Guide'},
      'files': [
        {'name': 'g.sqlite', 'size': 1, 'sha256': 'a' * 64},
      ],
      'signed': '2026-11-23T09:00:00+09:00',
    }, by);

    test('a record names a short key id: labelled by the full key', () async {
      final label = added.labelOfRecord(await record(sendai));
      expect(label?.check, PublisherCheck.attested);
      // A key not trusted here: no label rather than a wrong one.
      expect(added.labelOfRecord(await record(fake)), isNull);
    });

    test('a key the publisher replaced stays attested', () async {
      final next = await Ed25519().newKeyPair();
      final s = await KeyStatement.replace(
        publisher: 'jp.city.sendai',
        oldKey: sendai,
        newKey: next,
        signed: '2026-11-23T12:00:00+09:00',
      );
      expect(await added.publishers.learn([s]), isTrue);
      expect(
        added.labelOf('jp.city.sendai', await publicKeyOf(next)).check,
        PublisherCheck.attested,
      );
    });

    test('a key the publisher revoked shows as revoked', () async {
      final s = await KeyStatement.revoke(
        publisher: 'jp.city.sendai',
        key: sendai,
        signed: '2026-11-23T12:00:00+09:00',
      );
      expect(await added.publishers.learn([s]), isTrue);
      final label = added.labelOf('jp.city.sendai', sendaiKey);
      expect(label.check, PublisherCheck.revoked);
      expect(label.isProblem, isTrue);
      expect(label.titleIn('en', 'jp.city.sendai'), 'jp.city.sendai');
    });
  });

  group('lookalikeOf', () {
    List<Attestation> vs() => [attested, gone];

    test('a name or title like an attested publisher', () {
      expect(lookalikeOf('jp.clty.sendai', null, vs()), Lookalike.attested);
      expect(lookalikeOf('jp.city-sendai', null, vs()), Lookalike.attested);
      expect(lookalikeOf('org.help', '仙台市 防災', vs()), Lookalike.attested);
      expect(lookalikeOf('org.help', 'ＳＥＮＤＡＩ　ＣＩＴＹ', vs()), Lookalike.attested);
      expect(lookalikeOf('org.help', 'Old Town', vs()), Lookalike.attested);
      // Cyrillic letters drawn like Latin ones.
      expect(lookalikeOf('org.help', 'Ѕеndаі Сіtу', vs()), Lookalike.attested);
      // The attested name itself is decided by its attestation, not here.
      expect(
        lookalikeOf('jp.city.sendai', 'Sendai', vs()),
        isNot(Lookalike.attested),
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
        ('org.help', 'KobeCity'),
        ('org.sendai-city', null),
        ('org.help', 'Міnіstrу'),
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
      expect(lookalikeOf('club.example', '', vs()), isNull);
      expect(lookalikeOf('club.example', 'A', vs()), isNull);
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

    testWidgets('attested: the checked name, no tick', (t) async {
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

    testWidgets('a withdrawn attestation: warned, tick', (t) async {
      await open(t, PublisherLink(name: 'jp.town.gone', key: sendaiKey));
      expect(find.textContaining('took back its check'), findsOneWidget);
      expect(add(t).onPressed, isNull);
    });

    testWidgets('the attested name with another key: warned, tick', (t) async {
      await open(
        t,
        PublisherLink(name: 'jp.city.sendai', key: fakeKey, title: '仙台市'),
      );
      expect(find.textContaining('may be fake'), findsOneWidget);
      expect(add(t).onPressed, isNull);
    });
  });
}
