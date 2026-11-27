import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_dialogs.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Snacklist Premium for the whole household (`/more/lifetime`), laid out as
/// PW-P4 „Haushalt“ (job 87): the household as the hero, the status, the
/// yearly plan and Lifetime as two tiles with the store's own prices, one Buy
/// for the picked plan, restore, and the plan's management. A page of the
/// More tab, which gives it its frame. Opening it reads the server switch
/// and the store's prices (StoreKit or Play Billing, A2-5); only Buy and
/// Restore start RevenueCat (Legal Review H-67).
class const PremiumScreen({
  super.key,

  /// Where it was opened from, for paywall_viewed.
  final PaywallEntry entry = PaywallEntry.more,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final purchases = context.read<PurchaseCubit>()..pageOpened();
      return PremiumPageCubit(
        context.read<PremiumServer>(),
        context.read<StorePriceReader>(),
        context.read<Entitlements>(),
        sells: purchases.state.noSale == null,
        analytics: context.read<Analytics?>(),
        entry: entry,
      );
    },
    child: const _PremiumView(),
  );
}

class const _PremiumView() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final entitlements = context.watch<Entitlements>();
    final premium = entitlements.premium;
    bool offers(PremiumPlan plan) =>
        entitlements.canOffer(Entitlement.premium, plan);
    final household = context.select<SessionCubit, Household?>(
      (s) => switch (s.state) {
        InHousehold(:final household) => household,
        _ => null,
      },
    );
    final page = context.watch<PremiumPageCubit>().state;
    final mine = page.mine;
    final cubit = context.read<PurchaseCubit>();
    final state = context.watch<PurchaseCubit>().state;
    final noSale = state.noSale;
    final sells = noSale == null;
    final prices = switch (page.offer) {
      OfferPrices(:final prices) => prices,
      _ => const <PremiumPlan, StorePrice>{},
    };
    // A plan is offered only with its store price, the server switch on and
    // the household known not to have it (A2-5, H-84).
    final cards = [
      if (sells && household != null)
        for (final plan in PremiumPlan.values)
          if (offers(plan) && prices[plan] != null) plan,
    ];
    final launched = page.launch == OfferSwitch.on;
    final selling = launched && sells;
    // The store took money: a purchase row, or one on its way here or bound
    // to another household.
    final paid =
        entitlements.purchased ||
        switch (state.flow) {
          FlowUnlocking() || FlowUnlockDelayed() || FlowUsedElsewhere() => true,
          _ => false,
        };
    final yearlyRuns =
        premium is ActivePremium && premium.source == PremiumSource.yearly ||
        entitlements.yearlyBilled;
    final manage = !kIsWeb && yearlyRuns;
    void buy(PremiumPlan plan) => unawaited(() async {
      if (plan == PremiumPlan.lifetime &&
          entitlements.yearlyBilled &&
          !await confirmLifetimeWhileYearly(
            context,
            subscriber: mine?.subscriber ?? false,
          )) {
        return;
      }
      await cubit.buy(plan);
    }());
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: const ValueKey('lifetime-screen'),
          // Clear of the floating tab pill.
          padding: EdgeInsets.only(
            top: 8,
            bottom: 8 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // Each block is its own semantics node: one line for a screen
            // reader (and the web's DOM) instead of the page run together.
            _Hero(selling: selling),
            if (premium case ActivePremium(
              :final source,
              :final expiresAt,
              :final renews,
              :final free,
            ))
              _Unlocked(free: free, switch (source) {
                PremiumSource.yearly when renews => l10n.premiumStatusRenews(
                  expiresAt!.toLocal(),
                ),
                PremiumSource.yearly => l10n.premiumStatusEnds(
                  expiresAt!.toLocal(),
                ),
                PremiumSource.lifetime => l10n.premiumStatusLifetime,
                // A free unlock (Legal Review final texts, 2026-11-03): the
                // grant says whose it is, not the switch (N-70).
                PremiumSource.promotional => switch (free) {
                  FreeUnlock.tester => l10n.premiumStatusFree,
                  FreeUnlock.betaLifetime => l10n.premiumStatusBetaLifetime,
                  FreeUnlock.beta || null => l10n.premiumStatusBeta,
                },
              }),
            // A household's unlock is not the user's Premium (Terms §6).
            if (premium is ActivePremium &&
                entitlements.ownPremium is NoPremium)
              _Note(
                'premium-household-only',
                Icons.info_outline,
                l10n.premiumHouseholdOnly,
              ),
            if (mine case MyYearlyPlan(billingIssue: true, :final until?))
              _Note(
                'premium-billing-issue',
                Icons.credit_card_off_outlined,
                l10n.premiumBillingIssue(until.toLocal()),
                error: true,
              ),
            if (premium case ActivePremium(source: PremiumSource.lifetime)
                when entitlements.yearlyBilled)
              Semantics(
                container: true,
                child: ListTile(
                  key: const ValueKey('premium-lifetime-while-yearly'),
                  leading: const Icon(Icons.info_outline),
                  title: LinkedText(
                    mine?.subscriber ?? false
                        ? l10n.premiumLifetimeWhileYearlySubscriber
                        : l10n.premiumLifetimeWhileYearly,
                    key: const ValueKey('premium-lifetime-while-yearly-manage'),
                    onTap: () => unawaited(openManageSubscriptions(context)),
                  ),
                ),
              ),
            if (entitlements.twoYearlyPlans)
              _Note(
                'premium-two-yearly',
                Icons.info_outline,
                l10n.premiumTwoYearly,
              ),
            if (manage)
              FocusRingTile(
                key: const ValueKey('premium-manage'),
                child: ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(l10n.premiumManage),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => unawaited(openManageSubscriptions(context)),
                ),
              ),
            if (kIsWeb && yearlyRuns) _ManageOnWeb(language: language),
            if (entitlements.boughtLifetimeTwice)
              _Note(
                'lifetime-bought-twice',
                Icons.info_outline,
                l10n.lifetimeBoughtTwice,
              ),
            ?_flow(context, state.flow),
            if (premium == null && sells)
              _Note('lifetime-checking', Icons.sync, l10n.premiumChecking),
            // Where to buy, only once sales started (Legal Review final
            // texts: nothing about buying on the web before).
            if (noSale is PurchasesUnsupported && page.launch == OfferSwitch.on)
              _Note('lifetime-web', Icons.phone_iphone, l10n.premiumWeb),
            if (sells &&
                household != null &&
                PremiumPlan.values.any(offers) &&
                cards.isEmpty)
              ?switch (page.offer) {
                OfferLoading() || OfferClosed() => null,
                OfferUnavailable() || OfferPrices() => _Note(
                  'premium-unavailable',
                  Icons.cloud_off,
                  l10n.premiumUnavailable,
                ),
              },
            if (household != null && cards.isNotEmpty)
              _Plans(cards: cards, prices: prices, onBuy: buy),
            // Only to someone who paid, once sales start, or bought twice:
            // before, it would suggest a purchase (Legal Review N-69); to a
            // promotional grant alone, a refund of nothing paid (N-346).
            if (launched && paid || entitlements.boughtLifetimeTwice)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
                child: RefundHelpLink(
                  key: const ValueKey('lifetime-refund-help'),
                  label: l10n.lifetimeRefundLink,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget? _flow(BuildContext context, PurchaseFlow flow) {
    final l10n = AppLocalizations.of(context);
    return switch (flow) {
      FlowIdle() || FlowBuying() || FlowRestoring() => null,
      FlowAwaitingApproval() => Semantics(
        container: true,
        child: ListTile(
          key: const ValueKey('lifetime-pending'),
          leading: const Icon(Icons.hourglass_top),
          title: Text(l10n.lifetimePending),
          subtitle: Text(l10n.lifetimePendingBody),
        ),
      ),
      FlowUnlocking() => Semantics(
        container: true,
        child: ListTile(
          key: const ValueKey('lifetime-unlocking'),
          leading: const _Spinner(),
          title: Text(l10n.lifetimeUnlocking),
        ),
      ),
      FlowUnlockDelayed() => _Note(
        'lifetime-unlock-delayed',
        Icons.schedule,
        l10n.lifetimeUnlockDelayed,
      ),
      FlowCanceled() => _Note(
        'lifetime-canceled',
        Icons.close,
        l10n.lifetimeCanceled,
      ),
      FlowNotAvailable() => _Note(
        'lifetime-unavailable',
        Icons.schedule,
        l10n.premiumUnavailable,
      ),
      FlowUsedElsewhere(:final plan) => Semantics(
        container: true,
        child: ListTile(
          key: const ValueKey('lifetime-used-elsewhere'),
          leading: const Icon(Icons.home_outlined),
          title: Text(l10n.lifetimeUsedElsewhere),
          subtitle: plan == PremiumPlan.yearly
              ? Text(l10n.premiumUsedElsewhereYearly)
              : null,
        ),
      ),
      FlowNothingRestored() => _Note(
        'lifetime-nothing-restored',
        Icons.search_off,
        l10n.lifetimeNothingRestored,
      ),
      FlowFailed(kind: FailureKind.offline) => _Note(
        'lifetime-offline',
        Icons.cloud_off,
        l10n.lifetimeStoreOffline,
      ),
      FlowFailed(:final kind, :final code) => _Note(
        'lifetime-error',
        Icons.error_outline,
        switch (kind) {
          FailureKind.store => l10n.lifetimeStoreFailed(code),
          FailureKind.offline => l10n.lifetimeStoreOffline,
        },
        error: true,
      ),
    };
  }
}

