import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../push/household_add_alert_test.dart' show FakePrefs;
import '../settings/shopping_day_test.dart'
    show FakePush, FakeShoppingDayServer;
import 'more_harness.dart';

/// Job 463: the push switches and the shopping-day reminder left
/// Einstellungen for their own More page, Mitteilungen, listed while a flag
/// offers one of them.
void main() {
  setUpAll(fakeSupabase);

  Finder key(String k) => find.byKey(ValueKey(k));

  const tall = Size(390, 3000);
  const both = {pushHouseholdAddFlag, shoppingDayFlag};

  String path(More more) =>
      more.router.routerDelegate.currentConfiguration.uri.toString();

  /// The alert as a build without push has it: the name switch alone.
  HouseholdAddAlert webAlert() {
    final alert = HouseholdAddAlert(null, FakePrefs());
    addTearDown(alert.close);
    return alert;
  }

  Future<More> pumpWith(
    WidgetTester tester, {
    required Set<String> flags,
    bool alert = true,
    bool reminder = true,
    String location = morePath,
    Size size = tall,
  }) => pumpMore(
    tester,
    size: size,
    location: location,
    flags: flags,
    householdAdd: alert ? webAlert() : null,
    shoppingDay: reminder
        ? FakePush().service(FakeShoppingDayServer({}))
        : null,
  );

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  testWidgets('More lists Mitteilungen below Einstellungen, in its group', (
    tester,
  ) async {
    await pumpWith(tester, flags: both);
    expect(
      find.descendant(
        of: key('more-notifications'),
        matching: find.text('Mitteilungen'),
      ),
      findsOneWidget,
    );
    Element group(String row) => tester.element(
      find.ancestor(of: key(row), matching: find.byType(HlSticker)),
    );
    expect(group('more-notifications'), group('more-settings'));
    expect(
      tester.getRect(key('more-notifications')).top,
      greaterThan(tester.getRect(key('more-settings')).top),
    );
  });

  testWidgets('it opens the page with both sections; back returns to More', (
    tester,
  ) async {
    final more = await pumpWith(tester, flags: both);
    await tapKey(tester, 'more-notifications');
    expect(path(more), notificationsPath);
    expect(key('notifications-page'), findsOneWidget);
    expect(find.text('Mitteilungen'), findsOneWidget, reason: 'the title');
    expect(key('settings-push-name-hidden'), findsOneWidget);
    expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsOneWidget);
    expect(key('shopping-day-1'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(path(more), morePath);
  });

  testWidgets('Einstellungen no longer holds either section', (tester) async {
    await pumpWith(tester, flags: both, location: appSettingsPath);
    expect(key('settings-screen'), findsOneWidget);
    expect(key('settings-push-name-hidden'), findsNothing);
    expect(key('settings-push-household-add'), findsNothing);
    expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsNothing);
    expect(key('shopping-day-1'), findsNothing);
  });

  testWidgets('with the reminder flag alone the page shows the reminder', (
    tester,
  ) async {
    await pumpWith(
      tester,
      flags: const {shoppingDayFlag},
      location: notificationsPath,
    );
    expect(key('shopping-day-1'), findsOneWidget);
    expect(key('settings-push-name-hidden'), findsNothing);
  });

  testWidgets('with the alert flag alone the page shows the alert', (
    tester,
  ) async {
    await pumpWith(
      tester,
      flags: const {pushHouseholdAddFlag},
      location: notificationsPath,
    );
    expect(key('settings-push-name-hidden'), findsOneWidget);
    expect(key('shopping-day-1'), findsNothing);
  });

  for (final (why, flags, alert, reminder) in [
    ('no flag', const <String>{}, true, true),
    // The web: no reminder without push, and the alert's flag is off.
    (
      'the reminder flag in a build without push',
      {shoppingDayFlag},
      true,
      false,
    ),
    ('the alert flag without the alert', {pushHouseholdAddFlag}, false, true),
  ]) {
    testWidgets('with $why there is no row, and its link goes to More', (
      tester,
    ) async {
      await pumpWith(tester, flags: flags, alert: alert, reminder: reminder);
      expect(key('more-settings'), findsOneWidget);
      expect(key('more-notifications'), findsNothing);

      final linked = await pumpWith(
        tester,
        flags: flags,
        alert: alert,
        reminder: reminder,
        location: notificationsPath,
      );
      expect(path(linked), morePath);
    });
  }

  testWidgets('beside the list on wide screens, its row is selected', (
    tester,
  ) async {
    await pumpWith(
      tester,
      flags: both,
      location: notificationsPath,
      size: const Size(1200, 900),
    );
    expect(key('notifications-page'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: key('more-notifications'),
              matching: find.byType(ListTile),
              matchRoot: true,
            ),
          )
          .selected,
      isTrue,
    );
  });
}
