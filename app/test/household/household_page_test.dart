import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../purchases/fakes.dart';
import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

String _location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

const _club = Household(id: 'club', name: 'Sommerfest', memberCount: 12);

/// Peter sees [shown] of Zuhause (his default) and Sommerfest.
InHousehold _peterIn(Household shown) =>
    InHousehold('peter', shown, const [home, _club]);

FakeInvites _members(String household, List<String> names) =>
    FakeInvites()
      ..memberLists[household] = [
        for (final name in names)
          HouseholdMember(userId: name.toLowerCase(), displayName: name),
      ];

void main() {
  testWidgets('shows the name, the members and that it is the default', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
      invites: _members('home', ['Peter', 'Lea', '']),
    );
    expect(find.text('Zuhause'), findsOneWidget);
    expect(find.text('Peter (du)'), findsOneWidget);
    expect(find.text('Lea'), findsOneWidget);
    expect(find.text('Ohne Namen'), findsOneWidget);
    expect(
      find.text('Siri, Alexa und KI-Assistenten nutzen diesen Haushalt.'),
      findsOneWidget,
    );
  });

  testWidgets('another household names the default and can become it', (
    tester,
  ) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(_club),
    );
    expect(
      find.text('Siri, Alexa und KI-Assistenten nutzen gerade „Zuhause“.'),
      findsOneWidget,
    );
    await tapKey(tester, 'household-default');
    expect(o.session.defaults, ['club']);
    expect(
      find.text('Siri, Alexa und KI-Assistenten nutzen diesen Haushalt.'),
      findsOneWidget,
    );
    expect(_key('household-default'), findsNothing, reason: 'it stays on');
  });

  testWidgets('rename: an empty name is refused, a new one saved', (
    tester,
  ) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
    );
    await tester.tap(_key('household-rename'));
    await tester.pumpAndSettle();
    expect(find.text('Haushalt umbenennen'), findsOneWidget);
    await tester.enterText(_key('household-rename-field'), '   ');
    await tester.tap(_key('household-rename-save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Gib einen Namen mit 1 bis 80 Zeichen ein.'),
      findsOneWidget,
    );
    await tester.enterText(_key('household-rename-field'), 'Wohnung ');
    await tester.tap(_key('household-rename-save'));
    await tester.pumpAndSettle();
    expect(o.session.renames, [('home', 'Wohnung')]);
    expect(find.text('Wohnung'), findsOneWidget);
  });

  testWidgets('leaving a shared household: the others keep the list', (
    tester,
  ) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
      invites: _members('home', ['Peter', 'Lea']),
    );
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    expect(find.text('„Zuhause“ verlassen?'), findsOneWidget);
    expect(
      find.text(
        'Die anderen Mitglieder behalten die Liste. Zurück kommst du nur mit '
        'einer neuen Einladung.',
      ),
      findsOneWidget,
    );
    await tester.tap(_key('household-leave-confirm'));
    await tester.pumpAndSettle();
    expect(o.session.leaves, [('home', false)]);
    expect(_location(o), listPath);
    expect((o.session.state as InHousehold).household.id, 'club');
  });

  testWidgets('the dialog reads the members when it opens, not when the page '
      'did', (tester) async {
    final invites = _members('home', ['Peter', 'Lea']);
    await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
      invites: invites,
    );
    expect(find.text('Lea'), findsOneWidget);
    // Lea leaves on her phone while Peter's page is open.
    invites.memberLists['home'] = [
      const HouseholdMember(userId: 'peter', displayName: 'Peter'),
    ];
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Du bist das letzte Mitglied. Der Haushalt wird mit Liste, Verlauf, '
        'Kategorien und Geschäften gelöscht.',
      ),
      findsOneWidget,
    );
    await tester.tap(_key('household-leave-cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Lea'), findsNothing, reason: 'the page shows them too');
  });

  testWidgets('cancel leaves nothing', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
    );
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    await tester.tap(_key('household-leave-cancel'));
    await tester.pumpAndSettle();
    expect(o.session.leaves, isEmpty);
    expect(_location(o), householdPath);
  });

  testWidgets('a double tap on leave opens one dialog', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
    );
    // The members are asked again first; both taps land while that is out.
    final hold = o.invites.hold = Completer<void>();
    await tester.tap(_key('household-leave'));
    await tester.pump();
    await tester.tap(_key('household-leave'));
    await tester.pump();
    hold.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('household-leave-cancel'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('the last member hears that the household goes', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
    );
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Du bist das letzte Mitglied. Der Haushalt wird mit Liste, Verlauf, '
        'Kategorien und Geschäften gelöscht.',
      ),
      findsOneWidget,
    );
    expect(_key('household-leave-refund-help'), findsNothing);
    await tester.tap(_key('household-leave-confirm'));
    await tester.pumpAndSettle();
    expect(o.session.leaves, [('home', false)]);
  });

  testWidgets('leaving the last household goes to onboarding', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: inHome,
    );
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    await tester.tap(_key('household-leave-confirm'));
    await tester.pumpAndSettle();
    expect(o.session.state, isA<NeedsHousehold>());
    expect(_location(o), welcomePath);
  });

  group('Snacklist Lifetime of the last member (job 43)', () {
    FakeInvites unlocked() => FakeInvites()..unlocked.add('home');

    testWidgets('it ends with the household: said, with the refund help', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        invites: unlocked(),
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Snacklist Lifetime endet mit ihm'),
        findsOneWidget,
      );
      expect(_key('household-leave-refund-help'), findsOneWidget);
      await tester.tap(_key('household-leave-confirm'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, [('home', false)]);
    });

    testWidgets('with archiving: archive and leave keeps it', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        invites: unlocked(),
        archiveOffered: true,
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Archiviere den Haushalt, statt ihn zu löschen'),
        findsOneWidget,
      );
      expect(_key('household-leave-confirm'), findsNothing);
      await tester.tap(_key('household-leave-archive'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, [('home', true)]);
    });

    testWidgets('with archiving: delete and leave deletes', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        invites: unlocked(),
        archiveOffered: true,
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-delete'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, [('home', false)]);
    });
  });

  group('a yearly plan keeps being billed when leaving (H-85)', () {
    const subscriber = MyYearlyPlan(subscriber: true, renewing: true);

    testWidgets('the subscriber hears so, then leaves', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        premium: FakePremiumServer(mine: subscriber),
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-confirm'));
      await tester.pumpAndSettle();
      expect(_key('premium-billing-continues'), findsOneWidget);
      expect(o.session.leaves, isEmpty);
      await tester.tap(_key('premium-billing-continue'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, [('home', false)]);
    });

    testWidgets('Abo verwalten stays', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        premium: FakePremiumServer(mine: subscriber),
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-confirm'));
      await tester.pumpAndSettle();
      await tester.tap(_key('premium-billing-manage'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, isEmpty);
    });

    testWidgets('another member of a billed household: the short line', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: householdPath,
        session: _peterIn(home),
        premium: FakePremiumServer(
          mine: const MyYearlyPlan(householdBilled: true),
        ),
      );
      await tester.tap(_key('household-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-confirm'));
      await tester.pumpAndSettle();
      expect(_key('premium-billing-other'), findsOneWidget);
      await tester.tap(_key('premium-billing-cancel'));
      await tester.pumpAndSettle();
      expect(o.session.leaves, isEmpty);
    });
  });

  testWidgets('a refusal is told, the household stays', (tester) async {
    final o = await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(home),
    );
    o.session.fail = HouseholdProblem.offline;
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    await tester.tap(_key('household-leave-confirm'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Keine Internetverbindung. Versuche es erneut, sobald du online bist.',
      ),
      findsOneWidget,
    );
    expect(_location(o), householdPath);
  });

  testWidgets('in English', (tester) async {
    await pumpOnboarding(
      tester,
      location: householdPath,
      session: _peterIn(_club),
      locale: const Locale('en'),
    );
    expect(find.text('Make default'), findsOneWidget);
    expect(
      find.text('Siri, Alexa and AI assistants now use “Zuhause”.'),
      findsOneWidget,
    );
    expect(find.text('Peter (you)'), findsOneWidget);
    await tester.tap(_key('household-leave'));
    await tester.pumpAndSettle();
    expect(find.text('Leave “Sommerfest”?'), findsOneWidget);
  });

  group('members and their roles (job 169b W2)', () {
    FakeInvites crew() => FakeInvites()
      ..memberLists['home'] = const [
        HouseholdMember(
          userId: 'peter',
          displayName: 'Peter',
          role: HouseholdRole.owner,
        ),
        HouseholdMember(
          userId: 'lea',
          displayName: 'Lea',
          role: HouseholdRole.admin,
        ),
        HouseholdMember(userId: 'tom', displayName: 'Tom'),
      ];

    Future<Onboarding> pumpAs(
      WidgetTester tester,
      String user,
      HouseholdRole role, {
      FakeInvites? invites,
    }) {
      final household = Household(
        id: 'home',
        name: 'Zuhause',
        isDefault: true,
        role: role,
      );
      return pumpOnboarding(
        tester,
        location: householdPath,
        session: InHousehold(user, household, [household]),
        invites: invites ?? crew(),
      );
    }

    Future<List<String>> menuOf(WidgetTester tester, String user) async {
      await tester.tap(_key('member-actions-$user'));
      await tester.pumpAndSettle();
      final items = [
        for (final item in tester.widgetList<PopupMenuItem<Object?>>(
          find.byWidgetPredicate((w) => w is PopupMenuItem),
        ))
          (item.key! as ValueKey<String>).value,
      ];
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return items;
    }

    testWidgets('roles show under the names', (tester) async {
      await pumpAs(tester, 'peter', HouseholdRole.owner);
      expect(
        find.descendant(
          of: _key('member-peter'),
          matching: find.text('Hauptadmin'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _key('member-lea'), matching: find.text('Admin')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _key('member-tom'), matching: find.text('Tom')),
        findsOneWidget,
      );
    });

    testWidgets('the owner names admins and removes anyone but themselves', (
      tester,
    ) async {
      await pumpAs(tester, 'peter', HouseholdRole.owner);
      expect(_key('member-actions-peter'), findsNothing);
      expect(await menuOf(tester, 'lea'), [
        'member-removeAdmin',
        'member-remove',
      ]);
      expect(await menuOf(tester, 'tom'), [
        'member-makeAdmin',
        'member-remove',
      ]);
    });

    testWidgets('an admin removes members only; a member does nothing', (
      tester,
    ) async {
      await pumpAs(tester, 'lea', HouseholdRole.admin);
      expect(_key('member-actions-peter'), findsNothing);
      expect(_key('member-actions-lea'), findsNothing);
      expect(await menuOf(tester, 'tom'), ['member-remove']);
    });

    testWidgets('someone made admin elsewhere gets the admin menu at once', (
      tester,
    ) async {
      // The session still says member; the members list just read says admin.
      await pumpAs(tester, 'lea', HouseholdRole.member);
      expect(await menuOf(tester, 'tom'), ['member-remove']);
    });

    testWidgets('a member has no member actions', (tester) async {
      await pumpAs(tester, 'tom', HouseholdRole.member);
      expect(find.byWidgetPredicate((w) => w is PopupMenuButton), findsNothing);
    });

    testWidgets('removing asks, naming the person; then the list refreshes', (
      tester,
    ) async {
      final o = await pumpAs(tester, 'peter', HouseholdRole.owner);
      await tester.tap(_key('member-actions-tom'));
      await tester.pumpAndSettle();
      await tester.tap(_key('member-remove'));
      await tester.pumpAndSettle();
      expect(find.text('Tom entfernen?'), findsOneWidget);
      expect(
        find.text(
          'Tom sieht die Liste von „Zuhause“ dann nicht mehr und kommt über '
          'bisherige Einladungen oder den jetzigen Gruppenlink nicht zurück. '
          'In den nächsten 30 Tagen holt Tom nur eine neue Einladung oder '
          'ein neuer Gruppenlink von einem Admin zurück.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(o.invites.removed, isEmpty);
      await tester.tap(_key('member-actions-tom'));
      await tester.pumpAndSettle();
      await tester.tap(_key('member-remove'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'member-remove-confirm');
      expect(o.invites.removed, [('home', 'tom')]);
      expect(_key('member-tom'), findsNothing);
      expect(o.session.refreshes, 1, reason: 'the member count');
      final events = await sentEvents(tester, o);
      expect(events.map((e) => e['event']), ['member_removed']);
    });

    testWidgets('making an admin shows the new role', (tester) async {
      final o = await pumpAs(tester, 'peter', HouseholdRole.owner);
      await tester.tap(_key('member-actions-tom'));
      await tester.pumpAndSettle();
      await tester.tap(_key('member-makeAdmin'));
      await tester.pumpAndSettle();
      expect(o.invites.roles, [('home', 'tom', HouseholdRole.admin)]);
      expect(
        find.descendant(of: _key('member-tom'), matching: find.text('Admin')),
        findsOneWidget,
      );
    });

    testWidgets('a refusal is told and nobody is removed', (tester) async {
      final o = await pumpAs(tester, 'lea', HouseholdRole.admin);
      o.invites.next = HouseholdProblem.cannotRemove;
      await tester.tap(_key('member-actions-tom'));
      await tester.pumpAndSettle();
      await tester.tap(_key('member-remove'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'member-remove-confirm');
      expect(
        find.text('Diese Person kannst du nicht entfernen.'),
        findsOneWidget,
      );
      expect(_key('member-tom'), findsOneWidget);
    });

    testWidgets('Leute einladen opens the invite sheet', (tester) async {
      await pumpAs(tester, 'tom', HouseholdRole.member);
      await tapKey(tester, 'household-invite');
      expect(_key('invite-sheet'), findsOneWidget);
    });
  });
}
