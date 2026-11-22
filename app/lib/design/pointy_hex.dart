import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The site's `.hxp`: a pointy-top hexagon with a face and the 2 px contour,
/// its content centred. The add bar's "+" and the empty list's cart.
///
/// Under [Look.soft] the hexagon is a rounded square as wide as the
/// hexagon, centred in the same box, so nothing around it moves.
class const PointyHex({
  required final Color face,

  /// The contour; the navy edge when null.
  final Color? contour,

  /// The hexagon's height, tip to tip; it is `0.866` times as wide.
  final double size = 32,
  final Widget? child,
  super.key,
}) extends StatelessWidget {
  /// Width over height of a regular pointy-top hexagon.
  static const aspect = 0.866;

  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final width = size * aspect;
    final shape = Container(
      width: width,
      height: softLook ? width : size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: face,
        shape: HexBorder(
          orientation: HexOrientation.pointyTop,
          side: BorderSide(color: contour ?? t.edge, width: HlBorder.width),
        ),
      ),
      child: child,
    );
    if (!softLook) {
      return shape;
    }
    return SizedBox(
      width: width,
      height: size,
      child: Center(child: shape),
    );
  }
}
