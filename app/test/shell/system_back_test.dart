import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/shell/safe_back_dispatcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../analytics/fakes.dart';
import '../more/more_harness.dart';
import '../session/fake_your_name.dart';

/// System back (`didPopRoute`) on the app's real router, in the states
/// before a household: signed out, the guided start, a redirect.
void main() {
  setUpAll(fakeSupabase);

  Future<GoRouter> pumpApp(
    WidgetTester tester,
    Session state,
    String location,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    final cache = DeviceCache(SharedPreferencesAsync());
    NativePostHog().install();
    final analytics = Analytics(
      testClient(FlagsServer()),
      cache,
      releaseConfig,
    );
    await analytics.load();
    final session = FakeSession();
    whenListen(session, const Stream<Session>.empty(), initialState: state);
    final router = buildRouter(
      session,
      analytics,
      PendingInvite(cache),
      ListLinks(),
      Popups(),
      OnboardingCubit(cache),
      idleYourName(),
    )..go(location);
    addTearDown(router.dispose);
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
            routerConfig: guardedBack(router),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  /// Whether back was handled, with no error reported.
  Future<bool> back(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return handled;
  }

  for (final (name, state, location) in [
    ('signed out, the start', const SignedOut(), '/'),
    ('the guided start, a step', const SignedOut(), '/start/who'),
    ('a legacy /settings link', const SignedOut(), '/settings'),
    ('welcome', const NeedsHousehold('u'), '/'),
  ]) {
    testWidgets('back, $name', (tester) async {
      final router = await pumpApp(tester, state, location);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        isNot(location),
        reason: 'the redirect ran',
      );
      expect(await back(tester), isFalse, reason: 'the app exits');
      expect(await back(tester), isFalse, reason: 'still the first page');
    });
  }
}
