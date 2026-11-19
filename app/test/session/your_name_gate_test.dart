import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../household/harness.dart' show TestSession;
import 'fake_your_name.dart';

/// Job 297: the real router sends a new user to the name step only while
/// the flag `display-name` is on, and goes on once the name is saved.
void main() {
  late GoRouter router;
  late FakeNameRepository server;
  late Flags flags;
  late TestSession session;
  late StreamController<AuthState> auth;

  Future<void> pumpRouter(
    WidgetTester tester, {
    required bool flag,
    Session start = const NeedsHousehold('lea'),
    NameRow row = (name: 'lea.brandt87', chosen: false, fromEmail: true),
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final cache = DeviceCache(SharedPreferencesAsync());
    final analytics = Analytics.off(cache);
    addTearDown(analytics.close);
    flags = analytics.flags;
    analytics.flags.replace({displayNameFlag: flag});
    session = TestSession(start);
    addTearDown(session.close);
    auth = StreamController<AuthState>.broadcast();
    addTearDown(auth.close);
    server = FakeNameRepository(row: row);
    final names = YourNameCubit(server, MemoryPostponements(), auth.stream);
    addTearDown(names.close);
    final onboarding = OnboardingCubit(cache);
    addTearDown(onboarding.close);
    router = buildRouter(
      session,
      analytics,
      PendingInvite(cache),
      ListLinks(),
      Popups(),
      onboarding,
      names,
    );
    addTearDown(router.dispose);
    auth.add(signedInAs('lea'));
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: cache,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: analytics),
            BlocProvider.value(value: analytics.flags),
            BlocProvider.value(value: onboarding),
            BlocProvider.value(value: names),
          ],
          child: MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('flag off: no name step', (tester) async {
    await pumpRouter(tester, flag: false);
    expect(location(), welcomePath);
    expect(find.byKey(const ValueKey('your-name-screen')), findsNothing);
  });

  testWidgets('flag on: the name step, then the welcome once saved', (
    tester,
  ) async {
    await pumpRouter(tester, flag: true);
    expect(location(), yourNamePath);
    await tester.enterText(
      find.byKey(const ValueKey('your-name-field')),
      'Lea',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('your-name-save')));
    await tester.pumpAndSettle();
    expect(server.saved, ['Lea']);
    expect(location(), welcomePath);
  });

  testWidgets('a flag served later sends the user to the name step', (
    tester,
  ) async {
    await pumpRouter(tester, flag: false);
    flags.replace({displayNameFlag: true});
    await tester.pumpAndSettle();
    expect(location(), yourNamePath);
  });

  for (final nameFirst in [true, false]) {
    testWidgets('signing out on More goes to the sign-in without a link '
        '(the name ${nameFirst ? 'before' : 'after'} the session)', (
      tester,
    ) async {
      const home = Household(id: 'h', name: 'Zuhause', isDefault: true);
      await pumpRouter(
        tester,
        flag: true,
        start: const InHousehold('lea', home, [home]),
        row: (name: 'Lea', chosen: true, fromEmail: false),
      );
      router.go(morePath);
      await tester.pumpAndSettle();
      // More and the sign-in need providers this harness leaves out.
      tester.takeException();
      expect(location(), morePath);
      const out = AuthState(AuthChangeEvent.signedOut, null);
      if (nameFirst) {
        auth.add(out);
        await session.signOut();
      } else {
        await session.signOut();
        auth.add(out);
      }
      await tester.pumpAndSettle();
      tester.takeException();
      expect(location(), loginPath);
    });
  }

  testWidgets('sign-out on the name step goes to the sign-in, not back to '
      'the step', (tester) async {
    await pumpRouter(tester, flag: true);
    expect(location(), yourNamePath);
    await tester.tap(find.byKey(const ValueKey('your-name-sign-out')));
    await tester.pumpAndSettle();
    // The sign-in needs providers this harness leaves out.
    tester.takeException();
    expect(location(), loginPath);
    expect(server.saved, isEmpty);
  });

  testWidgets('sign-out on the name step keeps an invite for the next '
      'sign-in, as the analytics question does', (tester) async {
    await pumpRouter(tester, flag: true);
    router.go('$yourNamePath?invite=ABCD2345');
    await tester.pumpAndSettle();
    expect(location(), '$yourNamePath?invite=ABCD2345');
    await tester.tap(find.byKey(const ValueKey('your-name-sign-out')));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(location(), '$loginPath?invite=ABCD2345');
  });
}
