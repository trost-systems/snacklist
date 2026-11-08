import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../household/harness.dart' show FakeInvites;
import '../purchases/fakes.dart';
import 'more_harness.dart';

void main() {
  setUpAll(fakeSupabase);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<More> pumpArchiving(
    WidgetTester tester, {
    FakeInvites? invites,
    FakeEntitlementsSource? entitlements,
    AppLanguage? language,
  }) => pumpMore(
    tester,
    language: language,
    invites: invites,
    entitlements: entitlements,
    routes: [
      GoRoute(
        path: morePath,
        builder: (_, _) => const MoreScreen(showArchived: true),
      ),
    ],
  );

  testWidgets('off by default: More offers no archived households', (
    tester,
  ) async {
    await pumpMore(tester);
    expect(key('more-archived'), findsNothing);
  });

  testWidgets('none archived: says so', (tester) async {
    await pumpArchiving(tester);
    await tester.tap(key('more-archived'));
    await tester.pumpAndSettle();
    expect(find.text('Archivierte Haushalte'), findsWidgets);
    expect(find.text('Du hast keinen Haushalt archiviert.'), findsOneWidget);
  });

  for (final (language, text) in [
    (
      AppLanguage.de,
      'Mit Hummlist Lifetime\nWird am 31. Oktober 2028 gelöscht',
    ),
    (
      AppLanguage.en,
      'With Hummlist Lifetime\nWill be deleted on October 31, 2028',
    ),
  ]) {
    testWidgets('each says when it is deleted (${language.name})', (
      tester,
    ) async {
      final invites = FakeInvites()
        ..archivedNow.add(
          ArchivedHousehold(
            id: 'old',
            name: 'Altbau',
            archivedAt: DateTime.utc(2026, 10, 31, 12),
            unlocked: true,
            deletesAt: DateTime.utc(2028, 10, 31, 12),
          ),
        );
      await pumpArchiving(tester, invites: invites, language: language);
      await tester.tap(key('more-archived'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('archived-deletes-old')).data, text);
    });
  }

  testWidgets('bring one back: it joins the other households, nothing is '
      'left (job 169b)', (tester) async {
    final invites = FakeInvites()
      ..archivedNow.add(
        ArchivedHousehold(
          id: 'old',
          name: 'Altbau',
          archivedAt: DateTime.utc(2026, 10, 31),
          unlocked: true,
        ),
      );
    final more = await pumpArchiving(
      tester,
      invites: invites,
      entitlements: FakeEntitlementsSource(unlockedNow: true),
    );
    when(() => more.session.unarchive(any())).thenAnswer((_) async {});
    await tester.tap(key('more-archived'));
    await tester.pumpAndSettle();
    expect(find.text('Altbau'), findsOneWidget);
    expect(find.text('Mit Hummlist Lifetime'), findsOneWidget);
    await tester.tap(key('archived-restore'));
    await tester.pumpAndSettle();
    expect(find.text('„Altbau“ wieder aktivieren?'), findsOneWidget);
    expect(
      find.text(
        'Du bist wieder Mitglied von „Altbau“. Deine anderen Haushalte '
        'bleiben.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('„Zuhause“'), findsNothing);
    await tester.tap(key('archived-restore-confirm'));
    await tester.pumpAndSettle();
    verify(() => more.session.unarchive('old')).called(1);
    expect(key('archived-households'), findsNothing, reason: 'closed');
  });

  testWidgets('cancel brings nothing back', (tester) async {
    final invites = FakeInvites()
      ..archivedNow.add(
        ArchivedHousehold(
          id: 'old',
          name: 'Altbau',
          archivedAt: DateTime.utc(2026, 10, 31),
          unlocked: true,
        ),
      );
    final more = await pumpArchiving(tester, invites: invites);
    await tester.tap(key('more-archived'));
    await tester.pumpAndSettle();
    await tester.tap(key('archived-restore'));
    await tester.pumpAndSettle();
    expect(key('archived-restore-dialog'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    verifyNever(() => more.session.unarchive(any()));
  });
}
