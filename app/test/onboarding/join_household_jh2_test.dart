import 'dart:async';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

Flags jh2On() => Flags(forced: {joinHouseholdJh2Flag});

const atName = OnboardingDraft(step: OnboardingStep.name, name: 'Wir');
const atJoin = OnboardingDraft(step: OnboardingStep.join, name: 'Wir');

bool joinEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(key('join-code-join')).onPressed != null;

Future<Onboarding> pumpJoinStep(
  WidgetTester tester, {
  Session session = const SignedOut(),
  FakeInvites? invites,
}) => pumpOnboarding(
  tester,
  location: '/start/join',
  session: session,
  draft: atJoin,
  invites: invites,
  flags: jh2On(),
);

Future<void> enter(WidgetTester tester, String text) async {
  await tester.enterText(key('join-code-field'), text);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(key('join-code-field')).controller!.text;

void main() {
  group('the name step', () {
    testWidgets('offers joining an existing household with JH2, keeping the '
        'name typed', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/name',
        session: const SignedOut(),
        draft: atName,
        flags: jh2On(),
      );
      await tester.enterText(key('household-name'), 'Familie Trost');
      await tapKey(tester, 'onboarding-join-existing');
      expect(location(o), '/start/join');
      expect(find.text('Einladungscode'), findsOneWidget);
      expect(o.onboarding.state?.step, OnboardingStep.join);
      expect(o.onboarding.state?.name, 'Familie Trost');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(o), '/start/name');
      expect(find.text('Familie Trost'), findsOneWidget);
    });

    testWidgets('has no join button with the flag off', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/start/name',
        session: const SignedOut(),
        draft: atName,
      );
      expect(key('onboarding-join-existing'), findsNothing);
      expect(find.text('Bestehendem Haushalt beitreten'), findsNothing);
      expect(key('onboarding-next'), findsOneWidget);
    });
  });

  group('the code step', () {
    testWidgets('looks the code up at the 8th typed character, once, and '
        'shows the household', (tester) async {
      final o = await pumpJoinStep(tester);
      expect(joinEnabled(tester), isFalse);
      const code = 'ABCD2345';
      for (var i = 1; i <= code.length; i++) {
        await enter(tester, code.substring(0, i));
      }
      expect(o.invites.publicPreviews, ['ABCD2345']);
      expect(
        find.text('Peter lädt dich zu „Familie Trost“ ein'),
        findsOneWidget,
      );
      expect(find.text('2 Mitglieder · 5 offene Einträge'), findsOneWidget);
      expect(joinEnabled(tester), isTrue);
    });

    for (final (what, pasted) in [
      ('a whole code', 'ABCD2345'),
      ('a code with its dash, in lower case', 'abcd-2345'),
      (
        'a shared message with a join link',
        'Komm in unseren Haushalt bei Snacklist: '
            'https://app.snacklist.app/join/ABCD2345 (Code ABCD-2345)',
      ),
    ]) {
      testWidgets('a paste of $what looks the code up once', (tester) async {
        final o = await pumpJoinStep(tester);
        await enter(tester, pasted);
        expect(fieldText(tester), 'ABCD2345');
        expect(o.invites.publicPreviews, ['ABCD2345']);
        expect(joinEnabled(tester), isTrue);
      });
    }

    testWidgets('a code pasted after a typed start is the pasted code', (
      tester,
    ) async {
      final o = await pumpJoinStep(tester);
      await enter(tester, 'XY');
      await enter(tester, 'XYABCD-2345');
      expect(fieldText(tester), 'ABCD2345');
      expect(o.invites.publicPreviews, ['ABCD2345']);
    });

    testWidgets('drops characters no code has', (tester) async {
      final o = await pumpJoinStep(tester);
      await enter(tester, 'a0b1-cio');
      expect(fieldText(tester), 'ABC');
      await enter(tester, 'ABCD23456789');
      expect(fieldText(tester), 'ABCD2345');
      expect(o.invites.publicPreviews, ['ABCD2345']);
    });

    testWidgets('an edit after the lookup takes the household away', (
      tester,
    ) async {
      await pumpJoinStep(tester);
      await enter(tester, 'ABCD2345');
      expect(key('join-code-preview'), findsOneWidget);
      await enter(tester, 'ABCD234');
      expect(key('join-code-preview'), findsNothing);
      expect(joinEnabled(tester), isFalse);
    });

    testWidgets('an answer for a code no longer in the field is dropped', (
      tester,
    ) async {
      final invites = FakeInvites()..hold = Completer<void>();
      await pumpJoinStep(tester, invites: invites);
      await tester.enterText(key('join-code-field'), 'ABCD2345');
      await tester.pump();
      await tester.enterText(key('join-code-field'), 'ABCD234');
      await tester.pump();
      invites.hold!.complete();
      await tester.pumpAndSettle();
      expect(key('join-code-preview'), findsNothing);
      expect(find.textContaining('Familie Trost'), findsNothing);
      expect(joinEnabled(tester), isFalse);
    });

    const unavailable =
        'Diese Einladung gilt nicht mehr. Bitte um eine neue Einladung.';
    for (final (what, answer, line) in [
      ('made up', null, unavailable),
      ('full', const PublicInviteUnavailable(), unavailable),
      (
        'rate-limited',
        const PublicInviteRateLimited(),
        'Gerade zu viele Versuche. Versuch es später noch einmal.',
      ),
    ]) {
      testWidgets('a $what code shows one line and no way to join', (
        tester,
      ) async {
        final invites = FakeInvites();
        if (answer != null) {
          invites.publicAnswers['ABCD2345'] = answer;
        }
        final o = await pumpJoinStep(tester, invites: invites);
        await enter(tester, answer == null ? 'WXYZ6789' : 'ABCD2345');
        expect(find.text(line), findsOneWidget);
        expect(key('join-code-preview'), findsNothing);
        expect(joinEnabled(tester), isFalse);
        await tester.tap(key('join-code-join'));
        await tester.pumpAndSettle();
        expect(location(o), '/start/join');
        expect(o.pending.code, isNull);
        expect(o.session.joins, isEmpty);
      });
    }

    testWidgets('offline says so and tries again on its button', (
      tester,
    ) async {
      final invites = FakeInvites()..next = HouseholdProblem.offline;
      final o = await pumpJoinStep(tester, invites: invites);
      await enter(tester, 'ABCD2345');
      expect(
        find.text(
          'Keine Internetverbindung. Versuche es erneut, sobald du online '
          'bist.',
        ),
        findsOneWidget,
      );
      expect(joinEnabled(tester), isFalse);
      await tapKey(tester, 'join-code-retry');
      expect(o.invites.publicPreviews, ['ABCD2345', 'ABCD2345']);
      expect(joinEnabled(tester), isTrue);
    });

    testWidgets('Join signed out keeps the code, ends the guided start and '
        'signs in first', (tester) async {
      final o = await pumpJoinStep(tester);
      await enter(tester, 'ABCD2345');
      await tapKey(tester, 'join-code-join');
      expect(location(o), '/login?invite=ABCD2345');
      expect(o.onboarding.state, isNull);
      expect(o.pending.code, 'ABCD2345');
      expect(o.pending.methodOf('ABCD2345'), JoinMethod.code);
      expect(o.session.joins, isEmpty);
    });

    testWidgets('Join keeps a code that was answered before', (tester) async {
      final o = await pumpJoinStep(tester);
      o.pending
        ..remember('ABCD2345')
        ..clear();
      await enter(tester, 'ABCD2345');
      await tapKey(tester, 'join-code-join');
      expect(location(o), '/login?invite=ABCD2345');
      expect(o.pending.code, 'ABCD2345');
    });

    testWidgets('Join signed in joins without asking again and lands on the '
        'list', (tester) async {
      final o = await pumpJoinStep(
        tester,
        session: const NeedsHousehold('peter'),
      );
      await enter(tester, 'ABCD2345');
      await tapKey(tester, 'join-code-join');
      expect(o.session.joins, [('ABCD2345', JoinMethod.code)]);
      expect(o.onboarding.state, isNull);
      expect(location(o), '/');
      expect(o.backend.items, isEmpty);
    });
  });

  group('an invite link', () {
    testWidgets('joins at once with JH2: one join, no confirm tap', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        flags: jh2On(),
      );
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
    });

    testWidgets('shows the household and progress, no Join, while it joins', (
      tester,
    ) async {
      final flags = Flags();
      addTearDown(flags.close);
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        flags: flags,
      );
      o.session.hold = Completer<void>();
      flags.replace({joinHouseholdJh2Flag: true});
      await tester.pump();
      await tester.pump();
      expect(o.session.joins, hasLength(1));
      expect(find.text('Familie Trost'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(key('join-confirm'), findsNothing);
      o.session.hold!.complete();
      await tester.pumpAndSettle();
      expect(location(o), '/');
    });

    testWidgets('waits for the confirm with the flag off', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      expect(key('join-confirm'), findsOneWidget);
      expect(o.session.joins, isEmpty);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

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
      flags.replace({joinHouseholdJh2Flag: true});
      await tester.pumpAndSettle();
      flags.replace({joinHouseholdJh2Flag: true, 'other': true});
      await tester.pumpAndSettle();
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
    });

    testWidgets('a typed code in the join field still needs the tap', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join', flags: jh2On());
      await tester.enterText(key('invite-code'), 'ABCD2345');
      await tapKey(tester, 'invite-check');
      expect(key('join-confirm'), findsOneWidget);
      expect(o.session.joins, isEmpty);
    });

    testWidgets('drops a guided start not set up yet before joining, so no '
        'setup runs into that household', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        draft: const OnboardingDraft(
          step: OnboardingStep.stores,
          name: 'Wir',
          items: [DraftItem(id: 'i1', text: 'Milch')],
        ),
        flags: jh2On(),
      );
      expect(o.session.joins, hasLength(1));
      expect(o.onboarding.state, isNull);
      expect(location(o), '/');
      expect(o.backend.items, isEmpty);
    });

    testWidgets('a refused link shows the field as before', (tester) async {
      final invites = FakeInvites()..households.clear();
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: invites,
        flags: jh2On(),
      );
      expect(key('join-problem'), findsOneWidget);
      expect(key('invite-code'), findsOneWidget);
      expect(o.session.joins, isEmpty);
    });
  });

  group('the approval wait', () {
    const waiting = NeedsHousehold(
      'peter',
      requests: [
        JoinRequest(id: 'r1', householdId: 'club', householdName: 'Sommerfest'),
      ],
    );

    testWidgets('with JH2 says what happens and offers an own list as a '
        'text button', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/welcome/waiting',
        session: waiting,
        flags: jh2On(),
      );
      expect(
        find.text(
          'Deine Anfrage liegt bei „Sommerfest“. Ein Admin sieht dort deinen '
          'Namen und lässt dich rein. Deine Liste öffnet sich von selbst, '
          'sobald das passiert.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Eigenen Haushalt anlegen'), findsNothing);
      expect(
        find.widgetWithText(TextButton, 'Lieber eigene Liste anlegen'),
        findsOneWidget,
      );
      await tapKey(tester, 'join-request-go-on');
      expect(o.onboarding.state?.ownHouseholdFor, 'peter');
      expect(location(o), '/start/who');
    });

    testWidgets('without the flag keeps its words and button', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/welcome/waiting',
        session: waiting,
      );
      expect(
        find.text(
          'Anfrage gesendet: Ein Admin von „Sommerfest“ bestätigt deinen '
          'Beitritt.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Eigenen Haushalt anlegen'),
        findsOneWidget,
      );
    });

    testWidgets('in a household with JH2 still goes to the list', (
      tester,
    ) async {
      final flags = Flags();
      addTearDown(flags.close);
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        flags: flags,
      );
      o.session.requestNext = const Household(id: 'club', name: 'Sommerfest');
      flags.replace({joinHouseholdJh2Flag: true});
      await tester.pumpAndSettle();
      expect(key('join-request-waiting'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Zur Liste'), findsOneWidget);
      expect(find.text('Lieber eigene Liste anlegen'), findsNothing);
    });
  });

  group('the start screens', () {
    testWidgets("with JH2: Los geht's and Schon ein Konto, no paste", (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        flags: jh2On(),
      );
      expect(location(o), '/start');
      expect(find.text("Los geht's"), findsOneWidget);
      expect(find.text('Schon ein Konto'), findsOneWidget);
      expect(key('invite-paste'), findsNothing);
      await tapKey(tester, 'start-log-in');
      expect(location(o), '/login');
    });

    testWidgets('Willkommen has no paste with JH2', (tester) async {
      await pumpOnboarding(tester, location: '/welcome', flags: jh2On());
      expect(key('onboarding-create'), findsOneWidget);
      expect(key('invite-paste'), findsNothing);
    });

    testWidgets('without the flag both keep the paste', (tester) async {
      await pumpOnboarding(tester, location: '/welcome');
      expect(key('invite-paste'), findsOneWidget);
    });
  });
}
