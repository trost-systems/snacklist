/// The Snacklist Widgetbook: components, addons and the scenario matrix,
/// shared by the app (`main.dart`) and the tests.
library;

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart' hide ThemeMode;
import 'package:snacklist_widgetbook/src/addons.dart';
import 'package:snacklist_widgetbook/src/app_widgets.dart';
import 'package:snacklist_widgetbook/src/controls.dart';
import 'package:snacklist_widgetbook/src/fields.dart';
import 'package:snacklist_widgetbook/src/hex_controls.dart';
import 'package:snacklist_widgetbook/src/hex_segmented_stories.dart';
import 'package:snacklist_widgetbook/src/hex_shapes.dart';
import 'package:snacklist_widgetbook/src/home.dart';
import 'package:snacklist_widgetbook/src/stickers.dart';
import 'package:snacklist_widgetbook/src/story.dart';
import 'package:snacklist_widgetbook/src/surfaces.dart';
import 'package:snacklist_widgetbook/src/tokens.dart';
import 'package:widgetbook/widgetbook.dart';

export 'package:snacklist_widgetbook/src/fonts.dart';

/// Every component of the catalogue, in navigation order.
final components = [
  for (final control in buttons)
    component('Material/Buttons', control.name, controlStories(control)),
  for (final control in selection)
    component('Material/Auswahl', control.name, controlStories(control)),
  ...surfaceComponents,
  ...hexControlComponents,
  ...hexSegmentedComponents,
  ...stickerComponents,
  ...hexShapeComponents,
  ...fieldComponents,
  ...appComponents,
  ...tokenComponents,
];

/// Puts the story on the theme's surface, centred with a gutter, on a
/// [Material] so ink and text styles come from the theme.
Widget _themed(BuildContext context, ThemeData theme, Widget child) => Theme(
  data: theme,
  child: Material(
    color: theme.colorScheme.surface,
    child: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

Config catalogConfig({ScenarioCallback? setUp}) => Config(
  components: components,
  home: const CatalogHome(),
  appBuilder: (context, child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: child,
  ),
  addons: [
    ThemeAddon<ThemeData>(themes, _themed),
    TextSizeAddon(),
    ReducedMotionAddon(),
    TimeDilationAddon(),
    ViewportAddon([
      Viewports.none,
      IosViewports.iPhone13,
      IosViewports.iPhoneSE,
      AndroidViewports.samsungGalaxyS20,
    ]),
  ],
  scenarioConfig: ScenarioConfig(
    definitions: [
      for (final MapEntry(key: name, value: theme) in themes.entries)
        ScenarioDefinition(
          name: name,
          modes: [ThemeMode<ThemeData>(name, theme, _themed)],
          strategy: ScenarioStrategy.perStory,
        ),
    ],
    setUp: setUp,
  ),
);
