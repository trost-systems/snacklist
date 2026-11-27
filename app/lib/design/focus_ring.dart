import 'dart:math' as math;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/rendering.dart' show RenderClipRRect;
import 'package:material_ui/material_ui.dart';

/// How far the outer focus ring reached past a control before FH1 (a 2 px
/// gap and the 3 px ring). The room it took stays where layout or a clip
/// counted on it (a field's helper row, a tactile button's clip), so
/// nothing unfocused moved when the ring went inside.
const outerRingReach = 5.0;

/// The focus colour (FH1, job 487): navy on a honey face, cobalt on any
/// other, in both themes. [honey] is how far the face has turned honey, for
/// a check box, switch or radio on its way between off and on.
Color focusRingColor(SnacklistColors t, {double honey = 0}) =>
    Color.lerp(t.accent, t.onHoney, honey)!;

/// Strokes the focus ring inside a control: [HlFocus.ringWidth] wide, from
/// the inner edge of its [contour] inward, so nothing reaches past the
/// control. [outline] is the control's outer outline moved out by its
/// argument (inward when negative). A caller that draws its own contour
/// draws it in [color] while focused, so contour and ring read as one band.
void paintFocusRing(
  Canvas canvas,
  Path Function(double outset) outline,
  Color color, {
  double contour = 0,
}) => canvas.drawPath(
  outline(-(contour + HlFocus.ringWidth / 2)),
  Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = HlFocus.ringWidth
    ..color = color,
);

/// Tab's focus request ([FocusTraversalPolicy.requestFocusCallback]): focuses
/// [node] and scrolls it into view whichever side it is on. Flutter's own
/// scrolls only down for Tab (`keepVisibleAtEnd`), so a Tab onto a control
/// above the view (the add sheet's first row after the clear key, the first
/// control of a scrolled page after the last) focused it out of sight.
void revealFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final context = node.context;
  if (context == null) {
    return;
  }
  // Each moves only when the node is past its edge, so one of them at most.
  for (final edge in [
    ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  ]) {
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: edge,
      duration: duration ?? Duration.zero,
      curve: curve ?? Curves.ease,
    );
  }
}

/// Whether a Material control in [states] shows its focus ring: when it has
/// focus and the user moves focus with keys, as an [InkWell] decides for its
/// focus highlight. A tap never shows it.
bool showsFocusRing(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) &&
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// [style] with the focus ring instead of the focus fill: the inset ring
/// in [color], over the button's own [contour] (0 for a text button). A
/// `styleFrom` with its own foreground brings its own fill, so a text button
/// that sets one passes its style through here too (navy on a honey face).
/// Unfocused, the shape keeps its own side.
ButtonStyle withFocusRing(
  ButtonStyle style,
  Color color, {
  double contour = 0,
}) => style.copyWith(
  overlayColor: WidgetStateProperty.resolveWith(
    (states) => _focusOnly(states)
        ? Colors.transparent
        : style.overlayColor?.resolve(states),
  ),
  side: WidgetStateBorderSide.resolveWith(
    (states) => showsFocusRing(states)
        ? BorderSide(color: color, width: contour + HlFocus.ringWidth)
        : style.side?.resolve(states),
  ),
);

/// Focused, and neither hovered nor pressed: the overlay would only be the
/// focus fill, which the ring replaces. Hover and press keep their ink.
bool _focusOnly(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) &&
    !states.contains(WidgetState.hovered) &&
    !states.contains(WidgetState.pressed);