/// The household has Premium: [status] says which, on a honey sticker
/// under the hero.
class const _Unlocked(
  final String status, {

  /// A free unlock: what it costs and how it ends, and where the privacy
  /// policy explains it.
  required final FreeUnlock? free,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s3,
        HlSpace.s4,
        HlSpace.s2,
      ),
      child: Semantics(
        container: true,
        child: HlSticker(
          key: const ValueKey('lifetime-unlocked'),
          color: t.honey,
          child: Padding(
            padding: const EdgeInsets.all(HlSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PointyHex(
                  face: t.surfaceRaised,
                  size: 36,
                  child: Icon(Icons.check, size: 20, color: t.text),
                ),
                const SizedBox(width: HlSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Own nodes: next to the link, text merged into the
                      // card would only be its label, not text, on the web.
                      Semantics(
                        container: true,
                        child: Text(
                          status,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: t.onHoney,
                          ),
                        ),
                      ),
                      if (free != null) ...[
                        const SizedBox(height: HlSpace.s1),
                        Semantics(
                          container: true,
                          child: Text(
                            free == FreeUnlock.betaLifetime
                                ? l10n.premiumBetaLifetimeBody
                                : l10n.premiumBetaBody,
                            key: ValueKey(
                              free == FreeUnlock.betaLifetime
                                  ? 'premium-beta-lifetime-body'
                                  : 'premium-beta-body',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: t.onHoney,
                            ),
                          ),
                        ),
                        LegalLink(
                          key: const ValueKey('premium-beta-privacy'),
                          url: privacyPolicyUrl(
                            Localizations.localeOf(context).languageCode,
                          ).replace(fragment: 'premium-beta'),
                          builder: (context, open) => TextButton(
                            style: withFocusRing(
                              TextButton.styleFrom(
                                foregroundColor: t.onHoney,
                                padding: EdgeInsets.zero,
                                textStyle: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              focusRingColor(t, honey: 1),
                            ),
                            onPressed: open,
                            child: Text(l10n.premiumBetaPrivacyLink),
                          ),
                        ),
                      ],
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

/// One line of state with its icon.
class const _Note(
  final String id,
  final IconData icon,
  final String text, {
  final bool error = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: ListTile(
        key: ValueKey(id),
        leading: Icon(icon),
        iconColor: error ? scheme.error : null,
        title: Text(text),
      ),
    );
  }
}

class const _Spinner() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

TextStyle _display(BuildContext context, double size, {Color? color}) {
  final t = SnacklistColors.of(Theme.of(context).brightness);
  return TextStyle(
    fontFamily: HlFont.display,
    fontSize: size,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.02 * size,
    color: color ?? t.text,
  );
}

/// Premium for you (Legal N-348): the household's members as hexes, what
/// Premium is for the household, and what it unlocks. No Siri or Alexa
/// (both stay free, job 184 and Legal Review N-27).
class const _Hero({
  /// This build sells and sales started: only then the buying slogan
  /// (Legal Review N-68).
  required final bool selling,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    // No Flags above (a screen on its own, in tests): off.
    final api = context.select<Flags?, bool>(
      (flags) => flags?.isOn(publicApiFlag) ?? false,
    );
    Widget hex(Color face, IconData icon, Color ink) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: PointyHex(
        face: face,
        size: 56,
        child: Icon(icon, color: ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s3,
        HlSpace.s4,
        HlSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                hex(t.cobalt, Icons.person_outline, t.onCobalt),
                hex(t.mint, Icons.person_outline, t.onMint),
                hex(t.tomato, Icons.person_outline, t.onTomato),
                hex(t.surfaceRaised, Icons.add, t.text),
              ],
            ),
          ),
          const SizedBox(height: HlSpace.s4),
          if (selling) ...[
            Semantics(
              header: true,
              container: true,
              child: Text(
                l10n.premiumHeroTitle,
                key: const ValueKey('premium-hero-title'),
                textAlign: TextAlign.center,
                style: _display(context, 26),
              ),
            ),
            const SizedBox(height: HlSpace.s2),
          ],
          // Its own node: without the title it would merge into the hero's,
          // a label next to the benefits instead of text on the web.
          Semantics(
            container: true,
            child: Text(
              l10n.premiumHeroBody,
              key: const ValueKey('premium-hero-body'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: HlSpace.s4),
          _Benefit(Icons.smart_toy_outlined, l10n.premiumBenefitAi),
          if (api) _Benefit(Icons.terminal, l10n.premiumBenefitApi),
        ],
      ),
    );
  }
}

class const _Benefit(final IconData icon, final String text)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HlSpace.s1),
        child: Row(
          children: [
            PointyHex(
              face: t.honey,
              size: 30,
              child: Icon(icon, size: 16, color: t.onHoney),
            ),
            const SizedBox(width: HlSpace.s3),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// The offered plans as tiles to pick from, that Premium is the
/// account's (Legal N-350), one Buy for the picked plan with its terms,
/// restore and the legal links. The pick lives in [PremiumPageCubit], so it
/// survives the tiles scrolling out of the lazy list.
class const _Plans({
  /// The plans on offer, each with a price in [prices]; never empty.
  required final List<PremiumPlan> cards,
  required final Map<PremiumPlan, StorePrice> prices,
  required final void Function(PremiumPlan plan) onBuy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final cubit = context.read<PurchaseCubit>();
    final state = context.watch<PurchaseCubit>().state;
    final page = context.read<PremiumPageCubit>();
    final wanted = context.select<PremiumPageCubit, PremiumPlan>(
      (c) => c.state.picked,
    );
    final picked = cards.contains(wanted) ? wanted : cards.first;
    Widget tile(PremiumPlan plan) => _PlanTile(
      plan: plan,
      price: prices[plan]!,
      picked: plan == picked,
      onTap: state.busy ? null : () => page.pick(plan),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(HlSpace.s4, HlSpace.s3, HlSpace.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cards case [final only])
            tile(only)
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final plan in cards) ...[
                    if (plan != cards.first) const SizedBox(width: HlSpace.s3),
                    Expanded(child: tile(plan)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: HlSpace.s3),
          Semantics(
            container: true,
            child: Row(
              key: const ValueKey('premium-household'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_outlined, size: 18),
                const SizedBox(width: HlSpace.s2),
                Expanded(
                  child: Text(
                    l10n.premiumHousehold,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HlSpace.s4),
          _BuyButton(
            plan: picked,
            buying: state.flow is FlowBuying,
            onPressed: state.busy ? null : () => onBuy(picked),
          ),
          const SizedBox(height: HlSpace.s3),
          Text(
            switch (picked) {
              PremiumPlan.yearly => l10n.premiumYearlyTerms,
              PremiumPlan.lifetime => l10n.premiumLifetimeValue,
            },
            key: ValueKey('premium-terms-${picked.name}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: HlSpace.s2),
          Center(
            child: TextButton.icon(
              key: const ValueKey('lifetime-restore'),
              icon: state.flow is FlowRestoring
                  ? const _Spinner()
                  : const Icon(Icons.restore),
              label: Text(l10n.lifetimeRestore),
              onPressed: state.busy ? null : () => unawaited(cubit.restore()),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              _Link(
                'premium-terms',
                l10n.premiumTermsLink,
                termsUrl(language),
                small: true,
              ),
              if (appleEulaShown(web: kIsWeb, platform: defaultTargetPlatform))
                _Link(
                  'premium-apple-eula',
                  l10n.premiumAppleEulaLink,
                  appleEulaUrl,
                  small: true,
                ),
              _Link(
                'premium-privacy',
                l10n.premiumPrivacyLink,
                privacyPolicyUrl(language),
                small: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One plan with the store's price, exactly as the store formats it;
/// "inkl. MwSt." only for a price in euros (K.13.P.3). Honey while picked.
class const _PlanTile({
  required final PremiumPlan plan,
  required final StorePrice price,
  required final bool picked,

  /// Null while a purchase or restore runs.
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final ink = picked ? t.onHoney : t.text;
    final period = switch (plan) {
      PremiumPlan.yearly => l10n.premiumPerYear,
      PremiumPlan.lifetime => l10n.premiumOneTime,
    };
    return MergeSemantics(
      key: ValueKey('premium-card-${plan.name}'),
      child: Semantics(
        button: true,
        selected: picked,
        enabled: onTap != null,
        inMutuallyExclusiveGroup: true,
        child: HlSticker(
          depth: picked ? StickerDepth.m : StickerDepth.s,
          color: picked ? t.honey : null,
          child: Material(
            type: MaterialType.transparency,
            child: FocusRingInkWell(
              outline: HlSticker.innerOutline,
              color: focusRingColor(t, honey: picked ? 1 : 0),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(HlSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(switch (plan) {
                      PremiumPlan.yearly => l10n.premiumYearlyTitle,
                      PremiumPlan.lifetime => l10n.premiumLifetimeTitle,
                    }, style: theme.textTheme.titleSmall?.copyWith(color: ink)),
                    const SizedBox(height: HlSpace.s1),
                    Text(
                      price.formatted,
                      key: ValueKey('premium-price-${plan.name}'),
                      style: _display(context, 24, color: ink),
                    ),
                    Text(
                      price.euro ? l10n.premiumWithVat(period) : period,
                      key: ValueKey('premium-period-${plan.name}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buy for the picked plan; RevenueCat starts only on this tap (H-67).
class const _BuyButton({
  required final PremiumPlan plan,
  required final bool buying,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = Text(switch (plan) {
      PremiumPlan.yearly => l10n.premiumBuyYearly,
      PremiumPlan.lifetime => l10n.premiumBuyLifetime,
    });
    final key = ValueKey('premium-buy-${plan.name}');
    return buying
        ? FilledButton.icon(
            key: key,
            icon: const _Spinner(),
            label: label,
            onPressed: onPressed,
          )
        : FilledButton(key: key, onPressed: onPressed, child: label);
  }
}

class const _Link(
  final String id,
  final String label,
  final Uri url, {

  /// Smaller and tighter, for the terms and privacy side by side under Buy.
  final bool small = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LegalLink(
    key: ValueKey(id),
    url: url,
    builder: (context, open) => TextButton(
      style: small
          ? TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: HlSpace.s2),
              textStyle: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            )
          : null,
      onPressed: open,
      child: Text(label),
    ),
  );
}

/// The web sells nothing and can't open a store's sheet: the two pages
/// where a yearly plan is managed.
class const _ManageOnWeb({required final String language})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const ValueKey('premium-manage-web'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.premiumManageWeb),
          Wrap(
            children: [
              _Link(
                'premium-manage-apple',
                l10n.premiumManageApple,
                appleSubscriptionsUrl,
              ),
              _Link(
                'premium-manage-google',
                l10n.premiumManageGoogle,
                googleSubscriptionsUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
