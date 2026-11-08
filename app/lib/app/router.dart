import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/consent_screen.dart';
import 'package:family_groceries/app/deep_links.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/invite_partner_screen.dart';
import 'package:family_groceries/household/join_screen.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/welcome_screen.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/store_details_screen.dart';
import 'package:family_groceries/list/stores_screen.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/oauth/consent_screen.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

const listPath = '/';

/// App links to the list (job 66): the list itself, with the add sheet
/// open, or at a store (`/stores/<id>`, [listLinkOf]).
const listLinkPath = '/list';
const addPath = '/add';
const loginPath = '/login';

/// The List tab's Anpassen (job 78): the stores screen, and below it one
/// store's details or, for [noStoreSegment], the categories of the section
/// without a store.
const editPath = '/edit';
const noStoreSegment = 'none';
String storeDetailsPath(String? storeId) =>
    '$editPath/${storeId ?? noStoreSegment}';

/// Onboarding (job 22): Step 1 chooses, Step 2a creates, Step 3 invites
/// the partner; Step 2b is the join screen ([joinCodePath], [joinPath]).
const welcomePath = '/welcome';
const createHouseholdPath = '/welcome/create';
const invitePartnerPath = '/welcome/invite';

/// The switcher's "Neuer Haushalt" (job 169b): the create step for one
/// more household, then Step 3 for it.
const newHouseholdPath = '/households/new';

/// The join screen for a typed code: onboarding's "Einladung annehmen" and
/// More's "Anderem Haushalt beitreten".
const joinCodePath = '/join';

/// More's „Anderem Haushalt beitreten“: the join screen inside the More
/// tab, so back returns to More (job 78).
const moreJoinPath = '/more/join';

/// The analytics consent (job 19), asked once per install right after the
/// first sign-in. Not [consentPath], which is MCP's OAuth consent.
const analyticsConsentPath = '/analytics-consent';
const consentPath = '/oauth/consent';
const morePath = '/more';

/// More's Zugänge: the MCP server, tokens and connected apps.
const accessPath = '/more/access';

/// More's Konto: export and account deletion.
const accountPath = '/more/account';

/// More's Einladungen: invite the partner, the open invites, revoke one.
const invitesPath = '/more/invites';

/// More's Haushalt (job 169b): the shown household's name, members, the
/// default for Siri, Alexa & KI, and leaving it.
const householdPath = '/more/household';

/// More's Hummlist Premium: the purchase of either plan, its restore and
/// the household's premium status. The path and its screen name stay
/// `lifetime` from before job 49, so links and analytics keep their name.
const premiumPath = '/more/lifetime';

/// More's Einstellungen: theme and language.
const appSettingsPath = '/more/settings';

/// The language list below Einstellungen.
const languagePath = '/more/settings/language';

/// More's Nutzungsdaten: the usage-data switch.
const usageDataPath = '/more/usage-data';

/// A Rechtliches page More had before its rows moved onto More itself
/// (job 85); old links land on More.
const moreLegalPath = '/more/legal';

/// Before job 29d both were one page here (Konto at `?section=account`);
/// old links redirect ([legacySettingsRedirect]).
const settingsPath = '/settings';
String joinPath(String code) => '/join/$code';

/// The fixed screen names feedback and analytics report (job 21): a
/// route's name, never its path, so an invite code or anything typed can't
/// get in. Sheets (add, edit) report the route under them; the List tab's
/// Anpassen pages are `stores`, never a store's id.
const screenNames = {
  'list',
  'stores',
  'more',
  'access',
  'account',
  'invites',
  'household',
  'lifetime',
  'settings',
  'language',
  'usage_data',
  'login',
  'welcome',
  'onboarding_create',
  'onboarding_invite',
  'new_household',
  'analytics_consent',
  'oauth_consent',
  'join',
  'other',
};

