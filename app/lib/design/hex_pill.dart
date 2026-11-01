import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// A settings row as the site's stores scene draws it: a horizontal hex with
/// the 2 px contour on a raised face, resting on its [HlDepth.edge] edge. The
/// row being dragged is lifted instead: no edge, the sticker-l shadow
/// ([HexPill.lift] wraps a reorderable list's proxy).
class const HexPill({
  required final Widget child,
  final VoidCallback? onTap,
  final FocusNode? focusNode,
  super.key,
}) extends StatelessWidget {
  static const height = 56.0;

  /// Space around the pill in a list.
  static const margin = EdgeInsets.symmetric(
    horizontal: HlSpace.s4,
    vertical: HlSpace.s1,
  );

  /// The proxy decorator of a reorderable list of pills.
  static Widget lift(Widget child, int index, Animation<double> animation) =>
      _Lifted(child: child);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final t = HummlistColors.of(brightness);
    final lifted =
        context.dependOnInheritedWidgetOfExactType<_Lifted>() != null;
    final face = Material(
      color: t.surfaceRaised,
      shape: HexBorder(
        side: BorderSide(color: t.border, width: HlBorder.width),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          customBorder: const HexBorder(),
          focusNode: focusNode,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.only(
                left: HlSpace.s5,
                right: HlSpace.s4,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: lifted
          ? DecoratedBox(
              decoration: ShapeDecoration(
                shape: const HexBorder(),
                shadows: HlSticker.shadow(brightness, StickerDepth.l),
              ),
              child: face,
            )
          : Stack(
              children: [
                Positioned.fill(
                  top: HlDepth.edge,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.edge,
                      shape: const HexBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: HlDepth.edge),
                  child: face,
                ),
              ],
            ),
    );
  }
}

class const _Lifted({required super.child}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_Lifted oldWidget) => false;
}

/// The 32 px pointy yellow hex that holds a step's number.
class const HexStep(final int number, {super.key}) extends StatelessWidget {
  static const size = Size(32, 37);

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.honey,
          shape: HexBorder(
            orientation: HexOrientation.pointyTop,
            side: BorderSide(color: t.border, width: HlBorder.width),
          ),
        ),
        child: SizedBox.fromSize(
          size: size,
          child: Center(
            child: Text(
              '$number',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: HlFont.display,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1,
                color: t.onHoney,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill's name, in the display face the site's stores scene sets it in.
class const PillTitle(final String text, {super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: HlFont.display,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: HummlistColors.of(Theme.of(context).brightness).text,
    ),
  );
}

/// The drag handle of a reorderable pill, a 48 dp target. Its own node:
/// merged into the row, its label would rename the row.
class const PillDragHandle({
  required final int index,
  required final String label,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    child: SizedBox.square(
      dimension: HlSize.target,
      child: Semantics(
        container: true,
        child: Icon(
          Icons.drag_handle,
          semanticLabel: label,
          color: HummlistColors.of(Theme.of(context).brightness).textMuted,
        ),
      ),
    ),
  );
}
