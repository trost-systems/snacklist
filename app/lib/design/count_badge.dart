import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// A count on a small honey hex: open join requests, unread answers.
/// Screen readers hear [label] instead of the bare number; with none the
/// badge is silent and the row it sits in names the count.
class const HlCountBadge(final int count, {final String? label, super.key})
    extends StatelessWidget {
  static const _height = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final badge = Container(
      constraints: const BoxConstraints(minWidth: 30, minHeight: _height),
      padding: const EdgeInsets.symmetric(
        horizontal: HlHex.tip * _height + HlSpace.s1,
      ),
      decoration: ShapeDecoration(
        color: t.honey,
        shape: HexBorder(
          side: BorderSide(color: t.edge, width: HlBorder.width),
        ),
      ),
      // Its own size, also in a taller row: an alignment would stretch it.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
            color: t.onHoney,
          ),
        ),
      ),
    );
    return switch (label) {
      final label? => Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: badge,
      ),
      null => ExcludeSemantics(child: badge),
    };
  }
}
