import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A honey hex with the cart over the empty list's text, like the site's
/// numbered step hexes (Peter, job 56 item 31).
class const EmptyList({super.key}) extends StatelessWidget {
  static const _hex = 72.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      key: const ValueKey('list-empty'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Column(
        spacing: 12,
        children: [
          ExcludeSemantics(
            child: PointyHex(
              key: const ValueKey('list-empty-mark'),
              face: t.honey,
              size: _hex,
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 32,
                color: t.onHoney,
              ),
            ),
          ),
          Text(
            AppLocalizations.of(context).emptyList,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
