import 'dart:async';

import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Apple's refund requests (support.apple.com/118223): sign in, "Request a
/// refund", pick the purchase.
final appleRefundUrl = Uri.parse('https://reportaproblem.apple.com/');

/// Google Play's "Request a refund" steps (answer 15574897): Payments &
/// subscriptions, Budget & order history, Report a problem.
Uri googleRefundUrl(String language) => Uri.https(
  'support.google.com',
  '/googleplay/answer/15574897',
  {'hl': language},
);

/// The refund help (DECISIONS 43.5, H-76): Apple alone refunds App Store
/// purchases; Google Play refunds go to Google in the first 48 hours, after
/// that to our support, which looks at each case in the Play Console. Links
/// to Apple, Google and the FAQ on snacklist.app. A sheet rather than a page,
/// so the join screen keeps its state and it works before the user has a
/// household.
Future<void> showRefundHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  showDragHandle: true,
  builder: (_) => const RefundHelp(),
);

class const RefundHelp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    Widget store(String key, String label, Uri url) => LegalLink(
      key: ValueKey(key),
      url: url,
      builder: (context, open) => OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: Text(label),
        onPressed: open,
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('refund-help'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.refundHelpTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            paragraph(l10n.refundHelpBody),
            paragraph(l10n.refundHelpApple),
            paragraph(l10n.refundHelpGoogle),
            paragraph(l10n.refundHelpReason),
            // H-76's texts name only Lifetime and stay word for word; the
            // yearly plan gets its own note (NEEDS_LEAD Job 49).
            paragraph(l10n.premiumRefundYearly),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                store('refund-apple', l10n.refundHelpAppleLink, appleRefundUrl),
                store(
                  'refund-google',
                  l10n.refundHelpGoogleLink,
                  googleRefundUrl(language),
                ),
                store(
                  'refund-faq',
                  l10n.refundHelpFaqLink,
                  supportUrl(language),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Paid twice?" as a small link that opens [showRefundHelp].
class const RefundHelpLink({required final String label, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      icon: const Icon(Icons.help_outline),
      label: Text(label),
      onPressed: () => unawaited(showRefundHelp(context)),
    ),
  );
}
