// The fallback cell of an item without a known emoji (job 147), in the
// list row's 28 px icon column at 18 px and the add sheet's 24 px column at
// 20 px, on the plain, new (honey) and ticked (mint) row, light and dark.
// Emoji beside it are in docs/screenshots/147/ (the tester has no emoji
// font in CI). After a deliberate look change:
//   flutter test --update-goldens test/design/item_icon_fallback_golden_test.dart
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/list/list_view/item_icon_fallback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fonts.dart';

class const _Row({
  required final String name,
  required final double size,
  required final double column,
  required final Color color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: HlSpace.s4, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(
          width: column,
          child: Center(child: ItemIconFallback(size: size)),
        ),
        Text(
          name,
          style: TextStyle(
            fontFamily: HlFont.display,
            fontSize: 17,
            height: 21.25 / 17,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the cell is decorative and as big as the emoji font size', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Center(
          child: MergeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [ItemIconFallback(size: 18), Text('Kerzen')],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(MergeSemantics)),
      matchesSemantics(label: 'Kerzen'),
    );
    expect(
      tester.getSize(find.byType(ItemIconFallback)),
      const Size.square(18),
    );
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('item icon fallback, ${brightness.name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(240, 200);
      addTearDown(tester.view.reset);
      final hl = SnacklistColors.of(brightness);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          home: Scaffold(
            body: Column(
              children: [
                for (final (name, color) in [
                  ('Geschenkkarte', null),
                  ('Ohrenstäbchen', hl.honeySoft),
                  ('Batterien', hl.mintSoft),
                ])
                  _Row(
                    name: name,
                    size: 18,
                    column: 28,
                    color: color ?? hl.surface,
                  ),
                _Row(name: 'Kerzen', size: 20, column: 24, color: hl.honeySoft),
              ],
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/item-icon-fallback-${brightness.name}.png'),
      );
    });
  }
}
