import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

Flags flagsOn({bool jh2 = false, bool joinerDirect = true}) => Flags(
  forced: {
    if (jh2) joinHouseholdJh2Flag,
    if (joinerDirect) joinerDirectListFlag,
  },
);

const phones = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

Future<Onboarding> pumpStart(
  WidgetTester tester, {
  required Flags flags,
  bool consentAnswered = true,
  ValueNotifier<bool>? askName,
}) => pumpOnboarding(
  tester,
  location: '/',
  session: const SignedOut(),
  flags: flags,
  consentAnswered: consentAnswered,
  askName: askName,
);

Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(key('join-code-field'), code);
  await tester.pumpAndSettle();
}

void main() {
  group('the start screen', () {
    for (final jh2 in [false, true]) {
      testWidgets('JH2 ${jh2 ? 'on' : 'off'}: has no Mit Code beitreten, '
          'also with the flag on', (tester) async {
        await pumpStart(tester, flags: flagsOn(jh2: jh2));
        expect(find.text("Los geht's"), findsOneWidget);
        expect(find.text('Mit Code beitreten'), findsNothing);
        expect(key('start-join-code'), findsNothing);
      });
    }
  });

  group('a typed code, name step to list', () {
    testWidgets('code, sign-in, name step, then the list without a confirm', (
      tester,
    ) async {
      final askName = ValueNotifier(true);
      addTearDown(askName.dispose);
      final o = await pumpOnboarding(
        tester,
        location: '/start/name',
        session: const SignedOut(),
        draft: const OnboardingDraft(step: OnboardingStep.name, name: 'Wir'),
        flags: flagsOn(jh2: true),
        askName: askName,
      );
      await tapKey(tester, 'onboarding-join-existing');
      await enterCode(tester, 'ABCD2345');
      expect(
        find.text('Peter lädt dich zu „Familie Trost“ ein'),
        findsOneWidget,
      );
      await tapKey(tester, 'join-code-join');
      expect(location(o), '/login?invite=ABCD2345');
      expect(o.onboarding.state, isNull);

      o.session.emit(const NeedsHousehold('peter'));
      await tester.pumpAndSettle();
      expect(location(o), '/your-name?invite=ABCD2345');
      expect(o.session.joins, isEmpty);

      askName.value = false;
      await tester.pumpAndSettle();
      expect(o.session.joins, [('ABCD2345', JoinMethod.code)]);
      expect(key('join-confirm'), findsNothing);
      expect(location(o), '/');
      expect(o.session.creates, isEmpty);
    }, variant: phones);
  });

  group('an invite link', () {
    testWidgets(
      'joins at once with only joiner-direct-list on: no confirm tap',
      (tester) async {
        final o = await pumpOnboarding(
          tester,
          location: '/join/ABCD2345',
          flags: flagsOn(),
        );
        expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
        expect(location(o), '/');
      },
      variant: phones,
    );

    testWidgets('waits for the confirm with both flags off', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        flags: flagsOn(joinerDirect: false),
      );
      expect(key('join-confirm'), findsOneWidget);
      expect(o.session.joins, isEmpty);
      expect(location(o), '/join/ABCD2345');
    }, variant: phones);

    testWidgets('joins once the flag arrives after the preview', (
      tester,
    ) async {
      final flags = Flags();
      addTearDown(flags.close);
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        flags: flags,
      );
      expect(o.session.joins, isEmpty);
      flags.replace({joinerDirectListFlag: true});
      await tester.pumpAndSettle();
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
    });

    testWidgets('a household that confirms joins still waits for its admin', (
      tester,
    ) async {
      final flags = Flags();
      addTearDown(flags.close);
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        flags: flags,
      );
      o.session.requestNext = const Household(id: 'club', name: 'Sommerfest');
      flags.replace({joinerDirectListFlag: true});
      await tester.pumpAndSettle();
      expect(o.session.joins, hasLength(1));
      expect(key('join-request-waiting'), findsOneWidget);
      expect(o.session.state, isA<NeedsHousehold>());
    });
  });
}
