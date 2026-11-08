import 'dart:math' as math;

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../more/more_harness.dart';
import 'fonts.dart';

/// Labels stay clear of a hex's pointed ends at large text (job 154): on a
/// 375 px phone at 150 % text, the settings segments, a category pill and
/// the edit sheet's chips and options keep [hexLabelClearance] between
/// their lines and the hex's outline.
void main() {
  setUpAll(() async {
    await fakeSupabase();
    await loadAppFonts();
  });

  const phone = Size(375, 667);
  const scale = 1.5;
  Finder key(String k) => find.byKey(ValueKey(k));

  void large(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// How far [text]'s line box stays inside the slanted sides of the
  /// horizontal hex drawn in [face], on the closer side: they run from the
  /// tips at mid-height to [HlHex.tip] times the height in at the top and
  /// bottom.
  double offTips(Rect face, Rect text) {
    final half = face.height / 2;
    final reach = math.min(
      half,
      math.max(
        (text.top - face.center.dy).abs(),
        (text.bottom - face.center.dy).abs(),
      ),
    );
    final slant = HlHex.tip * face.height * reach / half;
    return math.min(
      text.left - (face.left + slant),
      face.right - slant - text.right,
    );
  }

  void clear(WidgetTester tester, Rect face, Finder text, String what) {
    expect(text, findsOneWidget, reason: what);
    final line = tester.getRect(text);
    final tips = offTips(face, line);
    expect(
      tips,
      greaterThanOrEqualTo(hexLabelClearance - 0.01),
      reason: '$what: $tips px from the tips',
    );
    // A line box has leading of its own; it only has to clear the contour.
    final flat = math.min(line.top - face.top, face.bottom - line.bottom);
    expect(
      flat,
      greaterThanOrEqualTo(HlBorder.width),
      reason: '$what: $flat px from the flat sides',
    );
  }

  testWidgets('the settings segments keep their labels off the tips', (
    tester,
  ) async {
    large(tester);
    await pumpMore(tester, location: appSettingsPath, size: phone);
    for (final (segment, label) in [
      ('theme-system', 'System'),
      ('theme-light', 'Hell'),
      ('theme-dark', 'Dunkel'),
    ]) {
      // The honey indicator's hex fills the segment, inside the track's
      // contour.
      final slot = tester.getRect(key(segment));
      final face = Rect.fromLTRB(
        slot.left,
        slot.top + HlBorder.width + 2,
        slot.right,
        slot.bottom - HlBorder.width - 2,
      );
      clear(
        tester,
        face,
        find.descendant(of: key(segment), matching: find.text(label)),
        label,
      );
    }
  });

  testWidgets("a store's category pills keep their titles off the tips", (
    tester,
  ) async {
    large(tester);
    await pumpMore(
      tester,
      location: storeDetailsPath('lidl'),
      size: phone,
      routes: listTabRoutes(),
    );
    for (final name in ['Obst & Gemüse', 'Kühlregal']) {
      final title = find.text(name);
      final face = tester.getRect(
        find.ancestor(of: title, matching: find.byType(InkWell)).first,
      );
      clear(tester, face, title, name);
    }
  });

  testWidgets("the edit sheet's chips keep their labels off the tips", (
    tester,
  ) async {
    large(tester);
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: FoldoutChips(
            catalog: const Catalog(
              categories: [
                Category(id: 'cool', name: 'Kühlregal', sortOrder: 1),
              ],
              stores: [Store(id: 'lidl', name: 'Lidl', sortOrder: 1)],
            ),
            storeId: 'lidl',
            categoryId: 'cool',
            storeLabel: 'Ohne Laden',
            categoryLabel: 'Kategorie',
            onStore: (_) {},
            onCategory: (_) {},
            chipIcons: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (chip, label) in [
      ('chip-store', 'Lidl'),
      ('chip-category', 'Kühlregal'),
    ]) {
      final button = tester.getRect(
        find.descendant(of: key(chip), matching: find.byType(TactileFace)),
      );
      // The face rests on its edge.
      final face = Rect.fromLTRB(
        button.left,
        button.top,
        button.right,
        button.bottom - (raisedFaces ? HlDepth.edge : 0),
      );
      clear(
        tester,
        face,
        find.descendant(of: key(chip), matching: find.text(label)),
        label,
      );
    }
    await tester.tap(key('chip-category'));
    await tester.pumpAndSettle();
    final option = key('category-option-cool');
    clear(
      tester,
      tester.getRect(
        find.descendant(of: option, matching: find.byType(Material)).first,
      ),
      find.descendant(of: option, matching: find.text('Kühlregal')),
      'option Kühlregal',
    );
  });
}
