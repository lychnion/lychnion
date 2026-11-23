import 'dart:ui' show Locale;

import '../app/lang.dart' show appLanguages;
import '../knowledge/grounded_answer.dart';
import '../l10n/app_localizations.dart';
import '../ui/answer_text.dart';

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
Map<String, Object?> webAnswer(GroundedAnswer a) {
  final sources = {
    for (final al in a.alerts) al.source.id: al.source,
    for (final h in a.citedHits) h.passage.source.id: h.passage.source,
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
    },
    'shown': a.isGrounded || a.saysNoSource
        ? shownAnswer(a.text, a.alerts)
        : a.text,
    'grounded': a.isGrounded,
    'no_source': a.saysNoSource || a.hits.isEmpty,
    'partly': a.admitsGap,
    'alerts': [for (final al in a.alerts) al.textIn(a.lang)],
    'sources': [
      for (final s in sources.values)
        {
          'publisher': s.publisher,
          'title': s.title,
          'licence': s.licence,
          'url': s.url,
        },
    ],
  };
}
