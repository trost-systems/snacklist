import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// How far a sticker stands off the page: its hard shadow's depth.
enum StickerDepth() {
  /// On the page: the contour without a shadow, for a surface that is not
  /// pressed as a whole (a hint card, job 168b).
  flat,
  s,
  m,
  l,
}

/// The site's `.sticker`: a raised surface with the 2 px navy contour and a
/// hard shadow, the sticker shadow in light and the night shadow in dark.
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
  /// The shadow of [depth] in [brightness].
  static List<BoxShadow> shadow(Brightness brightness, StickerDepth depth) =>
      switch ((brightness, depth)) {
        (_, StickerDepth.flat) => const [],
        (Brightness.light, StickerDepth.s) => HlShadow.stickerS,
        (Brightness.light, StickerDepth.m) => HlShadow.sticker,
        (Brightness.light, StickerDepth.l) => HlShadow.stickerL,
        (Brightness.dark, StickerDepth.s) => HlShadow.nightS,
        (Brightness.dark, StickerDepth.m) => HlShadow.night,
        (Brightness.dark, StickerDepth.l) => HlShadow.nightL,
      };

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
