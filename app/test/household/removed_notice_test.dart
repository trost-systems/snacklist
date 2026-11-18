import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/join_decision_notices.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/removed_notice.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as auth_types
    show Session;
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../analytics/fakes.dart';
import '../more/more_harness.dart';
import '../session/fake_auth.dart';
import '../session/fake_households.dart';
import '../session/fake_your_name.dart';

const _peter = User(
  id: 'peter',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-22T12:00:00Z',
);

const _notice =
    'Du wurdest aus dem Haushalt „Zuhause“ entfernt. 30 Tage lang kommst '
    'du über alte Einladungen nicht zurück. Beitreten kannst du in dieser '
    'Zeit nur über eine neue Einladung vom Hauptadmin oder einem Admin.';

/// The real session, router and consent screen: a person removed from
/// their only household signs in, and the analytics consent (asked again
/// under a new text version, Legal N-125) comes first (review 1, Must
/// fix 1).
void main() {
  setUpAll(fakeSupabase);

  late FakeAuth auth;
  late FakeHouseholds server;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    NativePostHog().install();
    auth = FakeAuth()..user = _peter;
    server = FakeHouseholds(auth)
      ..member('peter', 'home', 'Zuhause')
      ..member('mia', 'home', 'Zuhause')
      ..removedBySomeone('peter', 'home');
  });

  tearDown(() => auth.close());

  /// The app as it starts on this device, signed in as Peter.
  Future<void> start(
    WidgetTester tester, {
    void Function(String user, void Function() onChange)? watch,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(358, 780);
    addTearDown(tester.view.reset);
    final cache = DeviceCache(SharedPreferencesAsync());
    final analytics = Analytics(testClient(), cache, releaseConfig);
    await analytics.load();
    final session = SessionCubit(
      server,
      cache,
      watchJoinRequests: (user, onChange) {
        watch?.call(user, onChange);
        return () async {};
      },
    );
    final popups = Popups();
    final router = buildRouter(
      session,
      analytics,
      PendingInvite(cache),
      ListLinks(),
      popups,
      OnboardingCubit(cache),
      idleYourName(),
    );
    addTearDown(router.dispose);
    addTearDown(session.close);
    addTearDown(analytics.close);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: cache,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: analytics),
          ],
          child: MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            routerConfig: router,
            builder: (context, child) => NoticesHost(
              popups: popups,
              child: RemovedNotices(
                router: router,
                child: JoinDecisionNotices(router: router, child: child!),
              ),
            ),
          ),
        ),
      ),
    );
    auth.states.add(
      AuthState(
        AuthChangeEvent.initialSession,
        auth_types.Session(
          accessToken: 'jwt',
          tokenType: 'bearer',
          user: _peter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final consent = find.byKey(const ValueKey('analytics-consent'));
  final accept = find.byKey(const ValueKey('analytics-consent-accept'));
  final decline = find.byKey(const ValueKey('analytics-consent-decline'));
  final removed = find.byKey(const ValueKey('household-removed'));

  Future<Set<String>> told() =>
      DeviceCache(SharedPreferencesAsync()).toldRemovals('peter');

  /// Reads the consent text for 20 s, longer than the notice would stay.
  Future<void> readConsent(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(removed, findsNothing, reason: 'held behind the consent, $i s');
    }
  }

  Future<void> answer(WidgetTester tester, Finder button) async {
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.descendant(
        of: consent,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the removal notice waits for the consent answer, then shows '
      'on the welcome screen and only then counts as told', (tester) async {
    await start(tester);
    expect(consent, findsOneWidget);
    await readConsent(tester);
    await tester.scrollUntilVisible(
      accept,
      200,
      scrollable: find.descendant(
        of: consent,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(accept.hitTestable(), findsOneWidget);
    expect(decline.hitTestable(), findsOneWidget);
    expect(await told(), isEmpty, reason: 'not seen yet');

    await answer(tester, decline);
    expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);
    expect(await told(), hasLength(1));

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text(_notice), findsOneWidget, reason: 'still readable');
  });

  testWidgets('killed while the consent is open: the next start tells it', (
    tester,
  ) async {
    await start(tester);
    await readConsent(tester);
    expect(await told(), isEmpty);
    await tester.pumpWidget(const SizedBox());

    await start(tester);
    expect(consent, findsOneWidget, reason: 'still unanswered');
    await answer(tester, accept);
    expect(find.text(_notice), findsOneWidget);
    expect(await told(), hasLength(1));
  });

  testWidgets('a join decision made while the consent is open waits for '
      'the answer too', (tester) async {
    server = FakeHouseholds(auth)
      ..member('peter', 'home', 'Zuhause')
      ..member('lea', 'club', 'Sommerfest')
      ..approval.add('club')
      ..requests['r1'] = (user: 'peter', household: 'club');
    void Function()? changed;
    await start(tester, watch: (_, onChange) => changed = onChange);
    expect(consent, findsOneWidget);
    expect(changed, isNotNull, reason: 'the session watches the request');

    server.decide('r1', approve: false);
    changed!();
    const declined = 'Deine Anfrage für „Sommerfest“ wurde nicht angenommen.';
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(declined), findsNothing, reason: 'held, $i s');
    }
    await tester.scrollUntilVisible(
      accept,
      200,
      scrollable: find.descendant(
        of: consent,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(accept.hitTestable(), findsOneWidget);
    expect(decline.hitTestable(), findsOneWidget);

    await answer(tester, decline);
    expect(consent, findsNothing);
    expect(find.text(declined), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
