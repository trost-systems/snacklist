import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/consent_version.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../core/fake_launcher.dart';
import '../more/more_harness.dart';
import '../session/fake_your_name.dart';
import 'fakes.dart';

/// The real router and screens: sign-in, then the analytics consent, then
/// onboarding (Peter, 2026-10-27).
void main() {
  setUpAll(fakeSupabase);

  late NativePostHog sink;
  late FlagsServer server;
  late Analytics analytics;
  late DeviceCache cache;

  Future<void> pumpApp(
    WidgetTester tester,
    Session state, {
    Locale locale = const Locale('de'),
    Size size = const Size(390, 844),
    Map<String, Object> stored = const {},
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({...stored});
    cache = DeviceCache(SharedPreferencesAsync());
    sink = NativePostHog()..install();
    server = FlagsServer()..served = {'shared-thing': true};
    analytics = Analytics(testClient(server), cache, releaseConfig);
    await analytics.load();
    analytics.setUser(const AnalyticsUser(email: 'neu@gmail.com'));
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
    );
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
            locale: locale,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final consent = find.byKey(const ValueKey('analytics-consent'));
  final accept = find.byKey(const ValueKey('analytics-consent-accept'));
  final decline = find.byKey(const ValueKey('analytics-consent-decline'));
  final welcome = find.byKey(const ValueKey('welcome'));

  /// Scrolls the consent text to [target]: on a phone the answers sit
  /// below it.
  Future<void> reach(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.descendant(
        of: consent,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('at 360 px the answers stack, decline first, no label wraps', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const NeedsHousehold('u'),
      size: const Size(360, 780),
    );
    await reach(tester, accept);
    final declineBox = tester.getRect(decline);
    final acceptBox = tester.getRect(accept);
    expect(declineBox.bottom, lessThan(acceptBox.top));
    expect(declineBox.width, acceptBox.width);
    expect(declineBox.width, greaterThan(250));
    for (final button in [decline, accept]) {
      final text = find.descendant(of: button, matching: find.byType(Text));
      expect(
        tester.getSize(text).height,
        lessThan(24),
        reason: tester.widget<Text>(text).data,
      );
    }
  });

  testWidgets('a first sign-in asks before onboarding; yes sends first_open', (
    tester,
  ) async {
    await pumpApp(tester, const NeedsHousehold('u'));
    expect(consent, findsOneWidget);
    expect(welcome, findsNothing);
    await reach(tester, accept);
    expect(
      find.textContaining('ENTWURF'),
      findsNothing,
      reason: 'Peter approved the wording on 2026-10-30',
    );
    // A titled page: screen readers start on its heading.
    expect(find.widgetWithText(AppBar, 'Nutzungsdaten'), findsOneWidget);
    await analytics.flush();
    expect(sink.events, isEmpty);
    expect(await cache.installId(), isNull, reason: 'nothing stored yet');

    await reach(tester, accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(welcome, findsOneWidget);
    await analytics.flush();
    expect(sink.names, ['first_open']);
    expect(await cache.installId(), matches(uuidPattern));
  });

  for (final (locale, title, link, url, yes, no) in [
    (
      const Locale('de'),
      'Darf Snacklist Nutzungsdaten erfassen?',
      'Datenschutzerklärung',
      'https://snacklist.app/datenschutz',
      'Erlauben',
      'Nicht erlauben',
    ),
    (
      const Locale('en'),
      'May Snacklist collect usage data?',
      'privacy policy',
      'https://snacklist.app/en/privacy',
      'Allow',
      "Don't allow",
    ),
  ]) {
    testWidgets('$locale: two equal answers, $yes and $no, none chosen', (
      tester,
    ) async {
      await pumpApp(tester, const NeedsHousehold('u'), locale: locale);
      await reach(tester, accept);
      expect(find.descendant(of: accept, matching: find.text(yes)), findsOne);
      expect(find.descendant(of: decline, matching: find.text(no)), findsOne);
      final (a, d) = (
        tester.widget<ButtonStyleButton>(accept),
        tester.widget<ButtonStyleButton>(decline),
      );
      expect(a.runtimeType, d.runtimeType, reason: 'the same weight');
      expect(a.style, d.style);
      expect(analytics.state.consent, isNull, reason: 'nothing pre-selected');
    });

    testWidgets('$locale: the text names Peter Trost and links the policy', (
      tester,
    ) async {
      final launcher = fakeLauncher();
      await pumpApp(tester, const NeedsHousehold('u'), locale: locale);
      expect(find.text(title), findsOneWidget);
      expect(
        find.textContaining('Peter Trost', findRichText: true),
        findsOneWidget,
      );
      await reach(tester, find.text(link));
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(launcher.opened, [(url, PreferredLaunchMode.externalApplication)]);
      expect(consent, findsOneWidget, reason: 'still waits for an answer');
    });
  }

  testWidgets('no goes on to onboarding, sends only shared flag requests '
      'and keeps no id', (tester) async {
    await pumpApp(tester, const NeedsHousehold('u'));
    await reach(tester, decline);
    await tester.tap(decline);
    await tester.pumpAndSettle();
    expect(welcome, findsOneWidget);
    expect(analytics.state.consent, isFalse);
    expect(await cache.installId(), isNull);
    analytics.track('household_created');
    await analytics.flush();
    await tester.pumpAndSettle();
    expect(sink.calls, isEmpty);
    expect(
      [for (final r in server.requests) r.body],
      [sharedFlagsBody, sharedFlagsBody],
    );
    expect(analytics.flags.isOn('shared-thing'), isTrue);
    final kept = await SharedPreferencesAsync().getAll();
    expect(
      {
        for (final MapEntry(:key, :value) in kept.entries)
          if (key.startsWith('analytics.')) key: value,
      },
      {
        'analytics.consent': false,
        'analytics.consent_text_version': consentTextVersion,
        'analytics.shared_flags': '{"shared-thing":true}',
      },
    );
  });

  testWidgets('both answers are the same size: declining is as easy', (
    tester,
  ) async {
    await pumpApp(tester, const NeedsHousehold('u'));
    await reach(tester, accept);
    expect(tester.getSize(accept), tester.getSize(decline));
  });

  // Legal Review 2026-11-01, 12:35: a yes counts only for the text it was
  // given under. One an older build stored (no version) or one under an
  // older text is no decision: asked again, and before the new answer only
  // the shared flag request goes to PostHog.
  const kept = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc';
  for (final (label, version) in [
    ('no version (an older build)', null),
    ('the 2026-10-30 text', '2026-10-30'),
  ]) {
    testWidgets('a yes under $label is asked again, only shared flags before', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const NeedsHousehold('u'),
        stored: {
          'analytics.consent': true,
          'analytics.install_id': kept,
          'analytics.first_open': kept,
          'analytics.consent_text_version': ?version,
        },
      );
      expect(consent, findsOneWidget);
      expect(welcome, findsNothing);
      analytics.track('household_created');
      await analytics.flush();
      expect(sink.calls, isEmpty, reason: 'no setup, no event');
      expect([for (final r in server.requests) r.body], [sharedFlagsBody]);
      expect(sink.forgotten, ['phc_unit_test'], reason: 'as on a no');
      expect(await cache.installId(), isNull);
      expect(await cache.consent(), isNull);

      await reach(tester, accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(welcome, findsOneWidget);
      await analytics.flush();
      expect(await cache.consentTextVersion(), consentTextVersion);
      expect(await cache.installId(), allOf(isNotNull, isNot(kept)));
      expect(sink.names, ['first_open']);
    });
  }

  testWidgets('a yes to the current text is not asked again and sends', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const NeedsHousehold('u'),
      stored: {
        'analytics.consent': true,
        'analytics.install_id': kept,
        'analytics.first_open': kept,
        'analytics.consent_text_version': consentTextVersion,
      },
    );
    expect(consent, findsNothing);
    expect(welcome, findsOneWidget);
    analytics.track('household_created');
    await analytics.flush();
    expect(sink.methods, containsAll(['setup', 'getAllFeatureFlags']));
    expect(sink.names, ['household_created']);
  });

  testWidgets('a decided install is not asked again', (tester) async {
    await pumpApp(tester, const NeedsHousehold('u'));
    await reach(tester, decline);
    await tester.tap(decline);
    await tester.pumpAndSettle();
    final again = Analytics(testClient(), cache, releaseConfig);
    await again.load();
    expect(again.asksConsent, isFalse);
    unawaited(again.close());
  });
}
