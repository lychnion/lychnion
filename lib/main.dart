import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/brand.dart';
import 'app/lang.dart';
import 'app/notices.dart';
import 'app/settings.dart';
import 'app/splash.dart';
import 'app/theme.dart';
import 'knowledge/bundled_packages.dart';
import 'l10n/app_localizations.dart';
import 'llm/local_llm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  addLicenses();
  await LocalLlm.init();
  final settings = AppSettings();
  await settings.load();
  runApp(LychnionApp(settings: settings));
}

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
