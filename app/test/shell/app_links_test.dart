import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/guides/source.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import '../session/fake_auth.dart';
import '../session/fake_your_name.dart';

/// Job 66: the real router hands `/add` and `/stores/<id>` to the list only
/// once the user is in the household.
void main() {
  setUpAll(fakeSupabase);

  late StreamController<Session> sessions;
  late ListLinks links;
  late GoRouter router;

  Future<void> pumpRouter(WidgetTester tester, Session state) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final cache = DeviceCache(SharedPreferencesAsync());
    final analytics = Analytics.off(cache);
    sessions = StreamController<Session>.broadcast();
    addTearDown(sessions.close);
    final session = FakeSession();
    whenListen(session, sessions.stream, initialState: state);
    links = ListLinks();
    addTearDown(links.dispose);
    router = buildRouter(
      session,
      analytics,
      PendingInvite(cache),
      links,
      Popups(),
      OnboardingCubit(cache),
      idleYourName(),
    );
    addTearDown(router.dispose);
    final auth = FakeAuth();
    addTearDown(auth.close);
    final language = LanguageCubit(cache, AppLanguage.de);
    addTearDown(language.close);
    final purchases = TestPurchases(session: session);
    addTearDown(purchases.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: links),
          RepositoryProvider<PremiumServer>.value(value: purchases.premium),
          RepositoryProvider(
            create: (_) =>
                GuideSource(MockClient((_) async => http.Response('', 404))),
          ),
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
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: analytics),
            BlocProvider.value(value: language),
            BlocProvider.value(value: purchases.entitlements),
            BlocProvider.value(value: purchases.purchases),
          ],
          child: MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  const household = InHousehold(
    'peter',
    Household(id: 'home', name: 'Zuhause'),
    [Household(id: 'home', name: 'Zuhause')],
  );

  /// Unmounts the app and lets the list's timers run out.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('signed out, /add waits for sign-in', (tester) async {
    await pumpRouter(tester, const SignedOut());
    router.go('/add');
    await tester.pump();
    expect(location(), '/login?next=%2Fadd');
    expect(links.take<AddLink>(), isNull);
  });

  testWidgets('signed in, /add opens the list with the sheet', (tester) async {
    await pumpRouter(tester, household);
    await tester.pumpAndSettle();
    router.go('/add');
    await tester.pumpAndSettle();
    expect(location(), '/');
    expect(find.byKey(const ValueKey('add-sheet')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a sign-in that comes back at / still opens the sheet', (
    tester,
  ) async {
    await pumpRouter(tester, const SignedOut());
    router.go('/add');
    await tester.pump();
    // The mobile apps' sign-in callback loses the location.
    router.go('/');
    await tester.pump();
    expect(location(), '/login?next=%2Fadd');
    sessions.add(household);
    await tester.pumpAndSettle();
    expect(location(), '/');
    expect(find.byKey(const ValueKey('add-sheet')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a sign-out in More goes to plain sign-in', (tester) async {
    await pumpRouter(tester, household);
    router.go('/more');
    await tester.pumpAndSettle();
    expect(location(), '/more');
    sessions.add(const SignedOut());
    await tester.pumpAndSettle();
    expect(location(), '/login');
    await unmount(tester);
  });

  // Job 462: what the platform hands the router when a link opens the app.
  testWidgets('the browser handoff com.snacklist.app://open/join/<code> is '
      'the invite link', (tester) async {
    await pumpRouter(tester, const SignedOut());
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute(
      'com.snacklist.app://open/join/ABCD2345',
    );
    await tester.pumpAndSettle();
    expect(location(), '/login?invite=ABCD2345');
    await unmount(tester);
  });

  testWidgets('a guide link signed out shows the guide, then the start', (
    tester,
  ) async {
    await pumpRouter(tester, const SignedOut());
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute(
      'https://snacklist.app/de/anleitungen/siri-kurzbefehl',
    );
    await tester.pumpAndSettle();
    expect(find.text('Diese Anleitung gibt es nicht mehr.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-close')));
    await tester.pumpAndSettle();
    expect(location(), '/start');
    await unmount(tester);
  });
}
