// FH1 (job 487): every control shows keyboard focus as a ring inside it,
// in cobalt, or navy on a honey face. Each case renders the control,
// focuses it and compares the pixels: the focus colour appears, no pixel
// changes outside the control, and nothing moves.
import 'dart:typed_data';

import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'focus_cases.dart';

void main() {
  setUpAll(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );
  tearDown(() {
    appLook = Look.hex;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<Uint8List> shoot(WidgetTester tester) async {
    final image = await captureFocusCase(tester);
    final bytes = await tester.runAsync(() async {
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// Focuses [c] with [strategy] and compares the frames: the pixels that
  /// changed, and the control's and its neighbour's rects before and after.
  Future<({List<(int, int, Color)> changed, bool moved})> focus(
    WidgetTester tester,
    FocusCase c,
    FocusHighlightStrategy strategy,
  ) async {
    FocusManager.instance.highlightStrategy = strategy;
    await tester.pumpAndSettle();
    final before = await shoot(tester);
    final rects = [
      c.bounds(tester),
      tester.getRect(find.byKey(const ValueKey('neighbour'))),
    ];
    c.node(tester).requestFocus();
    await tester.pumpAndSettle();
    final after = await shoot(tester);
    final moved =
        rects[0] != c.bounds(tester) ||
        rects[1] != tester.getRect(find.byKey(const ValueKey('neighbour')));
    final width = tester.view.physicalSize.width.toInt();
    final changed = <(int, int, Color)>[];
    for (var i = 0; i < after.length; i += 4) {
      if (before[i] != after[i] ||
          before[i + 1] != after[i + 1] ||
          before[i + 2] != after[i + 2] ||
          before[i + 3] != after[i + 3]) {
        final p = i ~/ 4;
        changed.add((
          p % width,
          p ~/ width,
          Color.fromARGB(after[i + 3], after[i], after[i + 1], after[i + 2]),
        ));
      }
    }
    return (changed: changed, moved: moved);
  }

  bool near(Color a, Color b) =>
      ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 12;

  for (final look in Look.values) {
    for (final brightness in Brightness.values) {
      for (final c in focusCases) {
        final variant = '${look.name}, ${brightness.name}';
        testWidgets('${c.name} ($variant): focused, the ring is inside in '
            '${c.honey ? 'navy' : 'cobalt'} and nothing moves', (tester) async {
          appLook = look;
          final t = SnacklistColors.of(brightness);
          await pumpFocusCase(tester, brightness, c);
          final bounds = c.bounds(tester);
          final result = await focus(
            tester,
            c,
            FocusHighlightStrategy.alwaysTraditional,
          );
          expect(result.moved, isFalse, reason: 'focus moved a control');
          final colour = c.honey ? t.onHoney : t.accent;
          final inColour = result.changed.where((p) => near(p.$3, colour));
          // At least a 3 px band along one long side.
          expect(inColour.length, greaterThan(3 * bounds.width ~/ 2));
          final outside = result.changed.where(
            (p) =>
                p.$1 < bounds.left.floor() ||
                p.$1 >= bounds.right.ceil() ||
                p.$2 < bounds.top.floor() ||
                p.$2 >= bounds.bottom.ceil(),
          );
          expect(outside, isEmpty, reason: 'pixels changed past $bounds');
          if (c.inkWell) {
            // A ring, not the ink's focus fill over the whole face.
            expect(
              result.changed.length,
              lessThan(bounds.width * bounds.height / 2),
            );
          }
        });

        if (c.inkWell) {
          testWidgets('${c.name} ($variant): focus without a key shows no '
              'ring', (tester) async {
            appLook = look;
            await pumpFocusCase(tester, brightness, c);
            final result = await focus(
              tester,
              c,
              FocusHighlightStrategy.alwaysTouch,
            );
            expect(result.changed, isEmpty);
            expect(result.moved, isFalse);
          });
        }
      }
    }
  }

  testWidgets('a focused list row shows the ring once a key is pressed', (
    tester,
  ) async {
    final row = focusCases.singleWhere((c) => c.name == 'list row');
    await pumpFocusCase(tester, Brightness.light, row);
    await focus(tester, row, FocusHighlightStrategy.alwaysTouch);
    final before = await shoot(tester);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpAndSettle();
    expect(await shoot(tester), isNot(before));
  });

  testWidgets('a picked option keeps its navy contour while unfocused', (
    tester,
  ) async {
    final option = focusCases.singleWhere((c) => c.name == 'picked option');
    await pumpFocusCase(tester, Brightness.light, option);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(OptionChip),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      (material.shape! as OutlinedBorder).side,
      BorderSide(color: SnacklistColors.light.edge, width: HlBorder.width),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('a pill shows no ring while its delete button has focus '
        '(${brightness.name})', (tester) async {
      final t = SnacklistColors.of(brightness);
      final pill = (
        name: 'pill with a delete button',
        build: () => SizedBox(
          width: 300,
          child: HexPill(
            onTap: () {},
            child: Row(
              children: [
                const Expanded(child: PillTitle('Bäcker')),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Löschen',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
        node: (WidgetTester tester) =>
            Focus.of(tester.element(find.text('Bäcker'))),
        bounds: (WidgetTester tester) => tester.getRect(
          find
              .descendant(
                of: find.byType(HexPill),
                matching: find.byType(Material),
              )
              .first,
        ),
        honey: false,
        inkWell: true,
      );
      await pumpFocusCase(tester, brightness, pill);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      pill.node(tester).requestFocus();
      await tester.pumpAndSettle();
      int ringPixels(Uint8List image, Rect outside) {
        final width = tester.view.physicalSize.width.toInt();
        final bounds = pill.bounds(tester);
        var count = 0;
        for (var i = 0; i < image.length; i += 4) {
          final p = i ~/ 4;
          final at = Offset((p % width) + 0.5, (p ~/ width) + 0.5);
          if (!bounds.contains(at) || outside.contains(at)) {
            continue;
          }
          if (near(
            Color.fromARGB(image[i + 3], image[i], image[i + 1], image[i + 2]),
            t.accent,
          )) {
            count++;
          }
        }
        return count;
      }

      final button = tester.getRect(find.byType(IconButton));
      expect(
        ringPixels(await shoot(tester), button),
        greaterThan(100),
        reason: 'the focused pill shows its ring',
      );
      Focus.of(tester.element(find.byIcon(Icons.delete_outline)))
          .requestFocus();
      await tester.pumpAndSettle();
      expect(
        ringPixels(await shoot(tester), button),
        0,
        reason: 'only the delete button shows focus, not the pill around it',
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('a tile shows no ring while its menu button has focus '
        '(${brightness.name})', (tester) async {
      final t = SnacklistColors.of(brightness);
      FocusCase tile({required bool ring}) {
        final listTile = ListTile(
          title: const Text('Wocheneinkauf'),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mehr',
            onPressed: () {},
          ),
          onTap: () {},
        );
        return (
          name: ring ? 'tile with a menu button' : 'bare tile',
          build: () => SizedBox(
            width: 300,
            child: ring ? FocusRingTile(child: listTile) : listTile,
          ),
          node: (tester) =>
              Focus.of(tester.element(find.text('Wocheneinkauf'))),
          bounds: (tester) => tester.getRect(find.byType(ListTile)),
          honey: false,
          inkWell: true,
        );
      }

      int ringPixels(Uint8List image, Rect bounds) {
        final width = tester.view.physicalSize.width.toInt();
        var count = 0;
        for (var i = 0; i < image.length; i += 4) {
          final p = i ~/ 4;
          final at = Offset((p % width) + 0.5, (p ~/ width) + 0.5);
          if (bounds.contains(at) &&
              near(
                Color.fromARGB(
                  image[i + 3],
                  image[i],
                  image[i + 1],
                  image[i + 2],
                ),
                t.accent,
              )) {
            count++;
          }
        }
        return count;
      }

      Future<void> focusButton() async {
        Focus.of(tester.element(find.byIcon(Icons.more_vert))).requestFocus();
        await tester.pumpAndSettle();
      }

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      // The button's own ring, in a tile that draws none.
      final bare = tile(ring: false);
      await pumpFocusCase(tester, brightness, bare);
      await focusButton();
      final buttonOnly = ringPixels(await shoot(tester), bare.bounds(tester));
      expect(buttonOnly, greaterThan(0), reason: 'the button shows its ring');

      final ringed = tile(ring: true);
      await pumpFocusCase(tester, brightness, ringed);
      ringed.node(tester).requestFocus();
      await tester.pumpAndSettle();
      expect(
        ringPixels(await shoot(tester), ringed.bounds(tester)),
        greaterThan(buttonOnly + 300),
        reason: 'the focused tile shows its ring',
      );
      await focusButton();
      expect(
        ringPixels(await shoot(tester), ringed.bounds(tester)),
        // The bare tile's grey fill shifts a few edge pixels of the ring.
        closeTo(buttonOnly, 20),
        reason: 'only the menu button shows focus, not the tile around it',
      );
    });
  }

  testWidgets('a tile in a rounded group shows one unbroken ring along the '
      "card's corners", (tester) async {
    const t = SnacklistColors.light;
    final tile = focusCases.singleWhere((c) => c.name == 'tile in a group');
    await pumpFocusCase(tester, Brightness.light, tile);
    final result = await focus(
      tester,
      tile,
      FocusHighlightStrategy.alwaysTraditional,
    );
    final ring = {
      for (final p in result.changed)
        if (near(p.$3, t.accent)) (p.$1, p.$2),
    };
    expect(ring, isNotEmpty);
    // One piece, 8-connected: a rectangle cut by the rounded clip falls
    // apart into its four sides.
    final seen = <(int, int)>{ring.first};
    final todo = [ring.first];
    while (todo.isNotEmpty) {
      final (x, y) = todo.removeLast();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final next = (x + dx, y + dy);
          if (ring.contains(next) && seen.add(next)) {
            todo.add(next);
          }
        }
      }
    }
    expect(seen.length, ring.length, reason: 'the ring is in pieces');
  });
}
