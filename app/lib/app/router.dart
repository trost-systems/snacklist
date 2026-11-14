import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/consent_screen.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/deep_links.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/invite_partner_screen.dart';
import 'package:family_groceries/household/join_request_waiting.dart';
import 'package:family_groceries/household/join_screen.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/welcome_screen.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/store_details_screen.dart';
import 'package:family_groceries/list/stores_screen.dart';
import 'package:family_groceries/log/history_screen.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/oauth/consent_screen.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/start_screen.dart';
import 'package:family_groceries/onboarding/steps.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/trip/summary_page.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

const listPath = '/';

/// App links to the list (job 66): the list itself, with the add sheet
/// open, or at a store (`/stores/<id>`, [listLinkOf]).
const listLinkPath = '/list';
const addPath = '/add';
const loginPath = '/login';

/// Where a provider sign-in on the web returns from the sign-in screen
/// (job 168b): the sign-in itself, which shows a cancel or a failure; `/`
/// opens the guided start.
const signInReturnPath = loginPath;

/// The List tab's Anpassen (job 78): the stores screen, and below it one
/// store's details or, for [noStoreSegment], the categories of the section
/// without a store.
const editPath = '/edit';
const noStoreSegment = 'none';
String storeDetailsPath(String? storeId) =>
    '$editPath/${storeId ?? noStoreSegment}';

/// Signed in without a household (job 22): create one (the guided start
/// from [onboardingWhoPath]) or join with a code ([joinCodePath],
/// [joinPath]).
const welcomePath = '/welcome';

/// Waiting for a join request (job 169b W3 M), instead of [welcomePath]
/// while the user has no household but a request ([PendingJoinScreen]).
const joinWaitingPath = '/welcome/waiting';

/// The guided start (job 168b): the first screen signed out, „Los geht's“
/// or „Schon ein Konto? Anmelden“.
const startPath = '/start';

/// The guided start's step [step], at `/start/<step>`.
String onboardingPath(OnboardingStep step) => '$startPath/${step.name}';

/// „Mit wem kaufst du ein?“, where creating a household starts.
final onboardingWhoPath = onboardingPath(OnboardingStep.who);

/// The guided start's step at [uri], or null.
OnboardingStep? onboardingStepOf(Uri uri) => switch (uri.pathSegments) {
  ['start', final step] => OnboardingStep.parse(step),
  _ => null,
};

/// The switcher's "Neuer Haushalt" (job 169b): the create step for one
/// more household, then its invite step ([invitePartnerPath]).
const newHouseholdPath = '/households/new';
const invitePartnerPath = '/households/new/invite';

/// The join screen for a typed code: onboarding's "Einladung annehmen" and
/// the household sheet's "Mit Code beitreten".
const joinCodePath = '/join';

/// The analytics consent (job 19), asked once per install right after the
/// first sign-in. Not [consentPath], which is MCP's OAuth consent.
const analyticsConsentPath = '/analytics-consent';
const consentPath = '/oauth/consent';
const morePath = '/more';

/// The Verlauf tab (job 199): the grocery log, only while the flag
/// `grocery-log` is on; otherwise the path goes to the list.
const historyPath = '/history';

/// A trip-mode trip's summary (job 234): in the List tab after its end or
/// from the list's card, in Verlauf from one of its entries.
String tripSummaryPath(String id) => '/trip/$id';
String historyTripPath(String id) => '$historyPath/trip/$id';

/// Whether [location] is a trip summary, in either tab.
bool inTripSummary(Uri location) => switch (location.pathSegments) {
  ['trip', _] || ['history', 'trip', _] => true,
  _ => false,
};

/// More's Zugänge: the MCP server, tokens and connected apps.
const accessPath = '/more/access';

/// More's Konto: export and account deletion.
const accountPath = '/more/account';

/// More's Einladungen: invite the partner, the open invites, revoke one.
const invitesPath = '/more/invites';

/// More's Haushalt (job 169b): the shown household's name, members, the
/// default for Siri, Alexa & KI, and leaving it.
const householdPath = '/more/household';

