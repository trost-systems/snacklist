import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../purchases/fakes.dart';
import 'harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

const offline =
    'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';

void main() {
  group('Step 1', () {
    testWidgets('offers create and join; create starts the guided start at '
        '"Mit wem"', (tester) async {
      final o = await pumpOnboarding(tester, location: '/');
      expect(location(o), '/welcome');
      expect(find.text('Willkommen bei Snacklist'), findsOneWidget);
      expect(find.text('Haushalt erstellen'), findsOneWidget);
      expect(find.text('Einladung annehmen'), findsOneWidget);
      await tapKey(tester, 'onboarding-join');
      expect(location(o), '/join');
      o.router.go('/welcome');
      await tester.pumpAndSettle();
      await tapKey(tester, 'onboarding-create');
      expect(location(o), '/start/who');
      expect(find.text('Mit wem kaufst du ein?'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(tester, location: '/', locale: const Locale('en'));
      expect(find.text('Welcome to Snacklist'), findsOneWidget);
      expect(find.text('Create a household'), findsOneWidget);
      expect(find.text('Join with an invite'), findsOneWidget);
    });

    testWidgets('a pending invite skips it and opens the join screen', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        pendingCode: 'ABCD2345',
      );
      expect(location(o), '/join/ABCD2345');
      expect(find.text('Familie Trost'), findsOneWidget);
    });
  });

  group('Step 2b: join', () {
    testWidgets('a link shows the household; Join joins by link', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      expect(o.pending.code, 'ABCD2345');
      expect(find.text('Einladung in den Haushalt'), findsOneWidget);
      expect(find.text('Familie Trost'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ABCD2345'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
    });

    testWidgets('a typed code is checked, then joined by code', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join');
      await tester.enterText(key('invite-code'), 'abcd-2345');
      await tapKey(tester, 'invite-check');
      expect(o.invites.previews, ['ABCD2345']);
      expect(find.text('Familie Trost'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.code)]);
      expect(location(o), '/');
    });

    testWidgets('an edited link code is a typed code', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.invites.households['WXYZ6789'] = 'Nachbarn';
      await tester.enterText(key('invite-code'), 'WXYZ6789');
      await tester.pump();
      // The preview went with the old code.
      expect(key('invite-household'), findsNothing);
      await tapKey(tester, 'invite-check');
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('WXYZ6789', JoinMethod.code)]);
    });

    testWidgets('an invalid code: one message, the code stays, the link '
        'is forgotten', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ZZZZ2345');
      expect(
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'ZZZZ2345'), findsOneWidget);
      expect(o.pending.code, isNull);
      expect(o.session.joins, isEmpty);
      // Retry with a good one.
      await tester.enterText(key('invite-code'), 'ABCD2345');
      await tapKey(tester, 'invite-check');
      expect(find.text('Familie Trost'), findsOneWidget);
    });

    testWidgets('the rate limit says so and keeps the code', (tester) async {
      final invites = FakeInvites()..next = HouseholdProblem.tooManyAttempts;
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: invites,
      );
      expect(
        find.text('Zu viele Versuche. Bitte später noch einmal.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'ABCD2345'), findsOneWidget);
    });

    testWidgets('offline at the preview, then back: the retry works', (
      tester,
    ) async {
      final invites = FakeInvites()..next = HouseholdProblem.offline;
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: invites,
      );
      expect(find.text(offline), findsOneWidget);
      expect(o.pending.code, 'ABCD2345', reason: 'offline is no answer');
      await tapKey(tester, 'invite-check');
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('offline at the join keeps the preview; the retry joins once', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.session.fail = HouseholdProblem.offline;
      await tapKey(tester, 'join-confirm');
      expect(find.text(offline), findsOneWidget);
      expect(find.text('Familie Trost'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, hasLength(2));
      expect(location(o), '/');
    });

    testWidgets('a double tap on Join joins once', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.session.hold = Completer();
      await tester.tap(key('join-confirm'));
      await tester.pump();
      await tester.tap(key('join-confirm'), warnIfMissed: false);
      await tester.pump();
      o.session.hold!.complete();
      await tester.pumpAndSettle();
      expect(o.session.joins, hasLength(1));
    });

    testWidgets('an MCP authorization on the way survives the join', (
      tester,
    ) async {
      const next = '/oauth/consent?authorization_id=abc';
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345?next=${Uri.encodeComponent(next)}',
      );
      await tapKey(tester, 'join-confirm');
      expect(location(o), next);
    });

    testWidgets('a typo after a link keeps the link pending', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      await tester.enterText(key('invite-code'), 'ZZZZ2345');
      await tester.pump();
      await tapKey(tester, 'invite-check');
      expect(
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
        findsOneWidget,
      );
      expect(o.pending.code, 'ABCD2345');
    });

    testWidgets('Cancel forgets the link and goes back to Step 1', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      await tapKey(tester, 'join-cancel');
      expect(o.pending.code, isNull);
      expect(location(o), '/welcome');
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ZZZZ2345',
        locale: const Locale('en'),
      );
      expect(find.text('This code is invalid or has expired.'), findsOneWidget);
      expect(find.text('Join with an invite'), findsOneWidget);
    });
  });

  group('joining from a household adds it (job 169b)', () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets('a link shows no move warning; Join is the main answer', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
      );
      expect(find.text('Haushalt beitreten'), findsWidgets);
      expect(find.textContaining('verlässt'), findsNothing);
      expect(find.textContaining('gelöscht'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Haushalt beitreten'),
        findsOneWidget,
      );
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
      final state = o.session.state as InHousehold;
      expect(state.household.id, 'other', reason: 'the joined one shows');
      expect([for (final h in state.households) h.id], ['home', 'other']);
    });

    testWidgets('Cancel moves nobody and answers the link', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
      );
      await tapKey(tester, 'join-cancel');
      expect(o.session.joins, isEmpty);
      expect(o.pending.code, isNull);
      expect(location(o), '/');
    });

    testWidgets("a link of one of the user's households shows it on the "
        'list (job 169b)', (tester) async {
      final invites = FakeInvites()..own.add('ABCD2345');
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: const InHousehold('peter', home, [
          home,
          Household(id: 'other', name: 'Familie Trost'),
        ]),
        invites: invites,
      );
      expect(location(o), '/');
      expect((o.session.state as InHousehold).household.id, 'other');
      expect(o.pending.code, isNull);
    });

    testWidgets('joining asks nothing about a yearly plan: nothing is left', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        premium: FakePremiumServer(
          mine: const MyYearlyPlan(subscriber: true, renewing: true),
        ),
      );
      await tapKey(tester, 'join-confirm');
      expect(key('premium-billing-continues'), findsNothing);
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        locale: const Locale('en'),
      );
      expect(find.text('Join a household'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('Snacklist Lifetime at the join (job 43)', () {
    const inHome = InHousehold('peter', home, [home]);
    FakeInvites says(JoinLifetime lifetime) =>
        FakeInvites()..lifetime['ABCD2345'] = lifetime;

    testWidgets('(a) the household has it: nothing to buy', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: says(const JoinLifetime(targetUnlocked: true)),
      );
      expect(
        find.text(
          'Dieser Haushalt hat Snacklist Lifetime. Du musst nichts kaufen.',
        ),
        findsOneWidget,
      );
      expect(
        key('join-refund-help'),
        findsNothing,
        reason: 'no recent purchase',
      );
      expect(key('join-lifetime-ends'), findsNothing);
    });

    testWidgets('(c) paid recently and it has it: the refund help', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: says(
          const JoinLifetime(targetUnlocked: true, recentPurchase: true),
        ),
      );
      expect(key('join-target-unlocked'), findsOneWidget);
      await tapKey(tester, 'join-refund-help');
      expect(key('refund-help'), findsOneWidget);
      expect(find.text('Kauf zurückfordern'), findsOneWidget);
      // Closing the help (back, or a drag on its handle) keeps the join where
      // it was.
      Navigator.of(tester.element(key('refund-help'))).pop();
      await tester.pumpAndSettle();
      expect(key('refund-help'), findsNothing);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('a recent purchase alone links nothing', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: says(const JoinLifetime(recentPurchase: true)),
      );
      expect(key('join-refund-help'), findsNothing);
      expect(key('join-target-unlocked'), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        locale: const Locale('en'),
        invites: says(
          const JoinLifetime(targetUnlocked: true, recentPurchase: true),
        ),
      );
      expect(
        find.text(
          'This household has Snacklist Lifetime. '
          "You don't need to buy anything.",
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        key('join-confirm'),
        200,
        scrollable: find
            .descendant(
              of: key('join-screen'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text(
          'Bought Snacklist Lifetime recently? How to request a refund',
        ),
        findsOneWidget,
      );
    });
  });

  group("the new household's invite step", () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets("the switcher's Neuer Haushalt creates one more, then "
        'offers its invites, not the guided start', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: newHouseholdPath,
        session: inHome,
      );
      expect(find.text('Neuer Haushalt'), findsOneWidget);
      await tester.enterText(key('household-name'), 'Ferienhaus');
      await tapKey(tester, 'skip-stores');
      expect(o.session.creates, [('Ferienhaus', '')]);
      expect(o.session.origins, [HouseholdOrigin.switcher]);
      expect(location(o), invitePartnerPath);
      expect(key('invite-partner-screen'), findsOneWidget);
      expect(find.text(joinPageHintDe).hitTestable(), findsOneWidget);
      await tapKey(tester, 'invite-later');
      expect(location(o), '/');
      expect(o.onboarding.state, isNull);
    });

    testWidgets('makes one invite, opens the share sheet with link and code', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: invitePartnerPath,
        session: inHome,
      );
      expect(find.text('Später'), findsOneWidget);
      o.invites.hold = Completer();
      await tester.tap(key('invite-partner'));
      await tester.pump();
      await tester.tap(key('invite-partner'), warnIfMissed: false);
      o.invites.hold!.complete();
      await tester.pumpAndSettle();
      expect(o.invites.created, hasLength(1));
      final code = o.invites.created.single.code;
      expect(o.sharer.shared, [
        // No APP_URL in tests: the code alone.
        'Komm in unseren Snacklist-Haushalt. Code: $code',
      ]);
      expect(find.bySemanticsLabel('Code $code'), findsOneWidget);
      expect(
        find.textContaining('gültig bis 6. November 2026'),
        findsOneWidget,
      );
      final events = await sentEvents(tester, o);
      expect(events.map((e) => e['event']), ['invite_sent']);
      final properties = events.single['properties']! as Map;
      expect(properties['channel'], 'share_sheet');
      expect(properties['context'], 'onboarding');
      expect(jsonEncode(events), isNot(contains(code)));
      await tapKey(tester, 'invite-later');
      expect(location(o), '/');
    });

    testWidgets('without a share sheet: copy the code, counted once', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: invitePartnerPath,
        session: inHome,
        sharer: FakeSharer(available: false),
      );
      await tapKey(tester, 'invite-partner');
      expect(o.sharer.shared, isEmpty);
      expect(key('invite-share'), findsNothing);
      await tapKey(tester, 'invite-copy-code');
      expect(o.sharer.copied, [o.invites.created.single.code]);
      expect(find.text('Code kopiert'), findsOneWidget);
      final events = await sentEvents(tester, o);
      expect(events.map((e) => (e['properties']! as Map)['channel']), [
        'copy_code',
      ]);
    });

    testWidgets('offline says so; the retry makes the invite', (tester) async {
      final invites = FakeInvites()..next = HouseholdProblem.offline;
      final o = await pumpOnboarding(
        tester,
        location: invitePartnerPath,
        session: inHome,
        invites: invites,
      );
      await tapKey(tester, 'invite-partner');
      expect(find.text(offline), findsOneWidget);
      expect(o.invites.created, isEmpty);
      await tapKey(tester, 'invite-partner');
      expect(o.invites.created, hasLength(1));
      // Analytics sends what the share queued.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('in English', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: invitePartnerPath,
        session: inHome,
        locale: const Locale('en'),
      );
      expect(find.text('Invite your partner'), findsWidgets);
      expect(find.text(joinPageHintEn).hitTestable(), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      await tapKey(tester, 'invite-partner');
      expect(
        o.sharer.shared.single,
        startsWith('Join our Snacklist household.'),
      );
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group("More's Einladungen", () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets('lists open invites; revoking one removes it', (tester) async {
      final invites = FakeInvites();
      await invites.create('home');
      await invites.create('home');
      final o = await pumpOnboarding(
        tester,
        location: '/more/invites',
        session: inHome,
        invites: invites,
      );
      final [first, second] = invites.created;
      expect(find.text(joinPageHintDe).hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('Code ${first.code}'), findsOneWidget);
      expect(find.bySemanticsLabel('Code ${second.code}'), findsOneWidget);
      final revoke = find.descendant(
        of: key('invite-${first.code}'),
        matching: key('invite-revoke'),
      );
      await scrollTo(tester, revoke);
      await tester.pumpAndSettle();
      await tester.tap(revoke);
      await tester.pumpAndSettle();
      expect(o.invites.revoked, [first.id]);
      expect(find.bySemanticsLabel('Code ${first.code}'), findsNothing);
      expect(find.byType(SnackBar), findsNothing, reason: 'its card is gone');
    });

    testWidgets('a new invite is shared from the settings', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/more/invites',
        session: inHome,
      );
      await tapKey(tester, 'invite-new');
      expect(o.invites.created, hasLength(1));
      final events = await sentEvents(tester, o);
      expect((events.single['properties']! as Map)['context'], 'settings');
    });
  });
}
