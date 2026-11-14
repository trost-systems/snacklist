import 'package:family_groceries/l10n/app_localizations.dart';

/// The stores onboarding offers, nothing preselected (Peter, job 58
/// ADDENDUM 3). Change the offer here and nowhere else. Names are plain
/// text: no logos, colours or ® (Legal Review N-23). "EDEKA", "Lidl" and
/// "dm" become those chains on the server, with their researched walking
/// order (`public.add_store`). The hardware store („Baumarkt“, "Hardware
/// store") is a store type, not a chain, so it is offered in the UI
/// language; the server knows both names and brings the DIY categories
/// (job 151).
List<String> popularStores(AppLocalizations l10n) => [
  'EDEKA',
  'REWE',
  'Lidl',
  'Aldi Süd',
  'Aldi Nord',
  'Kaufland',
  'Netto',
  'Penny',
  'dm',
  'Rossmann',
  l10n.storeHardware,
];