/// More's Snacklist Premium: the purchase of either plan, its restore and
/// the household's premium status. The path and its screen name stay
/// `lifetime` from before job 49, so links and analytics keep their name.
const premiumPath = '/more/lifetime';

/// More's Tipps: every hint of the List tab, to read again (job 168b).
const tipsPath = '/more/tips';

/// More's Einstellungen: theme and language.
const appSettingsPath = '/more/settings';

/// The language list below Einstellungen.
const languagePath = '/more/settings/language';

/// More's Nutzungsdaten: the usage-data switch.
const usageDataPath = '/more/usage-data';

/// A Rechtliches page More had before its rows moved onto More itself
/// (job 85); old links land on More.
const moreLegalPath = '/more/legal';

/// The join screen inside More (job 78) while More had „Anderem Haushalt
/// beitreten“; joining is the household sheet's since job 206. Old links
/// land on [joinCodePath].
const moreJoinPath = '/more/join';

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
  'history',
  'trip_summary',
  'access',
  'account',
  'invites',
  'household',
  'lifetime',
  'settings',
  'language',
  'usage_data',
  'tips',
  'login',
  'welcome',
  'start',
  // One per OnboardingStep, 'onboarding_<step>' ([screenNameOf]).
  'onboarding_usage',
  'onboarding_who',
  'onboarding_name',
  'onboarding_stores',
  'onboarding_need',
  'onboarding_account',
  'onboarding_setup',
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
String screenNameOf(Uri location) {
  if (onboardingStepOf(location) case final step?) {
    return 'onboarding_${step.name}';
  }
  return _screenNameOfPath(location);
}

String _screenNameOfPath(Uri location) => switch (location.path) {
  listPath || '' => 'list',
  _ when location.pathSegments.firstOrNull == 'edit' => 'stores',
  morePath => 'more',
  historyPath => 'history',
  _ when inTripSummary(location) => 'trip_summary',
  accessPath => 'access',
  accountPath => 'account',
  invitesPath => 'invites',
  householdPath => 'household',
  premiumPath => 'lifetime',
  appSettingsPath => 'settings',
  languagePath => 'language',
  usageDataPath => 'usage_data',
  tipsPath => 'tips',
  settingsPath when location.queryParameters['section'] == 'account' =>
    'account',
  settingsPath => 'access',
  loginPath => 'login',
  welcomePath => 'welcome',
  startPath => 'start',
  invitePartnerPath => 'onboarding_invite',
  newHouseholdPath => 'new_household',
  analyticsConsentPath => 'analytics_consent',
  consentPath => 'oauth_consent',
  joinWaitingPath => 'join',
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
  tipsPath,
  moreLegalPath,
  moreJoinPath,
}.contains(location.path);

/// Whether [location] is one of the List tab's Anpassen pages: the stores
/// at [editPath], one store's details below it.
bool inListTab(Uri location) {
  final segments = location.pathSegments;
  return segments.firstOrNull == 'edit' && segments.length <= 2;
}

/// Where the user lives, past every gate before it (sign-in, the analytics
/// consent, the guided start, a join, an OAuth consent, a new household's
/// setup): the list and More tabs, and without a household the welcome and
/// waiting screens. Notices no tap asked for wait for these (Legal N-114):
/// on a gate they would cover its answers and run out while it is read.
bool atHome(Uri location) =>
    location.path == listPath ||
    location.path == historyPath ||
    inTripSummary(location) ||
    inListTab(location) ||
    inMoreTab(location) ||
    location.path == welcomePath ||
    location.path == joinWaitingPath;

/// The invite code in [uri]: a `/join/<code>` link's or one carried as
/// `?invite=`.
String? inviteIn(Uri uri) {
  final segments = uri.pathSegments;
  return segments.length == 2 && segments.first == 'join'
      ? segments[1]
      : uri.queryParameters['invite'];
}

/// Where someone without a household may be: the steps before there is
/// one.
const _beforeHousehold = {welcomePath, joinCodePath, joinWaitingPath};

