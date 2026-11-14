import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The list's card after the long-running rule ended a trip (job 234): it
/// ended at the last tick, [endedAt]. The trip can go on („Doch weiter“)
/// until the card is closed.
class const TripEndedCard({
  required final DateTime endedAt,
  required final VoidCallback onKeepGoing,
  required final VoidCallback onShowSummary,
  required final VoidCallback onDismiss,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final time = DateFormat.Hm(locale).format(endedAt.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
      child: Semantics(
        container: true,
        child: HlSticker(
          key: const ValueKey('trip-ended-card'),
          depth: StickerDepth.s,
          color: t.mintSoft,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              HlSpace.s3,
              HlSpace.s3,
              HlSpace.s1,
              HlSpace.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s1,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: HlSpace.s2,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.flag_outlined, color: t.text),
                    ),
                    Expanded(
                      // One group, read before the close button; the title
                      // and the body each their own node in it.
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: HlSpace.s1,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                l10n.shopAutoEndedTitle,
                                style: HlType.title.copyWith(color: t.text),
                              ),
                            ),
                            Text(
                              l10n.shopAutoEndedBody(time),
                              style: HlType.body.copyWith(color: t.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // A label, not a tooltip: on the web a showing tooltip
                    // moves the route's semantics and blurs the add field.
                    Semantics(
                      container: true,
                      button: true,
                      label: l10n.close,
                      excludeSemantics: true,
                      onTap: onDismiss,
                      child: IconButton(
                        key: const ValueKey('trip-ended-dismiss'),
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: HlSpace.s2,
                    children: [
                      TextButton(
                        key: const ValueKey('trip-ended-keep-going'),
                        onPressed: onKeepGoing,
                        child: Text(l10n.shopKeepGoing),
                      ),
                      FilledButton(
                        key: const ValueKey('trip-ended-summary'),
                        onPressed: onShowSummary,
                        child: Text(l10n.shopShowSummary),
                      ),
                    ],
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
