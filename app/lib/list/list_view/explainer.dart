import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The temporary card at the top that names the gestures, until dismissed.
class const ExplainerCard({required final VoidCallback onDismiss, super.key})
    extends StatelessWidget {
  /// The largest text scale at which the button fits beside the hint on a
  /// 320 px phone.
  static const _rowScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    final icon = Icon(Icons.touch_app_outlined, size: 22, color: t.brand);
    final text = Text(
      l10n.listHint,
      style: TextStyle(fontSize: 13, height: 1.35, color: t.text),
    );
    final dismiss = TextButton(
      key: const ValueKey('list-hint-dismiss'),
      onPressed: onDismiss,
      // A sunken hex face shows the whole 44 high target, not just the word.
      style: TextButton.styleFrom(
        // surfaceDim: the sunken face in light, the page in dark, where the
        // sunken token is too close to the card to show the hex.
        backgroundColor: Theme.of(context).colorScheme.surfaceDim,
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(
          fontFamily: HlFont.sans,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(l10n.listHintDismiss),
    );
    // Large text would squeeze the hint beside the button to a word per
    // line, or push the button out of the card.
    final large = MediaQuery.textScalerOf(context).scale(1) > _rowScale;
    return Padding(
      key: const ValueKey('list-hint'),
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
      child: HlSticker(
        depth: StickerDepth.s,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            HlSpace.s3,
            HlSpace.s2,
            HlSpace.s2,
            HlSpace.s2,
          ),
          child: large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      spacing: HlSpace.s3,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        Expanded(child: text),
                      ],
                    ),
                    dismiss,
                  ],
                )
              : Row(
                  spacing: HlSpace.s3,
                  children: [
                    icon,
                    Expanded(child: text),
                    dismiss,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A honey hex with the cart over the empty list's text, like the site's
/// numbered step hexes (Peter, job 56 item 31). The text is the screen's
/// heading, narrow enough to wrap into even lines.
class const EmptyList({super.key}) extends StatelessWidget {
  static const _hex = 72.0;
  static const _textWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      key: const ValueKey('list-empty'),
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s6,
        vertical: HlSpace.s7,
      ),
      child: Column(
        spacing: HlSpace.s4,
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _textWidth),
            child: Text(
              AppLocalizations.of(context).emptyList,
              textAlign: TextAlign.center,
              style: HlType.title.copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}
