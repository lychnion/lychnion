import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../knowledge/language.dart';

/// Languages are ISO 639-1 codes ('ja', 'en', later 'es', 'zh', …), never
/// a ja/en switch. App texts live in `lib/l10n/app_<lang>.arb`; data
/// (packages, safety lines, notices, catalog) carries maps by code.

/// The app's language: the locale the app shows, as a code.
String appLang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// App texts for the current locale (generated from the ARB files).
extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => appLang(this);
}

/// Languages with app texts: Japanese first (the app is made for Japan),
/// then the others in the order of their ARB files.
final appLanguages = [
  for (final l in AppLocalizations.supportedLocales) l.languageCode,
]..sort((a, b) => (a == 'ja' ? 0 : 1).compareTo(b == 'ja' ? 0 : 1));

/// [lang] when the app has texts for it, else English.
String appTextLang(String lang) => appLanguages.contains(lang) ? lang : 'en';

/// Shows [child] with app texts in [lang] instead of the app's language:
/// an answer follows the language of its question.
class InLanguage extends StatelessWidget {
  const InLanguage({super.key, required this.lang, required this.child});

  final String lang;
  final Widget child;

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: Locale(appTextLang(lang)),
    child: child,
  );
}
