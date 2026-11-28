import 'dart:ui' as ui;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 497: the compact add sheet's first row sits just under the sheet's
/// rounded top. Its top corners take the sheet's radius, so its face, the
/// Enter outline and the focus ring follow the sheet's curve and the sheet
/// cuts none of them; AE2's split row (flag `add-ae2-list-peeks`) rounds
/// the merge part's top-left and the tick key's top-right.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => appLook = Look.hex);

  const phone = Size(390, 844);

  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool peeks,
    required String text,
    double textScale = 1,
    Locale locale = const Locale('de'),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = phone * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = FakeRepository()
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Bananen', quantity: '6', storeId: 'lidl')
      ..parsed['Milch'] = const ParsedEntry(
        name: 'Milch',
        categoryId: 'chilled',
        storeId: 'lidl',
      );
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    final flags = Flags(
      forced: {
        addFeedbackListFlag,
        inputStableRowsFlag,
        addSheetCompactFlag,
        addMatchRowsFlag,
        if (peeks) addAe2ListPeeksFlag,
      },
    );
    addTearDown(list.close);
    addTearDown(flags.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: flags),
          BlocProvider.value(value: list),
        ],
        child: MaterialApp.router(
          theme: appTheme(brightness),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('add-item-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Finder keyStarting(String prefix) => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith(prefix);
  });

  /// The first row of each kind, its top corners and the colours of its
  /// face and edge.
  final kinds =
      <
        ({
          String name,
          bool peeks,
          String text,
          List<({Finder part, bool left, bool right})> parts,
          Color Function(ColorScheme) face,
          Color Function(ColorScheme)? edge,
          String? golden,
        })
      >[
        (
          name: 'AE2 merge and tick off',
          peeks: true,
          text: 'Bananen',
          parts: [
            (
              part: find.byKey(const ValueKey('match-split-merge')),
              left: true,
              right: false,
            ),
          ],
          face: (s) => s.primaryContainer,
          edge: (s) => s.primary,
          golden: 'ae2',
        ),
        (
          name: 'AE2 tick key',
          peeks: true,
          text: 'Bananen',
          parts: [
            (
              part: find.byKey(const ValueKey('match-split-tick')),
              left: false,
              right: true,
            ),
          ],
          face: (s) => s.tertiaryContainer,
          edge: null,
          golden: null,
        ),
        (
          name: 'AE2 suggestion',
          peeks: true,
          text: 'Milch',
          parts: [(part: keyStarting('suggestion-'), left: true, right: true)],
          face: (s) => s.secondaryContainer,
          edge: null,
          golden: null,
        ),
        (
          name: 'match row',
          peeks: false,
          text: 'Bananen',
          parts: [
            (part: keyStarting('match-MergeRow-'), left: true, right: true),
          ],
          face: (s) => s.primaryContainer,
          edge: null,
          golden: 'compact',
        ),
        (
          name: 'suggestion',
          peeks: false,
          text: 'Milch',
          parts: [(part: keyStarting('suggestion-'), left: true, right: true)],
          face: (s) => s.secondaryContainer,
          edge: null,
          golden: null,
        ),
      ];

  Future<({ByteData pixels, int width, double scale})> capture(
    WidgetTester tester,
  ) async {
    final image = (await tester.runAsync(
      () => captureImage(tester.element(find.byType(MaterialApp))),
    ))!;
    final pixels = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
    ))!;
    return (
      pixels: pixels,
      width: image.width,
      scale: image.width / phone.width,
    );
  }

  bool near(Color a, Color b) =>
      ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 12;

  /// The points of [row]'s top [left] or right corner that break the sheet's
  /// curve: outside an arc of [sheetRadius] from the row's top in the
  /// [face] colour, a little inside it not in the face colour, or, when the
  /// corner has an [edge] (the Enter outline, the focus ring), just inside
  /// the arc not in the edge's colour.
  Future<List<String>> cornerFaults(
    WidgetTester tester,
    Rect row, {
    required bool left,
    required Color face,
    Color? edge,
    double edgeWidth = 0,
  }) async {
    final shot = await capture(tester);
    Color at(Offset p) {
      final i =
          ((p.dy * shot.scale).floor() * shot.width +
              (p.dx * shot.scale).floor()) *
          4;
      final rgba = shot.pixels.getUint32(i);
      return Color.fromARGB(
        rgba & 0xff,
        rgba >> 24 & 0xff,
        rgba >> 16 & 0xff,
        rgba >> 8 & 0xff,
      );
    }

    final r = sheetRadius;
    final centre = Offset(left ? row.left + r : row.right - r, row.top + r);
    final faults = <String>[];
    for (var dy = 0.25; dy < r; dy += 0.5) {
      for (var dx = 0.25; dx < r; dx += 0.5) {
        final p = Offset(left ? row.left + dx : row.right - dx, row.top + dy);
        final out = (p - centre).distance - r;
        final colour = at(p);
        final fault = switch (out) {
          > 1.5 when near(colour, face) => 'face outside the arc',
          < 0 when edge != null && out > -edgeWidth + 0.75 && out < -0.75 =>
            near(colour, edge) ? null : 'no edge along the arc',
          < 0 when out < -edgeWidth - 1.5 && out > -edgeWidth - 5 =>
            near(colour, face) ? null : 'no face inside the arc',
          _ => null,
        };
        if (fault != null) {
          faults.add(
            '$fault at (${dx.toStringAsFixed(2)}, '
            '${dy.toStringAsFixed(2)})',
          );
        }
      }
    }
    return faults;
  }

  Future<void> expectCorners(
    WidgetTester tester, {
    required List<({Finder part, bool left, bool right})> parts,
    required Color face,
    Color? edge,
    double edgeWidth = 0,
  }) async {
    final surface = tester.getRect(
      find.byKey(const ValueKey('add-sheet-surface')),
    );
    for (final (:part, :left, :right) in parts) {
      final row = tester.getRect(part.first);
      expect(row.top, greaterThan(surface.top), reason: 'under the handle');
      expect(
        row.top - surface.top,
        lessThan(sheetRadius),
        reason: 'in the curve',
      );
      for (final (side, on) in [('left', left), ('right', right)]) {
        if (!on) {
          continue;
        }
        final faults = await cornerFaults(
          tester,
          row,
          left: side == 'left',
          face: face,
          edge: edge,
          edgeWidth: edgeWidth,
        );
        expect(
          faults,
          isEmpty,
          reason:
              'top-$side corner: ${faults.length} faults, first '
              '${faults.take(3).join('; ')}',
        );
      }
    }
  }

  for (final kind in kinds) {
    for (final look in Look.values) {
      for (final brightness in Brightness.values) {
        for (final textScale in [1.0, 2.0]) {
          for (final locale in const [Locale('de'), Locale('en')]) {
            // The soft look once per row: only its radius differs.
            if (look == Look.soft &&
                (brightness == Brightness.dark ||
                    textScale != 1 ||
                    locale.languageCode != 'de')) {
              continue;
            }
            testWidgets("${kind.name}: the top row follows the sheet's "
                'corners (${look.name}, ${brightness.name}, '
                '${(textScale * 100).round()} %, ${locale.languageCode})', (
              tester,
            ) async {
              appLook = look;
              await pumpSheet(
                tester,
                peeks: kind.peeks,
                text: kind.text,
                textScale: textScale,
                locale: locale,
                brightness: brightness,
              );
              final scheme = Theme.of(tester.element(find.byType(ShoppingList)))
                  .colorScheme;
              await expectCorners(
                tester,
                parts: kind.parts,
                face: kind.face(scheme),
                edge: kind.edge?.call(scheme),
                edgeWidth: kind.edge == null ? 0 : 2,
              );
              if (kind.golden case final golden? when look == Look.hex) {
                final name =
                    'top-row-$golden-${brightness.name}-'
                    '${(textScale * 100).round()}-${locale.languageCode}';
                await expectLater(
                  find.byKey(const ValueKey('add-sheet-surface')),
                  matchesGoldenFile('goldens/$name.png'),
                );
              }
            });
          }
        }
      }
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets("the focus ring follows the top row's corners "
        '(${brightness.name})', (tester) async {
      await pumpSheet(
        tester,
        peeks: true,
        text: 'Milch',
        brightness: brightness,
      );
      final row = keyStarting('suggestion-').first;
      var reached = false;
      for (var i = 0; i < 12 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null &&
            find
                .ancestor(
                  of: find.byElementPredicate((e) => e == focused),
                  matching: row,
                )
                .evaluate()
                .isNotEmpty) {
          reached = true;
        }
      }
      expect(reached, isTrue, reason: 'Tab reaches the first row');
      final context = tester.element(find.byType(ShoppingList));
      final scheme = Theme.of(context).colorScheme;
      await expectCorners(
        tester,
        parts: [(part: row, left: true, right: true)],
        face: scheme.secondaryContainer,
        edge: focusRingColor(SnacklistColors.of(brightness)),
        edgeWidth: HlFocus.ringWidth,
      );
    });
  }
}
