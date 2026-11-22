// Peter's rule for the soft look (job 368): only buttons cast a drop shadow.
// Each screen is pumped under Look.soft and its render tree searched for a
// shadow outside a button.
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'shell_harness.dart';

/// Whether [box] paints a shadow: a decoration's shadows, or an elevation
/// with a visible shadow colour.
bool _castsShadow(RenderObject box) => switch (box) {
  RenderDecoratedBox(decoration: BoxDecoration(:final boxShadow?)) =>
    boxShadow.isNotEmpty,
  RenderDecoratedBox(decoration: ShapeDecoration(:final shadows?)) =>
    shadows.isNotEmpty,
  RenderPhysicalModel(:final elevation, :final shadowColor) ||
  RenderPhysicalShape(
    :final elevation,
    :final shadowColor,
  ) => elevation > 0 && shadowColor.a > 0,
  _ => false,
};

/// Whether the widget that made [box] sits in a button: a Material button
/// (the tactile ones among them) or a bare tactile face.
bool _inButton(RenderObject box) {
  final creator = box.debugCreator;
  if (creator is! DebugCreator) {
    return false;
  }
  var found = false;
  creator.element.visitAncestorElements((element) {
    found =
        element.widget is ButtonStyleButton || element.widget is TactileFace;
    return !found;
  });
  return found;
}

/// The widgets that cast a shadow outside a button, by type.
List<String> _shadowsOutsideButtons(WidgetTester tester) => [
  for (final box in tester.allRenderObjects)
    if (_castsShadow(box) && !_inButton(box))
      switch (box.debugCreator) {
        final DebugCreator creator => creator.element.debugGetCreatorChain(5),
        _ => '${box.runtimeType}',
      },
];

void main() {
  setUpAll(fakeSupabase);
  setUp(() => appLook = Look.soft);
  tearDown(() => appLook = Look.hex);

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    testWidgets('the list with items, $mode', (tester) async {
      await pumpShell(tester, brightness, long: true);
      expect(_shadowsOutsideButtons(tester), isEmpty);
    });

    testWidgets('the add sheet, $mode', (tester) async {
      await pumpShell(tester, brightness);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      expect(_shadowsOutsideButtons(tester), isEmpty);
    });

    testWidgets('the household switcher sheet, $mode', (tester) async {
      await pumpShell(tester, brightness);
      await tester.tap(find.byKey(const ValueKey('household-chip')));
      await tester.pumpAndSettle();
      expect(_shadowsOutsideButtons(tester), isEmpty);
    });

    testWidgets('a popup menu, $mode', (tester) async {
      await pumpShell(
        tester,
        brightness,
        initialLocation: householdPath,
        seed: (repo) => repo.lists = const [
          HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
          HouseholdList(id: 'party', name: 'Sommerfest', position: 1),
        ],
      );
      final menu = find.byKey(const ValueKey('list-actions-weekly'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is PopupMenuItem), findsWidgets);
      expect(_shadowsOutsideButtons(tester), isEmpty);
    });

    for (final (name, location) in [
      ('More', morePath),
      ('Einstellungen', appSettingsPath),
      ('Premium', premiumPath),
    ]) {
      testWidgets('$name, $mode', (tester) async {
        await pumpMore(
          tester,
          location: location,
          theme: ThemeMode.values.byName(mode),
          language: AppLanguage.de,
        );
        expect(_shadowsOutsideButtons(tester), isEmpty);
      });
    }

    testWidgets('a dialog, $mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNameDialog(
                    context,
                    title: 'Laden umbenennen',
                    confirm: 'Speichern',
                    label: 'Name',
                    initial: 'Wochenmarkt',
                    save: (_) async => true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(_shadowsOutsideButtons(tester), isEmpty);
    });
  }
}
