import 'dart:math' as math;

import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/widgets.dart';

enum HexOrientation() {
  /// Flat top and bottom, pointed left and right ends: buttons, chips, check
  /// boxes.
  horizontal,

  /// Pointed top and bottom: badges.
  pointyTop,
}

/// A hexagon with filleted corners (Hex Soft).
///
/// The tips are [HlHex.tip] times the height (the width for
/// [HexOrientation.pointyTop]) wide, so every corner is 120°. The corner
/// radius is [HlHex.cornerRadius] at [HlHex.referenceHeight] and scales with
/// the height, so a small chip is as round, relative to its size, as a large
/// button.
class const HexBorder({
  final HexOrientation orientation = HexOrientation.horizontal,
  super.side,
}) extends OutlinedBorder {
  /// The outline of [rect]'s hexagon moved outward by [outset] (inward when
  /// negative), as a true parallel curve: straight sides move by [outset]
  /// along their normal and every fillet radius grows by [outset]. Focus
  /// rings and strokes use it.
  Path pathFor(Rect rect, {double outset = 0}) {
    final across = orientation == HexOrientation.horizontal
        ? rect.height
        : rect.width;
    // Every vertex keeps its angle under an offset, so the outset hexagon has
    // the same tip ratio and only the rect grows: by [outset] across the flat
    // sides and by outset / sin(phi) towards the tips.
    final phi = math.atan(1 / (2 * HlHex.tip));
    final along = outset / math.sin(phi);
    final grown = orientation == HexOrientation.horizontal
        ? Rect.fromLTRB(
            rect.left - along,
            rect.top - outset,
            rect.right + along,
            rect.bottom + outset,
          )
        : Rect.fromLTRB(
            rect.left - outset,
            rect.top - along,
            rect.right + outset,
            rect.bottom + along,
          );
    final radius = math.max<double>(
      0,
      HlHex.cornerRadius * across / HlHex.referenceHeight + outset,
    );
    return _roundedPolygon(_vertices(grown), radius);
  }

  List<Offset> _vertices(Rect r) {
    switch (orientation) {
      case HexOrientation.horizontal:
        final t = math.min(HlHex.tip * r.height, r.width / 2);
        return [
          Offset(r.left, r.center.dy),
          Offset(r.left + t, r.top),
          Offset(r.right - t, r.top),
          Offset(r.right, r.center.dy),
          Offset(r.right - t, r.bottom),
          Offset(r.left + t, r.bottom),
        ];
      case HexOrientation.pointyTop:
        final t = math.min(HlHex.tip * r.width, r.height / 2);
        return [
          Offset(r.center.dx, r.top),
          Offset(r.right, r.top + t),
          Offset(r.right, r.bottom - t),
          Offset(r.center.dx, r.bottom),
          Offset(r.left, r.bottom - t),
          Offset(r.left, r.top + t),
        ];
    }
  }

  /// Vertices run clockwise on screen. Each corner becomes a circular arc
  /// tangent to both sides: the tangent points sit radius / tan(angle / 2)
  /// from the vertex, clamped to half the shorter side so neighbouring fillets
  /// never overlap. A hexagon no wider than its two tips has coincident
  /// vertices (it is a rhombus); they count once.
  static Path _roundedPolygon(List<Offset> vertices, double radius) {
    final path = Path();
    final v = [
      for (final (i, p) in vertices.indexed)
        if (p != vertices[(i - 1 + vertices.length) % vertices.length]) p,
    ];
    if (radius <= 0 || v.length < 3) {
      return path..addPolygon(v, true);
    }
    final n = v.length;
    for (var i = 0; i < n; i++) {
      final prev = v[(i - 1 + n) % n];
      final cur = v[i];
      final next = v[(i + 1) % n];
      final toPrev = prev - cur;
      final toNext = next - cur;
      final a = toPrev / toPrev.distance;
      final b = toNext / toNext.distance;
      final angle = math.acos((a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0));
      final halfTan = math.tan(angle / 2);
      final t = math.min(
        radius / halfTan,
        math.min(toPrev.distance, toNext.distance) / 2,
      );
      final r = t * halfTan;
      final start = cur + a * t;
      final end = cur + b * t;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.arcToPoint(end, radius: Radius.circular(r));
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      pathFor(rect, outset: -side.strokeInset);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) {
      return;
    }
    canvas.drawPath(
      pathFor(rect, outset: side.strokeOffset / 2),
      side.toPaint()..isAntiAlias = true,
    );
  }

  @override
  HexBorder copyWith({BorderSide? side}) =>
      HexBorder(orientation: orientation, side: side ?? this.side);

  @override
  HexBorder scale(double t) => copyWith(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is HexBorder && a.orientation == orientation
      ? copyWith(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is HexBorder && b.orientation == orientation
      ? copyWith(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is HexBorder &&
      other.orientation == orientation &&
      other.side == side;

  @override
  int get hashCode => Object.hash(orientation, side);
}

/// What a label keeps between its line box and a horizontal hex's outline:
/// the contour and [HlSpace.s1].
const hexLabelClearance = HlBorder.width + HlSpace.s1;

/// How far a line of [style] text, centred in a horizontal hex, has to start
/// in from the hex's tips to keep [hexLabelClearance] off its slanted sides.
/// Those reach [HlHex.tip] times the line's height in at the line's top and
/// bottom, whatever the hex's height, so the inset grows with the text
/// scale.
double hexLabelInset(TextStyle style, TextScaler scaler) {
  final line = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textScaler: scaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final height = line.height;
  line.dispose();
  return HlHex.tip * height + hexLabelClearance;
}
