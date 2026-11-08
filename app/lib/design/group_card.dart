import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// A section's rows in an inset group (More, Einstellungen): the 2 px
/// contour, the small sticker shadow, hairlines between the rows.
class const HlGroup({
  required final List<Widget> children,
  final double top = HlSpace.s5,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: EdgeInsets.fromLTRB(HlSpace.s4, top, HlSpace.s4, 0),
      child: HlSticker(
        depth: StickerDepth.s,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HlRadius.m - HlBorder.width),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 60,
                      // Ends where the trailing icons do, clear of the
                      // card's edge.
                      endIndent: HlSpace.s3,
                      color: t.divider,
                    ),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A group row's leading icon in a small pointy hexagon. Glyph and contour
/// share the border ink, so the outline glyphs read as line art in both
/// modes (in dark, the bright text ink bled them into filled shapes).
class const HlRowHex(
  final IconData icon, {
  required final Color face,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return PointyHex(
      face: face,
      contour: t.border,
      size: 34,
      child: Icon(icon, size: 18, color: t.border),
    );
  }
}
