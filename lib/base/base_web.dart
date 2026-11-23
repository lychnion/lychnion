import 'dart:ui' show Locale;

import '../app/lang.dart' show appLanguages;
import '../knowledge/grounded_answer.dart';
import '../l10n/app_localizations.dart';
import '../knowledge/knowledge_package.dart' show Source, SourceLabel;
import '../ui/answer_text.dart';
import '../ui/source_label_text.dart';

/// Data for the page the base computer serves to phones without the
/// app (assets/web/base.html): its texts in the browser's language,
/// taken from the app's ARB files (one place to translate), and answers
/// ready to show.
///
/// The page is plain http and not signed, so anyone on the Wi-Fi can
/// change it on the way (lychnion/lychnion#116). It therefore shows no
/// current facts (shelter status, warnings): those are on the base's
/// screen, with the staff, and in the app, which checks them. It says
/// that it is not checked, and the base's screen says so next to the
/// page's QR code, where nobody on the Wi-Fi can change it.
AppLocalizations webTexts(String lang) => lookupAppLocalizations(
  Locale(
    AppLocalizations.supportedLocales.any((l) => l.languageCode == lang)
        ? lang
        : 'en',
  ),
);

Map<String, Object?> webInfo({required String lang, required String name}) {
  final l = webTexts(lang);
  return {
    'lang': l.localeName,
    'name': name,
    // For the page's language menu: each language in its own name.
    'languages': [
      for (final code in appLanguages)
        {'code': code, 'name': webTexts(code).languageName},
    ],
    'texts': {
      'language': l.settingsLanguage,
      'appName': l.appName,
      'intro': l.askIntro,
      'hint': l.askHint,
      'send': l.askSend,
      'looking': l.answerLooking,
      'notCovered': l.answerNotCovered,
      'partly': l.answerPartlyCovered,
      'unchecked': l.answerUnchecked,
      'sources': l.answerSources,
      'pageUnchecked': l.webPageUnchecked,
      'beforeYouStart': l.beforeYouStart,
      'notice': [
        l.noticeAi,
        l.noticeOfficialFirst,
        l.noticeNotADoctor,
        l.noticeAsk,
        l.noticeOffline,
      ],
      'base': l.answerBaseComputer(name),
      'error': l.webError,
    },
  };
}

/// What the page shows for an answer: the text without citation marks or
/// sentences that repeat a safety line, the safety lines in the question's
/// language, the card's labels in that language too, and the sources once
/// (publisher, title, licence, address).
/// [labelOf]: how this base labels each source's signer (#119).
Map<String, Object?> webAnswer(
  GroundedAnswer a, {
  SourceLabel? Function(Source)? labelOf,
}) {
  SourceLabel? label(Source s) => labelOf?.call(s) ?? s.label;
  final sources = {
    // By signer too: two publishers' packages may use the same source id.
    for (final al in a.alerts) _key(al.source): al.source,
    for (final h in a.citedHits) _key(h.passage.source): h.passage.source,
  };
  // Labels in the answer's language, not the browser's: a Japanese
  // question on an English phone gets a Japanese answer card.
  final l = webTexts(a.lang);
  return {
    'lang': a.lang,
    'texts': {
      'notCovered': l.answerNotCovered,
      'partly': l.answerPartlyCovered,
      'unchecked': l.answerUnchecked,
      'sources': l.answerSources,
      'someUnchecked': l.answerSourcesNotChecked(l.appName),
    },
    'shown': a.isGrounded || a.saysNoSource
        ? shownAnswer(a.text, a.alerts)
        : a.text,
    'grounded': a.isGrounded,
    'no_source': a.saysNoSource || a.hits.isEmpty,
    'partly': a.admitsGap,
    'alerts': [for (final al in a.alerts) al.textIn(a.lang)],
    'some_unchecked': a.citedHits.any(
      (h) => label(h.passage.source)?.isUnchecked ?? false,
    ),
    'sources': [
      for (final s in sources.values)
        {
          'publisher': s.publisher,
          'title': s.title,
          'licence': s.licence,
          'url': s.url,
          // Who signed its guide, as this base labels it (#119).
          'label': ?sourceLabelText(l, label(s), a.lang),
        },
    ],
  };
}

String _key(Source s) => '${s.signer ?? s.label?.name}/${s.id}';
