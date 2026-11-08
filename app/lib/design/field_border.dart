import 'dart:math' as math;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// The outline of a text field: a hex for single-line fields, a rounded
/// rectangle ([HlRadius.s]) for multi-line ones.
enum FieldShape() {
  hex,
  rounded,
}

/// A text field's 2 px contour in [shape], with an optional focus [ring]
/// [HlFocus.ringGap] outside it. Every state uses the same shape and width,
/// so focus changes only colours and never the field's padding.
///
/// A hex is an outline ([isOutline]): Flutter then centres a single line of
/// text in it exactly, where a non-outline border centres it twice over and
/// it sits low (job 148). An outline's label would float onto the contour,
/// so a hex field takes its label above it ([LabeledField]), never inside.
/// The rounded multi-line fields are no outline, so their floating label
/// stays inside the face instead of cutting a gap into the contour.
class const ContourInputBorder({
  final FieldShape shape = FieldShape.hex,
  super.borderSide,
  final BorderSide ring = BorderSide.none,
}) extends InputBorder {
  static const _hex = HexBorder();

  /// [rect]'s outline moved outward by [outset].
  Path _path(Rect rect, double outset) => switch (shape) {
    FieldShape.hex => _hex.pathFor(rect, outset: outset),
    FieldShape.rounded =>
      Path()..addRRect(
        RRect.fromRectAndRadius(
          rect.inflate(outset),
          Radius.circular(math.max(0, HlRadius.s + outset)),
        ),
      ),
  };

  @override
  bool get isOutline => shape == FieldShape.hex;

  @override
  ContourInputBorder copyWith({BorderSide? borderSide, BorderSide? ring}) =>
      ContourInputBorder(
        shape: shape,
        borderSide: borderSide ?? this.borderSide,
        ring: ring ?? this.ring,
      );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.strokeInset);

  @override
  ContourInputBorder scale(double t) =>
      copyWith(borderSide: borderSide.scale(t), ring: ring.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, -borderSide.strokeInset);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, 0);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style != BorderStyle.none && borderSide.width > 0) {
      canvas.drawPath(
        _path(rect, borderSide.strokeOffset / 2),
        borderSide.toPaint()..isAntiAlias = true,
      );
    }
    if (ring.style != BorderStyle.none && ring.width > 0) {
      canvas.drawPath(
        _path(rect, HlFocus.ringGap + ring.width / 2),
        ring.toPaint()..isAntiAlias = true,
      );
    }
  }

  ContourInputBorder _lerp(
    ContourInputBorder a,
    ContourInputBorder b,
    double t,
  ) => ContourInputBorder(
    shape: b.shape,
    borderSide: BorderSide.lerp(a.borderSide, b.borderSide, t),
    ring: BorderSide.lerp(a.ring, b.ring, t),
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is ContourInputBorder && a.shape == shape
      ? _lerp(a, this, t)
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is ContourInputBorder && b.shape == shape
      ? _lerp(this, b, t)
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is ContourInputBorder &&
      other.shape == shape &&
      other.borderSide == borderSide &&
      other.ring == ring;

  @override
  int get hashCode => Object.hash(shape, borderSide, ring);
}

/// Text starts this far in from a hex field's edge: past the tip of a
/// 48 dp field plus a little air, which also clears the slant beside the
/// text. A [LabeledField]'s label starts here too.
const hexFieldInset = HlHex.tip * HlSize.target + HlSpace.s1;

/// Text field decoration in [shape], from the tokens: a raised face, the
/// 2 px contour (cobalt plus the focus ring when focused, the error colour
/// on an error, faded when disabled).
///
/// The app theme gives every field the hex. A theme cannot tell a
/// multi-line field from a single-line one, so multi-line fields sit in a
/// [RoundedFields].
InputDecorationThemeData fieldTheme(HummlistColors t, FieldShape shape) {
  ContourInputBorder contour(Color color, {bool focused = false}) =>
      ContourInputBorder(
        shape: shape,
        borderSide: BorderSide(color: color, width: HlBorder.width),
        ring: focused
            ? BorderSide(color: t.accent, width: HlFocus.ringWidth)
            : BorderSide.none,
      );
  final idle = contour(t.border);
  return InputDecorationThemeData(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? t.surfaceSunken
          : t.surfaceRaised,
    ),
    hoverColor: Colors.transparent,
    // Without a limit the decorator cuts these to one line with an
    // ellipsis; German messages at large text sizes need several.
    errorMaxLines: 8,
    helperMaxLines: 8,
    contentPadding: switch (shape) {
      FieldShape.hex => const EdgeInsets.symmetric(
        horizontal: hexFieldInset,
        vertical: HlSpace.s2,
      ),
      FieldShape.rounded => const EdgeInsets.all(HlSpace.s3),
    },
    border: idle,
    enabledBorder: idle,
    focusedBorder: contour(t.brand, focused: true),
    errorBorder: contour(t.error),
    focusedErrorBorder: contour(t.error, focused: true),
    disabledBorder: contour(t.border.withValues(alpha: 0.38)),
  );
}

/// A field's error [message] after an error icon, so the error does not
/// rest on the red alone (WCAG 1.4.1). Pass it as [InputDecoration.error],
/// or from a [FormField]'s `errorBuilder`. The decorator
/// gives it the error style; screen readers get the message only.
///
/// Unlike `errorText`, an error widget does not become the field's
/// semantics hint, so a screen reader on the field would not hear it: wrap
/// the field in `Semantics(hint: message ?? '')` as well. Keep the hint
/// there while there is no error: a hint that comes and goes gives the
/// field a new semantics node, and on the web a new input that drops the
/// typed text (feedback.spec.ts, typing past the limit).
class const FieldError(final String message, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final fontSize = MediaQuery.textScalerOf(context)
        .scale(style.fontSize ?? 14);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: HlSpace.s1,
      children: [
        // Centred on the first line, however many lines follow.
        SizedBox(
          height: fontSize * (style.height ?? 1.2),
          child: ExcludeSemantics(
            child: Icon(
              Icons.error_outline,
              size: 16,
              color: style.color ?? Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        Expanded(child: Text(message)),
      ],
    );
  }
}

/// Gives the multi-line fields in [child] the rounded contour instead of the
/// theme's hex.
class const RoundedFields({required final Widget child, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InputDecorationTheme(
    data: fieldTheme(
      HummlistColors.of(Theme.of(context).brightness),
      FieldShape.rounded,
    ),
    child: child,
  );
}

/// A hex field with its [label] above it, over the field's text rather
/// than its tip. The label names the field for screen readers too. It is
/// the field's own label, not a merge: merged, the web would read the
/// field's error and counter into its name too.
class const LabeledField({
  required final String label,
  required final Widget field,
  super.key,
}) extends StatelessWidget {
  /// The label's type, without its color.
  static const labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: HlSpace.s1,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: hexFieldInset),
        child: ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      Semantics(label: label, child: field),
    ],
  );
}
