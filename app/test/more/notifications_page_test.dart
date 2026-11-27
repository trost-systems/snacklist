import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../push/household_add_alert_test.dart' show FakePrefs;
import '../push/push_registration_test.dart'
    show FakePushPlugin, FakePushTokens, MemoryPushStore, Sessions;
import '../settings/shopping_day_test.dart'
    show FakePush, FakeShoppingDayServer;
import '../settings/shopping_reminders_test.dart'
    show FakeReminderPush, FakeRemindersServer;
import 'more_harness.dart';

/// Job 463: the push switches and the shopping-day reminder left
/// Einstellungen for their own More page, Mitteilungen, listed while it has
/// one of them to show. The name switch has no flag (N-425), so an app with
/// the household-add group always lists it.
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

  testWidgets('More lists Benachrichtigungen & Erinnerungen below '
      'Einstellungen, in its group', (tester) async {
    await pumpWith(tester, flags: both);
    expect(
      find.descendant(
        of: key('more-notifications'),
        matching: findLabel('Benachrichtigungen & Erinnerungen'),
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
    expect(
      findLabel('Benachrichtigungen & Erinnerungen'),
      findsOneWidget,
      reason: 'the title',
    );
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

  testWidgets('with the reminder flag alone the page shows the reminder and '
      'the name switch', (tester) async {
    await pumpWith(
      tester,
      flags: const {shoppingDayFlag},
      location: notificationsPath,
    );
    expect(key('shopping-day-1'), findsOneWidget);
    expect(key('settings-push-name-hidden'), findsOneWidget);
  });

  testWidgets('with no flag More lists Mitteilungen, which holds the name '
      'switch alone', (tester) async {
    final more = await pumpWith(tester, flags: const {});
    await tapKey(tester, 'more-notifications');
    expect(path(more), notificationsPath);
    expect(key('settings-push-name-hidden'), findsOneWidget);
    expect(key('settings-push-household-add'), findsNothing);
    expect(key('shopping-day-1'), findsNothing);
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
    ('no flag and no alert', const <String>{}, false, true),
    (
      'the reminder flag in a build without push or alert',
      {shoppingDayFlag},
      false,
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

  group('job 472: shopping reminders SR1', () {
    const sr1 = {pushHouseholdAddFlag, shoppingDayFlag, shoppingRemindersFlag};

    testWidgets('English names the row and the page Notifications & '
        'Reminders', (tester) async {
      await pumpMore(
        tester,
        size: tall,
        device: const [Locale('en')],
        flags: both,
        householdAdd: webAlert(),
        shoppingDay: FakePush().service(FakeShoppingDayServer({})),
      );
      expect(
        find.descendant(
          of: key('more-notifications'),
          matching: find.text('Notifications & Reminders'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'more-notifications');
      expect(find.text('Notifications & Reminders'), findsOneWidget);
    });

    testWidgets('with its flag, SR1 replaces the weekday chips, below the '
        'name switch on the same page (Legal M2)', (tester) async {
      final server = FakeRemindersServer();
      await pumpMore(
        tester,
        size: tall,
        location: notificationsPath,
        flags: sr1,
        householdAdd: webAlert(),
        shoppingDay: FakePush().service(FakeShoppingDayServer({})),
        shoppingReminders: FakeReminderPush().service(server),
      );
      expect(key('shopping-reminders'), findsOneWidget);
      expect(key('shopping-day-1'), findsNothing);
      expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsNothing);
      expect(
        find.textContaining('Am Abend davor um 19 Uhr'),
        findsNothing,
        reason: 'the old hint stays on the flag-off path only (M4)',
      );
      expect(
        tester.getRect(key('settings-push-name-hidden')).bottom,
        lessThanOrEqualTo(tester.getRect(key('shopping-reminders')).top),
      );
    });

    testWidgets('without it, the chips and their 19:00 hint stay', (
      tester,
    ) async {
      final server = FakeRemindersServer();
      await pumpMore(
        tester,
        size: tall,
        location: notificationsPath,
        flags: both,
        householdAdd: webAlert(),
        shoppingDay: FakePush().service(FakeShoppingDayServer({})),
        shoppingReminders: FakeReminderPush().service(server),
      );
      expect(key('shopping-day-1'), findsOneWidget);
      expect(find.textContaining('Am Abend davor um 19 Uhr'), findsOneWidget);
      expect(key('shopping-reminders'), findsNothing);
      expect(server.calls, isEmpty);
    });

    testWidgets('its flag alone lists the row', (tester) async {
      await pumpMore(
        tester,
        size: tall,
        flags: const {shoppingRemindersFlag},
        shoppingReminders: FakeReminderPush().service(FakeRemindersServer()),
      );
      expect(key('more-notifications'), findsOneWidget);
    });

    testWidgets('the household-add switch alone creates no reminder (C2)', (
      tester,
    ) async {
      final sessions = Sessions();
      final plugin = FakePushPlugin();
      final push = PushRegistration(
        plugin,
        MemoryPushStore(),
        FakePushTokens(sessions),
      );
      final alert = HouseholdAddAlert(push, FakePrefs());
      addTearDown(() async {
        await alert.close();
        await push.close();
        await plugin.close();
        await sessions.close();
      });
      final server = FakeRemindersServer();
      final reminders = FakeReminderPush();
      await pumpMore(
        tester,
        size: tall,
        location: notificationsPath,
        flags: sr1,
        householdAdd: alert,
        shoppingReminders: reminders.service(server),
      );
      await tapKey(tester, 'settings-push-household-add');
      expect(
        tester.widget<HexSwitchTile>(key('settings-push-household-add')).value,
        isTrue,
      );
      expect(server.calls, ['read'], reason: 'no reminder row');
      expect(server.rows, isEmpty);
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
    });
  });
}
