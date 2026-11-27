import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The 6b radio button: a horizontal hex with a 2 px contour, as the check
/// boxes are. Picked, it turns lemon and a navy hex dot, parallel to its
/// outline, grows in its middle in [HlDuration.short] (at once with reduced
/// motion). One of a [RadioGroup] above it, like Material's [Radio]: the
/// group, keyboard, focus and the radio semantics come from [RawRadio].
/// Under [Look.soft] the hex and its dot are circles, the outline as wide
/// as the hex is tall.
class const HexRadio<T>({
  required final T value,
  final bool enabled = true,
  super.key,
}) extends StatefulWidget {
  /// The hex itself; its box is [HlSize.target] square.
  static const hex = Size(24, 20);

  @override
  State<HexRadio<T>> createState() => _HexRadioState<T>();
}

class _HexRadioState<T>() extends State<HexRadio<T>> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = RadioGroup.maybeOf<T>(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final enabled = widget.enabled && registry != null;
    return RawRadio<T>(
      value: widget.value,
      mouseCursor: WidgetStateMouseCursor.clickable,
      toggleable: false,
      focusNode: _focus,
      autofocus: false,
      groupRegistry: registry,
      enabled: enabled,
      builder: (context, state) {
        state.positionController.duration = hlMotion(context, HlDuration.short);
        return CustomPaint(
          size: const Size.square(HlSize.target),
          painter: _HexRadioPainter(
            picked: state.position,
            contour: enabled ? t.border : t.divider,
            pickedFill: enabled ? t.honey : t.honeySoft,
            pickedContour: enabled ? t.edge : t.divider,
            dot: enabled ? t.onHoney : t.textMuted,
            focus: state.states.contains(WidgetState.focused) ? t : null,
          ),
        );
      },
    );
  }
}

class _HexRadioPainter({
  required final Animation<double> picked,
  required final Color contour,
  required final Color pickedFill,
  required final Color pickedContour,
  required final Color dot,

  /// The colours to draw the focus ring from; null when not focused.
  required final SnacklistColors? focus,
}) extends CustomPainter {
  this : super(repaint: picked);

  static const _shape = HexBorder();

  /// From the outline to the dot: the contour and 3 px of lemon.
  static const _gap = HlBorder.width + 3;

  /// The outline of [hex] moved out by [outset]: the hexagon, or under the
  /// soft look the circle in its middle.
  static Path _outline(Rect hex, {double outset = 0}) => softLook
      ? (Path()..addOval(
          Rect.fromCircle(
            center: hex.center,
            radius: hex.shortestSide / 2 + outset,
          ),
        ))
      : _shape.pathFor(hex, outset: outset);

  @override
  void paint(Canvas canvas, Size size) {
    final hex = Alignment.center.inscribe(HexRadio.hex, Offset.zero & size);
    final p = picked.value;
    final focus = switch (this.focus) {
      final t? => focusRingColor(t, honey: p),
      null => null,
    };
    canvas
      ..drawPath(
        _outline(hex),
        Paint()..color = pickedFill.withValues(alpha: pickedFill.a * p),
      )
      ..drawPath(
        _outline(hex, outset: -HlBorder.width / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = HlBorder.width
          ..color = focus ?? Color.lerp(contour, pickedContour, p)!,
      );
    if (focus != null) {
      paintFocusRing(
        canvas,
        (outset) => _outline(hex, outset: outset),
        focus,
        contour: HlBorder.width,
      );
    }
    if (p > 0) {
      final center = hex.center;
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..scale(p)
        ..translate(-center.dx, -center.dy)
        ..drawPath(_outline(hex, outset: -_gap), Paint()..color = dot)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_HexRadioPainter oldDelegate) =>
      oldDelegate.contour != contour ||
      oldDelegate.pickedFill != pickedFill ||
      oldDelegate.pickedContour != pickedContour ||
      oldDelegate.dot != dot ||
      oldDelegate.focus != focus;
}

/// A list row with a [HexRadio] at its start, as [RadioListTile] has: a tap
/// anywhere on the row picks [value] in the [RadioGroup] above, and the row
/// reads as one radio button with the title and subtitle as its label.
class const HexRadioTile<T>({
  required final T value,
  required final Widget title,
  final Widget? subtitle,
  final bool enabled = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: FocusRingTile(
      child: ListTile(
        // The row takes focus and taps; the radio only shows the pick.
        leading: ExcludeFocus(
          child: HexRadio<T>(value: value, enabled: enabled),
        ),
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        onTap: () => RadioGroup.maybeOf<T>(context)?.onChanged(value),
      ),
    ),
  );
}