/// The focus ring of a horizontal hex (a tab, a segment) painted over it:
/// the hex's [contour] (0 for a hex with none) in [color], then the ring
/// inside it. [inset] moves the hex in from the top and bottom of the
/// painted box.
class const HexFocusRingPainter(
  final Color color, {
  final double contour = 0,
  final double inset = 0,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hex = Rect.fromLTRB(0, inset, size.width, size.height - inset);
    Path outline(double outset) =>
        const HexBorder().pathFor(hex, outset: outset);
    if (contour > 0) {
      canvas.drawPath(
        outline(-contour / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = contour
          ..color = color,
      );
    }
    paintFocusRing(canvas, outline, color, contour: contour);
  }

  @override
  bool shouldRepaint(HexFocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.contour != contour ||
      oldDelegate.inset != inset;
}

/// A [HexBorder] whose side may carry the focus ring (a chip's): only the
/// first [contour] of the side's width counts as the border's room, so a
/// focused side, [contour] plus [HlFocus.ringWidth] wide, paints inward
/// over the face and never moves the label.
class const RingHexBorder({super.side, final double contour = 1})
    extends HexBorder {
  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.all(math.min(side.strokeInset, contour));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      pathFor(rect, outset: -math.min(side.strokeInset, contour));

  @override
  RingHexBorder copyWith({BorderSide? side}) =>
      RingHexBorder(side: side ?? this.side, contour: contour);

  @override
  RingHexBorder scale(double t) => copyWith(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is RingHexBorder
      ? copyWith(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is RingHexBorder
      ? copyWith(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is RingHexBorder && other.side == side && other.contour == contour;

  @override
  int get hashCode => Object.hash(side, contour);
}

/// Takes the grey focus fill off a chip: [RawChip]'s ink reads it from
/// [ThemeData.focusColor] and takes no colour of its own. The chip shows
/// focus with the inset ring of the theme's chip side instead.
class const FocusRingChip({required final Widget chip, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(focusColor: Colors.transparent),
    child: chip,
  );
}

/// An [InkWell] that shows keyboard focus as the inset ring instead of its
/// focus fill, when the fill would show: focused while the user moves focus
/// with keys. [outline] is the control's outline in its box, moved out by
/// the second argument; [contour] is the width of the control's own
/// contour, which [onRingChanged] lets the caller draw in the focus colour.
class const FocusRingInkWell({
  required final Path Function(Rect rect, double outset) outline,
  required final Widget child,
  final double contour = 0,

  /// The ring's colour; cobalt when null. Pass navy on a honey face.
  final Color? color,
  final ValueChanged<bool>? onRingChanged,
  final VoidCallback? onTap,
  final VoidCallback? onSecondaryTap,
  final FocusNode? focusNode,
  final ShapeBorder? customBorder,
  final InteractiveInkFeatureFactory? splashFactory,
  final Color? highlightColor,
  final bool excludeFromSemantics = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<FocusRingInkWell> createState() => _FocusRingInkWellState();
}

class _FocusRingInkWellState() extends State<FocusRingInkWell> {
  FocusNode? _own;

  /// The ink well's own node. Its ring shows only while this node has the
  /// primary focus: the ink well's `hasFocus` stays true while a control
  /// inside it (a pill's delete button) is focused, and two rings would
  /// leave a keyboard user guessing which one Enter presses.
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  var _ring = false;

  bool get _shows =>
      _node.hasPrimaryFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    _node.addListener(_update);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void didUpdateWidget(FocusRingInkWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.focusNode ?? _own;
    if (old != _node) {
      old?.removeListener(_update);
      _node.addListener(_update);
      _update();
    }
  }

  @override
  void dispose() {
    _node.removeListener(_update);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _own?.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) => _update();

  void _update() {
    final shows = _shows;
    if (shows == _ring || !mounted) {
      return;
    }
    setState(() => _ring = shows);
    widget.onRingChanged?.call(shows);
  }

  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return InkWell(
      onTap: widget.onTap,
      onSecondaryTap: widget.onSecondaryTap,
      focusNode: _node,
      customBorder: widget.customBorder,
      splashFactory: widget.splashFactory,
      highlightColor: widget.highlightColor,
      excludeFromSemantics: widget.excludeFromSemantics,
      focusColor: Colors.transparent,
      child: CustomPaint(
        foregroundPainter: _ring
            ? _InkWellRing(
                widget.outline,
                widget.color ?? focusRingColor(t),
                widget.contour,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

class const _InkWellRing(
  final Path Function(Rect rect, double outset) outline,
  final Color color,
  final double contour,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintFocusRing(
    canvas,
    (outset) => outline(Offset.zero & size, outset),
    color,
    contour: contour,
  );

  @override
  bool shouldRepaint(_InkWellRing oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.contour != contour ||
      oldDelegate.outline != outline;
}

/// A Material list tile ([ListTile], or a tile built on one:
/// [CheckboxListTile], [RadioListTile], [ExpansionTile]'s header) that shows
/// keyboard focus as the inset ring instead of its grey focus fill. The
/// tile's ink reads the fill from [ThemeData.focusColor], so this sets that
/// transparent below it, as [FocusRingChip] does for a chip.
///
/// The ring follows the tile's own focus node: the first one under this
/// widget. A control inside the tile (a trailing menu button) sits one
/// level deeper and shows its own focus while the tile shows none; a node
/// beside the tile's (an [ExpansionTile]'s rows) is not a tile's.
class const FocusRingTile({required final Widget child, super.key})
    extends StatefulWidget {
  @override
  State<FocusRingTile> createState() => _FocusRingTileState();
}

class _FocusRingTileState() extends State<FocusRingTile> {
  final _scope = FocusNode(debugLabel: 'FocusRingTile');

  /// The focused tile's box while it shows the ring, and the box it is
  /// painted in.
  (RenderBox, RenderBox)? _ring;

  @override
  void initState() {
    super.initState();
    FocusManager.instance
      ..addListener(_update)
      ..addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance
      ..removeListener(_update)
      ..removeHighlightModeListener(_onHighlightMode);
    _scope.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) => _update();

  void _update() {
    if (!mounted) {
      return;
    }
    final focused = FocusManager.instance.primaryFocus;
    final host = context.findRenderObject();
    final ring =
        focused != null &&
            host is RenderBox &&
            focused.parent == _scope &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional &&
            focused.context?.findAncestorWidgetOfExactType<ListTile>() != null
        ? switch (focused.context?.findRenderObject()) {
            final RenderBox tile => (tile, host),
            _ => null,
          }
        : null;
    if (ring != _ring) {
      setState(() => _ring = ring);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ring = _ring;
    return Focus(
      focusNode: _scope,
      canRequestFocus: false,
      skipTraversal: true,
      // A semantics node here would cover the tile on web and take its taps.
      includeSemantics: false,
      child: CustomPaint(
        foregroundPainter: ring == null
            ? null
            : _TileRing(
                ring.$1,
                ring.$2,
                focusRingColor(SnacklistColors.of(theme.brightness)),
              ),
        child: Theme(
          data: theme.copyWith(focusColor: Colors.transparent),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The ring inside [tile]'s box, painted by [host], a box that holds it:
/// all of it for a [ListTile], the top for an [ExpansionTile]'s header. In a
/// rounded clip (an `HlGroup` card) it follows the clip's corners too.
class const _TileRing(
  final RenderBox tile,
  final RenderBox host,
  final Color color,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (!tile.attached || !tile.hasSize || !host.attached) {
      return;
    }
    final box = tile.localToGlobal(Offset.zero, ancestor: host) & tile.size;
    final clip = _roundedClip();
    paintFocusRing(canvas, (outset) {
      final rect = Path()
        ..addRect(box.intersect(Offset.zero & size).inflate(outset));
      return switch (clip) {
        final rrect? => Path.combine(
          PathOperation.intersect,
          rect,
          Path()..addRRect(rrect.inflate(outset)),
        ),
        null => rect,
      };
    }, color);
  }

  /// The nearest rounded clip above [host], in [host]'s coordinates.
  RRect? _roundedClip() {
    var above = host.parent;
    while (above != null && above is! RenderClipRRect) {
      above = above.parent;
    }
    if (above is! RenderClipRRect || !above.hasSize) {
      return null;
    }
    final at = host.localToGlobal(Offset.zero, ancestor: above);
    final shape =
        above.clipper?.getClip(above.size) ??
        above.borderRadius
            .resolve(above.textDirection)
            .toRRect(Offset.zero & above.size);
    return shape.shift(-at);
  }

  @override
  bool shouldRepaint(_TileRing oldDelegate) =>
      oldDelegate.tile != tile ||
      oldDelegate.host != host ||
      oldDelegate.color != color;
}
