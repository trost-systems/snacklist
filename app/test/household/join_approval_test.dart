import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    testWidgets('without a household: wait, or create one instead', (
      tester,
    ) async {
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
      expect(_location(o), createHouseholdPath);
    });

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

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: joinWaitingPath,
        session: const NeedsHousehold('peter', requests: [_waiting]),
        locale: const Locale('en'),
      );
      expect(
        find.text('Request sent: an admin of “Sommerfest” will let you in.'),
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
