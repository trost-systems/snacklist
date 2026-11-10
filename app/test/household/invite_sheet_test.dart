import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

Household _home({
  HouseholdRole role = HouseholdRole.member,
  bool premium = false,
}) => Household(
  id: 'home',
  name: 'Zuhause',
  isDefault: true,
  memberCount: 3,
  role: role,
  premium: premium,
);

/// The household page with Peter in [household], then the invite sheet
/// opened from it.
Future<Onboarding> _openSheet(
  WidgetTester tester,
  Household household, {
  FakeInvites? invites,
  Locale locale = const Locale('de'),
}) async {
  final o = await pumpOnboarding(
    tester,
    location: householdPath,
    session: InHousehold('peter', household, [household]),
    invites: invites,
    locale: locale,
  );
  await tapKey(tester, 'household-invite');
  expect(_key('invite-sheet'), findsOneWidget);
  return o;
}

/// A group link of Zuhause, made before the sheet opens, [used] joined.
FakeInvites _withGroupLink({int used = 0, List<InviteJoin> joins = const []}) {
  final invites = FakeInvites();
  const id = 'group-1';
  invites.created.add(
    Invite(
      id: id,
      code: 'GRUP2345',
      expiresAt: DateTime.utc(2026, 12, 8, 9, 30),
      kind: InviteKind.group,
      maxUses: 50,
      useCount: used,
    ),
  );
  invites.joinLists[id] = [...joins];
  return invites;
}

final _anna = InviteJoin(
  userId: 'anna',
  displayName: 'Anna',
  joinedAt: DateTime.utc(2026, 11, 8, 10),
);

Future<void> _scrollTo(WidgetTester tester, String key) =>
    scrollTo(tester, _key(key));