/// The screen name of a router [location]: `/join/<code>` (and `/join`) is
/// `join`, an
/// unknown path `other`. Query parameters are ignored, except an old
/// `/settings` link's section (it redirects to Zugänge or Konto).
String screenNameOf(Uri location) => switch (location.path) {
  listPath || '' => 'list',
  _ when location.pathSegments.firstOrNull == 'edit' => 'stores',
  morePath => 'more',
  accessPath => 'access',
  accountPath => 'account',
  invitesPath => 'invites',
  householdPath => 'household',
  premiumPath => 'lifetime',
  appSettingsPath => 'settings',
  languagePath => 'language',
  usageDataPath => 'usage_data',
  settingsPath when location.queryParameters['section'] == 'account' =>
    'account',
  settingsPath => 'access',
  loginPath => 'login',
  welcomePath => 'welcome',
  createHouseholdPath => 'onboarding_create',
  invitePartnerPath => 'onboarding_invite',
  newHouseholdPath => 'new_household',
  analyticsConsentPath => 'analytics_consent',
  consentPath => 'oauth_consent',
  moreJoinPath => 'join',
  _ when location.pathSegments.firstOrNull == 'join' => 'join',
  _ => 'other',
};

/// Whether [location] is in the More tab (More itself or one of its
/// pages); the list is `/` itself, with its Anpassen pages below
/// ([inListTab]). Signed in, any other shell path goes to the list.
bool inMoreTab(Uri location) => const {
  settingsPath,
  morePath,
  accessPath,
  accountPath,
  invitesPath,
  householdPath,
  premiumPath,
  appSettingsPath,
  languagePath,
  usageDataPath,
  moreLegalPath,
  moreJoinPath,
}.contains(location.path);

/// Whether [location] is one of the List tab's Anpassen pages: the stores
/// at [editPath], one store's details below it.
bool inListTab(Uri location) {
  final segments = location.pathSegments;
  return segments.firstOrNull == 'edit' && segments.length <= 2;
}

/// The invite code in [uri]: a `/join/<code>` link's or one carried as
/// `?invite=`.
String? inviteIn(Uri uri) {
  final segments = uri.pathSegments;
  return segments.length == 2 && segments.first == 'join'
      ? segments[1]
      : uri.queryParameters['invite'];
}

/// Where someone without a household may be: onboarding's steps before
/// there is one.
const _beforeHousehold = {welcomePath, createHouseholdPath, joinCodePath};

/// The only auth gate. An invite code from a `/join/<code>` link survives
/// sign-in, the analytics consent and onboarding as the `invite` query
/// parameter and as [pendingInvite] (kept on the device, for when the
/// location loses it: the mobile apps' sign-in callback, an app kill). The
/// `next` query parameter carries an OAuth consent URL or an app link's
/// location (job 66, [appLinks]), [pendingNext] the link when the location
/// lost it. [justSignedOut]: the user signed out here, which carries no
/// link to the next sign-in.
///
/// [askConsent]: this install has not decided on analytics yet. Signed in,
/// it goes to the analytics consent first, before onboarding and before the
/// list; a browser tab authorizing an MCP client (`next`) is not
/// interrupted and the app asks the next time it is opened.
///
/// Without a household: Step 1 ([welcomePath]), or the join screen at once
/// for an invite. In one: the list and its Anpassen pages, the More tab,
/// Step 3 right after creating ([invitePartnerPath]), creating one more
/// ([newHouseholdPath]), or the join screen for an invite.
String? authRedirect(
  Session session,
  Uri uri, {
  bool askConsent = false,
  String? pendingInvite,
  String? pendingNext,
  bool justSignedOut = false,
}) {
  final invite = inviteIn(uri) ?? pendingInvite;
  final consent = uri.path == consentPath
      ? uri.toString()
      : _vetted(
          uri.queryParameters['next'],
          (next) => next.path == consentPath,
        );
  // Signed in, a link location is the screen itself, never a `next`.
  final link = justSignedOut || invite != null
      ? null
      : _vetted(uri.queryParameters['next'], _continues) ??
            (session is InHousehold ? null : _linkHere(uri)) ??
            pendingNext;
  final next = consent ?? link;
  String carry(String path) => next != null
      ? Uri(path: path, queryParameters: {'next': next}).toString()
      : invite != null && inviteIn(Uri(path: path)) == null
      ? '$path?invite=$invite'
      : path;
  final target = switch (session) {
    SessionLoading() => null,
    SignedOut() => carry(loginPath),
    NeedsHousehold() || InHousehold() when askConsent && consent == null =>
      carry(analyticsConsentPath),
    NeedsHousehold() when invite != null => carry(joinPath(invite)),
    // An MCP authorization or a link (`next`) rides along onboarding's
    // steps.
    NeedsHousehold() when _beforeHousehold.contains(uri.path) => carry(
      uri.path,
    ),
    NeedsHousehold() => carry(welcomePath),
    InHousehold() when next != null => next,
    InHousehold() when invite != null => joinPath(invite),
    // Created just now: Step 3, inviting the partner.
    InHousehold() when uri.path == createHouseholdPath => invitePartnerPath,
    InHousehold()
        when uri.path == invitePartnerPath ||
            uri.path == newHouseholdPath ||
            uri.path == joinCodePath ||
            inMoreTab(uri) ||
            inListTab(uri) =>
      uri.toString(),
    InHousehold() => listPath,
  };
  return target == null || target == uri.toString() ? null : target;
}

