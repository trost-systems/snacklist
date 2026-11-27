// The switch, check box and radio draw a focus ring of their own, which goes
// almost solid navy when they are on (FH1, job 487). In the app they only sit
// in their tiles, which take the focus: Tab never reaches the control itself.
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final tiles = <(String, Type, Widget)>[
    (
      'switch tile',
      HexSwitch,
      HexSwitchTile(title: const Text('A'), value: true, onChanged: (_) {}),
    ),
    (
      'check box tile',
      HexCheckbox,
      HexCheckboxListTile(
        title: const Text('A'),
        value: true,
        onChanged: (_) {},
      ),
    ),
    (
      'radio tile',
      HexRadio<int>,
      RadioGroup<int>(
        groupValue: 1,
        onChanged: (_) {},
        child: const HexRadioTile(value: 1, title: Text('A')),
      ),
    ),
  ];

  for (final (name, control, tile) in tiles) {
    testWidgets('a $name takes the focus; its control never does', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [tile, const TextField(autofillHints: null)],
            ),
          ),
        ),
      );
      Finder at(Element element) =>
          find.byElementPredicate((e) => e == element);
      var tileFocused = false;
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final primary = FocusManager.instance.primaryFocus?.context;
        if (primary is! Element) {
          continue;
        }
        expect(
          find.descendant(of: find.byType(control), matching: at(primary)),
          findsNothing,
          reason: 'the control inside the tile took the focus',
        );
        if (find
            .ancestor(of: at(primary), matching: find.byType(ListTile))
            .evaluate()
            .isNotEmpty) {
          tileFocused = true;
        }
      }
      expect(tileFocused, isTrue, reason: 'Tab never reached the tile');
    });
  }
}
