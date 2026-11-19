// Goldens of list rows while they are ticked off (job 57): a partner's new
// row (honey), mid-strike and struck, a wrapped name struck on both lines,
// light and dark, at the 358 px compact width. After a deliberate look change:
//   flutter test --update-goldens test/design/list_row_golden_test.dart
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fonts.dart';

final _at = DateTime.utc(2026, 11);

Item _item(String name, {String? quantity, String category = 'produce'}) =>
    Item(
      id: name,
      name: name,
      quantity: quantity,
      status: ItemStatus.active,
      createdAt: _at,
      updatedAt: _at,
      categoryId: category,
      sortKey: 0,
    );

final _rows = [
  _item('Bananen', quantity: '6'),
  _item('Vollmilch', quantity: '2 l', category: 'dairy'),
  _item('Brot', category: 'bakery'),
  _item('Laktosefreie Bio-Vollmilch aus der Region', category: 'dairy'),
];

void main() {
  setUpAll(() async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await loadAppFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('list rows ticking off, ${brightness.name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(358, 330);
      addTearDown(tester.view.reset);
      final leaving = LeavingRows();
      addTearDown(leaving.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          locale: const Locale('de'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                for (final item in _rows)
                  ItemRow(
                    key: ValueKey(item.id),
                    item: item,
                    category: null,
                    leaving: leaving,
                    // A partner's new row is honey (job 56 item 34).
                    fresh: item == _rows.first,
                    last: item == _rows.last,
                    onVisible: (_) {},
                    onTickStart: (_) {},
                    onTick: (_) {},
                    onEdit: (_) {},
                    onDelete: (_) {},
                  ),
              ],
            ),
          ),
        ),
      );
      Finder row(Item item) => find.byKey(ValueKey(item.id));
      // Brot and the long name struck, Vollmilch a quarter into its draw.
      await tester.tap(row(_rows[2]));
      await tester.tap(row(_rows[3]));
      await tester.pump();
      await tester.pump(HlDuration.short * 3 ~/ 4);
      await tester.tap(row(_rows[1]));
      await tester.pump();
      await tester.pump(HlDuration.short ~/ 4);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-rows-${brightness.name}.png'),
      );
      await tester.pumpAndSettle();
    });
  }
}
