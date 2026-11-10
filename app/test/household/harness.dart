import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/household_page.dart';
import 'package:family_groceries/household/invite_partner_screen.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invites_page.dart';
import 'package:family_groceries/household/join_request_waiting.dart';
import 'package:family_groceries/household/join_screen.dart';
import 'package:family_groceries/household/paste_invite.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/welcome_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/start_screen.dart';
import 'package:family_groceries/onboarding/steps.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../analytics/fakes.dart';
import '../purchases/fakes.dart';
import '../session/fake_auth.dart';
import '../settings/fake_account.dart';

const home = Household(id: 'home', name: 'Zuhause', isDefault: true);

/// The user in [home] only.
const inHome = InHousehold('peter', home, [home]);

/// The server's invites, answered without a network. [next] makes the next
/// call fail with that problem (once).
class FakeInvites() implements InviteRepository {
  /// Code to the household it leads to.
  final households = <String, String>{'ABCD2345': 'Familie Trost'};

  /// Codes of the household the user is in.
  final own = <String>{};

  /// What `preview_invite` says about Snacklist Lifetime, by code.
  final lifetime = <String, JoinLifetime>{};

  /// Each household's members, by household id.
  final memberLists = <String, List<HouseholdMember>>{};

  /// Households whose Snacklist Premium ends when the last member leaves.
  final unlocked = <String>{};
  final created = <Invite>[];
  final revoked = <String>[];

  /// Who joined with each invite, by invite id.
  final joinLists = <String, List<InviteJoin>>{};

  /// Each removal and role change: household, user (and role).
  final removed = <(String, String)>[];
  final roles = <(String, String, HouseholdRole)>[];

  /// The sheets watching joins, by household: call one to say someone
  /// joined.
  final previews = <String>[];
  HouseholdProblem? next;
  var _n = 0;

  /// Calls wait for this, so a test can tap twice while one is out.
  Completer<void>? hold;

  /// How often the open invites were asked for.
  var loads = 0;

  /// Loads answer what was open when they were asked, once this completes:
  /// a slow answer that arrives after a revoke.
  Completer<void>? slowLoads;

  Future<void> _answer() async {
    await hold?.future;
    if (next case final problem?) {
      next = null;
      throw HouseholdError(problem);
    }
  }

  @override
  Future<Invite> create(
    String householdId, {
    InviteKind kind = InviteKind.person,
  }) async {
    await _answer();
    if (kind == InviteKind.group) {
      if (created
              .where((i) => i.kind == kind && !revoked.contains(i.id))
              .firstOrNull
          case final open?) {
        return open;
      }
    }
    final invite = Invite(
      id: 'invite-${++_n}',
      code: 'NEWCODE${'XYZ'[_n % 3]}',
      expiresAt: kind == InviteKind.group
          ? DateTime.utc(2026, 12, 8, 9, 30)
          : DateTime.utc(2026, 11, 6, 9, 30),
      kind: kind,
      maxUses: kind == InviteKind.group ? 50 : 1,
    );
    created.add(invite);
    return invite;
  }

  @override
  Future<List<Invite>> open(String householdId) async {
    loads++;
    List<Invite> now() => [
      for (final i in created.reversed)
        if (!revoked.contains(i.id)) i,
    ];
    if (slowLoads case final slow?) {
      final then = now();
      await slow.future;
      return then;
    }
    await _answer();
    return now();
  }

  @override
  Future<List<InviteJoin>> joins(String inviteId) async {
    await _answer();
    return [...?joinLists[inviteId]];
  }

  @override
  Future<void> removeMember(String householdId, String userId) async {
    removed.add((householdId, userId));
    await _answer();
    if (memberLists[householdId] case final members?) {
      memberLists[householdId] = [
        for (final m in members)
          if (m.userId != userId) m,
      ];
    }
  }

  @override
  Future<void> setRole(
    String householdId,
    String userId,
    HouseholdRole role,
  ) async {
    roles.add((householdId, userId, role));
    await _answer();
    final members = memberLists[householdId];
    if (members != null) {
      memberLists[householdId] = [
        for (final m in members)
          if (m.userId == userId)
            HouseholdMember(
              userId: m.userId,
              displayName: m.displayName,
              role: role,
            )
          else
            m,
      ];
    }
  }

  @override
  Future<void> revoke(String inviteId) async {
    await _answer();
    revoked.add(inviteId);
  }

  @override
  Future<InvitePreview> preview(String code) async {
    previews.add(code);
    await _answer();
    final name = households[code];
    if (name == null) {
      throw const HouseholdError(HouseholdProblem.invalidInvite);
    }
    return own.contains(code)
        ? InviteMember(name)
        : InviteOpen(name, lifetime: lifetime[code] ?? const JoinLifetime());
  }

