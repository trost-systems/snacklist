import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/household_page.dart';
import 'package:family_groceries/household/invite_partner_screen.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invites_page.dart';
import 'package:family_groceries/household/join_screen.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/welcome_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../analytics/fakes.dart';
import '../purchases/fakes.dart';
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

  /// What `preview_invite` says about Hummlist Lifetime, by code.
  final lifetime = <String, JoinLifetime>{};

  /// Each household's members, by household id.
  final memberLists = <String, List<HouseholdMember>>{};

  /// Households whose Hummlist Premium ends when the last member leaves.
  final unlocked = <String>{};
  final created = <Invite>[];
  final revoked = <String>[];
  final previews = <String>[];
  HouseholdProblem? next;
  var _n = 0;

  /// Calls wait for this, so a test can tap twice while one is out.
  Completer<void>? hold;

  Future<void> _answer() async {
    await hold?.future;
    if (next case final problem?) {
      next = null;
      throw HouseholdError(problem);
    }
  }

  @override
  Future<Invite> create(String householdId) async {
    await _answer();
    final invite = Invite(
      id: 'invite-${++_n}',
      code: 'NEWCODE${'XYZ'[_n % 3]}',
      expiresAt: DateTime.utc(2026, 11, 6, 9, 30),
    );
    created.add(invite);
    return invite;
  }

  @override
  Future<List<Invite>> open(String householdId) async {
    await _answer();
    return [
      for (final i in created.reversed)
        if (!revoked.contains(i.id)) i,
    ];
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

  @override
  Future<List<ArchivedHousehold>> archived() async {
    await _answer();
    return [...archivedNow];
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
  final unarchived = <String>[];

  /// Each create: the name and the stores, joined with ", ", and where.
  final creates = <(String, String)>[];
  final origins = <HouseholdOrigin>[];
  final defaults = <String>[];
  final renames = <(String, String)>[];

  /// Each leave: the household and whether it archives.
  final leaves = <(String, bool)>[];
  HouseholdProblem? fail;
  var refreshes = 0;
  Completer<void>? hold;

  @override
  PendingInvite? get pendingInvite => null;

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
        ? Household(id: household.id, name: household.name, isDefault: true)
        : household;
    emit(InHousehold('peter', shown, [...others, shown]));
  }

  @override
  Future<void> join(String code, {JoinMethod method = JoinMethod.code}) async {
    joins.add((code, method));
    await _answer();
    _show(const Household(id: 'other', name: 'Trost'));
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
  }) async {
    creates.add((name, stores.join(', ')));
    origins.add(from);
    await _answer();
    final id = _households.isEmpty ? 'home' : 'new-${creates.length}';
    _show(Household(id: id, name: name));
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
      Household flip(Household h) => Household(
        id: h.id,
        name: h.name,
        isDefault: h.id == householdId,
        memberCount: h.memberCount,
        openCount: h.openCount,
      );
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
      Household renamed(Household h) => h.id == householdId
          ? Household(
              id: h.id,
              name: name.trim(),
              isDefault: h.isDefault,
              memberCount: h.memberCount,
              openCount: h.openCount,
            )
          : h;
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
  ({String code, DateTime at})? saved;

  @override
  Future<({String code, DateTime at})?> pendingInvite() async => saved;

  @override
  Future<void> savePendingInvite(({String code, DateTime at})? invite) async =>
      saved = invite;
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
  await tester.runAsync(() => analytics!.decide(granted: true));
  analytics!.setUser(const AnalyticsUser(email: 'neu@gmail.com'));
  addTearDown(analytics.close);
  final server = premium ?? FakePremiumServer();
  final rows = Entitlements(
    entitlements ?? FakeEntitlementsSource(),
    testSession,
  );
  addTearDown(rows.close);
  final router = GoRouter(
    initialLocation: location,
    refreshListenable: _SessionListenable(testSession),
    redirect: (_, state) {
      if (inviteIn(state.uri) case final code?) {
        pending.remember(code);
      }
      return authRedirect(
        testSession.state,
        state.uri,
        pendingInvite: pending.code,
      );
    },
    routes: [
      GoRoute(path: listPath, builder: (_, _) => const Text('LIST')),
      GoRoute(path: loginPath, builder: (_, _) => const Text('LOGIN')),
      GoRoute(path: consentPath, builder: (_, _) => const Text('CONSENT')),
      GoRoute(
        path: invitesPath,
        builder: (_, _) => const Scaffold(body: InvitesPage()),
      ),
      GoRoute(
        path: householdPath,
        builder: (_, _) =>
            Scaffold(body: HouseholdPage(archiveOffered: archiveOffered)),
      ),
      GoRoute(
        path: welcomePath,
        builder: (_, _) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (_, _) => const CreateHouseholdScreen(),
          ),
          GoRoute(
            path: 'invite',
            builder: (_, _) => const InvitePartnerScreen(),
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
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: testSession),
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

class _SessionListenable(Cubit<Session> session) extends ChangeNotifier {
  this {
    _subscription = session.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Session> _subscription;

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
