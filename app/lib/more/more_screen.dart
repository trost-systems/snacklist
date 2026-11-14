import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/guides.dart';
import 'package:family_groceries/app/legal_links.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/feedback_sheet.dart';
import 'package:family_groceries/household/archived_households.dart';
import 'package:family_groceries/household/household_page.dart';
import 'package:family_groceries/household/invites_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/purchases/premium_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/access_screen.dart';
import 'package:family_groceries/settings/account_screen.dart';
import 'package:family_groceries/settings/settings_screen.dart';
import 'package:family_groceries/tips/tips_page.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The pages More opens: beside its list on wide screens, on their own
/// on phones.
enum MorePage() {
  /// The MCP server, tokens and connected apps (`/more/access`).
  access,

  /// The signed-in email, export and account deletion (`/more/account`).
  account,

  /// Invite the partner, the open invites, revoke (`/more/invites`).
  invites,

  /// The shown household: name, members, default, leave
  /// (`/more/household`, job 169b).
  household,

  /// Snacklist Premium's purchase, restore and status (`/more/lifetime`).
  premium,

  /// Theme and language (`/more/settings`).
  settings,

  /// The language list below [settings] (`/more/settings/language`).
  language,

  /// The usage-data switch (`/more/usage-data`).
  usageData,

  /// Every hint of the List tab (`/more/tips`).
  tips,
}