  @override
  Future<List<HouseholdMember>> members(String householdId) async {
    await _answer();
    return memberLists[householdId] ??
        const [HouseholdMember(userId: 'peter', displayName: 'Peter')];
  }

  @override
  Future<bool> leavesUnlocked(String householdId) async {
    await _answer();
    return unlocked.contains(householdId);
  }

  /// The user's archived households (job 43).
  final archivedNow = <ArchivedHousehold>[];

  /// Join requests waiting, by household (job 169b W3 M).
  final requestLists = <String, List<PendingJoin>>{};

  /// Each approval switch turned: household and value.
  final approvals = <(String, bool)>[];

  /// Each decision: request and whether it lets them in.
  final decisions = <(String, bool)>[];

  /// The sections watching join requests, by household: call one to say a
  /// request came or went.
  final requestWatchers = <String, void Function()>{};

  @override
  Future<void> setJoinApproval(String householdId, {required bool on}) async {
    approvals.add((householdId, on));
    await _answer();
  }

  @override
  Future<List<PendingJoin>> joinRequests(String householdId) async {
    await _answer();
    return [...?requestLists[householdId]];
  }

  /// Requests whose invite has no use left: approving them answers
  /// [JoinRequestOutcome.inviteFull] and keeps them waiting.
  final fullRequests = <String>{};

  @override
  Future<JoinRequestOutcome> decideJoinRequest(
    String requestId, {
    required bool approve,
  }) async {
    decisions.add((requestId, approve));
    await _answer();
    if (approve && fullRequests.contains(requestId)) {
      return JoinRequestOutcome.inviteFull;
    }
    for (final requests in requestLists.values) {
      requests.removeWhere((r) => r.id == requestId);
    }
    return approve ? JoinRequestOutcome.approved : JoinRequestOutcome.declined;
  }

  @override
  Future<void> Function() watchJoinRequests(
    String householdId,
    void Function() onChange,
  ) {
    requestWatchers[householdId] = onChange;
    return () async => requestWatchers.remove(householdId);
  }

  @override
  Future<List<ArchivedHousehold>> archived() async {
    await _answer();
    return [...archivedNow];
  }

  /// Accepted invites by id: who joined (job 168b).
  final acceptedNow = <String, String>{};

  /// The live watch's callback while one is open.
  void Function()? onChange;
  var watches = 0;

  @override
  Future<Map<String, String>> accepted(List<String> ids) async {
    await _answer();
    return {for (final id in ids) id: ?acceptedNow[id]};
  }

  @override
  Future<void> Function() watch(String householdId, void Function() onChange) {
    watches++;
    this.onChange = onChange;
    return () async => this.onChange = null;
  }

  /// Someone accepts invite [id] as [name], and realtime says so.
  void accept(String id, String name) {
    acceptedNow[id] = name;
    onChange?.call();
  }
}

/// The guided start's draft, in memory (job 168b).
class MemoryOnboardingStore({var String? json}) implements OnboardingStore {
  final later = <String, List<HouseholdKind>>{};

  @override
  Future<String?> onboardingDraft() async => json;

  @override
  Future<void> saveOnboardingDraft(String? json) async => this.json = json;

  @override
  Future<void> saveLaterKinds(String userId, List<HouseholdKind> kinds) async =>
      later[userId] = kinds;
}

/// What the guided start sent: kinds and items per household; [fail] fails
/// the next call once.
class FakeOnboardingBackend() implements OnboardingBackend {
  final kinds = <String, HouseholdKind>{};
  final items = <String, List<DraftItem>>{};
  HouseholdProblem? fail;

  void _answer() {
    if (fail case final problem?) {
      fail = null;
      throw HouseholdError(problem);
    }
  }

  @override
  Future<void> setKind(String householdId, HouseholdKind kind) async {
    _answer();
    kinds[householdId] = kind;
  }

  @override
  Future<void> addItems(String householdId, List<DraftItem> items) async {
    _answer();
    final added = this.items[householdId] ??= [];
    for (final item in items) {
      if (!added.any((i) => i.id == item.id)) {
        added.add(item);
      }
    }
  }
}

/// Records what would go to the share sheet and the clipboard.
class FakeSharer({final bool available = true}) implements InviteSharer {
  @override
  bool get canShare => available;
  final shared = <String>[];
  final copied = <String>[];

  @override
  Future<void> share(String text, {Rect? origin}) async => shared.add(text);

  @override
  Future<void> copy(String text) async => copied.add(text);
}