void main() {
  testWidgets('a member gets the person invite only', (tester) async {
    final o = await _openSheet(tester, _home());
    expect(find.text('Leute einladen'), findsWidgets);
    expect(_key('invite-new'), findsOneWidget);
    expect(_key('invite-group'), findsNothing);
    expect(_key('invite-joins'), findsNothing);
    expect(_key('invite-premium'), findsNothing);
    await tapKey(tester, 'invite-new');
    expect(o.invites.created.single.kind, InviteKind.person);
    expect(o.sharer.shared, hasLength(1));
    final events = await sentEvents(tester, o);
    expect(
      events.single['properties'],
      allOf(
        containsPair('channel', 'share_sheet'),
        containsPair('context', 'household'),
        containsPair('kind', 'person'),
      ),
    );
  });

  testWidgets('says what the join page shows, as plain text above the '
      'controls (Legal N-112)', (tester) async {
    await _openSheet(tester, _home(role: HouseholdRole.admin));
    final hint = find.text(joinPageHintDe);
    expect(hint.hitTestable(), findsOneWidget);
    expect(
      find.ancestor(of: hint, matching: find.byType(ButtonStyleButton)),
      findsNothing,
    );
    expect(
      tester.getTopLeft(hint).dy,
      lessThan(tester.getTopLeft(_key('invite-new')).dy),
    );
  });

  testWidgets('the join page hint in English', (tester) async {
    await _openSheet(tester, _home(), locale: const Locale('en'));
    expect(find.text(joinPageHintEn).hitTestable(), findsOneWidget);
  });

  testWidgets('with Premium it says that Premium covers everyone', (
    tester,
  ) async {
    await _openSheet(tester, _home(premium: true));
    expect(find.text('Premium gilt für alle im Haushalt.'), findsOneWidget);
  });

  testWidgets('an admin makes the group link: QR code, 0 of 50, no one yet', (
    tester,
  ) async {
    final o = await _openSheet(tester, _home(role: HouseholdRole.admin));
    expect(_key('invite-group-uses'), findsNothing);
    await _scrollTo(tester, 'invite-group-create');
    await tapKey(tester, 'invite-group-create');
    final link = o.invites.created.single;
    expect(link.kind, InviteKind.group);
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('0 von 50 beigetreten'), findsOneWidget);
    expect(find.bySemanticsLabel('QR-Code des Gruppenlinks'), findsOneWidget);
    expect(find.bySemanticsLabel('Code ${link.code}'), findsOneWidget);
    expect(find.textContaining('gültig bis 8. Dezember 2026'), findsOneWidget);
    await _scrollTo(tester, 'invite-joins-empty');
    expect(find.text('Noch niemand.'), findsOneWidget);
  });

  testWidgets('an active link: uses, who joined, within seconds of a join', (
    tester,
  ) async {
    final invites = _withGroupLink(used: 12, joins: [_anna]);
    await _openSheet(
      tester,
      _home(role: HouseholdRole.owner),
      invites: invites,
    );
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('12 von 50 beigetreten'), findsOneWidget);
    await _scrollTo(tester, 'invite-joins');
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('am 8. Nov.'), findsOneWidget);
    invites.joinLists['group-1']!.add(
      InviteJoin(
        userId: 'ben',
        displayName: 'Ben',
        joinedAt: DateTime.utc(2026, 11, 9, 10),
      ),
    );
    final link = invites.created.single;
    invites.created[0] = Invite(
      id: link.id,
      code: link.code,
      expiresAt: link.expiresAt,
      kind: link.kind,
      maxUses: link.maxUses,
      useCount: 13,
    );
    await tester.pump(InvitesCubit.livePeriod);
    await tester.pumpAndSettle();
    expect(find.text('Ben'), findsOneWidget);
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('13 von 50 beigetreten'), findsOneWidget);
  });

  testWidgets('copying the group link counts as kind group', (tester) async {
    final o = await _openSheet(
      tester,
      _home(role: HouseholdRole.owner),
      invites: _withGroupLink(),
    );
    await _scrollTo(tester, 'invite-group-copy-code');
    await tapKey(tester, 'invite-group-copy-code');
    expect(o.sharer.copied, ['GRUP2345']);
    final events = await sentEvents(tester, o);
    expect(
      events.single['properties'],
      allOf(
        containsPair('channel', 'copy_code'),
        containsPair('context', 'household'),
        containsPair('kind', 'group'),
      ),
    );
    expect(jsonEncode(events), isNot(contains('GRUP2345')));
  });

  testWidgets('a full link says so and offers a new one at once', (
    tester,
  ) async {
    final o = await _openSheet(
      tester,
      _home(role: HouseholdRole.admin),
      invites: _withGroupLink(used: 50),
    );
    await _scrollTo(tester, 'invite-group-full');
    expect(find.text('50 von 50 beigetreten'), findsOneWidget);
    expect(_key('invite-group-share'), findsNothing);
    expect(_key('invite-group-revoke'), findsNothing);
    await _scrollTo(tester, 'invite-group-renew');
    await tapKey(tester, 'invite-group-renew');
    expect(_key('invite-group-renew-dialog'), findsNothing);
    expect(o.invites.revoked, ['group-1']);
    final fresh = o.invites.created.last;
    expect((fresh.kind, fresh.id == 'group-1'), (InviteKind.group, false));
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('0 von 50 beigetreten'), findsOneWidget);
  });

  testWidgets('revoking asks first; a revoked link says so, then a new one', (
    tester,
  ) async {
    final o = await _openSheet(
      tester,
      _home(role: HouseholdRole.owner),
      invites: _withGroupLink(used: 1, joins: [_anna]),
    );
    await _scrollTo(tester, 'invite-group-revoke');
    await tapKey(tester, 'invite-group-revoke');
    expect(find.text('Gruppenlink widerrufen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(o.invites.revoked, isEmpty);
    await tapKey(tester, 'invite-group-revoke');
    await tapKey(tester, 'invite-group-revoke-dialog-confirm');
    expect(o.invites.revoked, ['group-1']);
    await _scrollTo(tester, 'invite-group-revoked');
    expect(
      find.text('Link widerrufen: Niemand kann mehr damit beitreten.'),
      findsOneWidget,
    );
    expect(find.text('Anna'), findsOneWidget, reason: 'who joined stays');
    await tapKey(tester, 'invite-group-renew');
    expect(o.invites.created.last.id, isNot('group-1'));
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('0 von 50 beigetreten'), findsOneWidget);
  });

  testWidgets('a new link in place of an active one asks first', (
    tester,
  ) async {
    final o = await _openSheet(
      tester,
      _home(role: HouseholdRole.admin),
      invites: _withGroupLink(),
    );
    await _scrollTo(tester, 'invite-group-renew');
    await tapKey(tester, 'invite-group-renew');
    expect(find.text('Neuen Link erstellen?'), findsOneWidget);
    await tapKey(tester, 'invite-group-renew-dialog-confirm');
    expect(o.invites.revoked, ['group-1']);
    expect(o.invites.created, hasLength(2));
  });

  testWidgets('one poll at a time: a slow answer is not asked again', (
    tester,
  ) async {
    final invites = _withGroupLink();
    await _openSheet(
      tester,
      _home(role: HouseholdRole.admin),
      invites: invites,
    );
    final slow = invites.slowLoads = Completer<void>();
    final loads = invites.loads;
    await tester.pump(InvitesCubit.livePeriod * 4);
    expect(invites.loads, loads + 1);
    slow.complete();
    await tester.pump();
    await tester.pump(InvitesCubit.livePeriod);
    expect(invites.loads, loads + 2);
  });

  testWidgets('a poll answered after a new link does not bring back the old', (
    tester,
  ) async {
    final invites = _withGroupLink();
    await _openSheet(
      tester,
      _home(role: HouseholdRole.admin),
      invites: invites,
    );
    final slow = invites.slowLoads = Completer<void>();
    await tester.pump(InvitesCubit.livePeriod);
    invites.slowLoads = null;
    await _scrollTo(tester, 'invite-group-renew');
    await tapKey(tester, 'invite-group-renew');
    await tapKey(tester, 'invite-group-renew-dialog-confirm');
    final renewed = invites.created.last.code;
    expect(find.bySemanticsLabel('Code $renewed'), findsOneWidget);
    slow.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Code $renewed'), findsOneWidget);
    expect(find.bySemanticsLabel('Code GRUP2345'), findsNothing);
  });

  testWidgets('in English', (tester) async {
    await _openSheet(
      tester,
      _home(role: HouseholdRole.owner, premium: true),
      invites: _withGroupLink(used: 12),
      locale: const Locale('en'),
    );
    expect(find.text('Invite people'), findsWidgets);
    expect(
      find.text('Premium covers everyone in the household.'),
      findsOneWidget,
    );
    await _scrollTo(tester, 'invite-group-uses');
    expect(find.text('12 of 50 joined'), findsOneWidget);
  });

  group('the share text', () {
    const link = 'https://app.snacklist.app/join/ABCD2345';
    for (final locale in AppLocalizations.supportedLocales) {
      for (final kind in HouseholdKind.values.map((k) => k.name)) {
        test('${locale.languageCode}, $kind: the link and the code', () {
          final text = lookupAppLocalizations(locale)
              .inviteShareKind(kind, 'Familie Trost', link, 'ABCD2345');
          expect(text, contains(link));
          expect(text, contains('Code: ABCD2345'));
        });
      }
    }

    test('names the household where the kind says who shops there', () {
      final de = lookupAppLocalizations(const Locale('de'));
      expect(
        de.inviteShareKind('flat', 'WG Lindenstraße', link, 'ABCD2345'),
        startsWith('Unsere WG-Einkaufsliste „WG Lindenstraße“'),
      );
    });
  });
}
