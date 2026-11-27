import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The 6b check box for opt-ins: a pointy-top hex like the site's `.hxp`
/// check boxes, 26 px tall, with the 2 px contour. Unchecked it is a raised
/// face on the navy contour; checked it turns lemon, the colour of every
/// picked control (switch, radio), and a navy check draws itself in
/// [HlDuration.short] (at once with reduced motion). The list's mint is for
/// a ticked item, not for a choice.
///
/// Built on [ToggleableStateMixin] like Material's check box: keyboard
/// activation, focus, hover and the checked semantics come from Flutter. Its
/// box is [HlSize.target] square. Under [Look.soft] the hex is a rounded
/// square as wide as the hex.
class const HexCheckbox({
  required final bool value,
  required final ValueChanged<bool>? onChanged,
  final bool autofocus = false,
  super.key,
}) extends StatefulWidget {
  /// The hex itself, pointy-top: [height] tall and `0.866 * height` wide.
  static const height = 26.0;

  @override
  State<HexCheckbox> createState() => _HexCheckboxState();
}

class _HexCheckboxState()
    extends State<HexCheckbox>
    with TickerProviderStateMixin, ToggleableStateMixin {
  @override
  ValueChanged<bool?>? get onChanged => switch (widget.onChanged) {
    final changed? => (on) => changed(on!),
    null => null,
  };

  @override
  bool? get value => widget.value;

  @override
  bool get tristate => false;

  @override
  void didUpdateWidget(HexCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      animateToValue();
    }
  }

  @override
  Widget build(BuildContext context) {
    positionController.duration = hlMotion(context, HlDuration.short);
    reactionController.duration = hlMotion(context, HlDuration.press);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final enabled = isInteractive;
    return Semantics(
      checked: widget.value,
      child: buildToggleable(
        autofocus: widget.autofocus,
        mouseCursor: WidgetStateMouseCursor.clickable,
        size: const Size.square(HlSize.target),
        painter: _HexCheckboxPainter(
          checked: position,
          face: t.surfaceRaised,
          contour: enabled ? t.border : t.divider,
          checkedFace: enabled ? t.honey : t.honeySoft,
          checkedContour: enabled ? t.edge : t.divider,
          check: enabled ? t.onHoney : t.textMuted,
          focus: states.contains(WidgetState.focused) ? t : null,
        ),
      ),
    );
  }
}

class _HexCheckboxPainter({
  required final Animation<double> checked,
  required final Color face,
  required final Color contour,
  required final Color checkedFace,
  required final Color checkedContour,
  required final Color check,

  /// The colours to draw the focus ring from; null when not focused.
  required final SnacklistColors? focus,
}) extends CustomPainter {
  this : super(repaint: checked);

  static const _shape = HexBorder(orientation: HexOrientation.pointyTop);

  @override
  void paint(Canvas canvas, Size size) {
    const height = HexCheckbox.height;
    final hex = Alignment.center.inscribe(
      softLook
          ? const Size.square(height * 0.866)
          : const Size(height * 0.866, height),
      Offset.zero & size,
    );
    final p = checked.value;
    final focus = switch (this.focus) {
      final t? => focusRingColor(t, honey: p),
      null => null,
    };
    canvas
      ..drawPath(_shape.pathFor(hex), Paint()..color = face)
      ..drawPath(
        _shape.pathFor(hex),
        Paint()..color = checkedFace.withValues(alpha: checkedFace.a * p),
      )
      ..drawPath(
        _shape.pathFor(hex, outset: -HlBorder.width / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = HlBorder.width
          ..color = focus ?? Color.lerp(contour, checkedContour, p)!,
      );
    if (focus != null) {
      paintFocusRing(
        canvas,
        (outset) => _shape.pathFor(hex, outset: outset),
        focus,
        contour: HlBorder.width,
      );
    }
    if (p > 0) {
      final tick = Path()
        ..moveTo(hex.left + hex.width * 0.28, hex.top + hex.height * 0.52)
        ..lineTo(hex.left + hex.width * 0.44, hex.top + hex.height * 0.66)
        ..lineTo(hex.left + hex.width * 0.74, hex.top + hex.height * 0.36);
      final metric = tick.computeMetrics().single;
      canvas.drawPath(
        metric.extractPath(0, metric.length * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check,
      );
    }
  }

  @override
  bool shouldRepaint(_HexCheckboxPainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.contour != contour ||
      oldDelegate.checkedFace != checkedFace ||
      oldDelegate.checkedContour != checkedContour ||
      oldDelegate.check != check ||
      oldDelegate.focus != focus;
}

/// A list row with a [HexCheckbox] at its start, as [CheckboxListTile] has: a
/// tap anywhere on the row flips it, and the row reads as one check box with
/// the title and subtitle as its label. Without [onChanged] the row and the
/// box are disabled.
class const HexCheckboxListTile({
  required final Widget title,
  required final bool value,
  required final ValueChanged<bool>? onChanged,
  final Widget? subtitle,
  final EdgeInsetsGeometry? contentPadding,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: FocusRingTile(
      child: ListTile(
        contentPadding: contentPadding,
        // The row takes focus and taps; the box only shows the value.
        leading: ExcludeFocus(
          child: HexCheckbox(value: value, onChanged: onChanged),
        ),
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        onTap: switch (onChanged) {
          final changed? => () => changed(!value),
          null => null,
        },
      ),
    ),
  );
}
