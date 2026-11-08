import 'package:family_groceries/design/fonts.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// A section title in the list's category-label style (the site's `.cat`):
/// [overline] capitals, muted, and a 1 px rule running on after the
/// text. A heading for screen readers, which read [text] as
/// written. Pass [padding] to fit the page; the default is the list's.
class const HlSectionLabel(
  final String text, {
  final EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 20, 16, 4),
  super.key,
}) extends StatelessWidget {
  /// The overline of section titles and the list's category labels: the
  /// caption token's weight and capitals at the app's one caption size,
  /// with its 0.08 em tracking. Height 1 keeps the line box of the former
  /// 12 px labels, so the rows around them keep their rhythm.
  static TextStyle overline(Color color) => HlType.caption.copyWith(
    fontSize: captionSize,
    letterSpacing: 0.08 * captionSize,
    height: 1,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        label: text,
        excludeSemantics: true,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            spacing: HlSpace.s3,
            children: [
              // Large text wraps a long title instead of running it past
              // the row. Not Flexible: that would split the row with the
              // rule and cut the title at half.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - HlSpace.s3).clamp(0, 1e9),
                ),
                child: Text(
                  // German capitals spell ß as SS (SÜSSES), as CSS does.
                  text.toUpperCase().replaceAll('ß', 'SS'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: overline(t.textMuted),
                ),
              ),
              Expanded(child: Container(height: 1, color: t.divider)),
            ],
          ),
        ),
      ),
    );
  }
}