/// The only auth gate. An invite code from a `/join/<code>` link survives
/// sign-in, the analytics consent and onboarding as the `invite` query
/// parameter and as [pendingInvite] (kept on the device, for when the
/// location loses it: the mobile apps' sign-in callback, an app kill). The
/// `next` query parameter carries an OAuth consent URL or an app link's
/// location (job 66, [appLinks]), [pendingNext] the link when the location
/// lost it. [justSignedOut]: the user signed out here, which carries no
/// link to the next sign-in.
///
/// Signed out (job 168b): the guided start ([startPath]), and with a [draft]
/// its step (the screens move on by changing the draft, never by going to a
/// step), or the sign-in for an invite, a link, after a sign-out and when
/// the user picks it ([goToSignIn]). [askConsent]:
/// this install has not decided on analytics yet. The guided start asks it
/// as its first step; signed in, it comes first, before onboarding and
/// before the list, except in a browser tab authorizing an MCP client
/// (`next`), and the app asks the next time it is opened.
///
/// Without a household: a [draft] past its last question is set up
/// ([OnboardingStep.setup]) and one before it resumed; otherwise
/// [welcomePath], or [joinWaitingPath] instead while a join request waits,
/// or the join screen at once for an invite. In one: the list and its
/// Anpassen pages, the More tab, the join screen for an invite, creating
/// one more ([newHouseholdPath]) and its invite step ([invitePartnerPath]),
/// and the draft's invite step until it is left. A draft not set up yet is
/// set up in the household the user is in (its items go on that list).
String? authRedirect(
  Session session,
  Uri uri, {
  bool askConsent = false,
  String? pendingInvite,
  String? pendingNext,
  bool justSignedOut = false,
  OnboardingDraft? draft,
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
  // A draft whose household exists is the invite step of that household
  // only; the cubit drops it for any other session.
  final pending = switch ((draft, session)) {
    (final d?, _) when !d.created => d,
    (final d?, InHousehold(:final household))
        when d.householdId == household.id =>
      d,
    _ => null,
  };
  // Where the draft resumes: the usage question only while it is open.
  OnboardingStep resumeAt(OnboardingDraft d, {required bool signedIn}) =>
      switch (d.step) {
        OnboardingStep.usage when !askConsent => OnboardingStep.who,
        OnboardingStep.usage when signedIn => OnboardingStep.who,
        final s when !signedIn && !s.beforeAccount => OnboardingStep.account,
        final s => s,
      };
  final target = switch (session) {
    SessionLoading() => null,
    SignedOut(:final deleted)
        when invite != null ||
            next != null ||
            justSignedOut ||
            deleted != null ||
            uri.path == loginPath =>
      carry(loginPath),
    SignedOut() when pending != null => onboardingPath(
      resumeAt(pending, signedIn: false),
    ),
    SignedOut() => startPath,
    NeedsHousehold() || InHousehold() when askConsent && consent == null =>
      carry(analyticsConsentPath),
    NeedsHousehold() when invite != null => carry(joinPath(invite)),
    // An MCP authorization or a link (`next`) rides along the steps. A
    // draft leads a waiting join request: it is how the waiting screen's
    // „Eigenen Haushalt erstellen“ goes on (job 168c).
    NeedsHousehold() when pending != null && !pending.beforeSignIn => carry(
      onboardingPath(OnboardingStep.setup),
    ),
    NeedsHousehold() when pending != null => carry(
      onboardingPath(resumeAt(pending, signedIn: true)),
    ),
    NeedsHousehold(requests: []) when uri.path == joinWaitingPath => carry(
      welcomePath,
    ),
    NeedsHousehold(requests: [_, ...]) when uri.path == welcomePath => carry(
      joinWaitingPath,
    ),
    NeedsHousehold() when _beforeHousehold.contains(uri.path) => carry(
      uri.path,
    ),
    NeedsHousehold(requests: []) => carry(welcomePath),
    NeedsHousehold() => carry(joinWaitingPath),
    // A household of its own, its questions not done, and a join request
    // approved meanwhile (job 168c): the questions go on.
    InHousehold(:final userId)
        when pending != null &&
            pending.ownFor(userId) &&
            pending.step.beforeAccount =>
      carry(onboardingPath(resumeAt(pending, signedIn: true))),
    // Before `next`: the setup finishes before anything else opens.
    InHousehold()
        when pending != null &&
            (!pending.created || pending.step != OnboardingStep.invite) =>
      carry(onboardingPath(OnboardingStep.setup)),
    InHousehold() when next != null => next,
    InHousehold() when invite != null => joinPath(invite),
    InHousehold()
        when uri.path == invitePartnerPath ||
            uri.path == newHouseholdPath ||
            uri.path == joinCodePath ||
            inMoreTab(uri) ||
            inListTab(uri) ||
            inTripSummary(uri) ||
            uri.path == historyPath =>
      uri.toString(),
    // Where the list would open: a link (`next`) went first and stays.
    InHousehold() when pending != null => onboardingPath(OnboardingStep.invite),
    InHousehold() => listPath,
  };
  return target == null || target == uri.toString() ? null : target;
}

/// The sign-in, when the user picks it (the guided start's „Anmelden“):
/// [authRedirect] keeps a signed-out user there.
void goToSignIn(BuildContext context) => context.go(loginPath);

/// The guided start's first screen, from the sign-in's „Neu bei
/// Snacklist?“: with a draft, [authRedirect] resumes it.
void goToStart(BuildContext context) => context.go(startPath);

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
    OnboardingDraft? draft,
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
      draft: draft,
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
        path: 'trip/:id',
        redirect: _withTripMode,
        builder: (_, state) => TripSummaryPage(id: state.pathParameters['id']!),
      ),
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
        ('tips', MorePage.tips),
      ])
        GoRoute(
          path: path,
          builder: (_, state) => MoreScreen(
            page: page,
            paywallEntry: PaywallEntry.parse(state.uri.queryParameters['from']),
          ),
        ),
      GoRoute(path: 'join', redirect: (_, _) => joinCodePath),
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

