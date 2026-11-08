import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// A section title in the list's category-label style (the site's `.cat`):
/// 11 px heavy capitals, 0.12 em tracking, muted, and a 1 px rule running
/// on after the text. A heading for screen readers, which read [text] as
/// written. Pass [padding] to fit the page; the default is the list's.
class const HlSectionLabel(
  final String text, {
  final EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 20, 16, 4),

  /// After the text, before the rule: a count, with its own semantics.
  final Widget? badge,
  super.key,
}) extends StatelessWidget {
  static const _size = 11.0;
  static const _badgeRoom = 48.0;

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: HlSpace.s3,
          children: [
            // Large text wraps a long title instead of running it past
            // the row. Not Flexible: that would split the row with the
            // rule and cut the title at half.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    (constraints.maxWidth -
                            HlSpace.s3 -
                            // A badge's room: a count of two digits.
                            (badge == null ? 0 : _badgeRoom + HlSpace.s3))
                        .clamp(0, 1e9),
              ),
              child: Semantics(
                // Its own node in a column of other text too.
                container: true,
                header: true,
                label: text,
                excludeSemantics: true,
                child: Text(
                  // German capitals spell ß as SS (SÜSSES), as CSS does.
                  text.toUpperCase().replaceAll('ß', 'SS'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _size,
                    fontWeight: FontWeight.w800,
                    letterSpacing: _size * 0.12,
                    color: t.textMuted,
                  ),
                ),
              ),
            ),
            ?badge,
            Expanded(child: Container(height: 1, color: t.divider)),
          ],
        ),
      ),
    );
  }
}
