import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// The app's strings plus Material's, Cupertino's and the widgets' own.
///
/// Not `AppLocalizations.localizationsDelegates`: gen-l10n (Flutter 3.50)
/// still lists flutter_localizations' in-framework Material delegate there,
/// and the material_ui widgets find no MaterialLocalizations through it.
const appLocalizationsDelegates = <LocalizationsDelegate<Object?>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
