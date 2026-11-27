import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

void main() {
  const t = SnacklistColors.light;

  Future<void> pumpField(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Center(child: SizedBox(width: 240, child: field)),
        ),
      ),
    );
    await tester.pump();
  }

  Finder decorator() => find.byType(InputDecorator);

  // Near the top-left corner: inside a rounded rectangle, outside the hex,
  // whose left side slants in towards the top.
  const corner = Offset(5, 5);

  testWidgets('a single-line field is a hex with the 2 px contour', (
    tester,
  ) async {
    await pumpField(
      tester,
      const TextField(decoration: InputDecoration(hintText: 'E-Mail')),
    );
    expect(
      decorator(),
      paints
        // The face, then the contour.
        ..path()
        ..path(
          style: PaintingStyle.stroke,
          strokeWidth: HlBorder.width,
          color: t.border,
          includes: [const Offset(120, 28)],
          excludes: [corner],
        ),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('focused (${brightness.name}), the contour turns cobalt and '
        'the ring grows inward from it, all inside the field', (tester) async {
      final colors = SnacklistColors.of(brightness);
      Future<Rect> pump({required bool focused}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  child: TextField(
                    key: ValueKey(focused),
                    autofocus: focused,
                    decoration: const InputDecoration(hintText: 'E-Mail'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getRect(decorator());
      }

      final idle = await pump(focused: false);
      final focused = await pump(focused: true);
      expect(focused, idle, reason: 'focus moves nothing');
      expect(
        decorator(),
        paints
          ..path()
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: HlBorder.width,
            color: colors.accent,
          )
          // From 2 to 5 px in from the field's top edge.
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: HlFocus.ringWidth,
            color: colors.accent,
            includes: [const Offset(120, 5.5)],
            excludes: [const Offset(120, 1.5), const Offset(120, -1)],
          ),
      );
    });
  }

  testWidgets('an error turns the contour to the error colour', (tester) async {
    await pumpField(
      tester,
      const TextField(
        decoration: InputDecoration(hintText: 'E-Mail', errorText: 'Nein'),
      ),
    );
    expect(
      decorator(),
      paints
        // The face, then the contour.
        ..path()
        ..path(
          style: PaintingStyle.stroke,
          strokeWidth: HlBorder.width,
          color: t.error,
        ),
    );
  });

  testWidgets('focused with an error, the error contour keeps the cobalt '
      'ring inside it', (tester) async {
    await pumpField(
      tester,
      const TextField(
        autofocus: true,
        decoration: InputDecoration(hintText: 'E-Mail', errorText: 'Nein'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      decorator(),
      paints
        ..path()
        ..path(
          style: PaintingStyle.stroke,
          strokeWidth: HlBorder.width,
          color: t.error,
        )
        ..path(
          style: PaintingStyle.stroke,
          strokeWidth: HlFocus.ringWidth,
          color: t.accent,
          includes: [const Offset(120, 5.5)],
          excludes: [const Offset(120, 1.5)],
        ),
    );
  });

  testWidgets('a multi-line field keeps the rounded contour', (tester) async {
    await pumpField(
      tester,
      const RoundedFields(
        child: TextField(
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: 'Nachricht'),
        ),
      ),
    );
    expect(
      decorator(),
      paints
        // The face, then the contour.
        ..path()
        ..path(
          style: PaintingStyle.stroke,
          strokeWidth: HlBorder.width,
          color: t.border,
          includes: [corner],
        ),
    );
  });

  for (final (name, field) in [
    ('hint only', const TextField(decoration: InputDecoration(hintText: 'x'))),
    ('labelled', const LabeledField(label: 'x', field: TextField())),
    (
      'multi-line',
      const RoundedFields(child: TextField(minLines: 2, maxLines: 4)),
    ),
  ]) {
    testWidgets('$name field is at least 48 dp tall', (tester) async {
      await pumpField(tester, field);
      expect(
        tester.getSize(decorator()).height,
        greaterThanOrEqualTo(HlSize.target),
      );
    });
  }

  for (final (name, wrap, lines) in [
    ('hex', (Widget f) => f, 1),
    ('multi-line', (Widget f) => RoundedFields(child: f), 3),
  ]) {
    for (final error in [true, false]) {
      final kind = error ? 'error' : 'helper';
      testWidgets('$name: the $kind and counter sit 13 px below the field, '
          'in line with the text', (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        Widget field({required bool subtext}) => wrap(
          TextField(
            autofillHints: null,
            focusNode: focus,
            autofocus: true,
            minLines: lines,
            maxLines: lines,
            maxLength: subtext ? 80 : null,
            decoration: InputDecoration(
              errorText: subtext && error ? 'Nein' : null,
              helperText: subtext && !error ? 'Nein' : null,
            ),
          ),
        );
        await pumpField(tester, field(subtext: false));
        await tester.pumpAndSettle();
        final contour = tester.getRect(decorator()).height;
        await pumpField(tester, field(subtext: true));
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(decorator()).dy;
        double below(String text) =>
            tester.getTopLeft(find.text(text)).dy - top - contour;

        // Where the outer focus ring before FH1 (job 487) ended, plus s2.
        expect(below('Nein'), 5 + HlSpace.s2);
        expect(below('0/80'), below('Nein'));
        final text = tester.getRect(find.byType(EditableText));
        expect(
          tester.getTopLeft(find.text('Nein')).dx,
          moreOrLessEquals(text.left),
        );
        expect(
          tester.getTopRight(find.text('0/80')).dx,
          moreOrLessEquals(text.right),
        );
      });
    }
  }

  group('the add field', () {
    final addField = find.byKey(const ValueKey('add-item-field'));

    /// The list with [theme], the add field tapped, so focused: where the
    /// field and its text sit.
    Future<(Rect, Rect)> focusedField(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: BlocProvider(
            create: (_) =>
                ListCubit(FakeRepository(), MemoryListCache(), userId: 'peter')
                  ..start(),
            child: const ShoppingList(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(addField);
      await tester.pumpAndSettle();
      Rect rect(Type type) => tester.getRect(
        find.descendant(of: addField, matching: find.byType(type)),
      );
      return (rect(InputDecorator), rect(EditableText));
    }

    // Job 52, DECISIONS item 7: a field theme that reached this field grew
    // the add sheet and broke e2e add-sheet.spec.ts:61 and list.spec.ts:12.
    testWidgets('draws no contour of its own and keeps its geometry', (
      tester,
    ) async {
      final app = appTheme(Brightness.light);
      final withoutFieldTheme = await focusedField(
        tester,
        app.copyWith(inputDecorationTheme: const InputDecorationThemeData()),
      );
      final themed = await focusedField(tester, app);
      expect(themed, withoutFieldTheme);
      expect(
        find.descendant(of: addField, matching: decorator()),
        isNot(paints..path()),
      );
    });
  });
}
