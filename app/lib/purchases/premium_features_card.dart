import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// What Snacklist Premium holds, as one sticker card: a [title], a [body] and
/// the AI assistants it unlocks (Siri and Alexa are free). Zugänge shows it
/// for an account without Premium; a [footer] (the buy button) goes at the
/// bottom.
class const PremiumFeaturesCard({
  required final String title,
  required final TextStyle? titleStyle,
  required final String body,
  final Widget? footer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return HlSticker(
      child: Padding(
        padding: const EdgeInsets.all(HlSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              // Its own node: without it the header flag merges into the
              // card and makes all of it one heading.
              container: true,
              header: true,
              child: Text(title, style: titleStyle),
            ),
            const SizedBox(height: HlSpace.s2),
            Text(body),
            const SizedBox(height: HlSpace.s2),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: HlSpace.s2),
                  Expanded(child: Text(l10n.integrationPremiumAi)),
                ],
              ),
            ),
            if (footer case final footer?) ...[
              const SizedBox(height: HlSpace.s3),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}
