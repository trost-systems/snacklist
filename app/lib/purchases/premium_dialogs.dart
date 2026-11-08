import 'dart:async';

import 'package:family_groceries/app/legal_links.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens where the yearly plan is managed and cancelled (H-83): StoreKit's
/// own sheet on iOS, else Apple's page; Google Play's page for the plan on
/// Android. Hummlist itself never cancels or refunds it.
Future<void> openManageSubscriptions(BuildContext context) async {
  final reader = context.read<StorePriceReader>();
  if (await reader.manageSubscriptions()) {
    return;
  }
  await openLegalPage(switch (defaultTargetPlatform) {
    TargetPlatform.android => googleSubscriptionUrl,
    _ => appleSubscriptionsUrl,
  });
}

/// [text] with its one `[label]` part as a link that calls [onTap]; the
/// brackets are not shown. Legal Review's strings mark the link this way,
/// so the sentence stays word for word. A recognizer on the span, not a
/// widget in it: screen readers (and the web's DOM) then get the sentence
/// as text and only the label as a link.
class const LinkedText(
  final String text, {
  required final VoidCallback onTap,
  super.key,
}) extends StatefulWidget {
  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState() extends State<LinkedText> {
  late final _tap = TapGestureRecognizer()..onTap = () => widget.onTap();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(widget.text);
    if (match == null) {
      return Text(widget.text);
    }
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.text.substring(0, match.start)),
          TextSpan(
            text: match.group(1),
            recognizer: _tap,
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
          TextSpan(text: widget.text.substring(match.end)),
        ],
      ),
    );
  }
}

/// Before Lifetime while a yearly plan is still billed (H-84): it keeps
/// running and being billed, and only its subscriber can cancel it. True
/// when the user still wants to buy; RevenueCat starts only after that
/// (H-67).
Future<bool> confirmLifetimeWhileYearly(
  BuildContext context, {
  required bool subscriber,
}) async {
  final l10n = AppLocalizations.of(context);
  final buy = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const ValueKey('premium-lifetime-warning'),
      content: LinkedText(
        subscriber
            ? l10n.premiumLifetimeWhileYearlySubscriber
            : l10n.premiumLifetimeWhileYearly,
        key: const ValueKey('premium-lifetime-warning-manage'),
        onTap: () => unawaited(openManageSubscriptions(dialog)),
      ),
      actions: [
        TextButton(
          key: const ValueKey('premium-lifetime-warning-cancel'),
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('premium-lifetime-warning-buy'),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l10n.premiumBuyAnyway),
        ),
      ],
    ),
  );
  return buy ?? false;
}

/// Before deleting the account ([account]) or leaving, deleting or
/// archiving the household (H-85): a yearly plan keeps being billed, and
/// none of these cancels it. The subscriber is told so, with the store's
/// manage page; other members of a household with such a plan get the
/// short line. True to go on. Nothing to say, or the server can't be asked:
/// true, the flow goes on as before.
///
/// [household]: the one being left (job 169b); null asks about the default.
Future<bool> confirmBillingContinues(
  BuildContext context, {
  required bool account,
  String? household,
}) async {
  final l10n = AppLocalizations.of(context);
  final MyYearlyPlan mine;
  try {
    mine = await context.read<PremiumServer>().myYearlyPlan(
      household: household,
    );
  } on Object {
    return true;
  }
  final subscriber =
      (mine.subscriber && mine.renewing) || (account && mine.elsewhere);
  // The server's answer, not the rows on this phone: a plan bought a moment
  // ago may not have reached them yet.
  if ((!subscriber && !mine.householdBilled) || !context.mounted) {
    return true;
  }
  final goOn = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: ValueKey(
        subscriber ? 'premium-billing-continues' : 'premium-billing-other',
      ),
      content: Text(
        subscriber
            ? l10n.premiumBillingContinues
            : l10n.premiumBillingContinuesOther,
      ),
      actions: [
        if (subscriber)
          TextButton(
            key: const ValueKey('premium-billing-manage'),
            onPressed: () {
              Navigator.of(dialog).pop(false);
              unawaited(openManageSubscriptions(context));
            },
            child: Text(l10n.premiumManageSubscription),
          )
        else
          TextButton(
            key: const ValueKey('premium-billing-cancel'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.cancel),
          ),
        FilledButton(
          key: const ValueKey('premium-billing-continue'),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l10n.premiumContinueAnyway),
        ),
      ],
    ),
  );
  return goOn ?? false;
}
