import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/l10n/app_localizations.dart';

/// A third language (Spanish here) needs no code changes: data carries
/// language maps, and app texts are one more ARB file. Until there is an
/// app_es.arb, Spanish falls back to English everywhere.
void main() {
  test('app texts: Japanese and English today; a new ARB adds a language', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'ja', 'en'},
    );
  });

  test('a Spanish question is recognised as Spanish in a Spanish app', () {
    expect(questionLanguage('¿Qué hago si tiembla?', appLang: 'es'), 'es');
    expect(questionLanguage('What if the ground shakes?', appLang: 'ja'), 'en');
    expect(questionLanguage('What is 避難指示?', appLang: 'en'), 'en');
    expect(questionLanguage('津波は一回だけですか？'), 'ja');
    expect(questionLanguage('スマホのGPSが使えない'), 'ja');
  });

  test('package data in Spanish is used when present, English otherwise', () {
    final src = Source('s', 't', 'p', '', 'PDL1.0', '');
    final p = Passage(
      1,
      src,
      '地震',
      '揺れたら机の下に。',
      texts: {
        'en': ('Earthquake', 'If it shakes, get under a desk.'),
        'es': ('Terremoto', 'Si tiembla, métete debajo de una mesa.'),
      },
    );
    expect(p.textIn('es'), 'Si tiembla, métete debajo de una mesa.');
    expect(p.textIn('fr'), p.text); // no French: the package's own text
    final info = PackageInfo(
      'x',
      'タイトル',
      '1',
      1,
      name: {'ja': '防災', 'en': 'Disasters', 'es': 'Desastres'},
      notice: {
        'en': ['Not a doctor.'],
      },
    );
    expect(info.nameIn('es'), 'Desastres');
    expect(info.noticeIn('es'), ['Not a doctor.']); // English fallback
    final alert = Alert('a', src, '公式の文。', translations: {'es': 'Texto.'});
    expect(alert.textIn('es'), 'Texto.');
    expect(alert.textIn('en'), '公式の文。');
  });

  test('the answerer has instructions for any language', () {
    final es = AnswerTexts.of('es');
    expect(es.instruction, contains('"es"'));
    expect(es.noSource, AnswerTexts.of('en').noSource);
  });
}
