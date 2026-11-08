import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// How far a sticker stands off the page: its hard shadow's depth.
enum StickerDepth() {
  s,
  m,
  l,
}

/// The site's `.sticker`: a raised surface with the 2 px navy contour and a
/// hard shadow in the contour's colour.
/// For cards, notes and anything lifted (a dragged row).
class const HlSticker({
  required final Widget child,
  final StickerDepth depth = StickerDepth.m,
  final BorderRadiusGeometry borderRadius = const BorderRadius.all(
    Radius.circular(HlRadius.m),
  ),

  /// The face; the raised surface when null.
  final Color? color,
  super.key,
}) extends StatelessWidget {
  /// The hard shadow of [depth] in [brightness]: the contour colour offset
  /// straight down, so the edge reads the same in light and dark (the
  /// night token's near-black edge vanished on the dark page).
  static List<BoxShadow> shadow(Brightness brightness, StickerDepth depth) {
    final light = switch (depth) {
      StickerDepth.s => HlShadow.stickerS,
      StickerDepth.m => HlShadow.sticker,
      StickerDepth.l => HlShadow.stickerL,
    };
    if (brightness == Brightness.light) {
      return light;
    }
    final contour = HummlistColors.dark.border;
    return [for (final s in light) BoxShadow(color: contour, offset: s.offset)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = HummlistColors.of(theme.brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? t.surfaceRaised,
        borderRadius: borderRadius,
        border: Border.all(color: t.border, width: HlBorder.width),
        boxShadow: shadow(theme.brightness, depth),
      ),
      child: ClipRRect(
        borderRadius: borderRadius.subtract(
          const BorderRadius.all(Radius.circular(HlBorder.width)),
        ),
        child: child,
      ),
    );
  }
}
