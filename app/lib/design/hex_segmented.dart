import 'dart:math' as math;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// One option of a [HexSegmented]: the [value] it picks, its [label] and
/// optionally an [icon] before it. [key] goes on the segment.
class const HexSegment<T>({
  required final T value,
  required final String label,
  final IconData? icon,
  final Key? key,
});

/// The 6b segmented control: all options at once in one horizontal hex track
/// with the 2 px contour, the picked one under a honey hex that slides to
/// the next pick in [HlDuration.medium] on the standard curve (it jumps with
/// reduced motion). One tap picks; nothing cycles.
///
/// Built on [RadioGroup] and [RawRadio] like `HexRadio`: each segment is a
/// radio button (checked, in a mutually exclusive group, 48 dp tall) with
/// its label, Space and Enter pick, the arrow keys move the pick and the
/// focused segment gets the focus ring. [label] names the group for screen
/// readers. Without [onChanged] the control is disabled.
class const HexSegmented<T>({
  required final List<HexSegment<T>> segments,
  required final T value,
  required final ValueChanged<T>? onChanged,
  final String? label,
  super.key,
}) extends StatelessWidget {
  /// Between the track's contour and the indicator's: the contour and 2 px.
  static const _gap = HlBorder.width + 2;
  static const _iconSize = 18.0;
  static const _iconGap = HlSpace.s2;

  @override
  Widget build(BuildContext context) {
    assert(segments.isNotEmpty, 'a segmented control needs options');
    final t = HummlistColors.of(Theme.of(context).brightness);
    final enabled = onChanged != null;
    final picked = segments.indexWhere((s) => s.value == value);
    // The indicator's slanted sides sit [_gap] from the track's.
    final along = _gap / math.sin(math.atan(1 / (2 * HlHex.tip)));
    final slide = hlMotion(context, HlDuration.medium);
    final scaler = MediaQuery.textScalerOf(context);
    // The picked weight, the widest a label gets.
    final style = DefaultTextStyle.of(context).style.merge(
      Theme.of(context).textTheme.labelLarge!
          .copyWith(fontWeight: FontWeight.w800),
    );
    final inset = hexLabelInset(style, scaler);
    double widthOf(HexSegment<T> segment) {
      final text = TextPainter(
        text: TextSpan(text: segment.label, style: style),
        textScaler: scaler,
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final width = text.width;
      text.dispose();
      return width + (segment.icon == null ? 0 : _iconSize + _iconGap);
    }

    final widest = segments.map(widthOf).reduce(math.max);
    return Semantics(
      container: true,
      label: label,
      child: RadioGroup<T>(
        groupValue: value,
        onChanged: (picked) {
          if (picked != null) {
            onChanged?.call(picked);
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: HlSize.target,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.surfaceSunken,
                      shape: HexBorder(
                        side: BorderSide(
                          color: enabled ? t.border : t.divider,
                          width: HlBorder.width,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: along,
                      vertical: _gap,
                    ),
                    child: AnimatedAlign(
                      duration: slide,
                      curve: HlEasing.standard,
                      alignment: Alignment(
                        segments.length == 1
                            ? 0
                            : -1 + 2 * picked / (segments.length - 1),
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / segments.length,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: enabled ? t.honey : t.honeySoft,
                            shape: HexBorder(
                              side: BorderSide(
                                color: enabled ? t.edge : t.divider,
                                width: HlBorder.width,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: along),
                    child: Row(
                      children: [
                        for (final segment in segments)
                          Expanded(
                            child: _Segment<T>(
                              key: segment.key,
                              segment: segment,
                              picked: segment.value == value,
                              enabled: enabled,
                              slide: slide,
                              inset: inset,
                              icon:
                                  widest + 2 * inset <=
                                  (constraints.maxWidth - 2 * along) /
                                      segments.length,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _Segment<T>({
  required final HexSegment<T> segment,
  required final bool picked,
  required final bool enabled,
  required final Duration slide,

  /// Room between the label and the segment's tips.
  required final double inset,

  /// Whether the segment shows its icon: all of them or none.
  required final bool icon,
  super.key,
}) extends StatefulWidget {
  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T>() extends State<_Segment<T>> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    final registry = RadioGroup.maybeOf<T>(context);
    final (segment, picked, enabled, slide) = (
      widget.segment,
      widget.picked,
      widget.enabled,
      widget.slide,
    );
    final color = !enabled
        ? t.textMuted
        : picked
        ? t.onHoney
        : t.text;
    return MergeSemantics(
      child: RawRadio<T>(
        value: segment.value,
        mouseCursor: WidgetStateMouseCursor.clickable,
        toggleable: false,
        focusNode: _focus,
        autofocus: false,
        groupRegistry: registry,
        enabled: enabled && registry != null,
        builder: (context, state) {
          state.positionController.duration = Duration.zero;
          state.reactionController.duration = hlMotion(
            context,
            HlDuration.press,
          );
          final focused = state.states.contains(WidgetState.focused);
          return CustomPaint(
            foregroundPainter: focused ? _Ring(t.accent) : null,
            child: Center(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: slide,
                builder: (context, color, _) => IconTheme.merge(
                  data: IconThemeData(
                    color: color,
                    size: HexSegmented._iconSize,
                  ),
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: color,
                      fontWeight: picked ? FontWeight.w800 : FontWeight.w600,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: widget.inset),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: HexSegmented._iconGap,
                        children: [
                          if (segment.icon case final icon? when widget.icon)
                            Icon(icon),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(segment.label, maxLines: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The focus ring: round the indicator's hex, [HlFocus.ringGap] off it, in
/// [color].
class const _Ring(final Color color) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      const HexBorder().pathFor(
        Rect.fromLTRB(
          0,
          HexSegmented._gap,
          size.width,
          size.height - HexSegmented._gap,
        ),
        outset: HlFocus.ringGap + HlFocus.ringWidth / 2,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HlFocus.ringWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) => oldDelegate.color != color;
}
