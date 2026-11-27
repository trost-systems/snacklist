import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// The 6b switch: a horizontal hex track with a 2 px contour and a hex thumb
/// nested in it, its slanted sides parallel to the track's. Off is a sunken
/// track with a raised thumb on the left; on is a lemon track with a navy
/// thumb on the right. The thumb travels in [HlDuration.medium] on the
/// standard curve (no travel with reduced motion) and stretches towards
/// where it goes while pressed.
///
/// Built on [ToggleableStateMixin] like Material's switch: keyboard
/// activation, focus, hover and the switch semantics (toggled state) come
/// from Flutter. Its box is [HlSize.target] tall.
class const HexSwitch({
  required final bool value,
  required final ValueChanged<bool>? onChanged,
  final bool autofocus = false,
  super.key,
}) extends StatefulWidget {
  /// The track, in a box of [size].
  static const track = Size(56, 30);

  /// The box the switch takes: the 48 dp target around the track.
  static const size = Size(68, HlSize.target);

  @override
  State<HexSwitch> createState() => _HexSwitchState();
}

class _HexSwitchState()
    extends State<HexSwitch>
    with TickerProviderStateMixin, ToggleableStateMixin {
  late final _travel = CurvedAnimation(
    parent: positionController,
    curve: HlEasing.standard,
    reverseCurve: HlEasing.standard.flipped,
  );

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
  void didUpdateWidget(HexSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      animateToValue();
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    positionController.duration = hlMotion(context, HlDuration.medium);
    reactionController.duration = hlMotion(context, HlDuration.press);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Semantics(
      toggled: widget.value,
      child: buildToggleable(
        autofocus: widget.autofocus,
        mouseCursor: WidgetStateMouseCursor.clickable,
        size: HexSwitch.size,
        painter: _HexSwitchPainter(
          travel: _travel,
          press: reaction,
          off: _HexSwitchColors.off(t, enabled: isInteractive),
          on: _HexSwitchColors.on(t, enabled: isInteractive),
          focus: states.contains(WidgetState.focused) ? t : null,
        ),
      ),
    );
  }
}

/// The switch's colours at one end of its travel.
@immutable
final class const _HexSwitchColors({
  required final Color track,
  required final Color contour,
  required final Color thumb,
  required final Color thumbContour,
}) {
  /// A sunken track with a raised thumb; disabled, the contours step back.
  factory off(SnacklistColors t, {required bool enabled}) => _HexSwitchColors(
    track: t.surfaceSunken,
    contour: enabled ? t.border : t.divider,
    thumb: t.surfaceRaised,
    thumbContour: enabled ? t.border : t.divider,
  );

  /// A lemon track with a navy thumb; disabled, pale lemon and a muted
  /// thumb, so the value still reads.
  factory on(SnacklistColors t, {required bool enabled}) => _HexSwitchColors(
    track: enabled ? t.honey : t.honeySoft,
    contour: enabled ? t.edge : t.divider,
    thumb: enabled ? t.onHoney : t.textMuted,
    thumbContour: enabled ? t.onHoney : t.textMuted,
  );

  factory lerp(_HexSwitchColors a, _HexSwitchColors b, double t) =>
      _HexSwitchColors(
        track: Color.lerp(a.track, b.track, t)!,
        contour: Color.lerp(a.contour, b.contour, t)!,
        thumb: Color.lerp(a.thumb, b.thumb, t)!,
        thumbContour: Color.lerp(a.thumbContour, b.thumbContour, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is _HexSwitchColors &&
      other.track == track &&
      other.contour == contour &&
      other.thumb == thumb &&
      other.thumbContour == thumbContour;

  @override
  int get hashCode => Object.hash(track, contour, thumb, thumbContour);
}

class _HexSwitchPainter({
  required final Animation<double> travel,
  required final Animation<double> press,
  required final _HexSwitchColors off,
  required final _HexSwitchColors on,

  /// The colours to draw the focus ring from; null when not focused.
  required final SnacklistColors? focus,
}) extends CustomPainter {
  this : super(repaint: Listenable.merge([travel, press]));

  static const _shape = HexBorder();

  /// Between the track's and the thumb's outlines: the contour and 2 px air.
  static const _gap = HlBorder.width + 2;

  /// How much wider the thumb gets while pressed.
  static const _stretch = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Alignment.center.inscribe(
      HexSwitch.track,
      Offset.zero & size,
    );
    final p = travel.value;
    final colors = _HexSwitchColors.lerp(off, on, p);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = HlBorder.width
      ..color = color;
    // Strokes sit inside the shape so the contour never grows the control.
    const inset = -HlBorder.width / 2;

    final focus = switch (this.focus) {
      final t? => focusRingColor(t, honey: p),
      null => null,
    };
    canvas
      ..drawPath(_shape.pathFor(track), Paint()..color = colors.track)
      ..drawPath(
        _shape.pathFor(track, outset: inset),
        stroke(focus ?? colors.contour),
      );
    if (focus != null) {
      paintFocusRing(
        canvas,
        (outset) => _shape.pathFor(track, outset: outset),
        focus,
        contour: HlBorder.width,
      );
    }

    // A thumb whose ends sit this far in from the track's has its sides
    // [_gap] from the track's (see [HexBorder.alongFor]).
    final along = HexBorder.alongFor(_gap);
    final height = track.height - 2 * _gap;
    final width = height * (2 * HlHex.tip + 0.5) + _stretch * press.value;
    final left = track.left + along;
    final right = track.right - along - width;
    final thumb = Rect.fromLTWH(
      left + (right - left) * p,
      track.top + _gap,
      width,
      height,
    );
    canvas
      ..drawPath(_shape.pathFor(thumb), Paint()..color = colors.thumb)
      ..drawPath(
        _shape.pathFor(thumb, outset: inset),
        stroke(colors.thumbContour),
      );
  }

  @override
  bool shouldRepaint(_HexSwitchPainter oldDelegate) =>
      oldDelegate.off != off ||
      oldDelegate.on != on ||
      oldDelegate.focus != focus;
}

/// A list row with a [HexSwitch] at its end, as [SwitchListTile] has: a tap
/// anywhere on the row flips it, and the row reads as one switch with the
/// title and subtitle as its label. Without [onChanged] the row and the
/// switch are disabled.
class const HexSwitchTile({
  required final Widget title,
  required final bool value,
  required final ValueChanged<bool>? onChanged,
  final Widget? subtitle,
  final Widget? leading,
  final bool isThreeLine = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      minTileHeight: 56,
      leading: leading,
      title: title,
      subtitle: subtitle,
      isThreeLine: isThreeLine,
      enabled: onChanged != null,
      // The row takes focus and taps; the switch only shows the value.
      trailing: ExcludeFocus(
        child: HexSwitch(value: value, onChanged: onChanged),
      ),
      onTap: switch (onChanged) {
        final changed? => () => changed(!value),
        null => null,
      },
    ),
  );
}
