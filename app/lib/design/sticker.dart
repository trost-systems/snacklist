import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

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
/// hard shadow in the contour's colour.
/// For cards, notes and anything lifted (a dragged row).
///
/// Under [Look.soft] only buttons stand off the page (job 368): a sticker
/// keeps its face and contour but has no shadow.
class const HlSticker({
  required final Widget child,
  final StickerDepth depth = StickerDepth.m,

  /// The corners; [cardRadius] when null.
  final BorderRadiusGeometry? borderRadius,

  /// The face; the raised surface when null.
  final Color? color,
  super.key,
}) extends StatelessWidget {
  /// The hard shadow of [depth] in [brightness]: the contour colour offset
  /// straight down, so the edge reads the same in light and dark (the
  /// night token's near-black edge vanished on the dark page).
  /// [StickerDepth.flat] has none, nor has any depth under [Look.soft].
  static List<BoxShadow> shadow(Brightness brightness, StickerDepth depth) {
    if (softLook) {
      return const [];
    }
    final light = switch (depth) {
      StickerDepth.flat => const <BoxShadow>[],
      StickerDepth.s => HlShadow.stickerS,
      StickerDepth.m => HlShadow.sticker,
      StickerDepth.l => HlShadow.stickerL,
    };
    if (brightness == Brightness.light) {
      return light;
    }
    final contour = SnacklistColors.dark.border;
    return [for (final s in light) BoxShadow(color: contour, offset: s.offset)];
  }

  /// A Material [elevation] for something lifted that is not a button: none
  /// under [Look.soft].
  static double elevation(double elevation) => softLook ? 0 : elevation;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        this.borderRadius ?? BorderRadius.all(Radius.circular(cardRadius));
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
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