/// The Verlauf tab's route; with the flag off it is the list.
List<RouteBase> historyTabRoutes() => [
  GoRoute(
    path: historyPath,
    redirect: (context, _) =>
        context.read<Flags?>()?.isOn(groceryLogFlag) ?? false ? null : listPath,
    builder: (_, _) => const HistoryScreen(),
    routes: [
      GoRoute(
        path: 'trip/:id',
        redirect: _withTripMode,
        builder: (_, state) => TripSummaryPage(id: state.pathParameters['id']!),
      ),
    ],
  ),
];

/// A trip summary's link with the flag `trip-mode` off is the list.
String? _withTripMode(BuildContext context, GoRouterState _) =>
    context.read<Flags?>()?.isOn(tripModeFlag) ?? false ? null : listPath;

/// Every route of the app; [repositories], [trips] and [tripSessions]
/// override the Supabase list repository and trips per household, for
/// tests.
List<RouteBase> appRoutes({
  ListRepository Function(String householdId)? repositories,
  TripRepository Function(String householdId)? trips,
  TripSessionRepository Function(String householdId)? tripSessions,
}) => [
  StatefulShellRoute.indexedStack(
    builder: (_, _, shell) => AppShell(
      shell: shell,
      repositories: repositories,
      trips: trips,
      tripSessions: tripSessions,
    ),
    // The shell's tabs keep these branch indices; Verlauf shows between
    // Liste and Mehr (`_Destination`).
    branches: [
      StatefulShellBranch(routes: listTabRoutes()),
      StatefulShellBranch(routes: moreTabRoutes()),
      StatefulShellBranch(routes: historyTabRoutes()),
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
      GoRoute(path: 'waiting', builder: (_, _) => const PendingJoinScreen()),
    ],
  ),
  GoRoute(
    path: startPath,
    builder: (_, _) => const StartScreen(),
    routes: [
      for (final step in OnboardingStep.values)
        GoRoute(path: step.name, builder: (_, _) => onboardingStepScreen(step)),
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
  GoRoute(
    path: invitePartnerPath,
    builder: (_, _) => const InvitePartnerScreen(),
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
  OnboardingCubit onboarding,
) {
  final memory = RedirectMemory();
  return GoRouter(
    observers: [popups],
    refreshListenable: Listenable.merge([
      _StreamListenable(session.stream),
      _StreamListenable(analytics.stream),
      _StreamListenable(onboarding.stream),
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
        draft: onboarding.state,
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
