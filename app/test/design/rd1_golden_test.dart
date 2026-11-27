// Goldens of RD1, the look without hexagons (job 368, flag redesign-rd1):
// the main screens and the components under Look.soft, light and dark, in
// German and English, at text scale 0.85 and 3.1. After a deliberate look
// change:
//   flutter test --update-goldens test/design/rd1_golden_test.dart
//
// Text at 3.1 overflows the components grid's fixed cells in either look;
// that test records the overflows in its name's line of the log and still
// compares the golden, so the matrix stays whole. Any other screen fails.
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/design/count_badge.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/list/list_view/item_icon_fallback.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import 'components_grid.dart';
import 'fonts.dart';
import 'shell_harness.dart';

/// The flags testers had on when RD1 landed (job 368), so the shots keep
/// prices and trip mode although HP2 turned them off for everyone (job
/// 401); all but grocery-log, whose Verlauf tab the shell harness has no
/// branch for. `test/launch/users_flags_test.dart` reads the users' set.
const _usersFlags = {
  publicApiFlag,
  pricesFlag,
  defaultListFlag,
  listDeclutterFlag,
  tripModeFlag,
  feedbackFb2Flag,
  feedbackFb4Flag,
  joinHouseholdJh2Flag,
  inputStableRowsFlag,
  onDeviceCatalogFlag,
  addFeedbackListFlag,
  displayNameFlag,
};

/// Today's prices, so the list counts them (`Price.isCurrent`); the rows
/// show amounts only, never the date.
Price _price(int cents) => Price(
  unitMicros: cents * microsPerCent,
  basis: PriceBasis.unit,
  per: PricePer.piece,
  currency: 'EUR',
  pricedAt: DateTime.now(),
);

/// Prices on two rows and an item without an emoji (the placeholder).
void _groceries(FakeRepository repo) {
  for (final (id, cents) in [('3', 119), ('4', 249)]) {
    repo.rows[id] = repo.rows[id]!.copyWith(price: () => _price(cents));
  }
  repo.rows['5'] = shellItem('5', 'Kabelbinder', 'dm', 'other');
}

const _households = [
  Household(id: 'home', name: 'Zuhause', isDefault: true, memberCount: 2),
  Household(id: 'club', name: 'Sommerfest', memberCount: 12),
];

