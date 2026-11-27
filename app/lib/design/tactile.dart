import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/hex_pill.dart' show HexPill;
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The one depth switch: true rests every pressable hex face on its edge
/// (the theme's buttons, the pages' add buttons, the store and category
/// chips, [HexPill] rows), false lays them all flat (Peter, job 148: one
/// depth style, 3D by default). The brand sign-in buttons keep their makers'
/// look either way.
const raisedFaces = true;

/// Colours of one tactile hex in one state.
@immutable
final class const TactileColors({
  required final Color face,
  required final Color contour,

  /// The solid edge the face rests on; null for a flat face.
  required final Color? edge,

  /// The keyboard focus ring and, while focused, the face's contour.
  required final Color focus,
}) {
  @override
  bool operator ==(Object other) =>
      other is TactileColors &&
      other.face == face &&
      other.contour == contour &&
      other.edge == edge &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(face, contour, edge, focus);
}

/// The 6b tactile look for a Material button: a hex face with a 2 px contour
/// resting on a hard edge [HlDepth.edge] tall. Hover lifts the face by
/// [HlDepth.lift], a press sinks it flush into the edge in
/// [HlDuration.press], and it springs back in [HlDuration.release] with the
/// bounce curve; with reduced motion it jumps. A disabled face sits flush.
///
/// Plug it into a [ButtonStyle] with [tactileButtonStyle]: the background
/// paints the face and the foreground moves the label with it, so the
/// button's ink, semantics, keys and tap target stay Material's.
class const TactileFace({
  required final Set<WidgetState> states,
  required final TactileColors colors,
  required final Widget? child,
  super.key,
}) extends StatefulWidget {
  /// How far the face of the enclosing tactile button has moved from rest:
  /// negative lifted, [HlDepth.press] sunk.
  static Animation<double>? offsetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FaceOffset>()?.notifier;

  @override
  State<TactileFace> createState() => _TactileFaceState();
}

class _TactileFaceState()
    extends State<TactileFace>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(
    vsync: this,
    value: _target,
  );

  double get _target {
    final states = widget.states;
    if (states.contains(WidgetState.disabled) ||
        states.contains(WidgetState.pressed)) {
      return HlDepth.press;
    }
    return states.contains(WidgetState.hovered) ? -HlDepth.lift : 0;
  }

  @override
  void didUpdateWidget(TactileFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _target;
    if (target == _offset.value) {
      return;
    }
    final sinking = target > _offset.value;
    final duration = hlMotion(
      context,
      sinking ? HlDuration.press : HlDuration.release,
    );
    if (duration == Duration.zero) {
      _offset.value = target;
      return;
    }
    _offset.animateTo(
      target,
      duration: duration,
      curve: sinking ? HlEasing.press : HlEasing.bounce,
    );
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FaceOffset(
    notifier: _offset,
    child: CustomPaint(
      painter: _TactilePainter(
        offset: _offset,
        colors: widget.colors,
        focused: widget.states.contains(WidgetState.focused),
      ),
      child: widget.child,
    ),
  );
}

class const _FaceOffset({
  required AnimationController super.notifier,
  required super.child,
}) extends InheritedNotifier<AnimationController>;

class _TactilePainter({
  required final Animation<double> offset,
  required final TactileColors colors,
  required final bool focused,
}) extends CustomPainter {
  this : super(repaint: offset);

  static const _shape = HexBorder();

  @override
  void paint(Canvas canvas, Size size) {
    final edge = raisedFaces ? colors.edge : null;
    final depth = edge == null ? 0.0 : HlDepth.edge;
    final rest = Rect.fromLTWH(0, 0, size.width, size.height - depth);
    Paint contour(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = HlBorder.width
      ..color = color;
    // Strokes sit inside the face so the contour never grows the control.
    const inset = -HlBorder.width / 2;
    if (edge != null) {
      final below = rest.shift(const Offset(0, HlDepth.edge));
      canvas
        ..drawPath(_shape.pathFor(below), Paint()..color = edge)
        ..drawPath(
          _shape.pathFor(below, outset: inset),
          contour(colors.contour),
        );
    }
    final face = rest.shift(Offset(0, edge == null ? 0 : offset.value));
    canvas
      ..drawPath(_shape.pathFor(face), Paint()..color = colors.face)
      ..drawPath(
        _shape.pathFor(face, outset: inset),
        contour(focused ? colors.focus : colors.contour),
      );
    if (focused) {
      paintFocusRing(
        canvas,
        (outset) => _shape.pathFor(face, outset: outset),
        colors.focus,
        contour: HlBorder.width,
      );
    }
  }

  @override
  bool shouldRepaint(_TactilePainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.focused != focused;
}

/// The label of a tactile button: centred on the face and moving with it.
/// A spinner in it (a button that is busy) takes the label's colour: the
/// theme's cobalt-light would sit on lemon in dark mode.
class const _TactileLabel({
  required final Widget? child,
  required final bool hasEdge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final offset = TactileFace.offsetOf(context);
    final child = ProgressIndicatorTheme(
      data: ProgressIndicatorTheme.of(context)
          .copyWith(color: DefaultTextStyle.of(context).style.color),
      child: this.child ?? const SizedBox.shrink(),
    );
    if (offset == null || !hasEdge) {
      return child;
    }
    return AnimatedBuilder(
      animation: offset,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, offset.value - HlDepth.edge / 2),
        child: child,
      ),
      child: child,
    );
  }
}

/// The tactile button's Material shape. A button with a background builder
/// clips to its shape, and the face's lift reaches past the button's box:
/// this shape is that box grown by [_room].
class const _RoomForFocus({super.side}) extends OutlinedBorder {
  static const _room = HlDepth.lift + outerRingReach;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect.inflate(_room));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  _RoomForFocus copyWith({BorderSide? side}) =>
      _RoomForFocus(side: side ?? this.side);

  @override
  _RoomForFocus scale(double t) => this;
}

/// Whether the button being built picked its own background colour without
/// a face of its own (the brand sign-in buttons): then it stays a plain
/// Material button in its own colours instead of a tactile face. A button
/// whose own style is a [tactileButtonStyle] keeps its face.
bool _ownsBackground(BuildContext context) => switch (context.widget) {
  ButtonStyleButton(:final style?) =>
    style.backgroundColor != null && style.backgroundBuilder == null,
  _ => false,
};

/// A [ButtonStyle] that draws the button as a [TactileFace] in [colors]
/// (resolved per state). The button's own background and elevation are off;
/// its ink still runs, under the opaque face.
ButtonStyle tactileButtonStyle({
  required TactileColors Function(Set<WidgetState> states) colors,
  required WidgetStateProperty<Color?> foreground,
  required TextStyle textStyle,
}) => ButtonStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  // The moving face is the feedback; ink would show around it.
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: foreground,
  iconColor: foreground,
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  side: const WidgetStatePropertyAll(BorderSide.none),
  shape: const WidgetStatePropertyAll(_RoomForFocus()),
  textStyle: WidgetStatePropertyAll(textStyle),
  minimumSize: const WidgetStatePropertyAll(Size(64, HlSize.target)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(
      horizontal: hexTextInset(HlSize.target),
      vertical: HlSpace.s2,
    ),
  ),
  backgroundBuilder: (context, states, child) => _ownsBackground(context)
      ? child ?? const SizedBox.shrink()
      : TactileFace(states: states, colors: colors(states), child: child),
  foregroundBuilder: (context, states, child) => _TactileLabel(
    hasEdge:
        raisedFaces && !_ownsBackground(context) && colors(states).edge != null,
    child: child,
  ),
);