/// A session the test drives: [join], [createHousehold] and the other
/// household calls record the call and move on as the server would, or
/// fail with [fail].
class TestSession(super.initialState)
    extends Cubit<Session>
    implements SessionCubit {
  final joins = <(String, JoinMethod)>[];

  /// The next [join] makes a request for this household instead (job 169b
  /// W3 M).
  Household? requestNext;
  final withdrawn = <String>[];
  final unarchived = <String>[];

  /// Each create: the name and the stores, joined with ", ", and where.
  final creates = <(String, String)>[];

  /// Each create's kind, null when none was sent.
  final createKinds = <String?>[];
  final origins = <HouseholdOrigin>[];

  /// The household each create request id made.
  final createdBy = <String, String>{};
  final defaults = <String>[];
  final renames = <(String, String)>[];

  /// Each leave: the household and whether it archives.
  final leaves = <(String, bool)>[];
  HouseholdProblem? fail;
  var refreshes = 0;
  Completer<void>? hold;

  @override
  PendingInvite? get pendingInvite => null;

  /// What [lostHouseholds] tells.
  final lost = StreamController<LostHousehold>.broadcast();

  @override
  Stream<LostHousehold> get lostHouseholds => lost.stream;

  /// Each [removalsTold] call's keys.
  final toldRemovals = <List<String>>[];

  @override
  Future<void> removalsTold(String userId, Iterable<String> keys) async =>
      toldRemovals.add([...keys]);

  /// What [joinDecisions] tells.
  final decidedOn = StreamController<JoinDecision>.broadcast();

  @override
  Stream<JoinDecision> get joinDecisions => decidedOn.stream;

  @override
  Future<void> close() async {
    await lost.close();
    await decidedOn.close();
    await super.close();
  }

  @override
  Analytics? get analytics => null;

  Future<void> _answer() async {
    await hold?.future;
    if (fail case final problem?) {
      fail = null;
      throw HouseholdError(problem);
    }
  }

  List<Household> get _households => switch (state) {
    InHousehold(:final households) => households,
    _ => const [],
  };

  /// Adds [household] (or replaces the one with its id) and shows it.
  void _show(Household household) {
    final others = [..._households.where((h) => h.id != household.id)];
    final first = others.isEmpty;
    final shown = first
        ? Household(
            id: household.id,
            name: household.name,
            isDefault: true,
            kind: household.kind,
          )
        : household;
    emit(InHousehold('peter', shown, [...others, shown]));
  }

  @override
  Future<JoinAnswer> join(
    String code, {
    JoinMethod method = JoinMethod.code,
  }) async {
    joins.add((code, method));
    await _answer();
    if (requestNext case final asked?) {
      requestNext = null;
      final request = JoinRequest(
        id: 'request-${asked.id}',
        householdId: asked.id,
        householdName: asked.name,
      );
      emit(switch (state) {
        InHousehold(:final userId, :final household, :final households) =>
          InHousehold(userId, household, households, requests: [request]),
        _ => NeedsHousehold('peter', requests: [request]),
      });
      return JoinRequested(asked.id);
    }
    _show(const Household(id: 'other', name: 'Trost'));
    return const Joined('other');
  }

  @override
  Future<void> withdrawJoinRequest(String householdId) async {
    withdrawn.add(householdId);
    await _answer();
    emit(switch (state) {
      InHousehold(:final userId, :final household, :final households) =>
        InHousehold(userId, household, households),
      _ => const NeedsHousehold('peter'),
    });
  }

  @override
  Future<void> unarchive(String householdId) async {
    unarchived.add(householdId);
    await _answer();
    _show(Household(id: householdId, name: 'Archiviert'));
  }

  @override
  Future<String> createHousehold(
    String name, {
    List<String> stores = const [],
    String? kind,
    HouseholdOrigin from = HouseholdOrigin.onboarding,
    String? requestId,
  }) async {
    // The server's answer to a repeated request id: the household it made.
    if (createdBy[requestId] case final id?) {
      _show(_households.firstWhere((h) => h.id == id));
      return id;
    }
    creates.add((name, stores.join(', ')));
    createKinds.add(kind);
    origins.add(from);
    await _answer();
    final id = _households.isEmpty ? 'home' : 'new-${creates.length}';
    if (requestId != null) {
      createdBy[requestId] = id;
    }
    _show(Household(id: id, name: name, kind: HouseholdKind.parse(kind)));
    return id;
  }

  @override
  Future<void> switchTo(String householdId) async {
    if (state case InHousehold(:final households)) {
      if (households.where((h) => h.id == householdId).firstOrNull
          case final next?) {
        emit(InHousehold('peter', next, households));
      }
    }
  }

  @override
  Future<void> setDefault(String householdId) async {
    defaults.add(householdId);
    await _answer();
    if (state case InHousehold(:final household, :final households)) {
      Household flip(Household h) => h.copyWith(isDefault: h.id == householdId);
      emit(
        InHousehold('peter', flip(household), [
          for (final h in households) flip(h),
        ]),
      );
    }
  }

  @override
  Future<void> rename(String householdId, String name) async {
    renames.add((householdId, name));
    await _answer();
    if (state case InHousehold(:final household, :final households)) {
      Household renamed(Household h) =>
          h.id == householdId ? h.copyWith(name: name.trim()) : h;
      emit(
        InHousehold('peter', renamed(household), [
          for (final h in households) renamed(h),
        ]),
      );
    }
  }

  @override
  Future<void> leave(String householdId, {bool archive = false}) async {
    leaves.add((householdId, archive));
    await _answer();
    if (state case InHousehold(:final household, :final households)) {
      final rest = [...households.where((h) => h.id != householdId)];
      if (rest.isEmpty) {
        emit(const NeedsHousehold('peter'));
        return;
      }
      final fallback = rest.where((h) => h.isDefault).firstOrNull ?? rest.first;
      emit(
        InHousehold(
          'peter',
          household.id == householdId ? fallback : household,
          rest,
        ),
      );
    }
  }

  @override
  Future<void> refresh({String? show}) async => refreshes++;

  @override
  Future<void> signOut() async => emit(const SignedOut());

  @override
  Future<void> accountDeleted(AccountDeletedNotice notice) async =>
      emit(SignedOut(deleted: notice));
}

