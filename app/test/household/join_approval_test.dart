import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

String _location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

const _verein = Household(id: 'verein', name: 'Sommerfest');
const _waiting = JoinRequest(
  id: 'r1',
  householdId: 'verein',
  householdName: 'Sommerfest',
);

const _sent =
    'Anfrage gesendet: Ein Admin von „Sommerfest“ bestätigt '
    'deinen Beitritt.';

Household _home({
  HouseholdRole role = HouseholdRole.owner,
  bool joinApproval = false,
}) => Household(
  id: 'home',
  name: 'Zuhause',
  isDefault: true,
  role: role,
  joinApproval: joinApproval,
);

/// The invite ABCD2345 leads to Sommerfest.
FakeInvites _sommerfest() =>
    FakeInvites()..households['ABCD2345'] = 'Sommerfest';

void main() {
  group('the joiner (job 169b W3 M)', () {
    testWidgets('in a household: the join waits, nothing switches', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: _sommerfest(),
      );
      o.session.requestNext = _verein;
      await tapKey(tester, 'join-confirm');
      expect(find.text(_sent), findsOneWidget);
      expect(o.pending.code, isNull, reason: 'the invite is answered');
      expect((o.session.state as InHousehold).household.id, 'home');
      await tapKey(tester, 'join-request-go-on');
      expect(_location(o), '/');
    });

    testWidgets('without a household: wait, or create one instead through '
        'the guided start', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: _sommerfest(),
      );
      o.session.requestNext = _verein;
      await tapKey(tester, 'join-confirm');
      expect(find.text(_sent), findsOneWidget);
      expect(find.text('Eigenen Haushalt anlegen'), findsOneWidget);
      await tapKey(tester, 'join-request-go-on');
      expect(_location(o), '/start/who');
      expect(find.text('Mit wem kaufst du ein?'), findsOneWidget);
    });

    testWidgets('approved during that guided start: its questions go on, '
        'and it makes a household of its own beside the joined one', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: _sommerfest(),
      );
      o.session.requestNext = _verein;
      await tapKey(tester, 'join-confirm');
      await tapKey(tester, 'join-request-go-on');
      expect(_location(o), '/start/who');
      o.session.emit(const InHousehold('peter', _verein, [_verein]));
      await tester.pumpAndSettle();
      expect(_location(o), '/start/who', reason: 'the questions go on');
      await tapKey(tester, 'onboarding-kind-family');
      await tapKey(tester, 'onboarding-next');
      await tapKey(tester, 'onboarding-next');
      await tapKey(tester, 'onboarding-skip');
      await tapKey(tester, 'onboarding-staple-Milch');
      await tapKey(tester, 'onboarding-next');
      expect(o.session.creates, [('Unsere Familie', '')]);
      final own = (o.session.state as InHousehold).household.id;
      expect(own, isNot('verein'));
      expect(o.backend.items['verein'], isNull, reason: 'the club list');
      expect(o.backend.items[own]?.map((i) => i.text), ['Milch']);
      expect(_location(o), '/start/invite');
    });

    for (final (who, own) in [('peter', true), ('lea', false)]) {
      testWidgets('signed in again at its account step as '
          '${own ? 'the same user' : 'someone else'}: '
          '${own ? 'a household of its own' : 'the items on theirs'}', (
        tester,
      ) async {
        final o = await pumpOnboarding(
          tester,
          location: '/start/account',
          session: const InHousehold('peter', _verein, [_verein]),
          draft: OnboardingDraft(
            step: OnboardingStep.account,
            kinds: const [HouseholdKind.family],
            items: const [DraftItem(id: 'i1', text: 'Milch')],
            ownHouseholdFor: who,
            requestId: 'r-1',
          ),
        );
        if (own) {
          expect(o.session.creates, [('Unsere Familie', '')]);
          final mine = (o.session.state as InHousehold).household.id;
          expect(o.backend.items[mine]?.map((i) => i.text), ['Milch']);
          expect(o.backend.items['verein'], isNull);
          expect(_location(o), '/start/invite');
        } else {
          expect(o.session.creates, isEmpty);
          expect(o.backend.items['verein']?.map((i) => i.text), ['Milch']);
          expect(_location(o), '/');
        }
      });
    }

    testWidgets('after a restart Step 1 is the wait', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: welcomePath,
        session: const NeedsHousehold('peter', requests: [_waiting]),
      );
      expect(_location(o), joinWaitingPath);
      expect(find.text(_sent), findsOneWidget);
    });

    testWidgets('withdrawn: back to Step 1', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: joinWaitingPath,
        session: const NeedsHousehold('peter', requests: [_waiting]),
      );
      await tapKey(tester, 'join-request-withdraw');
      expect(o.session.withdrawn, ['verein']);
      expect(_location(o), welcomePath);
      expect(find.text(_sent), findsNothing);
    });

    testWidgets('a refused withdraw says why and keeps waiting', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: joinWaitingPath,
        session: const NeedsHousehold('peter', requests: [_waiting]),
      );
      o.session.fail = HouseholdProblem.offline;
      await tapKey(tester, 'join-request-withdraw');
      expect(_key('join-request-problem'), findsOneWidget);
      expect(_location(o), joinWaitingPath);
    });

    testWidgets('approved: on to the list, which shows the household', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: _sommerfest(),
      );
      o.session.requestNext = _verein;
      await tapKey(tester, 'join-confirm');
      o.session.emit(const InHousehold('peter', _verein, [home, _verein]));
      await tester.pumpAndSettle();
      expect(_location(o), '/');
      expect(find.text('LIST'), findsOneWidget);
    });

    for (final (locale, text) in [
      (
        const Locale('de'),
        'Deine Anfrage für diesen Haushalt wurde vor Kurzem abgelehnt. Du '
            'kannst nach 24 Stunden wieder anfragen.',
      ),
      (
        const Locale('en'),
        'Your request to join this household was declined recently. You can '
            'ask again after 24 hours.',
      ),
    ]) {
      testWidgets('$locale: declined in the last day, said plainly, not as '
          'an error', (tester) async {
        final o = await pumpOnboarding(
          tester,
          location: '/join/ABCD2345',
          session: inHome,
          invites: _sommerfest(),
          locale: locale,
        );
        o.session.fail = HouseholdProblem.declinedRecently;
        await tapKey(tester, 'join-confirm');
        expect(find.text(text), findsOneWidget);
        final shown = tester.widget<Text>(find.text(text));
        final colors = Theme.of(tester.element(find.text(text))).colorScheme;
        expect(shown.style?.color, colors.onSurfaceVariant);
        expect((o.session.state as InHousehold).requests, isEmpty);
      });
    }

    // Job 173: the server refuses a join (or a join request) at 10.
    for (final (locale, text) in [
      (
        const Locale('de'),
        'Du bist schon in 20 Haushalten. Verlasse einen, bevor du einen neuen '
            'anlegst oder beitrittst.',
      ),
      (
        const Locale('en'),
        'You are in 20 households already. Leave one before you create or '
            'join another.',
      ),
    ]) {
      testWidgets('$locale: in 20 households, the join says so', (
        tester,
      ) async {
        final o = await pumpOnboarding(
          tester,
          location: '/join/ABCD2345',
          session: inHome,
          invites: _sommerfest(),
          locale: locale,
        );
        o.session.fail = HouseholdProblem.tooManyHouseholds;
        await tapKey(tester, 'join-confirm');
        expect(find.text(text), findsOneWidget);
        expect((o.session.state as InHousehold).households, hasLength(1));
      });
    }

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: joinWaitingPath,
        session: const NeedsHousehold('peter', requests: [_waiting]),
        locale: const Locale('en'),
      );
      expect(
        find.text(
          'Request sent. An admin of “Sommerfest” needs to approve it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Withdraw request'), findsOneWidget);
      expect(find.text('Create your own household'), findsOneWidget);
    });
  });

  group('the household page (job 169b W3 M)', () {
    const lea = PendingJoin(id: 'r1', userId: 'lea', displayName: 'Lea');
    const max = PendingJoin(id: 'r2', userId: 'max', displayName: '');

    FakeInvites waiting() => FakeInvites()..requestLists['home'] = [lea, max];

    testWidgets('a member sees no approval', (tester) async {
      final invites = waiting();
      await pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold('peter', _home(role: HouseholdRole.member), [
          _home(role: HouseholdRole.member),
        ]),
        invites: invites,
      );
      expect(_key('join-approval'), findsNothing);
      expect(find.text('Beitritte bestätigen'), findsNothing);
      expect(invites.requestWatchers, isEmpty);
    });

    for (final role in [HouseholdRole.owner, HouseholdRole.admin]) {
      testWidgets('the $role sees the requests with their count', (
        tester,
      ) async {
        final shown = _home(role: role, joinApproval: true);
        await pumpOnboarding(
          tester,
          location: householdPath,
          session: InHousehold('peter', shown, [shown]),
          invites: waiting(),
        );
        await scrollTo(tester, _key('join-requests-count'));
        expect(find.text('Beitritte bestätigen'), findsOneWidget);
        expect(
          find.text('Neue Leute warten, bis ein Admin sie aufnimmt.'),
          findsOneWidget,
        );
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('2 offene Anfragen'), findsOneWidget);
        semantics.dispose();
        await scrollTo(tester, _key('join-request-r2'));
        expect(
          find.descendant(
            of: _key('join-request-r1'),
            matching: find.text('Lea'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _key('join-request-r2'),
            matching: find.text('Ohne Namen'),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('the switch turns approval on', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold('peter', _home(), [_home()]),
      );
      await scrollTo(tester, _key('join-approval-switch'));
      expect(find.text('Keine offenen Anfragen.'), findsNothing);
      await tapKey(tester, 'join-approval-switch');
      expect(o.invites.approvals, [('home', true)]);
      expect(o.session.refreshes, greaterThan(0));
    });

    testWidgets('on, with nobody waiting, says so', (tester) async {
      final shown = _home(joinApproval: true);
      await pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold('peter', shown, [shown]),
      );
      await scrollTo(tester, _key('join-requests-none'));
      expect(find.text('Keine offenen Anfragen.'), findsOneWidget);
      expect(_key('join-requests-count'), findsNothing);
    });

    testWidgets('approve and decline: decided, counted, gone', (tester) async {
      final shown = _home(joinApproval: true);
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold('peter', shown, [shown]),
        invites: waiting(),
      );
      await tapKey(tester, 'join-request-approve-r1');
      await tapKey(tester, 'join-request-decline-r2');
      expect(o.invites.decisions, [('r1', true), ('r2', false)]);
      expect(_key('join-request-r1'), findsNothing);
      expect(_key('join-request-r2'), findsNothing);
      expect(_key('join-requests-count'), findsNothing);
      final events = await sentEvents(tester, o);
      expect(
        [
          for (final e in events)
            (e['event'], (e['properties']! as Map)['approved']),
        ],
        [('join_request_decided', true), ('join_request_decided', false)],
      );
    });

    for (final (locale, note) in [
      (
        'de',
        'Die Einladung zu dieser Anfrage ist voll. Schick einen neuen Link. '
            'Sobald er geöffnet ist, kannst du aufnehmen.',
      ),
      (
        'en',
        "The invite for this request is full. Send a new link. Once it's "
            'opened, you can let them in.',
      ),
    ]) {
      testWidgets('$locale: a full invite keeps the request and says why', (
        tester,
      ) async {
        final shown = _home(joinApproval: true);
        final invites = waiting()..fullRequests.add('r1');
        final o = await pumpOnboarding(
          tester,
          location: householdPath,
          session: InHousehold('peter', shown, [shown]),
          invites: invites,
          locale: Locale(locale),
        );
        await tapKey(tester, 'join-request-approve-r1');
        expect(o.invites.decisions, [('r1', true)]);
        expect(_key('join-request-r1'), findsOneWidget);
        expect(
          find.descendant(
            of: _key('join-request-r1'),
            matching: find.text(note),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _key('join-request-r2'),
            matching: find.text(note),
          ),
          findsNothing,
        );
        expect(await sentEvents(tester, o), isEmpty, reason: 'not decided');
      });
    }

    testWidgets('a request arriving over realtime shows', (tester) async {
      final shown = _home(joinApproval: true);
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold('peter', shown, [shown]),
      );
      o.invites.requestLists['home'] = [lea];
      o.invites.requestWatchers['home']!();
      await tester.pumpAndSettle();
      await scrollTo(tester, _key('join-request-r1'));
      await scrollTo(tester, _key('join-requests-count'));
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('1 offene Anfrage'), findsOneWidget);
      semantics.dispose();
    });
  });
}
