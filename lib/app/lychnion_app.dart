import 'package:flutter/material.dart';

import '../knowledge/bundled_packages.dart';
import '../l10n/app_localizations.dart';
import 'app_shell.dart';
import 'brand.dart';
import 'lang.dart';
import 'notices.dart';
import 'settings.dart';
import 'splash.dart';
import 'theme.dart';

/// The app: theme, language, splash and first-start notices around the
/// tabs.
class LychnionApp extends StatelessWidget {
  const LychnionApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AppShell(settings: settings),
      // Dev screenshots include pages pushed on top (conversations).
      // Headings in Latin-script languages use Lexend; the language is
      // known only here (it may follow the device).
      builder: (context, child) {
        final latin = usesLatinScript(context.lang);
        final shot = RepaintBoundary(key: appShotKey, child: child);
        // The splash stays at the top, so a language change keeps its state.
        return SplashOverlay(
          child: latin
              ? Theme(
                  data: withLatinHeadings(Theme.of(context)),
                  child: _gate(shot),
                )
              : _gate(shot),
        );
      },
    ),
  );

  /// First start: what the app can and cannot do, over the home page.
  Widget _gate(Widget child) => NoticeGate(
    settings: settings,
    packages: builtInPackageInfo,
    child: child,
  );
}
