// Goldens of the themed components in every state, light and dark (design
// job 52). After a deliberate look change:
//   flutter test --update-goldens test/design/components_golden_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'components_grid.dart';
import 'fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('component states, ${brightness.name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(880, 1320);
      addTearDown(tester.view.reset);
      // The focused switch shows its ring as after keyboard input.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpWidget(componentsGrid(brightness));
      // The spinner never settles.
      await tester.pump(const Duration(milliseconds: 500));
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).showSnackBar(
        SnackBar(
          content: const Text('Butter gelöscht'),
          action: SnackBarAction(label: 'Rückgängig', onPressed: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/components-${brightness.name}.png'),
      );
    });
  }
}
