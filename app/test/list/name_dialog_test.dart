import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The name dialog sizes to its content (job 152): title, label, field and
/// counter, then the buttons, with no empty space above them, keyboard open
/// or not, on a small phone and with large text.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required Size size,
    required double keyboard,
    required double textScale,
    required Locale locale,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNameDialog(
                  context,
                  title: AppLocalizations.of(context).storeRename('dm'),
                  confirm: AppLocalizations.of(context).save,
                  label: AppLocalizations.of(context).storeNameHint,
                  initial: 'dm',
                  maxLength: 40,
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
  }

  /// The whole field, its border and counter included, shows between the
  /// dialog's top and its buttons.
  ///
  /// With text at 2x on a small phone with the keyboard open, the label and
  /// field are taller than the room left between the title and the buttons:
  /// then [line], the line typed into, is what stays in view.
  void expectFieldInView(WidgetTester tester, {bool line = false}) {
    final field = tester.getRect(
      line
          ? find.byType(EditableText)
          : find.byKey(const ValueKey('name-dialog-field')),
    );
    final buttons = tester.getRect(find.byType(OverflowBar));
    final dialog = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(field.top, greaterThanOrEqualTo(dialog.top));
    expect(
      field.bottom,
      lessThanOrEqualTo(buttons.top),
      reason: 'the field the keyboard types into stays in view',
    );
  }

  testWidgets('iPhone SE: the keyboard rises after the dialog opened, and '
      'the whole field stays in view', (tester) async {
    for (final locale in const [Locale('de'), Locale('en')]) {
      await open(
        tester,
        size: const Size(320, 568),
        keyboard: 0,
        textScale: 1,
        locale: locale,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 253);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectFieldInView(tester);
      await tester.pumpWidget(const SizedBox());
    }
  });

  // The fix itself, without the name dialog's scrolling: a labelled field
  // in a plain dialog is as tall as its content.
  testWidgets('a LabeledField in a dialog takes only its own height', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: const AlertDialog(
          content: LabeledField(label: 'Name', field: TextField()),
          actions: [TextButton(onPressed: null, child: Text('OK'))],
        ),
      ),
    );
    expect(
      tester.getRect(find.byType(OverflowBar)).top -
          tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(HlSpace.s6),
    );
  });

  const phones = {'iPhone 15': Size(393, 852), 'iPhone SE': Size(320, 568)};
  const keyboards = {'iPhone 15': 336.0, 'iPhone SE': 253.0};

  for (final MapEntry(key: phone, value: size) in phones.entries) {
    for (final open_ in [false, true]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final locale in const [Locale('de'), Locale('en')]) {
          final keyboard = open_ ? keyboards[phone]! : 0.0;
          testWidgets(
            '$phone, keyboard ${open_ ? 'open' : 'closed'}, text x$scale, '
            '${locale.languageCode}: buttons right under the counter',
            (tester) async {
              await open(
                tester,
                size: size,
                keyboard: keyboard,
                textScale: scale,
                locale: locale,
              );
              expect(tester.takeException(), isNull);
              final field = tester.getRect(
                find.byKey(const ValueKey('name-dialog-field')),
              );
              final buttons = tester.getRect(find.byType(OverflowBar));
              final dialog = tester.getRect(
                find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.byType(Material),
                    )
                    .first,
              );
              expect(
                buttons.top - field.bottom,
                lessThanOrEqualTo(HlSpace.s6),
                reason: 'no dead space between counter and buttons',
              );
              expect(
                dialog.bottom,
                lessThanOrEqualTo(size.height - keyboard),
                reason: 'the dialog stays above the keyboard',
              );
              expect(buttons.bottom, lessThanOrEqualTo(dialog.bottom));
              expectFieldInView(
                tester,
                line: phone == 'iPhone SE' && open_ && scale == 2,
              );
            },
          );
        }
      }
    }
  }
}