/// Where an old `/settings` link goes now: Konto for `?section=account`,
/// Zugänge otherwise.
String legacySettingsRedirect(Uri uri) =>
    uri.queryParameters['section'] == 'account' ? accountPath : accessPath;

/// [next] if it is a same-origin location that [allowed] takes, or null:
/// `next` must not become an open redirect.
String? _vetted(String? next, bool Function(Uri next) allowed) {
  final uri = next == null ? null : Uri.tryParse(next);
  return uri != null && !uri.hasScheme && !uri.hasAuthority && allowed(uri)
      ? next
      : null;
}

/// An app link sign-in continues to, if it leads to a screen: an invite
/// link goes by its code.
bool _continues(Uri location) =>
    isAppLink(location) &&
    (location.path == listLinkPath ||
        listLinkOf(location) != null ||
        inMoreTab(location));

/// [uri] itself as a `next`, without the platform's scheme and host, if it
/// is a link sign-in continues to.
String? _linkHere(Uri uri) {
  final here = Uri(path: uri.path, query: uri.hasQuery ? uri.query : null);
  return _continues(here) ? here.toString() : null;
}

/// What the redirect keeps between its runs: the session it saw last, to
/// tell a sign-out, and a link's location while signed out. In memory
/// only: a sign-in that leaves the app (a magic link, Apple on Android)
/// comes back to the same process at `/`.
class RedirectMemory() {
  Session? _last;
  String? _next;

  /// [authRedirect] with what this remembers.
  String? redirect(
    Session session,
    Uri uri, {
    bool askConsent = false,
    String? pendingInvite,
  }) {
    final justSignedOut =
        session is SignedOut &&
        (_last is NeedsHousehold || _last is InHousehold);
    _last = session;
    if (justSignedOut) {
      _next = null;
    } else if (session is SignedOut) {
      _next =
          _vetted(uri.queryParameters['next'], _continues) ??
          _linkHere(uri) ??
          _next;
    }
    final target = authRedirect(
      session,
      uri,
      askConsent: askConsent,
      pendingInvite: pendingInvite,
      pendingNext: _next,
      justSignedOut: justSignedOut,
    );
    // Signed in, the link is in the location now (or was the location).
    if (session is InHousehold) {
      _next = null;
    }
    return target;
  }
}

/// The List tab's routes: the list at `/`, its Anpassen pages below it
/// ([editPath], [storeDetailsPath]), so back pops to the list.
List<RouteBase> listTabRoutes() => [
  GoRoute(
    path: listPath,
    builder: (_, _) => const ListScreen(),
    routes: [
      GoRoute(
        path: editPath.substring(1),
        builder: (_, _) => const StoresScreen(),
        routes: [
          GoRoute(
            path: ':store',
            builder: (_, state) => StoreDetailsScreen(
              storeId: switch (state.pathParameters['store']) {
                noStoreSegment => null,
                final id => id,
              },
            ),
          ),
        ],
      ),
    ],
  ),
];

