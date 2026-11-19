import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _lidl = Store(id: 'lidl', name: 'Lidl', sortOrder: 0, seedKey: 'lidl');
const _long = Store(
  id: 'long',
  name: 'Bioladen am Wochenmarkt Süd Großhandel',
  sortOrder: 0,
);

Future<void> _pump(
  WidgetTester tester,
  Store store,
  Brightness brightness, {
  double maxWidth = 220,
}) => tester.pumpWidget(
  MaterialApp(
    theme: appTheme(brightness),
    home: Center(child: StoreBadge(store, maxWidth: maxWidth)),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    final t = SnacklistColors.of(brightness);
    group('$brightness', () {
      testWidgets('shows the full name on token colours only', (tester) async {
        await _pump(tester, _lidl, brightness);
        expect(find.text('Lidl'), findsOneWidget);
        final text = tester.widget<Text>(find.text('Lidl'));
        expect(text.style?.color, t.text);
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byType(StoreBadge),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as ShapeDecoration;
        expect(decoration.color, t.surfaceRaised);
        final shape = decoration.shape as HexBorder;
        expect(shape.side.color, t.border);
        expect(shape.side.width, HlBorder.width);
        expect(tester.getSize(find.byType(StoreBadge)).height, 28);
      });

      testWidgets('a long name ends in an ellipsis, semantics keep it', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _long, brightness, maxWidth: 160);
        expect(tester.getSize(find.byType(StoreBadge)).width, 160);
        expect(
          tester.widget<Text>(find.text(_long.name)).overflow,
          TextOverflow.ellipsis,
        );
        expect(find.bySemanticsLabel(_long.name), findsOneWidget);
        handle.dispose();
      });
    });
  }

  testWidgets('an own store and a chain look the same but for the name', (
    tester,
  ) async {
    await _pump(tester, _lidl, Brightness.light);
    final chain = tester.getSize(find.byType(StoreBadge)).height;
    await _pump(
      tester,
      const Store(id: 'x', name: 'Bäcker', sortOrder: 0),
      Brightness.light,
    );
    expect(tester.getSize(find.byType(StoreBadge)).height, chain);
  });
}
