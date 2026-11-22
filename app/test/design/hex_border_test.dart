import 'dart:math' as math;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [path] is rounded at [rect]'s top-left corner with [radius]:
/// half a pixel inside the arc is in, half a pixel outside is out.
bool _roundedWith(Path path, Rect rect, double radius) {
  final centre = rect.topLeft + Offset(radius, radius);
  const diagonal = Offset(-math.sqrt1_2, -math.sqrt1_2);
  return path.contains(centre + diagonal * (radius - 0.5)) &&
      !path.contains(centre + diagonal * (radius + 0.5));
}

void main() {
  test('a hexagon no wider than its tips is a rhombus, not NaN', () {
    // A store badge squeezed by large text: 18.5 px wide, 53 px tall.
    const rect = Rect.fromLTWH(0, 0, 18.5, 53);
    for (final orientation in HexOrientation.values) {
      final bounds = HexBorder(
        orientation: orientation,
        side: const BorderSide(),
      ).pathFor(rect).getBounds();
      expect(bounds.isFinite, isTrue, reason: '$orientation');
      expect(bounds.width, greaterThan(0), reason: '$orientation');
    }
  });

  test('soft radii nest by size', () {
    expect(softRadius(20), HlSoft.xs);
    expect(softRadius(32), HlSoft.sm);
    expect(softRadius(48), HlSoft.md);
    expect(softRadius(56), HlSoft.md);
    expect(softRadius(64), HlSoft.lg);
  });

  group('under the soft look', () {
    setUp(() => appLook = Look.soft);
    tearDown(() => appLook = Look.hex);

    test('a hex is a rounded rectangle with the table radius', () {
      for (final orientation in HexOrientation.values) {
        for (final rect in const [
          Rect.fromLTWH(0, 0, 120, 48),
          Rect.fromLTWH(10, 10, 20, 26),
          Rect.fromLTWH(0, 0, 300, 64),
        ]) {
          final path = HexBorder(orientation: orientation).pathFor(rect);
          final radius = softRadius(rect.shortestSide);
          expect(path.getBounds(), rect, reason: '$orientation $rect');
          expect(
            _roundedWith(path, rect, radius),
            isTrue,
            reason: '$orientation $rect',
          );
          // Where a hexagon's slanted end leaves the corner empty.
          expect(
            path.contains(Offset(rect.left + 1, rect.center.dy - 6)),
            isTrue,
            reason: '$orientation $rect',
          );
        }
      }
    });

    test('an outset grows the rect and the radius alike', () {
      const rect = Rect.fromLTWH(0, 0, 120, 48);
      for (final outset in const [-1.0, 3.5]) {
        final path = const HexBorder().pathFor(rect, outset: outset);
        expect(path.getBounds(), rect.inflate(outset));
        expect(
          _roundedWith(path, rect.inflate(outset), HlSoft.md + outset),
          isTrue,
          reason: '$outset',
        );
      }
    });

    test('nested shapes move their ends by the outset', () {
      expect(HexBorder.alongFor(4), 4);
    });
  });

  test("a hexagon's ends move further than its sides", () {
    expect(
      HexBorder.alongFor(4),
      closeTo(4 / math.sin(math.atan(1 / (2 * HlHex.tip))), 1e-9),
    );
    expect(HexBorder.alongFor(4), greaterThan(4));
  });
}