class MemoryPendingStore() implements PendingInviteStore {
  KeptInvite? saved;

  @override
  Future<KeptInvite?> pendingInvite() async => saved;

  @override
  Future<void> savePendingInvite(KeptInvite? invite) async => saved = invite;
}

typedef Onboarding = ({
  TestSession session,
  FakeInvites invites,
  FakeSharer sharer,
  PendingInvite pending,
  GoRouter router,
  NativePostHog sink,
  Analytics analytics,
  FakePremiumServer premium,
  OnboardingCubit onboarding,
  MemoryOnboardingStore onboardingStore,
  FakeOnboardingBackend backend,
});

/// The onboarding routes as `buildRouter` has them, the list a stub, with
/// the app's redirect.
Future<Onboarding> pumpOnboarding(
  WidgetTester tester, {
  required String location,
  Session session = const NeedsHousehold('peter'),
  String? pendingCode,
  Locale locale = const Locale('de'),
  FakeSharer? sharer,
  FakeInvites? invites,

  /// The caller's yearly plan (billing warnings before leaving, H-85).
  FakePremiumServer? premium,

  /// The current household's premium rows.
  FakeEntitlementsSource? entitlements,

  /// The household page offers archiving (job 43).
  bool archiveOffered = false,

  /// The guided start's draft under way (job 168b).
  OnboardingDraft? draft,
  MemoryOnboardingStore? onboardingStore,

  /// Whether this install answered the usage-data question already.
  bool consentAnswered = true,

  /// The guided start's server calls; a fresh fake by default.
  FakeOnboardingBackend? backend,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final fakeInvites = invites ?? FakeInvites();
  final fakeSharer = sharer ?? FakeSharer();
  final store = MemoryPendingStore();
  final pending = PendingInvite(store);
  if (pendingCode != null) {
    pending.remember(pendingCode);
  }
  final sink = NativePostHog()..install();
  final analytics = await tester.runAsync(
    () => loadedAnalytics(MemoryAnalyticsStore()),
  );
  if (consentAnswered) {
    await tester.runAsync(() => analytics!.decide(granted: true));
  }
  analytics!.setUser(const AnalyticsUser(email: 'neu@gmail.com'));
  addTearDown(analytics.close);
  final server = premium ?? FakePremiumServer();
  final rows = Entitlements(
    entitlements ?? FakeEntitlementsSource(),
    testSession,
  );
  addTearDown(rows.close);
  final drafts = onboardingStore ?? MemoryOnboardingStore();
  final onboarding = draft != null
      ? OnboardingCubit(drafts, initial: draft, analytics: analytics)
      : await tester.runAsync(
          () => OnboardingCubit.load(drafts, analytics: analytics),
        );
  addTearDown(onboarding!.close);
  onboarding.sessionChanged(testSession.state);
  final sessions = testSession.stream.listen(onboarding.sessionChanged);
  addTearDown(sessions.cancel);
  final onboardingBackend = backend ?? FakeOnboardingBackend();
  final auth = FakeAuth();
  addTearDown(auth.close);
  final router = GoRouter(
    initialLocation: location,
    refreshListenable: Listenable.merge([
      _SessionListenable(testSession),
      _SessionListenable(onboarding),
      _SessionListenable(analytics),
    ]),
    redirect: (_, state) {
      if (inviteIn(state.uri) case final code?) {
        pending.remember(code);
      }
      return authRedirect(
        testSession.state,
        state.uri,
        pendingInvite: pending.code,
        draft: onboarding.state,
        askConsent: analytics.asksConsent,
      );
    },
    routes: [
      GoRoute(path: listPath, builder: (_, _) => const Text('LIST')),
      GoRoute(
        path: loginPath,
        builder: (_, state) => Scaffold(
          body: Column(
            children: [
              const Text('LOGIN'),
              PasteInvite(waiting: state.uri.queryParameters['invite']),
            ],
          ),
        ),
      ),
      GoRoute(path: consentPath, builder: (_, _) => const Text('CONSENT')),
      GoRoute(
        path: invitesPath,
        builder: (_, _) => const Scaffold(body: InvitesPage()),
      ),
      GoRoute(
        path: welcomePath,
        builder: (_, _) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'waiting',
            builder: (_, _) => const PendingJoinScreen(),
          ),
        ],
      ),
      GoRoute(
        path: householdPath,
        builder: (_, _) =>
            Scaffold(body: HouseholdPage(archiveOffered: archiveOffered)),
      ),
      GoRoute(
        path: newHouseholdPath,
        builder: (_, _) =>
            const CreateHouseholdScreen(from: HouseholdOrigin.switcher),
      ),
      GoRoute(
        path: invitePartnerPath,
        builder: (_, _) => const InvitePartnerScreen(),
      ),
      GoRoute(
        path: startPath,
        builder: (_, _) => const StartScreen(),
        routes: [
          for (final step in OnboardingStep.values)
            GoRoute(
              path: step.name,
              builder: (_, _) => onboardingStepScreen(step),
            ),
        ],
      ),
      GoRoute(path: joinCodePath, builder: (_, _) => const JoinScreen()),
      GoRoute(
        path: '/join/:code',
        builder: (_, state) => JoinScreen(link: state.pathParameters['code']),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<InviteRepository>.value(value: fakeInvites),
        RepositoryProvider<InviteSharer>.value(value: fakeSharer),
        RepositoryProvider.value(value: pending),
        RepositoryProvider<AccountRepository>.value(
          value: FakeAccountRepository(),
        ),
        RepositoryProvider<PremiumServer>.value(value: server),
        RepositoryProvider<StorePriceReader>.value(
          value: FakeStorePrices(fakeStorePrices, manages: true),
        ),
        RepositoryProvider<OnboardingBackend>.value(value: onboardingBackend),
        // The account step's sign-in panel; this build offers email only.
        RepositoryProvider.value(
          value: SocialSignIn(
            auth,
            flows: const {},
            native: FakeNativeSignIn(),
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: testSession),
          BlocProvider.value(value: onboarding),
          BlocProvider.value(value: analytics),
          BlocProvider.value(value: rows),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    session: testSession,
    invites: fakeInvites,
    sharer: fakeSharer,
    pending: pending,
    router: router,
    sink: sink,
    analytics: analytics,
    premium: server,
    onboarding: onboarding,
    onboardingStore: drafts,
    backend: onboardingBackend,
  );
}

/// What analytics sent, first_open aside.
Future<List<Map<String, Object?>>> sentEvents(
  WidgetTester tester,
  Onboarding o,
) async {
  await tester.runAsync(o.analytics.flush);
  return [
    for (final e in o.sink.events)
      if (e['event'] != 'first_open') e,
  ];
}

class _SessionListenable(BlocBase<Object?> session) extends ChangeNotifier {
  this {
    _subscription = session.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await scrollTo(tester, finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the page until [finder] is built and on screen: the onboarding
/// pages are lazy lists, which build nothing far below the fold.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
}

/// Legal's invite-sheet hint (N-112), byte for byte.
const joinPageHintDe =
    'Wer den Link hat, sieht auf der Beitrittsseite deinen Vornamen (aus '
    'deinem Anzeigenamen), den Namen und die Art des Haushalts und die Zahl '
    'der Mitglieder. Gib den Link nur an Personen weiter, die du einladen '
    'willst.';
const joinPageHintEn =
    'Anyone with the link sees your first name (from your display name), '
    "the household's name and kind and the number of members on the join "
    'page. Only share the link with people you want to invite.';
