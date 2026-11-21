import 'dart:ui' show Tristate;

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fakes.dart';

void main() {
  setUpAll(fakeSupabase);

  final toggle = find.byKey(const ValueKey('more-analytics'));
  bool on(WidgetTester tester) =>
      tester
          .getSemantics(toggle)
          .getSemanticsData()
          .flagsCollection
          .isToggled ==
      Tristate.isTrue;
  final version = find.byKey(const ValueKey('more-version'));

  /// More, then its Nutzungsdaten row: the switch lives on that page.
  Future<void> openUsageData(WidgetTester tester, Analytics analytics) async {
    await pumpMore(tester, analytics: analytics, size: const Size(390, 2000));
    expect(toggle, findsNothing, reason: 'not on the menu');
    await tester.tap(find.byKey(const ValueKey('more-usage-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-usage-data-page')), findsOneWidget);
  }

  late MemoryAnalyticsStore store;
  setUp(() => store = MemoryAnalyticsStore());

  Future<(Analytics, NativePostHog)> consented() async {
    final sink = NativePostHog()..install();
    final analytics = await loadedAnalytics(store)
      ..setUser(customer);
    await analytics.decide(granted: true);
    await analytics.flush();
    return (analytics, sink);
  }

  testWidgets('a build without a key has no Nutzungsdaten row or switch', (
    tester,
  ) async {
    await pumpMore(tester, size: const Size(390, 2000));
    expect(find.byKey(const ValueKey('more-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-usage-data')), findsNothing);
    expect(toggle, findsNothing);
    expect(find.text('Nutzungsdaten'), findsNothing);
  });

  final sheet = find.byKey(const ValueKey('analytics-consent-sheet'));
  final accept = find.byKey(const ValueKey('analytics-consent-accept'));
  final decline = find.byKey(const ValueKey('analytics-consent-decline'));

  testWidgets('the switch shows the decision; off stops sending at once', (
    tester,
  ) async {
    final (analytics, sink) = await consented();
    await openUsageData(tester, analytics);
    expect(toggle, findsOneWidget);
    expect(on(tester), isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing, reason: 'off asks nothing');
    expect(analytics.state.consent, isFalse);
    expect(on(tester), isFalse);
    expect(sink.methods.last, 'close', reason: 'off stops the SDK');
    expect(store.id, isNull, reason: 'off deletes the install id');
    analytics.track('item_ticked');
    await analytics.flush();
    expect(sink.names, ['first_open']);
  });

  group('on asks the consent question first (Legal N-298)', () {
    Future<(Analytics, NativePostHog)> declined() async {
      final sink = NativePostHog()..install();
      final analytics = await loadedAnalytics(store)
        ..setUser(customer);
      await analytics.decide(granted: false);
      await analytics.flush();
      return (analytics, sink);
    }

    Future<void> expectStillOff(
      WidgetTester tester,
      Analytics analytics,
      NativePostHog sink,
    ) async {
      expect(sheet, findsNothing);
      expect(analytics.state.consent, isFalse);
      expect(on(tester), isFalse);
      expect(store.id, isNull, reason: 'no install id');
      analytics.track('item_ticked');
      await analytics.flush();
      expect(sink.names, isEmpty, reason: 'nothing sent');
    }

    testWidgets('the sheet has the approved words; yes only on Erlauben', (
      tester,
    ) async {
      final (analytics, sink) = await declined();
      await openUsageData(tester, analytics);
      expect(on(tester), isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('de'));
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(l10n.analyticsConsentTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(const ValueKey('analytics-consent-privacy')),
        ),
        findsOneWidget,
      );
      expect(analytics.state.consent, isFalse, reason: 'not yet');
      expect(on(tester), isFalse, reason: 'not yet');
      expect(store.id, isNull, reason: 'no install id yet');

      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(analytics.state.consent, isTrue);
      expect(on(tester), isTrue);
      expect(store.id, isNotNull, reason: 'a new install id');
      await analytics.flush();
      expect(sink.names, ['first_open']);
    });

    testWidgets('Nicht erlauben in the sheet leaves it off', (tester) async {
      final (analytics, sink) = await declined();
      await openUsageData(tester, analytics);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(decline);
      await tester.pumpAndSettle();
      await expectStillOff(tester, analytics, sink);
    });

    testWidgets('closing the sheet leaves it off', (tester) async {
      final (analytics, sink) = await declined();
      await openUsageData(tester, analytics);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      await expectStillOff(tester, analytics, sink);
    });

    testWidgets('back closes the sheet and leaves it off', (tester) async {
      final (analytics, sink) = await declined();
      await openUsageData(tester, analytics);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();
      await expectStillOff(tester, analytics, sink);
      expect(
        find.byKey(const ValueKey('more-usage-data-page')),
        findsOneWidget,
        reason: 'back closed only the sheet',
      );
    });

    testWidgets('off, then on again: a new install id', (tester) async {
      final (analytics, sink) = await consented();
      await openUsageData(tester, analytics);
      final before = sink.events.single['properties']! as Map;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(analytics.state.consent, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(analytics.state.consent, isTrue);
      await analytics.flush();
      expect(sink.names, ['first_open', 'first_open']);
      expect(
        (sink.events.last['properties']! as Map)['install_id'],
        allOf(store.id, isNot(before['install_id'])),
      );
    });
  });

  testWidgets('a long press on the version unlocks nothing; the tester '
      'group internal shows the test error', (tester) async {
    final (analytics, _) = await consented();
    await pumpMore(tester, analytics: analytics, size: const Size(390, 2000));
    expect(find.byKey(const ValueKey('more-test-error')), findsNothing);
    await tester.longPress(version);
    await tester.pumpAndSettle();
    expect(analytics.internalNow, isFalse);
    expect(find.byKey(const ValueKey('more-test-error')), findsNothing);
    expect(find.byKey(const ValueKey('more-install-id')), findsNothing);
    analytics.setTesterGroups({'internal'});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-test-error')), findsOneWidget);
    analytics.setTesterGroups({'beta-de'});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-test-error')), findsNothing);
  });

  testWidgets('a release build shows no tools to the RevenueCat tester '
      'household (App Review) or a test account, internal as they are', (
    tester,
  ) async {
    final (analytics, _) = await consented();
    analytics.testerHousehold = householdA;
    await pumpMore(tester, analytics: analytics, size: const Size(390, 2000));
    expect(analytics.internalNow, isTrue);
    expect(find.byKey(const ValueKey('more-test-error')), findsNothing);
    expect(find.byKey(const ValueKey('more-install-id')), findsNothing);
    analytics
      ..testerHousehold = null
      ..setUser(
        const AnalyticsUser(
          email: 'review@example.com',
          householdId: householdA,
        ),
      );
    await tester.pumpAndSettle();
    expect(analytics.internalNow, isTrue);
    expect(find.byKey(const ValueKey('more-test-error')), findsNothing);
  });

  testWidgets('a debug or profile build shows the tools', (tester) async {
    NativePostHog().install();
    final analytics = await loadedAnalytics(
      store,
      config: const AnalyticsConfig(
        releaseBuild: false,
        householdGroups: false,
        platform: 'web',
        appVersion: '0.1.0+7',
      ),
    );
    await pumpMore(tester, analytics: analytics, size: const Size(390, 2000));
    expect(find.byKey(const ValueKey('more-test-error')), findsOneWidget);
  });

  testWidgets('an internal user copies the install id flags target', (
    tester,
  ) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    final (analytics, _) = await consented();
    await pumpMore(tester, analytics: analytics, size: const Size(390, 2000));
    final copy = find.byKey(const ValueKey('more-install-id'));
    expect(copy, findsNothing, reason: 'only for an internal user');
    analytics.setTesterGroups({'internal'});
    await tester.pumpAndSettle();
    expect(find.textContaining(store.id!), findsOneWidget);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, [store.id], reason: 'the distinct id PostHog sees');
  });
}