/// RD1's components below the grid: radios, count badges, the pointy
/// shapes, the item placeholder and a group.
List<Widget> _soft(BuildContext context) => [
  const SizedBox(height: HlSpace.s4),
  RadioGroup<int>(
    groupValue: 1,
    onChanged: (_) {},
    child: const Row(
      children: [
        SizedBox(width: 90, child: Text('Radio')),
        HexRadio<int>(value: 0),
        HexRadio<int>(value: 1),
        HexRadio<int>(value: 2, enabled: false),
        SizedBox(width: HlSpace.s5),
        HlCountBadge(3),
        SizedBox(width: HlSpace.s3),
        HlCountBadge(12),
        SizedBox(width: HlSpace.s5),
        PointyHex(face: Color(0xFFFFE14D), size: 34),
        SizedBox(width: HlSpace.s3),
        ItemIconFallback(size: 20),
      ],
    ),
  ),
  const HlGroup(
    top: HlSpace.s3,
    children: [
      ListTile(
        leading: HlRowHex(Icons.settings_outlined, face: Color(0xFFFFE14D)),
        title: Text('Gruppe'),
      ),
      ListTile(
        leading: HlRowHex(Icons.help_outline, face: Color(0xFFBFE8D2)),
        title: Text('Ohne Schatten'),
      ),
    ],
  ),
];

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await fakeSupabase();
    // The More harness keeps the debug banner; these goldens are PR shots.
    WidgetsApp.debugAllowBannerOverride = false;
  });
  setUp(() => appLook = Look.soft);
  tearDown(() => appLook = Look.hex);

  final screens =
      <String, Future<void> Function(WidgetTester, Brightness, String)>{
        'list': (tester, brightness, lang) async {
          await pumpShell(
            tester,
            brightness,
            locale: Locale(lang),
            flags: _usersFlags,
            seed: _groceries,
          );
          // Zahnpasta, the first row, struck off and still leaving. At 310 %
          // the „Erste Schritte“ card fills the screen: scroll the row in.
          if (find.text('Zahnpasta').evaluate().isEmpty) {
            await tester.dragUntilVisible(
              find.text('Zahnpasta'),
              find.byType(Scrollable).first,
              const Offset(0, -100),
            );
          }
          await tester.tap(find.text('Zahnpasta'));
          await tester.pump();
          await tester.pump(HlDuration.short);
        },
        'add-sheet': (tester, brightness, lang) async {
          await pumpShell(
            tester,
            brightness,
            locale: Locale(lang),
            flags: _usersFlags,
          );
          final field = find.byKey(const ValueKey('add-item-field'));
          await tester.tap(field);
          // The catalog follows the app language (job 470).
          await tester.enterText(field, lang == 'de' ? 'Milch' : 'Milk');
          await tester.pumpAndSettle();
        },
        'household-sheet': (tester, brightness, lang) async {
          await pumpShell(
            tester,
            brightness,
            locale: Locale(lang),
            flags: _usersFlags,
            households: _households,
          );
          await tester.tap(find.byKey(const ValueKey('list-switcher')));
          await tester.pumpAndSettle();
        },
        'list-empty': (tester, brightness, lang) async {
          await pumpShell(
            tester,
            brightness,
            locale: Locale(lang),
            flags: _usersFlags,
            empty: true,
          );
        },
        'more': (tester, brightness, lang) async {
          await pumpMore(
            tester,
            theme: ThemeMode.values.byName(brightness.name),
            language: AppLanguage.byCode(lang),
            flags: _usersFlags,
          );
        },
        'settings': (tester, brightness, lang) async {
          await pumpMore(
            tester,
            location: appSettingsPath,
            theme: ThemeMode.values.byName(brightness.name),
            language: AppLanguage.byCode(lang),
            flags: _usersFlags,
          );
        },
        'stores': (tester, brightness, lang) async {
          await pumpMore(
            tester,
            location: editPath,
            theme: ThemeMode.values.byName(brightness.name),
            language: AppLanguage.byCode(lang),
            flags: _usersFlags,
            routes: listTabRoutes(),
          );
        },
        'components': (tester, brightness, lang) async {
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = const Size(880, 1500);
          addTearDown(tester.view.reset);
          // The focused controls show their rings as after keyboard input.
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          addTearDown(
            () => FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.automatic,
          );
          await tester.pumpWidget(
            Builder(
              builder: (context) => componentsGrid(
                brightness,
                locale: Locale(lang),
                extra: _soft(context),
              ),
            ),
          );
          // The spinner never settles.
          await tester.pump(const Duration(milliseconds: 500));
          ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
              .showSnackBar(
                SnackBar(
                  content: const Text('Butter gelöscht'),
                  action: SnackBarAction(label: 'Rückgängig', onPressed: () {}),
                ),
              );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        },
      };

  for (final MapEntry(key: name, value: pump) in screens.entries) {
    for (final brightness in Brightness.values) {
      // The components grid's labels are German whatever the locale.
      for (final lang in name == 'components' ? ['de'] : ['de', 'en']) {
        for (final scale in [0.85, 3.1]) {
          final golden = '$name-$lang-${brightness.name}-x$scale';
          testWidgets(golden, (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final overflows = <String>[];
            final report = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              if (name == 'components' && text.contains('overflowed')) {
                overflows.add(text.split('\n').first);
              } else {
                report?.call(details);
              }
            };
            try {
              await pump(tester, brightness, lang);
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile('goldens/rd1/$golden.png'),
              );
              await tester.pump(const Duration(seconds: 10));
            } finally {
              FlutterError.onError = report;
            }
            if (overflows.isNotEmpty) {
              debugPrint('$golden overflows: ${overflows.toSet().join('; ')}');
            }
          });
        }
      }
    }
  }
}
