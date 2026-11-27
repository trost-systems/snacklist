import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/household_add_settings.dart';
import 'package:family_groceries/push/push_plugin.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'push_registration_test.dart'
    show FakePushPlugin, FakePushTokens, MemoryPushStore, Sessions;

class FakePrefs() implements HouseholdAddPrefs {
  ({bool on, String language, bool nameHidden})? row;
  var offline = false;

  /// The answer takes a moment, so a session change can come first.
  var slow = false;

  /// Set, a save waits for it.
  Completer<void>? hold;

  /// Set, a read waits for it.
  Completer<void>? loadHold;
  final saves = <String>[];

  @override
  Future<({bool on, String language, bool nameHidden})?> load() async {
    if (slow) {
      await pumpEventQueue();
    }
    await loadHold?.future;
    if (offline) {
      throw Exception('offline');
    }
    return row;
  }

  @override
  Future<void> save({required bool on, required String language}) async {
    await hold?.future;
    if (offline) {
      throw Exception('offline');
    }
    saves.add('$on $language');
    row = (on: on, language: language, nameHidden: row?.nameHidden ?? false);
  }

  @override
  Future<void> saveNameHidden({required bool hidden}) async {
    await hold?.future;
    if (offline) {
      throw Exception('offline');
    }
    saves.add('hidden $hidden');
    row = (
      on: row?.on ?? false,
      language: row?.language ?? 'de',
      nameHidden: hidden,
    );
  }
}

class MemoryPendingOff() implements PendingOffStore {
  ({String userId, String language})? off;

  @override
  Future<({String userId, String language})?> pendingOff() async => off;

  @override
  Future<void> savePendingOff(({String userId, String language})? off) async =>
      this.off = off;
}

