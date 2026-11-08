import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  final milk = Item(
    id: 'milk',
    name: 'Milch',
    quantity: '2',
    brand: 'Weihenstephan',
    categoryId: 'other',
    status: ItemStatus.active,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(WidgetTester tester, double width, double scale) async {
    tester.view
      ..physicalSize = Size(width, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEditItemSheet(
                  context,
                  item: milk,
                  catalog: const Catalog(
                    categories: [
                      Category(id: 'other', name: 'Sonstiges', sortOrder: 1),
                    ],
                  ),
                  onCreateStore: (_) async => null,
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
  }

  bool oneRow(WidgetTester tester) =>
      tester.getTopLeft(key('edit-brand')).dy ==
      tester.getTopLeft(key('edit-quantity')).dy;

  void expectUnclipped(WidgetTester tester) {
    final label = tester.renderObject<RenderParagraph>(find.text('Menge'));
    expect(
      label.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(label.size.width),
      reason: 'Menge fits its label',
    );
    final brand = tester
        .state<EditableTextState>(
          find.descendant(
            of: key('edit-brand'),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    expect(
      brand.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(brand.size.width),
      reason: 'Weihenstephan fits the brand field',
    );
  }

  testWidgets('turning the phone while Menge is focused keeps it focused', (
    tester,
  ) async {
    await open(tester, 375, 1);
    expect(oneRow(tester), isFalse);
    await tester.tap(key('edit-quantity'));
    await tester.enterText(key('edit-quantity'), '4');
    await tester.pump();
    bool quantityFocused() => tester
        .widget<EditableText>(
          find.descendant(
            of: key('edit-quantity'),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;
    expect(quantityFocused(), isTrue);

    tester.view.physicalSize = const Size(430, 1200);
    await tester.pumpAndSettle();

    expect(oneRow(tester), isTrue);
    expect(quantityFocused(), isTrue);
    expect(
      tester.widget<TextField>(key('edit-quantity')).controller!.text,
      '4',
    );
  });

  testWidgets('430 px at 100 %: Marke, Menge and steppers share a row', (
    tester,
  ) async {
    await open(tester, 430, 1);
    expect(oneRow(tester), isTrue);
    expectUnclipped(tester);
  });

  for (final (width, scale) in [(375.0, 1.0), (375.0, 1.5)]) {
    testWidgets('${width.round()} px at ${(scale * 100).round()} %: Marke '
        'goes above Menge, neither clipped', (tester) async {
      await open(tester, width, scale);
      expect(oneRow(tester), isFalse);
      expect(
        tester.getBottomLeft(key('edit-brand')).dy,
        lessThan(tester.getTopLeft(key('edit-quantity')).dy),
      );
      expect(
        tester.getSize(key('edit-brand')).width,
        tester.getSize(key('edit-name')).width,
        reason: 'Marke is full width',
      );
      expectUnclipped(tester);
    });
  }
}
