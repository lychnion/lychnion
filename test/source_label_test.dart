// Who signed a source's guide, and whether Lychnion checked that publisher,
// in answers on the phone, from a base and on the base's web page
// (lychnion/lychnion#119, part 3b). Labels only: nothing here changes
// which packages are used.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/text_delegates.dart';
import 'package:lychnion/base/base_protocol.dart';
import 'package:lychnion/base/base_web.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_label.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/knowledge/retriever.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/ui/answer_card.dart';
import 'package:lychnion/ui/source_label_text.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late SimpleKeyPair lychnion, sendai, club;
  late String sendaiKey, clubKey;
  late TrustedKeys builtIn;
  late Directory tmp;
  late DownloadStore store;

  String idOf(String key) =>
      recordKeyIdOf(base64Url.decode(base64Url.normalize(key)));

  setUpAll(() async {
    lychnion = await Ed25519().newKeyPair();
    sendai = await Ed25519().newKeyPair();
    club = await Ed25519().newKeyPair();
    sendaiKey = await publicKeyOf(sendai);
    clubKey = await publicKeyOf(club);
    builtIn = TrustedKeys({
      'lychnion': [await publicKeyOf(lychnion)],
    });
    tmp = await Directory.systemTemp.createTemp('lychnion-source-labels');
    store = DownloadStore(
      tmp,
      publishers: PublisherList(
        File('${tmp.path}/publishers.json'),
        builtIn: builtIn,
      ),
    );
    await store.publishers.add(
      PublisherLink(name: 'jp.city.sendai', key: sendaiKey),
    );
    await store.publishers.add(
      PublisherLink(name: 'club.aoba', key: clubKey, title: 'Aoba Club'),
    );
    await store.learnVouches([
      await Vouch.sign(
        publisher: 'jp.city.sendai',
        key: sendaiKey,
        title: {'ja': '仙台市', 'en': 'Sendai City'},
        checked: '2026-11-23',
        method: 'official-website',
        url: 'https://www.city.sendai.jp/',
        signed: '2026-11-23T10:00:00+09:00',
        signer: lychnion,
      ),
    ]);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  group('sourceLabelOf', () {
    test('Lychnion, vouched, added, unknown', () {
      expect(store.sourceLabelOf('lychnion', null)?.isBuiltIn, isTrue);
      final v = store.sourceLabelOf('jp.city.sendai', idOf(sendaiKey))!;
      expect(v.check, PublisherCheck.vouched);
      expect(v.titleIn('ja'), '仙台市');
      expect(v.isUnchecked, isFalse);
      final c = store.sourceLabelOf('club.aoba', idOf(clubKey))!;
      expect(c.check, PublisherCheck.notChecked);
      expect(c.titleIn('ja'), 'Aoba Club');
      expect(c.isUnchecked, isTrue);
      // Another key with that name, no signer, a publisher not added.
      expect(store.sourceLabelOf('club.aoba', idOf(sendaiKey)), isNull);
      expect(store.sourceLabelOf(null, null), isNull);
      expect(store.sourceLabelOf('x.unknown', idOf(clubKey)), isNull);
    });
  });

  group('SourceLabel on the wire', () {
    test('round trip, and only well-formed labels', () {
      const l = SourceLabel(
        PublisherCheck.vouched,
        name: 'jp.city.sendai',
        titles: {'ja': '仙台市', 'en': 'Sendai City'},
      );
      final back = SourceLabel.fromWire(l.toWire())!;
      expect(back.check, l.check);
      expect(back.name, l.name);
      expect(back.titles, l.titles);
      for (final bad in [
        null,
        'vouched',
        {'check': 'trusted', 'name': 'a.b'},
        {'check': 'vouched', 'name': 'Not A Name'},
        {'check': 'vouched'},
      ]) {
        expect(SourceLabel.fromWire(bad), isNull, reason: '$bad');
      }
      // Titles are cleaned like a link's: never the app's own name.
      final odd = SourceLabel.fromWire({
        'check': 'notChecked',
        'name': 'club.x',
        'titles': {'und': 'Lychnion', 'en': 'Club\u202eX', 'toolong': 'x'},
      })!;
      expect(odd.titles.containsKey('und'), isFalse);
      expect(odd.titles.containsKey('toolong'), isFalse);
      expect(odd.titles['en'] ?? '', isNot(contains('\u202e')));
    });

    test('a base answer keeps its labels; saved answers too', () {
      final src = Source(
        's1',
        'Guide',
        'Aoba Club',
        'https://example.org',
        'CC-BY-4.0',
        '',
        label: const SourceLabel(
          PublisherCheck.notChecked,
          name: 'club.aoba',
          titles: {'und': 'Aoba Club'},
        ),
      );
      final a = GroundedAnswer('q', lang: 'en')
        ..hits = [Hit(Passage(1, src, 'h', 'text'), 1)]
        ..text = 'answer [1]';
      final back = answerFromWire(answerToWire(a));
      final l = back.hits.single.passage.source.label!;
      expect(l.check, PublisherCheck.notChecked);
      expect(l.titleIn('en'), 'Aoba Club');
    });
  });

  test('relabel follows the store', () {
    final pkg = KnowledgePackage.open(
      'assets/packages/jp.bousai.core.sqlite',
      signer: 'club.aoba',
      signerKeyId: idOf(clubKey),
    );
    expect(pkg.passages.first.source.label, isNull);
    pkg.relabel((s) => store.sourceLabelOf(s.signer, s.signerKeyId));
    expect(
      pkg.passages.every(
        (p) => p.source.label?.check == PublisherCheck.notChecked,
      ),
      isTrue,
    );
  });

  test('texts: none for Lychnion, the base says so', () {
    final l = lookupAppLocalizations(const Locale('en'));
    const club = SourceLabel(
      PublisherCheck.notChecked,
      name: 'club.aoba',
      titles: {'und': 'Aoba Club'},
    );
    expect(
      sourceLabelText(l, club, 'en'),
      'via Aoba Club · not checked by Lychnion',
    );
    expect(
      sourceLabelText(l, club, 'en', fromBase: true),
      'via Aoba Club · not checked by Lychnion (as the base says)',
    );
    expect(
      sourceLabelText(
        l,
        const SourceLabel(PublisherCheck.builtIn, name: 'lychnion'),
        'en',
      ),
      isNull,
    );
    expect(sourceLabelText(l, null, 'en'), isNull);
  });

  test('the base web page shows the label', () {
    Source src(String id, SourceLabel? label) =>
        Source(id, 'Guide $id', 'p', '', '', '', label: label);
    final a = GroundedAnswer('q', lang: 'en')
      ..hits = [
        Hit(
          Passage(
            1,
            src(
              's',
              const SourceLabel(
                PublisherCheck.notChecked,
                name: 'club.aoba',
                titles: {'und': 'Aoba Club'},
              ),
            ),
            'h',
            't',
          ),
          1,
        ),
        // Same source id, Lychnion's package: shown once each.
        Hit(
          Passage(
            2,
            src(
              's',
              const SourceLabel(PublisherCheck.builtIn, name: 'lychnion'),
            ),
            'h',
            't',
          ),
          1,
        ),
      ]
      ..text = 'answer [1][2]';
    final web = webAnswer(a)['sources']! as List;
    expect(web, hasLength(2));
    expect((web[0] as Map)['label'], 'via Aoba Club · not checked by Lychnion');
    expect((web[1] as Map).containsKey('label'), isFalse);
  });

  testWidgets('the answer card says some sources were not checked', (t) async {
    final a = GroundedAnswer('q', lang: 'en')
      ..hits = [
        Hit(
          Passage(
            1,
            Source(
              's',
              'Guide',
              'Aoba Club',
              '',
              '',
              '',
              label: const SourceLabel(
                PublisherCheck.notChecked,
                name: 'club.aoba',
              ),
            ),
            'h',
            't',
          ),
          1,
        ),
      ]
      ..text = 'An answer [1].';
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appTextDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [AnswerCard(answer: a, grounded: true, done: true)],
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Some sources were not checked by Lychnion'),
      findsOneWidget,
    );
  });
}