/// Job 377: the household-add alert's switch is off until the user turns it
/// on; turning it on is what asks the OS, a refusal leaves it off, and
/// turning it off is the sign-out path (Legal N-401).
void main() {
  const home = Household(id: '00000000-0000-4000-8000-000000000001', name: 'A');
  const peter = InHousehold('00000000-0000-4000-8000-000000000011', home, [
    home,
  ]);
  const lea = InHousehold('00000000-0000-4000-8000-000000000012', home, [home]);

  late FakePushPlugin plugin;
  late MemoryPushStore store;
  late FakePushTokens tokens;
  late FakePrefs prefs;
  late Sessions session;
  late PushRegistration push;
  late HouseholdAddAlert alert;
  late MemoryPendingOff pending;
  late PushAlertRegistry alerts;

  void optedIn() {
    store.device = PushDevice.optedIn;
    plugin.permissionNow = PushPermission.granted;
  }

  void build() {
    push = PushRegistration(plugin, store, tokens);
    alert = HouseholdAddAlert(push, prefs, alerts: alerts, pending: pending)
      ..follow(session);
  }

  setUp(() {
    plugin = FakePushPlugin();
    store = MemoryPushStore();
    session = Sessions();
    tokens = FakePushTokens(session);
    prefs = FakePrefs();
    pending = MemoryPendingOff();
    alerts = PushAlertRegistry();
    build();
    session.emit(peter);
  });

  tearDown(() async {
    await alert.close();
    await push.close();
    await session.close();
    await plugin.close();
  });

  test('nothing saved reads as off, and asks nobody', () async {
    await alert.refresh('de');
    expect(alert.state?.on, isFalse);
    expect(alert.state?.nameHidden, isFalse);
    expect(plugin.prompts, 0);
    expect(prefs.saves, isEmpty);
  });

  test('turning it on prompts, then saves the app language', () async {
    final result = await alert.set(on: true, language: 'en');
    expect(result, HouseholdAddResult.done);
    expect(plugin.prompts, 1);
    expect(prefs.saves, ['true en']);
    expect(alert.state?.on, isTrue);
  });

  test('a refused OS prompt saves nothing and stays off', () async {
    plugin.answer = PushPermission.denied;
    final result = await alert.set(on: true, language: 'de');
    expect(result, HouseholdAddResult.blocked);
    expect(prefs.saves, isEmpty);
    expect(alert.state?.on, isNot(isTrue));
  });

  test('turning it off never prompts, and forgets the device as a sign-out '
      'does: unregistered, deleted at FCM, opt-in gone', () async {
    await alert.set(on: true, language: 'de');
    final prompts = plugin.prompts;
    expect(store.device, PushDevice.optedIn);

    expect(await alert.set(on: false, language: 'de'), HouseholdAddResult.done);

    expect(plugin.prompts, prompts);
    expect(prefs.saves.last, 'false de');
    expect(alert.state?.on, isFalse);
    expect(tokens.calls, contains('unregister test-token-a'));
    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
  });

  test(
    'off while another registered alert is on keeps the device registered',
    () async {
      alerts.register(() => true);
      await alert.set(on: true, language: 'de');

      await alert.set(on: false, language: 'de');

      expect(plugin.deleted, 0);
      expect(store.device, PushDevice.optedIn);
    },
  );

  test('an alert that is registered but off does not keep it', () async {
    alerts.register(() => false);
    await alert.set(on: true, language: 'de');

    await alert.set(on: false, language: 'de');

    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
  });

  test('an off the server did not take is sent at the next look, and '
      'again until it is taken', () async {
    await alert.set(on: true, language: 'de');
    prefs.offline = true;
    await alert.set(on: false, language: 'de');
    expect(pending.off, (userId: peter.userId, language: 'de'));

    await alert.refresh('de');
    expect(pending.off, isNotNull, reason: 'still offline: stays pending');
    expect(prefs.row?.on, isTrue);

    prefs.offline = false;
    await alert.refresh('de');
    expect(prefs.row?.on, isFalse);
    expect(pending.off, isNull);
  });

  test('a pending off is sent at the sign-in of its account, not of '
      'another one', () async {
    await alert.set(on: true, language: 'de');
    prefs.offline = true;
    await alert.set(on: false, language: 'de');
    prefs.offline = false;

    session
      ..emit(const SignedOut())
      ..emit(lea);
    await pumpEventQueue();
    expect(prefs.row?.on, isTrue, reason: "Lea does not write Peter's off");
    expect(pending.off, isNotNull);

    session
      ..emit(const SignedOut())
      ..emit(peter);
    await pumpEventQueue();
    expect(prefs.row?.on, isFalse);
    expect(pending.off, isNull);
  });

  test('a new yes replaces a pending off', () async {
    await alert.set(on: true, language: 'de');
    prefs.offline = true;
    await alert.set(on: false, language: 'de');
    prefs.offline = false;

    await alert.set(on: true, language: 'de');

    expect(pending.off, isNull);
    await alert.refresh('de');
    expect(prefs.row?.on, isTrue);
  });

  test('off while FCM is out of reach: the delete is caught up at the next '
      'start, as after an offline sign-out', () async {
    await alert.set(on: true, language: 'de');
    plugin.offline = true;
    await alert.set(on: false, language: 'de');
    expect(store.device, PushDevice.tokenLeft);

    plugin.offline = false;
    await push.resume();

    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
  });

  test('turning it on again after an off prompts nothing new and registers '
      'again', () async {
    await alert.set(on: true, language: 'de');
    await alert.set(on: false, language: 'de');
    tokens.calls.clear();
    expect(await alert.set(on: true, language: 'de'), HouseholdAddResult.done);
    plugin.refresh('test-token-b');
    await pumpEventQueue();
    expect(tokens.calls, ['register test-token-b ios']);
    expect(store.device, PushDevice.optedIn);
  });

  test('an off the server cannot be told of still takes this device off '
      'push, and reads off here (the server row stays on)', () async {
    await alert.set(on: true, language: 'de');
    prefs.offline = true;
    expect(
      await alert.set(on: false, language: 'de'),
      HouseholdAddResult.failed,
    );
    expect(alert.state?.on, isFalse);
    expect(store.device, PushDevice.off);
    expect(plugin.deleted, 1);
    expect(prefs.row?.on, isTrue);
  });

  test('signed out and in on the same phone: the server says on, this '
      'device is off push, so the switch reads off, and a tap opts in '
      'again', () async {
    await alert.set(on: true, language: 'de');
    await push.forget();
    session
      ..emit(const SignedOut())
      ..emit(peter);
    await pumpEventQueue();
    expect(store.device, PushDevice.off);

    await alert.refresh('de');
    expect(prefs.row?.on, isTrue);
    expect(alert.state?.on, isFalse);

    expect(await alert.set(on: true, language: 'de'), HouseholdAddResult.done);
    expect(store.device, PushDevice.optedIn);
    expect(alert.state?.on, isTrue);
  });

  test('a second phone of an account with the alert on reads off until '
      'its own yes', () async {
    prefs.row = (on: true, language: 'de', nameHidden: false);
    await alert.refresh('de');
    expect(alert.state?.on, isFalse);
    expect(plugin.prompts, 0);

    await alert.set(on: true, language: 'de');
    expect(plugin.prompts, 1);
    expect(alert.state?.on, isTrue);
  });

  test('without push (the web) there is only the name switch', () async {
    final web = HouseholdAddAlert(null, prefs)..follow(session);
    addTearDown(web.close);
    prefs.row = (on: true, language: 'de', nameHidden: false);
    await web.refresh('de');
    expect(web.canNotify, isFalse);
    expect(web.state?.on, isFalse);
    expect(await web.set(on: true, language: 'de'), HouseholdAddResult.failed);
    expect(await web.setNameHidden(hidden: true), HouseholdAddResult.done);
    expect(web.state?.nameHidden, isTrue);
  });

  test('offline: the switch stays hidden', () async {
    prefs.offline = true;
    await alert.refresh('de');
    expect(alert.state, isNull);
    expect(
      await alert.set(on: true, language: 'de'),
      HouseholdAddResult.failed,
    );
    expect(alert.state, isNull);
  });

  test('a changed app language is written again while it is on', () async {
    optedIn();
    prefs.row = (on: true, language: 'de', nameHidden: false);
    await alert.refresh('en');
    expect(alert.state?.on, isTrue);
    expect(prefs.saves, ['true en']);
  });

  test('another account signing in does not inherit the switch: it is '
      'forgotten and read again for them', () async {
    optedIn();
    prefs.row = (on: true, language: 'de', nameHidden: true);
    await alert.refresh('de');
    expect(alert.state?.on, isTrue);
    expect(alert.state?.nameHidden, isTrue);

    session.emit(const SignedOut());
    await pumpEventQueue();
    expect(alert.state, isNull);

    session.emit(lea);
    await pumpEventQueue();
    expect(alert.state, isNull, reason: 'not read yet: not shown');
    prefs.row = null;
    await alert.refresh('de');
    expect(alert.state?.on, isFalse);
    expect(alert.state?.nameHidden, isFalse);
  });

  test('an answer that comes after the account changed is dropped', () async {
    prefs
      ..row = (on: true, language: 'de', nameHidden: false)
      ..slow = true;
    final reading = alert.refresh('de');
    session.emit(lea);
    await reading;
    expect(alert.state, isNull);
  });

  test('hiding the name is saved on its own, without asking the OS', () async {
    await alert.refresh('de');
    expect(await alert.setNameHidden(hidden: true), HouseholdAddResult.done);
    expect(prefs.saves, ['hidden true']);
    expect(alert.state?.nameHidden, isTrue);
    expect(alert.state?.on, isFalse);
    expect(plugin.prompts, 0);
  });

  Future<void> pump(
    WidgetTester tester, {
    required Set<String> flags,
    bool deviceOn = false,
  }) async {
    // Built here, in the test's fake-async zone: a cubit made in setUp
    // would queue its work outside it.
    await alert.close();
    await push.close();
    store = MemoryPushStore();
    if (deviceOn) {
      optedIn();
    }
    build();
    session.emit(peter);
    final popups = Popups();
    addTearDown(popups.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => Flags(forced: flags)),
          BlocProvider.value(value: alert),
        ],
        child: MaterialApp(
          navigatorObservers: [popups],
          builder: (_, child) => NoticesHost(popups: popups, child: child!),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: HouseholdAddSettings()),
        ),
      ),
    );
  }

  final tile = find.byKey(const ValueKey('settings-push-household-add'));

  final nameTile = find.byKey(const ValueKey('settings-push-name-hidden'));

  // N-425: the flag may reach some members before others, and those may
  // name this user; the objection to that never waits for the flag.
  testWidgets('flag off: no alert switch, but the name switch, which saves', (
    tester,
  ) async {
    prefs.row = (on: false, language: 'de', nameHidden: true);
    await pump(tester, flags: const {}, deviceOn: true);
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    expect(find.text('Wenn jemand etwas hinzufügt'), findsNothing);
    expect(nameTile, findsOneWidget);
    expect(find.text('Meinen Namen in Mitteilungen weglassen'), findsOneWidget);
    expect(tester.widget<HexSwitchTile>(nameTile).value, isTrue);
    await tester.tap(nameTile);
    await tester.pumpAndSettle();
    expect(prefs.saves, ['hidden false']);
    expect(alert.state?.nameHidden, isFalse);
    expect(plugin.prompts, 0);
  });

  testWidgets('a choice the server cannot tell is no switch but a line to '
      'try again, which then shows the saved name switch', (tester) async {
    prefs
      ..row = (on: false, language: 'de', nameHidden: true)
      ..offline = true;
    await pump(tester, flags: const {}, deviceOn: true);
    await tester.pumpAndSettle();
    expect(find.text('Konnte nicht geladen werden.'), findsOneWidget);
    expect(find.byType(HexSwitch), findsNothing);

    prefs.offline = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Konnte nicht geladen werden.'), findsNothing);
    expect(find.text('Erneut versuchen'), findsNothing);
    expect(tile, findsNothing);
    expect(tester.widget<HexSwitchTile>(nameTile).value, isTrue);
  });

  final loading = find.byKey(const ValueKey('settings-push-loading'));

  testWidgets('while the choice is read, a spinner holds its place', (
    tester,
  ) async {
    prefs.loadHold = Completer();
    await pump(tester, flags: const {}, deviceOn: true);
    await tester.pump();
    expect(loading, findsOneWidget);
    expect(find.bySemanticsLabel('Lädt …'), findsOneWidget);
    expect(find.byType(HexSwitch), findsNothing);

    prefs.loadHold!.complete();
    await tester.pumpAndSettle();
    expect(loading, findsNothing);
    expect(nameTile, findsOneWidget);
  });

  testWidgets('during a retry the line stays, its button off until the '
      'answer', (tester) async {
    prefs.offline = true;
    await pump(tester, flags: const {}, deviceOn: true);
    await tester.pumpAndSettle();
    prefs
      ..offline = false
      ..loadHold = Completer();
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pump();
    final retry = find.byKey(const ValueKey('settings-push-retry'));
    expect(find.text('Konnte nicht geladen werden.'), findsOneWidget);
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    expect(loading, findsNothing);

    prefs.loadHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Konnte nicht geladen werden.'), findsNothing);
    expect(nameTile, findsOneWidget);
  });

  testWidgets('a retry that fails again keeps the line', (tester) async {
    prefs.offline = true;
    await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Konnte nicht geladen werden.'), findsOneWidget);
    expect(find.byType(HexSwitch), findsNothing);
  });

  testWidgets('flag on: the alert switch, then the name switch', (
    tester,
  ) async {
    await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(nameTile, findsOneWidget);
    expect(
      tester.getTopLeft(tile).dy,
      lessThan(tester.getTopLeft(nameTile).dy),
    );
  });

  testWidgets('flag on: an off switch with the example text; a tap asks the '
      'OS and turns it on', (tester) async {
    await pump(tester, flags: const {pushHouseholdAddFlag});
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(find.text('Wenn jemand etwas hinzufügt'), findsOneWidget);
    expect(find.textContaining('Lea hat Milch hinzugefügt'), findsOneWidget);
    expect(alert.state?.on, isFalse);
    await tester.tap(find.byType(HexSwitch).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(plugin.prompts, 1);
    expect(alert.state?.on, isTrue);
    expect(prefs.saves, ['true de']);
  });

  testWidgets('the settings read the choice each time they open, and another '
      'account signing in finds no switch of the one before', (tester) async {
    prefs.row = (on: true, language: 'de', nameHidden: false);
    await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
    await tester.pumpAndSettle();
    expect(
      tester.widget<HexSwitch>(find.byType(HexSwitch).first).value,
      isTrue,
    );

    session.emit(lea);
    await tester.pumpAndSettle();
    expect(tile, findsNothing, reason: 'forgotten until read for Lea');

    prefs.row = null;
    await alert.refresh('de');
    await tester.pumpAndSettle();
    expect(
      tester.widget<HexSwitch>(find.byType(HexSwitch).first).value,
      isFalse,
    );
  });

  testWidgets('the second switch hides the name, with no prompt', (
    tester,
  ) async {
    await pump(tester, flags: const {pushHouseholdAddFlag});
    await tester.pumpAndSettle();
    expect(find.text('Meinen Namen in Mitteilungen weglassen'), findsOneWidget);
    await tester.tap(find.byType(HexSwitch).last);
    await tester.pumpAndSettle();
    expect(prefs.saves, ['hidden true']);
    expect(plugin.prompts, 0);
  });

  bool shown(WidgetTester tester, String key) =>
      tester.widget<HexSwitchTile>(find.byKey(ValueKey(key))).value;

  group('a tap moves the switch at once', () {
    const alertKey = 'settings-push-household-add';
    const nameKey = 'settings-push-name-hidden';
    const failed = 'Die Änderung konnte nicht gespeichert werden.';

    testWidgets('before the server answers', (tester) async {
      await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
      await tester.pumpAndSettle();
      prefs.hold = Completer();
      await tester.tap(find.byKey(const ValueKey(alertKey)));
      await tester.pump();
      expect(shown(tester, alertKey), isTrue);
      expect(prefs.saves, isEmpty, reason: 'still saving');
      prefs.hold!.complete();
      await tester.pumpAndSettle();
      expect(shown(tester, alertKey), isTrue);
      expect(prefs.saves, ['true de']);
      expect(find.text(failed), findsNothing);
    });

    testWidgets('a save the server refuses puts it back, with a notice', (
      tester,
    ) async {
      await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
      await tester.pumpAndSettle();
      prefs
        ..offline = true
        ..hold = Completer();
      await tester.tap(find.byKey(const ValueKey(alertKey)));
      await tester.pump();
      expect(shown(tester, alertKey), isTrue);
      prefs.hold!.complete();
      await tester.pumpAndSettle();
      expect(shown(tester, alertKey), isFalse);
      expect(find.text(failed), findsOneWidget);
    });

    testWidgets('notifications refused in the OS put it back, with a notice', (
      tester,
    ) async {
      await pump(tester, flags: const {pushHouseholdAddFlag});
      await tester.pumpAndSettle();
      plugin.answer = PushPermission.denied;
      await tester.tap(find.byKey(const ValueKey(alertKey)));
      await tester.pumpAndSettle();
      expect(plugin.prompts, 1);
      expect(shown(tester, alertKey), isFalse);
      expect(prefs.saves, isEmpty);
      expect(
        find.textContaining('Mitteilungen sind für Snacklist ausgeschaltet'),
        findsOneWidget,
      );
    });

    testWidgets('the name switch too', (tester) async {
      await pump(tester, flags: const {pushHouseholdAddFlag});
      await tester.pumpAndSettle();
      prefs
        ..offline = true
        ..hold = Completer();
      await tester.tap(find.byKey(const ValueKey(nameKey)));
      await tester.pump();
      expect(shown(tester, nameKey), isTrue);
      prefs.hold!.complete();
      await tester.pumpAndSettle();
      expect(shown(tester, nameKey), isFalse);
      expect(find.text(failed), findsOneWidget);
    });

    testWidgets('quick taps are saved in their order and the last one shows', (
      tester,
    ) async {
      await pump(tester, flags: const {pushHouseholdAddFlag}, deviceOn: true);
      await tester.pumpAndSettle();
      prefs.hold = Completer();
      await tester.tap(find.byKey(const ValueKey(alertKey)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(alertKey)));
      await tester.pump();
      expect(shown(tester, alertKey), isFalse);
      prefs.hold!.complete();
      await tester.pumpAndSettle();
      expect(prefs.saves, ['true de', 'false de']);
      expect(shown(tester, alertKey), isFalse);
      expect(alert.state?.on, isFalse);
    });
  });

  testWidgets('a build without push shows the name switch alone', (
    tester,
  ) async {
    final popups = Popups();
    addTearDown(popups.dispose);
    final web = HouseholdAddAlert(null, prefs)..follow(session);
    addTearDown(web.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => Flags(forced: const {pushHouseholdAddFlag}),
          ),
          BlocProvider.value(value: web),
        ],
        child: MaterialApp(
          navigatorObservers: [popups],
          builder: (_, child) => NoticesHost(popups: popups, child: child!),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: HouseholdAddSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wenn jemand etwas hinzufügt'), findsNothing);
    expect(find.text('Meinen Namen in Mitteilungen weglassen'), findsOneWidget);
  });
}