/// The More tab's routes: the list at `/more` with its pages below it, so
/// back pops to the list, and the redirect for old `/settings` links.
List<RouteBase> moreTabRoutes() => [
  GoRoute(
    path: morePath,
    builder: (_, _) => const MoreScreen(),
    routes: [
      for (final (path, page) in const [
        ('access', MorePage.access),
        ('account', MorePage.account),
        ('invites', MorePage.invites),
        ('household', MorePage.household),
        ('lifetime', MorePage.premium),
        ('usage-data', MorePage.usageData),
      ])
        GoRoute(
          path: path,
          builder: (_, state) => MoreScreen(
            page: page,
            paywallEntry: PaywallEntry.parse(state.uri.queryParameters['from']),
          ),
        ),
      GoRoute(path: 'join', builder: (_, _) => const JoinScreen()),
      GoRoute(path: 'legal', redirect: (_, _) => morePath),
      GoRoute(
        path: 'settings',
        builder: (_, _) => const MoreScreen(page: MorePage.settings),
        routes: [
          GoRoute(
            path: 'language',
            builder: (_, _) => const MoreScreen(page: MorePage.language),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: settingsPath,
    redirect: (_, state) => legacySettingsRedirect(state.uri),
  ),
];

/// Every route of the app; [repositories] overrides the Supabase list
/// repository per household, for tests.
List<RouteBase> appRoutes({
  ListRepository Function(String householdId)? repositories,
}) => [
  StatefulShellRoute.indexedStack(
    builder: (_, _, shell) =>
        AppShell(shell: shell, repositories: repositories),
    branches: [
      StatefulShellBranch(routes: listTabRoutes()),
      StatefulShellBranch(routes: moreTabRoutes()),
    ],
  ),
  GoRoute(
    path: loginPath,
    builder: (_, state) => LoginScreen(
      invite: state.uri.queryParameters['invite'],
      next: state.uri.queryParameters['next'],
    ),
  ),
  GoRoute(
    path: analyticsConsentPath,
    builder: (_, _) => const AnalyticsConsentScreen(),
  ),
  GoRoute(
    path: welcomePath,
    builder: (_, _) => const WelcomeScreen(),
    routes: [
      GoRoute(path: 'create', builder: (_, _) => const CreateHouseholdScreen()),
      GoRoute(path: 'invite', builder: (_, _) => const InvitePartnerScreen()),
    ],
  ),
  GoRoute(
    path: consentPath,
    builder: (_, state) => ConsentScreen(
      authorizationId: state.uri.queryParameters['authorization_id'],
    ),
  ),
  // Only ever a step: the redirect goes on to the list, which then opens
  // the sheet or the store. Routes, so that a redirect to one (a sign-in's
  // `next`) is redirected again; the App shows a spinner while loading.
  for (final path in const [listLinkPath, addPath, '/stores/:id'])
    GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
  GoRoute(
    path: newHouseholdPath,
    builder: (_, _) =>
        const CreateHouseholdScreen(from: HouseholdOrigin.switcher),
  ),
  GoRoute(path: joinCodePath, builder: (_, _) => const JoinScreen()),
  GoRoute(
    path: '/join/:code',
    builder: (_, state) => JoinScreen(link: state.pathParameters['code']),
  ),
];

GoRouter buildRouter(
  SessionCubit session,
  Analytics analytics,
  PendingInvite pendingInvite,
  ListLinks listLinks,
  Popups popups,
) {
  final memory = RedirectMemory();
  return GoRouter(
    observers: [popups],
    refreshListenable: Listenable.merge([
      _StreamListenable(session.stream),
      _StreamListenable(analytics.stream),
    ]),
    redirect: (context, state) {
      // A link's code is kept the moment it arrives, before sign-in.
      if (inviteIn(state.uri) case final code?) {
        pendingInvite.remember(code);
      }
      final target = memory.redirect(
        session.state,
        state.uri,
        askConsent: analytics.asksConsent,
        pendingInvite: pendingInvite.code,
      );
      // Only once in the household: a sign-in or consent on the way would
      // fire it early.
      if (session.state is InHousehold && target == listPath) {
        if (listLinkOf(state.uri) case final link?) {
          listLinks.pending = link;
        }
      }
      return target;
    },
    routes: appRoutes(),
  );
}

class _StreamListenable(Stream<Object?> stream) extends ChangeNotifier {
  this {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
