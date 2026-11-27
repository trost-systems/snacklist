// Dead-end probes of the guided start (job 461), frozen before the
// baseline. measure.sh copies this file next to the onboarding tests and
// counts the probes that fail: each failure is one avoidable dead-end.
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('D1 need: text typed without + goes on the list with Weiter', (
    tester,
  ) async {
    final o = await pumpOnboarding(
      tester,
      location: '/start/need',
      session: const SignedOut(),
      draft: const OnboardingDraft(step: OnboardingStep.need),
    );
    await scrollTo(tester, key('onboarding-need-field'));
    await tester.enterText(key('onboarding-need-field'), 'Hafermilch');
    await tapKey(tester, 'onboarding-next');
    expect(location(o), '/start/account');
    expect(o.onboarding.state?.items.map((i) => i.text), ['Hafermilch']);
  });

  testWidgets('D2 name: the suggestion follows a kind changed on the way '
      'back', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: '/start/who',
      session: const SignedOut(),
      draft: const OnboardingDraft(step: OnboardingStep.who),
    );
    await tapKey(tester, 'onboarding-kind-family');
    await tapKey(tester, 'onboarding-next');
    expect(find.widgetWithText(TextField, 'Unsere Familie'), findsOneWidget);
    await tapKey(tester, 'onboarding-next');
    expect(location(o), '/start/stores');
    await back(tester);
    await back(tester);
    expect(location(o), '/start/who');
    await tapKey(tester, 'onboarding-kind-family');
    await tapKey(tester, 'onboarding-kind-flat');
    await tapKey(tester, 'onboarding-next');
    expect(find.widgetWithText(TextField, 'Unsere WG'), findsOneWidget);
  });

  testWidgets('D2b name: a typed name survives a kind changed on the way '
      'back', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: '/start/who',
      session: const SignedOut(),
      draft: const OnboardingDraft(step: OnboardingStep.who),
    );
    await tapKey(tester, 'onboarding-kind-family');
    await tapKey(tester, 'onboarding-next');
    await tester.enterText(key('household-name'), 'Familie Trost');
    await tapKey(tester, 'onboarding-next');
    await back(tester);
    await back(tester);
    await tapKey(tester, 'onboarding-kind-family');
    await tapKey(tester, 'onboarding-kind-flat');
    await tapKey(tester, 'onboarding-next');
    expect(find.widgetWithText(TextField, 'Familie Trost'), findsOneWidget);
    expect(location(o), '/start/name');
  });

  testWidgets('D3 stores: an own store typed without the check is kept by '
      'Weiter', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: '/start/stores',
      session: const SignedOut(),
      draft: const OnboardingDraft(step: OnboardingStep.stores),
    );
    await tapKey(tester, 'onboarding-store-own');
    await tester.enterText(key('store-new-field'), 'Hofladen');
    await tapKey(tester, 'onboarding-next');
    expect(location(o), '/start/need');
    expect(
      [for (final s in o.onboarding.state?.stores ?? <NewStore>[]) s.name],
      ['Hofladen'],
    );
  });

  testWidgets('D4 name: a name the field takes is one the server takes', (
    tester,
  ) async {
    final o = await pumpOnboarding(
      tester,
      location: '/start/name',
      session: const SignedOut(),
      draft: const OnboardingDraft(
        step: OnboardingStep.name,
        kinds: [HouseholdKind.family],
      ),
    );
    // 75 characters on screen, 81 code points for the server.
    await tester.enterText(key('household-name'), '${'A' * 74}👨‍👩‍👧‍👦');
    await tapKey(tester, 'onboarding-next');
    expect(location(o), '/start/stores');
  });
}
