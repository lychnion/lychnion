import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// The app's texts, and Material's, Cupertino's and Flutter's own in the
/// same languages.
///
/// Use this instead of `AppLocalizations.localizationsDelegates`: the
/// generator (Flutter 3.50) still lists the localizations that moved to
/// material_ui and cupertino_ui, and widgets from those packages do not
/// find them.
const appTextDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