/// The More tab (M-P2, job 85): the update card when there is one, inset
/// groups of rows, sign-out on its own, then the app version.
class const MoreScreen({
  super.key,
  final MorePage? page,

  /// Shows "Hilfe & Kontakt"; tests pass false to see a release build.
  @visibleForTesting final bool showHelp = supportLinkShown,

  /// Shows "Archivierte Haushalte" (job 43); tests pass true.
  @visibleForTesting final bool showArchived = Environment.householdArchive,

  /// Where the update card learns about an update.
  @visibleForTesting final AppUpdates updates = const NoAppUpdates(),

  /// Where the Premium page was opened from (`?from=`), for paywall_viewed.
  final PaywallEntry paywallEntry = PaywallEntry.more,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    if (wide) {
      final shown = page ?? MorePage.access;
      return Scaffold(
        // The pages sit below `/more`; beside the list there is nothing to
        // go back to.
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.tabMore),
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 360,
              child: _MoreList(
                showHelp: showHelp,
                showArchived: showArchived,
                updates: updates,
                selected: shown,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      spacing: 8,
                      children: [
                        // The language list sits below Einstellungen, also
                        // beside the list.
                        if (shown == MorePage.language)
                          BackButton(
                            onPressed: () => context.go(appSettingsPath),
                          ),
                        // Large text wraps a long title in the narrow pane.
                        Flexible(
                          child: Text(
                            _title(l10n, shown),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _Page(shown, paywallEntry)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (page case final page?) {
      // Every page is a route below `/more`, so back (the app bar's or the
      // system's) pops to the list, also after a deep link.
      return Scaffold(
        appBar: AppBar(title: Text(_title(l10n, page))),
        body: _Page(page, paywallEntry),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabMore)),
      body: _MoreList(
        showHelp: showHelp,
        showArchived: showArchived,
        updates: updates,
      ),
    );
  }

  static String _title(AppLocalizations l10n, MorePage page) => switch (page) {
    MorePage.access => l10n.accessTitle,
    MorePage.account => l10n.account,
    MorePage.invites => l10n.invitesTitle,
    MorePage.household => l10n.householdPageTitle,
    MorePage.premium => l10n.premiumTitle,
    MorePage.settings => l10n.settingsTitle,
    MorePage.language => l10n.language,
    MorePage.usageData => l10n.analyticsSection,
    MorePage.tips => l10n.hintsTitle,
  };
}

class const _Page(final MorePage page, final PaywallEntry paywallEntry)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => switch (page) {
    MorePage.access => const AccessScreen(),
    MorePage.account => const AccountScreen(),
    MorePage.invites => const InvitesPage(),
    MorePage.household => const HouseholdPage(),
    MorePage.premium => PremiumScreen(entry: paywallEntry),
    MorePage.settings => const SettingsScreen(),
    MorePage.language => const LanguageScreen(),
    MorePage.usageData => const _UsageDataPage(),
    MorePage.tips => const TipsPage(),
  };
}

/// A row of More, with its glyph and the hex face behind it: honey for the
/// household, cobalt for connections, mint for you and your data, the
/// sunken surface for the rest.
enum _Item(final IconData icon, final String key, final _Tint tint) {
  startTrip(Icons.shopping_cart_outlined, 'more-start-trip', _Tint.honey),
  account(Icons.manage_accounts_outlined, 'menu-account', _Tint.mint),
  premium(Icons.favorite_outline, 'more-lifetime', _Tint.honey),
  household(Icons.home_outlined, 'more-household', _Tint.honey),
  invite(Icons.person_add_outlined, 'more-invite', _Tint.honey),
  archived(Icons.inventory_2_outlined, 'more-archived', _Tint.honey),
  access(Icons.key_outlined, 'more-access', _Tint.cobalt),
  settings(Icons.settings_outlined, 'more-settings', _Tint.mint),
  usageData(Icons.insights_outlined, 'more-usage-data', _Tint.mint),
  tips(Icons.lightbulb_outline, 'more-tips', _Tint.plain),
  feedback(Icons.feedback_outlined, 'more-feedback', _Tint.plain),
  rate(Icons.star_outline, 'more-rate', _Tint.plain),
  help(Icons.help_outline, 'more-help', _Tint.plain),
  imprint(Icons.info_outline, 'more-imprint', _Tint.plain),
  privacyPolicy(Icons.privacy_tip_outlined, 'more-privacy-policy', _Tint.plain),
  terms(Icons.article_outlined, 'more-terms', _Tint.plain),
  licenses(Icons.description_outlined, 'more-licenses', _Tint.plain),
  signOut(Icons.logout, 'more-sign-out', _Tint.plain);

  /// The groups top to bottom; the legal pages are rows of their own
  /// group, so the imprint is one tap from the tab (DDG §5); sign-out
  /// stands alone at the end.
  static const groups = <List<_Item>>[
    [startTrip],
    [account, premium],
    [household, invite, archived],
    [access],
    [settings, usageData],
    [tips, feedback, rate, help],
    [imprint, privacyPolicy, terms, licenses],
    [signOut],
  ];
}

enum _Tint() {
  honey,
  cobalt,
  mint,
  plain,
}

class const _MoreList({
  required final bool showHelp,
  required final bool showArchived,
  required final AppUpdates updates,
  final MorePage? selected,
}) extends StatefulWidget {
  @override
  State<_MoreList> createState() => _MoreListState();
}

class _MoreListState() extends State<_MoreList> {
  late final Future<OfferSwitch> _offer = context
      .read<PremiumServer>()
      .offerSwitch();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = context.watch<SessionCubit>().state;
    final household = session is InHousehold ? session.household : null;
    final unlocked = context.select<Entitlements, bool>(
      (e) => e.has(Entitlement.premium),
    );
    final noSale = context.select<PurchaseCubit, NoSale?>(
      (c) => c.state.noSale,
    );
    // Job 234: by hand, only while no trip runs for the user.
    final tripMode = context.select<Flags?, bool>(
      (flags) => flags?.isOn(tripModeFlag) ?? false,
    );
    final noTrip = context.select<TripCubit?, bool>(
      (trips) => switch (trips?.state) {
        NoTrip() || Ended() => true,
        _ => false,
      },
    );
    final canStartTrip = tripMode && noTrip;
    return FutureBuilder(
      future: _offer,
      builder: (context, offer) {
        // The page stays reachable from the integration settings.
        final premium = premiumListed(
          held: unlocked,
          offer: offer.data,
          noSale: noSale,
        );
        bool shown(_Item item) => switch (item) {
          _Item.startTrip => canStartTrip,
          _Item.premium => premium,
          _Item.household || _Item.invite => household != null,
          _Item.archived => widget.showArchived,
          _Item.help => widget.showHelp,
          _Item.rate => storeListingShown(
            web: kIsWeb,
            platform: defaultTargetPlatform,
          ),
          _Item.usageData => context.read<Analytics>().enabled,
          _ => true,
        };
        return ListView(
          key: const ValueKey('more-screen'),
          // Clear of the floating tab pill.
          padding: EdgeInsets.only(
            bottom: HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _UpdateSlot(widget.updates),
            for (final all in _Item.groups)
              if (all.where(shown).toList() case final items
                  when items.isNotEmpty)
                HlGroup(
                  children: [
                    for (final item in items)
                      _row(context, l10n, item, household),
                  ],
                ),
            const _Version(),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    _Item item,
    Household? household,
  ) {
    final selected = widget.selected;
    final lang = Localizations.localeOf(context).languageCode;
    void go(String path) => context.go(path);
    void web(Uri url) => unawaited(openLegalPage(url));
    return switch (item) {
      _Item.startTrip => _Row(
        item,
        label: l10n.shopStartByHand,
        subtitle: l10n.shopStartByHandHint,
        trailing: _Trailing.none,
        onTap: () {
          context.read<TripCubit>().startByHand();
          go(listPath);
        },
      ),
      _Item.account => _Row(
        item,
        label: l10n.account,
        selected: selected == MorePage.account,
        onTap: () => go(accountPath),
      ),
      _Item.premium => _Row(
        item,
        label: l10n.premiumTitle,
        selected: selected == MorePage.premium,
        onTap: () => go(premiumPath),
      ),
      _Item.household => _Row(
        item,
        label: household?.name ?? l10n.householdPageTitle,
        selected: selected == MorePage.household,
        onTap: () => go(householdPath),
      ),
      _Item.invite => _Row(
        item,
        label: l10n.inviteMember,
        selected: selected == MorePage.invites,
        onTap: () => go(invitesPath),
      ),
      _Item.archived => _Row(
        item,
        label: l10n.archivedTitle,
        onTap: () => unawaited(showArchivedHouseholds(context)),
      ),
      _Item.access => _Row(
        item,
        label: l10n.accessTitle,
        selected: selected == MorePage.access,
        onTap: () => go(accessPath),
      ),
      _Item.settings => _Row(
        item,
        label: l10n.settingsTitle,
        selected:
            selected == MorePage.settings || selected == MorePage.language,
        onTap: () => go(appSettingsPath),
      ),
      _Item.usageData => _Row(
        item,
        label: l10n.analyticsSection,
        selected: selected == MorePage.usageData,
        onTap: () => go(usageDataPath),
      ),
      _Item.tips => _Row(
        item,
        label: l10n.hintsTitle,
        selected: selected == MorePage.tips,
        onTap: () => go(tipsPath),
      ),
      _Item.feedback => _Row(
        item,
        label: l10n.feedbackRow,
        onTap: () => unawaited(showFeedbackSheet(context)),
      ),
      // The listing, never the store's prompt: Apple refuses apps that ask
      // for a rating on a tap.
      _Item.rate => _Row(
        item,
        label: l10n.rateApp,
        trailing: _Trailing.external,
        onTap: () => unawaited(_openStoreListing(context)),
      ),
      _Item.help => _Row(
        item,
        label: l10n.helpRow,
        trailing: _Trailing.external,
        onTap: () => web(supportUrl(lang)),
      ),
      _Item.imprint => _Row(
        item,
        label: l10n.imprint,
        trailing: _Trailing.external,
        onTap: () => web(imprintUrl(lang)),
      ),
      _Item.privacyPolicy => _Row(
        item,
        label: l10n.privacyPolicy,
        trailing: _Trailing.external,
        onTap: () => web(privacyPolicyUrl(lang)),
      ),
      _Item.terms => _Row(
        item,
        label: l10n.premiumTermsLink,
        trailing: _Trailing.external,
        onTap: () => web(termsUrl(defaultTargetPlatform, lang)),
      ),
      _Item.licenses => _Row(
        item,
        label: l10n.licenses,
        onTap: () => unawaited(_showLicenses(context)),
      ),
      _Item.signOut => _Row(
        item,
        label: l10n.signOut,
        trailing: _Trailing.none,
        onTap: () => unawaited(context.read<SessionCubit>().signOut()),
      ),
    };
  }
}

/// The store's page for this app. A failure (no store app, no connection)
/// is told, and caught: an uncaught one would hold the rating prompt back.
Future<void> _openStoreListing(BuildContext context) async {
  final text = AppLocalizations.of(context).lifetimeStoreOffline;
  final notices = Notices.maybeOf(context);
  try {
    await context.read<StoreReview>().openStoreListing();
  } on Object {
    notices?.showSnackBar(SnackBar(content: Text(text)));
  }
}

enum _Trailing() {
  /// Opens a page in the app.
  chevron,

  /// Opens a web page outside the app.
  external,
  none,
}

class const _Row(
  final _Item item, {
  required final String label,
  required final VoidCallback onTap,
  final String? subtitle,
  final bool selected = false,
  final _Trailing trailing = _Trailing.chevron,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return ListTile(
      key: ValueKey(item.key),
      minTileHeight: 52,
      contentPadding: const EdgeInsets.symmetric(horizontal: HlSpace.s3),
      leading: HlRowHex(
        item.icon,
        face: switch (item.tint) {
          _Tint.honey => t.honeySoft,
          _Tint.cobalt => t.accentSoft,
          _Tint.mint => t.mintSoft,
          _Tint.plain => t.surfaceSunken,
        },
      ),
      title: Text(label),
      subtitle: switch (subtitle) {
        final text? => Text(text),
        null => null,
      },
      trailing: switch (trailing) {
        _Trailing.chevron => const Icon(Icons.chevron_right),
        _Trailing.external => const Icon(Icons.open_in_new, size: 18),
        _Trailing.none => null,
      },
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Nutzungsdaten: the analytics consent of this install, only in builds
/// that can send analytics (the row is hidden otherwise).
class const _UsageDataPage() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('more-usage-data-page'),
    padding: EdgeInsets.only(
      top: HlSpace.s3,
      bottom: HlSpace.s3 + MediaQuery.paddingOf(context).bottom,
    ),
    children: [if (context.read<Analytics>().enabled) const _AnalyticsSwitch()],
  );
}

Future<void> _showLicenses(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (context.mounted) {
    showLicensePage(
      context: context,
      applicationName: AppLocalizations.of(context).appTitle,
      applicationVersion: _versionOf(info),
    );
  }
}

/// The card on top of More while an update is ready; closing it hides it
/// until More is built anew.
class const _UpdateSlot(final AppUpdates updates) extends StatefulWidget {
  @override
  State<_UpdateSlot> createState() => _UpdateSlotState();
}

class _UpdateSlotState() extends State<_UpdateSlot> {
  late final Future<AppUpdate?> _update = widget.updates.available();
  var _closed = false;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _update,
    builder: (context, snapshot) => switch (snapshot.data) {
      final update? when !_closed => Padding(
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s4,
          HlSpace.s4,
          HlSpace.s4,
          0,
        ),
        child: _UpdateCard(
          update,
          onApply: () => unawaited(widget.updates.apply(update)),
          onClose: () => setState(() => _closed = true),
        ),
      ),
      _ => const SizedBox.shrink(),
    },
  );
}

/// Lemon, navy contour, sticker shadow; the same in light and dark.
class const _UpdateCard(
  final AppUpdate update, {
  required final VoidCallback onApply,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final (title, body, action, icon) = switch (update) {
      PatchReady() => (
        l10n.updatePatchTitle,
        l10n.updatePatchBody,
        l10n.updatePatchAction,
        Icons.restart_alt,
      ),
      StoreVersion(:final version) => (
        l10n.updateStoreTitle,
        l10n.updateStoreBody(version),
        l10n.updateStoreAction,
        Icons.system_update_outlined,
      ),
    };
    return HlSticker(
      key: const ValueKey('more-update-card'),
      color: t.honey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s4,
          HlSpace.s3,
          HlSpace.s2,
          HlSpace.s4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: HlSpace.s3,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: HlSpace.s1),
              child: PointyHex(
                face: SnacklistColors.light.surfaceRaised,
                contour: SnacklistColors.light.edge,
                size: 36,
                child: Icon(icon, size: 20, color: SnacklistColors.light.ink),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s1,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: HlSpace.s1),
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: HlType.title.copyWith(color: t.onHoney),
                      ),
                    ),
                  ),
                  Text(body, style: HlType.body.copyWith(color: t.onHoney)),
                  const SizedBox(height: HlSpace.s2),
                  FilledButton(
                    key: const ValueKey('more-update-action'),
                    onPressed: onApply,
                    child: Text(action),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('more-update-later'),
              tooltip: l10n.updateLater,
              icon: Icon(Icons.close, color: t.onHoney),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

String _versionOf(PackageInfo info) => info.buildNumber.isEmpty
    ? info.version
    : '${info.version} (${info.buildNumber})';

/// The analytics consent of this install (job 19): off stops sending at
/// once and drops what waits.
class const _AnalyticsSwitch() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consent = context.select<Analytics, bool>(
      (a) => a.state.consent ?? false,
    );
    return HexSwitchTile(
      key: const ValueKey('more-analytics'),
      title: Text(l10n.analyticsToggle),
      subtitle: Text(l10n.analyticsToggleHint),
      isThreeLine: true,
      value: consent,
      onChanged: (on) =>
          unawaited(context.read<Analytics>().decide(granted: on)),
    );
  }
}

/// The version; a long press marks this install internal (or not), so a
/// test phone's events are filtered out of the gate insights. An internal
/// install can raise a test error for error tracking.
class const _Version() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final internal = context.select<Analytics, bool>(
      (a) => a.state.internalInstall,
    );
    return Column(
      children: [
        GestureDetector(
          // The whole row, padding included, takes the long press.
          behavior: HitTestBehavior.opaque,
          onLongPress: () => unawaited(
            context.read<Analytics>().markInternalInstall(internal: !internal),
          ),
          child: FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                switch (snapshot.data) {
                  final info? => l10n.appVersion(_versionOf(info)),
                  null => '',
                },
                key: const ValueKey('more-version'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        if (internal) ...[
          Text(
            l10n.internalInstall,
            key: const ValueKey('more-internal'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (context.read<Analytics>().flagInstallId case final id?)
            TextButton(
              key: const ValueKey('more-install-id'),
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: id)));
                Notices.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.copied)));
              },
              child: Text(l10n.copyInstallId(id)),
            ),
          TextButton(
            key: const ValueKey('more-test-error'),
            onPressed: _raiseTestError,
            child: Text(l10n.sendTestError),
          ),
        ],
      ],
    );
  }

  /// Thrown outside any handler, so it takes the path a real crash takes.
  static void _raiseTestError() => Timer.run(
    () => throw StateError('Snacklist test error (More, internal install)'),
  );
}
