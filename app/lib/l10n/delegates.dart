import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';

/// What the app (and every test that builds a MaterialApp) passes as
/// `localizationsDelegates`: the app's own texts, and those of Material,
/// Cupertino and the widgets from `material_ui`.
///
/// Not `AppLocalizations.localizationsDelegates`: the generator still fills
/// that with the delegates from flutter_localizations, and since Material
/// became a package of its own (Flutter 3.50) those no longer provide what
/// `MaterialApp` looks for -- the date picker and the tooltips would be
/// English in a Dutch app.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
