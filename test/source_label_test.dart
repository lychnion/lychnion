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
    test('Lychnion, vouched, added; never none for a signer', () {
      expect(store.sourceLabelOf('lychnion', null)?.isBuiltIn, isTrue);
      final v = store.sourceLabelOf('jp.city.sendai', idOf(sendaiKey))!;
      expect(v.check, PublisherCheck.vouched);
      expect(v.titleIn('ja'), '仙台市');
      expect(v.isUnchecked, isFalse);
      final c = store.sourceLabelOf('club.aoba', idOf(clubKey))!;
      expect(c.check, PublisherCheck.notChecked);
      expect(c.titleIn('ja'), 'Aoba Club');
      expect(c.isUnchecked, isTrue);
      // A key not trusted here (revoked, or the publisher removed) is
      // labelled in red, never left without a label like Lychnion's.
      for (final (name, id) in [
        ('club.aoba', idOf(sendaiKey)),
        ('x.unknown', idOf(clubKey)),
        ('club.aoba', null),
      ]) {
        final l = store.sourceLabelOf(name, id)!;
        expect(l.check, PublisherCheck.revoked, reason: '$name $id');
        expect(l.isProblem, isTrue);
      }
      expect(
        store.sourceLabelOf('club.aoba', idOf(sendaiKey))!.titleIn('en'),
        'Aoba Club',
      );
      // The app's help has no signer.
      expect(store.sourceLabelOf(null, null), isNull);
    });
  });

  group('sourceLabelFor', () {
    Source src({SourceLabel? label}) => Source(
      's1',
      'Guide',
      'Aoba Club',
      '',
      '',
      '',
      signer: 'club.aoba',
      signerKeyId: idOf(clubKey),
      label: label,
    );

    test('this device\'s answer: looked up now from the signer', () {
      final a = GroundedAnswer('q');
      // A stale label saved with it does not count.
      final s = src(
        label: const SourceLabel(PublisherCheck.vouched, name: 'club.aoba'),
      );
      expect(sourceLabelFor(a, s, store)?.check, PublisherCheck.notChecked);
    });

    test('a base\'s answer: the base\'s word, never looked up', () {
      final a = GroundedAnswer('q')..answeredBy = 'Shelter';
      final s = src(
        label: const SourceLabel(PublisherCheck.vouched, name: 'club.aoba'),
      );
      expect(sourceLabelFor(a, s, store)?.check, PublisherCheck.vouched);
      expect(sourceLabelFor(a, src(), store), isNull);
    });

    test('a saved answer keeps its signer, so its label follows', () {
      final a = GroundedAnswer('q', lang: 'en')
        ..hits = [Hit(Passage(1, src(), 'h', 'text'), 1)]
        ..text = 'answer [1]';
      final back = answerFromWire(answerToWire(a));
      final s = back.hits.single.passage.source;
      expect(s.signer, 'club.aoba');
      expect(s.signerKeyId, idOf(clubKey));
      expect(sourceLabelFor(back, s, store)?.check, PublisherCheck.notChecked);
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
        // Only Lychnion's own guides carry its name.
        {'check': 'vouched', 'name': 'lychnion'},
      ]) {
        expect(SourceLabel.fromWire(bad), isNull, reason: '$bad');
      }
      expect(
        SourceLabel.fromWire({'check': 'builtIn', 'name': 'lychnion'})?.check,
        PublisherCheck.builtIn,
      );
      // Titles are cleaned like a link's, and none reads as part of the
      // label line: no app name, no separator.
      final odd = SourceLabel.fromWire({
        'check': 'notChecked',
        'name': 'club.x',
        'titles': {
          'und': 'Lychnion',
          'ja': 'リクニオン公式',
          'en': 'Club · checked by Lychnion',
          'fr': 'Club\u202eX',
          'toolong': 'x',
          'de': 42,
        },
      })!;
      expect(odd.titles.keys, everyElement(isIn(['fr'])));
      expect(odd.titles['fr'] ?? '', isNot(contains('\u202e')));
    });

    test('a base answer keeps its labels', () {
      final src = Source(
        's1',
        'Guide',
        'Aoba Club',
        'https://example.org',
        'CC-BY-4.0',
        '',
      );
      final a = GroundedAnswer('q', lang: 'en')
        ..hits = [Hit(Passage(1, src, 'h', 'text'), 1)]
        ..text = 'answer [1]';
      final wire = answerToWire(
        a,
        labelOf: (_) => const SourceLabel(
          PublisherCheck.notChecked,
          name: 'club.aoba',
          titles: {'und': 'Aoba Club'},
        ),
      );
      final l = answerFromWire(wire).hits.single.passage.source.label!;
      expect(l.check, PublisherCheck.notChecked);
      expect(l.titleIn('en'), 'Aoba Club');
    });
  });

  test('merged packages keep each source\'s own signer', () {
    final mine = KnowledgePackage.open(
      'assets/packages/jp.bousai.core.sqlite',
      signer: 'lychnion',
    );
    final theirs = KnowledgePackage.open(
      'assets/packages/jp.bousai.core.sqlite',
      signer: 'club.aoba',
      signerKeyId: idOf(clubKey),
    );
    final merged = KnowledgePackage.merge([mine, theirs]);
    final n = mine.passages.length;
    expect(merged.passages.take(n).map((p) => p.source.signer).toSet(), {
      'lychnion',
    });
    expect(merged.passages.skip(n).map((p) => p.source.signer).toSet(), {
      'club.aoba',
    });
    final a = GroundedAnswer('q')
      ..hits = [Hit(merged.passages.first, 1), Hit(merged.passages[n], 1)];
    expect(
      sourceLabelFor(a, a.hits[0].passage.source, store)?.isBuiltIn,
      isTrue,
    );
    expect(
      sourceLabelFor(a, a.hits[1].passage.source, store)?.check,
      PublisherCheck.notChecked,
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
      'via “Aoba Club” · not checked by Lychnion',
    );
    expect(
      sourceLabelText(l, club, 'en', fromBase: true),
      'via “Aoba Club” · not checked by Lychnion (as the base says)',
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

  test('the base web page shows the label and says some are unchecked', () {
    Source src(String signer) =>
        Source('s', 'Guide', 'p', '', '', '', signer: signer);
    final a = GroundedAnswer('q', lang: 'en')
      ..hits = [
        Hit(Passage(1, src('club.aoba'), 'h', 't'), 1),
        // Same source id, Lychnion's package: shown once each.
        Hit(Passage(2, src('lychnion'), 'h', 't'), 1),
      ]
      ..text = 'answer [1][2]';
    final page = webAnswer(
      a,
      labelOf: (s) => store.sourceLabelOf(s.signer, idOf(clubKey)),
    );
    final web = page['sources']! as List;
    expect(web, hasLength(2));
    expect(
      (web[0] as Map)['label'],
      'via “Aoba Club” · not checked by Lychnion',
    );
    expect((web[1] as Map).containsKey('label'), isFalse);
    expect(page['some_unchecked'], isTrue);
    expect(
      (page['texts']! as Map)['someUnchecked'],
      'Some sources were not checked by Lychnion',
    );
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
              signer: 'club.aoba',
              signerKeyId: idOf(clubKey),
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
            children: [
              AnswerCard(
                answer: a,
                grounded: true,
                done: true,
                labelOf: (s) => sourceLabelFor(a, s, store),
              ),
            ],
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
