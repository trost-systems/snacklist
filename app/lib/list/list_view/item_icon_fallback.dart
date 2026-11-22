import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The icon of an item without a known emoji (job 147): one quiet honeycomb
/// cell, never the category's emoji, which named the wrong thing
/// ("Geschenkkarte" showed 🧽).
///
/// A pointy-top hex [size] tall on a soft face with the thin navy contour.
/// The face and the thin line keep it apart from the unticked hex check box
/// (a raised face, the 2 px contour, 26 px). It is [size] square, the font
/// size of the emoji it stands in for, and sits in that emoji's line
/// (`ItemIcon`), so it shares the emoji's centre line and optical size
/// (Noto's ink is about 1.1 times the font size, the hex's 1.0 with a
/// filled face). Decorative: screen readers skip it.
///
/// Under [Look.soft] it is RD1's placeholder: a square as wide as the cell
/// on the same face, rounded with [HlSoft.xs], without the contour.
class const ItemIconFallback({required final double size, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CellPainter(
            height: size,
            face: t.surfaceEdge,
            contour: t.border,
          ),
        ),
      ),
    );
  }
}

class const _CellPainter({
  required final double height,
  required final Color face,
  required final Color contour,
}) extends CustomPainter {
  static const _shape = HexBorder(orientation: HexOrientation.pointyTop);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: height * 0.866,
      height: softLook ? height * 0.866 : height,
    );
    if (softLook) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, const Radius.circular(HlSoft.xs)),
        Paint()..color = face,
      );
      return;
    }
    canvas
      ..drawPath(_shape.pathFor(cell), Paint()..color = face)
      ..drawPath(
        _shape.pathFor(cell, outset: -HlBorder.widthThin / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = HlBorder.widthThin
          ..color = contour,
      );
  }

  @override
  bool shouldRepaint(_CellPainter oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.face != face ||
      oldDelegate.contour != contour;
}
