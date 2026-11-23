import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/shopping_day.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../push/household_add_alert_test.dart' show FakePrefs;
import '../push/push_registration_test.dart'
    show FakePushPlugin, FakePushTokens, MemoryPushStore, Sessions;

class FakeShoppingDayServer(final Set<int> initial)
    implements ShoppingDayRepository {
  late Set<int> days = initial;
  final calls = <String>[];
  var failing = false;
  var readFails = false;

  @override
  Future<Set<int>> read() async {
    if (readFails) {
      throw StateError('offline');
    }
    return days;
  }

  @override
  Future<void> refresh(String timeZone, String locale) async {
    calls.add('refresh $timeZone $locale');
  }

  @override
  Future<void> save(Set<int> weekdays, String timeZone, String locale) async {
    if (failing) {
      throw StateError('offline');
    }
    calls.add('${(weekdays.toList()..sort()).join(',')} $timeZone $locale');
    days = weekdays;
  }
}

class const FixedZone(final String zone) implements DeviceTimeZone {
  @override
  Future<String> name() async => zone;
}

/// PushRegistration as the section sees it: what it was asked, and whether
/// notifications are allowed and registered on this device.
class FakePush() {
  var allowed = true;
  var on = true;
  var householdAdd = false;
  final calls = <String>[];

  ShoppingDayService service(FakeShoppingDayServer server) =>
      ShoppingDayService(
        server,
        const FixedZone('Europe/Berlin'),
        () async {
          calls.add('optIn');
          return allowed;
        },
        () async {
          calls.add('resume');
          return on;
        },
        () async => calls.add('forget'),
        () async => householdAdd,
      );
}

void main() {
  Finder chip(int weekday) => find.byKey(ValueKey('shopping-day-$weekday'));

  group('ShoppingDayService', () {
    test(
      'a picked day asks for push first, then saves with the zone',
      () async {
        final server = FakeShoppingDayServer({});
        final push = FakePush();
        expect(
          await push.service(server).save({4}, 'de'),
          ShoppingDaySaved.saved,
        );
        expect(push.calls, ['optIn']);
        expect(server.calls, ['4 Europe/Berlin de']);
      },
    );

    test('notifications refused: nothing is saved', () async {
      final server = FakeShoppingDayServer({});
      final push = FakePush()..allowed = false;
      expect(
        await push.service(server).save({4}, 'de'),
        ShoppingDaySaved.pushBlocked,
      );
      expect(server.calls, isEmpty);
    });

    test('the last day unpicked takes the sign-out path (N-401)', () async {
      final server = FakeShoppingDayServer({4});
      final push = FakePush();
      expect(await push.service(server).save({}, 'en'), ShoppingDaySaved.saved);
      expect(push.calls, ['forget'], reason: 'no prompt, the device forgets');
      expect(server.calls, [' Europe/Berlin en']);
    });

    test('a day still picked keeps the device registered', () async {
      final server = FakeShoppingDayServer({1, 4});
      final push = FakePush();
      await push.service(server).save({1}, 'de');
      expect(push.calls, ['optIn']);
    });

    test('a clear the server does not take still forgets the device', () async {
      final server = FakeShoppingDayServer({4})..failing = true;
      final push = FakePush();
      expect(
        await push.service(server).save({}, 'de'),
        ShoppingDaySaved.failed,
      );
      expect(push.calls, ['forget']);
    });

    test('a server that fails is reported', () async {
      final server = FakeShoppingDayServer({})..failing = true;
      expect(
        await FakePush().service(server).save({1}, 'de'),
        ShoppingDaySaved.failed,
      );
    });

    test(
      'load: with push on the days stand, zone and language refreshed',
      () async {
        final server = FakeShoppingDayServer({1, 4});
        final loaded = await FakePush().service(server).load('en');
        expect(loaded.shown, {1, 4});
        await pumpEventQueue();
        expect(server.calls, [
          'refresh Europe/Berlin en',
        ], reason: 'only zone and language, never the days');
      },
    );

    test(
      'load: signed out and in again (push off here), no day shows',
      () async {
        final server = FakeShoppingDayServer({1, 4});
        final push = FakePush()..on = false;
        final loaded = await push.service(server).load('de');
        expect(loaded.shown, isEmpty);
        expect(loaded.saved, {1, 4}, reason: 'kept for the next pick');
        expect(server.calls, isEmpty, reason: 'nothing is rewritten');
      },
    );

    test('load: nothing saved, push is not touched', () async {
      final push = FakePush();
      final loaded = await push.service(FakeShoppingDayServer({})).load('de');
      expect(loaded.shown, isEmpty);
      expect(push.calls, isEmpty);
    });
  });

  group('ianaZone', () {
    test('IANA names and UTC stand', () {
      expect(
        ianaZone('Europe/Berlin', const Duration(hours: 1)),
        'Europe/Berlin',
      );
      expect(
        ianaZone('America/Argentina/Buenos_Aires', const Duration(hours: -3)),
        'America/Argentina/Buenos_Aires',
      );
      expect(ianaZone('UTC', Duration.zero), 'UTC');
    });

    test('a bare offset becomes the fixed-offset zone, sign inverted', () {
      expect(ianaZone('GMT+01:00', const Duration(hours: 1)), 'Etc/GMT-1');
      expect(ianaZone('GMT-05:00', const Duration(hours: -5)), 'Etc/GMT+5');
      expect(ianaZone('GMT', Duration.zero), 'Etc/UTC');
    });

    test('an offset of no whole hour has no such zone', () {
      expect(
        () => ianaZone('GMT+05:30', const Duration(minutes: 330)),
        throwsFormatException,
      );
    });
  });

  group('the last notification type off (Legal N-436, N-401)', () {
    const home = Household(
      id: '00000000-0000-4000-8000-000000000001',
      name: 'A',
    );
    const peter = InHousehold('00000000-0000-4000-8000-000000000011', home, [
      home,
    ]);
    late FakePushPlugin plugin;
    late MemoryPushStore store;
    late FakePushTokens tokens;
    late FakePrefs prefs;
    late FakeShoppingDayServer server;
    late Sessions session;
    late PushRegistration push;
    late HouseholdAddAlert alert;
    late ShoppingDayService service;
    ({String userId, String language})? pending;

    setUp(() async {
      plugin = FakePushPlugin();
      store = MemoryPushStore();
      session = Sessions();
      tokens = FakePushTokens(session);
      prefs = FakePrefs();
      server = FakeShoppingDayServer({});
      pending = null;
      push = PushRegistration(plugin, store, tokens);
      // Wired as main.dart does.
      final alerts = PushAlertRegistry()..register(() => service.hasDays());
      alert = HouseholdAddAlert(push, prefs, alerts: alerts)..follow(session);
      service = ShoppingDayService(
        server,
        const FixedZone('Europe/Berlin'),
        push.optIn,
        () async {
          await push.resume();
          return push.state is PushOn;
        },
        push.forget,
        alert.isOn,
        readPending: () async => pending,
        writePending: (clear) async => pending = clear,
      )..follow(session);
      session.emit(peter);
      await pumpEventQueue();
    });

    tearDown(() async {
      await service.close();
      await alert.close();
      await push.close();
      await session.close();
      await plugin.close();
    });

    test('clearing every day with the household alert off forgets the device '
        'as a sign-out does', () async {
      await service.save({4}, 'de');
      expect(store.device, PushDevice.optedIn);

      expect(await service.save({}, 'de'), ShoppingDaySaved.saved);

      expect(tokens.calls, contains('unregister test-token-a'));
      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
      expect(server.days, isEmpty);
    });

    test('offline at FCM the delete is caught up at the next start', () async {
      await service.save({4}, 'de');
      plugin.offline = true;
      await service.save({}, 'de');
      expect(store.device, PushDevice.tokenLeft);

      plugin.offline = false;
      await push.resume();

      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
    });

    test(
      'with the household alert on, clearing the days keeps the token',
      () async {
        await alert.set(on: true, language: 'de');
        await service.save({4}, 'de');

        await service.save({}, 'de');

        expect(plugin.deleted, 0);
        expect(store.device, PushDevice.optedIn);
      },
    );

    test('the whole phone offline: clearing the last day still takes the '
        'device off push, and the clear is reported failed', () async {
      await service.save({4}, 'de');
      prefs.offline = true;
      server
        ..failing = true
        ..readFails = true;
      plugin.offline = true;

      expect(await service.save({}, 'de'), ShoppingDaySaved.failed);

      expect(store.device, PushDevice.tokenLeft);
      plugin.offline = false;
      await push.resume();
      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
    });

    test('the whole phone offline: the household alert off, with the '
        'reminder unreadable, takes the device off push', () async {
      await alert.set(on: true, language: 'de');
      server.readFails = true;
      prefs.offline = true;
      plugin.offline = true;

      expect(
        await alert.set(on: false, language: 'de'),
        HouseholdAddResult.failed,
      );

      expect(store.device, PushDevice.tokenLeft);
      plugin.offline = false;
      await push.resume();
      expect(store.device, PushDevice.off);
    });

    test('a clear the phone could not send is kept for this account and sent '
        'again when it is back online', () async {
      await service.save({4}, 'en');
      server
        ..failing = true
        ..readFails = true;
      expect(await service.save({}, 'en'), ShoppingDaySaved.failed);
      expect(pending, (userId: peter.userId, language: 'en'));
      expect(server.days, {4});

      server
        ..failing = false
        ..readFails = false;
      await service.retryPendingClear();

      expect(server.days, isEmpty);
      expect(server.calls.last, ' UTC en');
      expect(pending, isNull);
    });

    test('a pending clear of another account is not sent', () async {
      await service.save({4}, 'de');
      pending = (userId: 'someone-else', language: 'de');

      await service.retryPendingClear();

      expect(server.days, {4});
      expect(pending, isNotNull);
    });

    test(
      'a later save that the server takes drops the pending clear',
      () async {
        pending = (userId: peter.userId, language: 'de');

        await service.save({2}, 'de');

        expect(pending, isNull);
      },
    );

    test('signing in again sends the pending clear', () async {
      await service.save({4}, 'de');
      server.failing = true;
      await service.save({}, 'de');
      server.failing = false;

      session
        ..emit(const SignedOut())
        ..emit(peter);
      await pumpEventQueue();

      expect(server.days, isEmpty);
      expect(pending, isNull);
    });

    test('the household alert off with days still picked keeps the token; '
        'with none picked it forgets', () async {
      await alert.set(on: true, language: 'de');
      await service.save({4}, 'de');
      await alert.set(on: false, language: 'de');
      expect(plugin.deleted, 0);
      expect(store.device, PushDevice.optedIn);

      await service.save({}, 'de');
      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
    });
  });

  group('the Settings section', () {
    Future<(FakeShoppingDayServer, FakePush)> pump(
      WidgetTester tester, {
      bool flag = true,
      bool withPush = true,
      Set<int> days = const {},
      Locale locale = const Locale('de'),
      void Function(FakePush push)? before,
    }) async {
      final server = FakeShoppingDayServer({...days});
      final push = FakePush();
      before?.call(push);
      final shown = Flags(forced: {if (flag) shoppingDayFlag});
      addTearDown(shown.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [BlocProvider.value(value: shown)],
          child: RepositoryProvider<ShoppingDayService?>.value(
            value: withPush ? push.service(server) : null,
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: locale,
              home: const Scaffold(
                body: SingleChildScrollView(child: ShoppingDaySettings()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (server, push);
    }

    bool picked(WidgetTester tester, int weekday) =>
        tester.widget<FilterChip>(chip(weekday)).selected;

    testWidgets('is off by default: no day picked, nothing saved', (
      tester,
    ) async {
      final (server, _) = await pump(tester);
      expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsOneWidget);
      for (var weekday = 1; weekday <= 7; weekday++) {
        expect(picked(tester, weekday), isFalse);
      }
      expect(server.calls, isEmpty);
    });

    testWidgets('shows the weekdays the server has', (tester) async {
      await pump(tester, days: {1, 4});
      expect(picked(tester, 1), isTrue);
      expect(picked(tester, 4), isTrue);
      expect(picked(tester, 2), isFalse);
      expect(find.text('Mo'), findsOneWidget);
    });

    testWidgets(
      'push off here (signed out and in, a second device): a pick adds',
      (tester) async {
        final (server, push) = await pump(
          tester,
          days: {1, 4},
          before: (push) => push.on = false,
        );
        expect(picked(tester, 1), isFalse);
        expect(picked(tester, 4), isFalse);
        await tester.tap(chip(2));
        await tester.pumpAndSettle();
        expect(push.calls, ['resume', 'optIn']);
        expect(server.calls, [
          '1,2,4 Europe/Berlin de',
        ], reason: 'the days saved from another device stay');
        expect(picked(tester, 1), isTrue);
        expect(picked(tester, 4), isTrue);
      },
    );

    testWidgets('picks and unpicks days, saved with the zone and language', (
      tester,
    ) async {
      final (server, _) = await pump(tester);
      for (final weekday in [4, 1, 4]) {
        await tester.tap(chip(weekday));
        await tester.pumpAndSettle();
      }
      expect(server.calls, [
        '4 Europe/Berlin de',
        '1,4 Europe/Berlin de',
        '1 Europe/Berlin de',
      ]);
    });

    testWidgets('unpicking the last day switches push off on the device', (
      tester,
    ) async {
      final (server, push) = await pump(tester, days: {4});
      push.calls.clear();
      await tester.tap(chip(4));
      await tester.pumpAndSettle();
      expect(picked(tester, 4), isFalse);
      expect(server.days, isEmpty);
      expect(push.calls, ['forget']);
    });

    testWidgets('English devices save the language en', (tester) async {
      final (server, _) = await pump(tester, locale: const Locale('en'));
      expect(find.text('SHOPPING-DAY REMINDER'), findsOneWidget);
      await tester.tap(chip(2));
      await tester.pumpAndSettle();
      expect(server.calls, ['2 Europe/Berlin en']);
    });

    testWidgets(
      'refused notifications: the chip goes back and a notice says why',
      (tester) async {
        final (server, _) = await pump(
          tester,
          before: (push) => push.allowed = false,
        );
        await tester.tap(chip(4));
        await tester.pumpAndSettle();
        expect(picked(tester, 4), isFalse);
        expect(server.calls, isEmpty);
        expect(
          find.textContaining('Mitteilungen sind für Snacklist ausgeschaltet'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a screen reader hears the day, its state, and can toggle it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (server, _) = await pump(tester, days: {1});
      final monday = tester.getSemantics(chip(1));
      expect(monday.label, contains('Montag'));
      expect(
        monday,
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(chip(2)),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('Dienstag')));
      await tester.pumpAndSettle();
      expect(server.calls.last, '1,2 Europe/Berlin de');
      handle.dispose();
    });

    testWidgets(
      'without the flag or without push in the build, nothing shows',
      (tester) async {
        await pump(tester, flag: false);
        expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsNothing);
        await pump(tester, withPush: false);
        expect(find.text('EINKAUFSTAG-ERINNERUNG'), findsNothing);
      },
    );
  });
}
