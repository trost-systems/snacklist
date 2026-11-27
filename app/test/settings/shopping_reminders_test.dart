import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/settings/shopping_reminders.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'shopping_day_test.dart' show FixedZone;

/// Thursday 26 November 2026, 10:30 on the device's clock.
final thursday = DateTime(2026, 11, 26, 10, 30);

ReminderSlot slot(int weekday, ReminderOffset offset, int hour, [int m = 0]) =>
    ReminderSlot(weekday: weekday, offset: offset, minute: hour * 60 + m);

const before = ReminderOffset.dayBefore;
const onDay = ReminderOffset.onTheDay;

/// The person's reminders on the server: a save at or after today's time
/// counts today as sent, a duplicate and a 15th are refused, as the RPCs do.
class FakeRemindersServer({
  final List<ReminderSlot> initial = const [],
  final DateTime Function()? clock,

  /// The date the initial reminders last went out.
  final DateTime? sentOn,
}) implements ShoppingRemindersRepository {
  late final rows = <ShoppingReminder>[
    for (final (i, slot) in initial.indexed)
      ShoppingReminder(id: 'r$i', slot: slot, sentOn: sentOn),
  ];
  final calls = <String>[];
  var failing = false;

  /// How many of the next writes fail, then the rest go through.
  var failNext = 0;

  /// How many of the next reads fail.
  var readFails = 0;

  /// Set, the next write is refused for it, whatever the rows say (another
  /// device got there first).
  ReminderRefusal? refuse;

  /// Set, a write waits for it.
  Completer<void>? hold;
  var _ids = 100;

  DateTime get _now => (clock ?? () => thursday)();

  @override
  Future<List<ShoppingReminder>> read() async {
    if (readFails > 0) {
      readFails--;
      throw StateError('offline');
    }
    calls.add('read');
    return [...rows];
  }

  Future<void> _gate() async {
    await hold?.future;
    if (failing) {
      throw StateError('offline');
    }
    if (failNext > 0) {
      failNext--;
      throw StateError('offline');
    }
    if (refuse case final reason?) {
      refuse = null;
      throw ReminderRefused(reason);
    }
  }

  /// As `update_shopping_reminder`: the old date only on the same days,
  /// today once today's time has passed, never back.
  ShoppingReminder _row(String id, ReminderSlot slot, ShoppingReminder? old) =>
      ShoppingReminder(
        id: id,
        slot: slot,
        sentOn: sentAfterSave(old, slot, _now),
      );

  @override
  Future<ShoppingReminder> add(
    ReminderSlot slot,
    String timeZone,
    String locale,
  ) async {
    await _gate();
    if (rows.any((r) => r.slot == slot)) {
      throw const ReminderRefused(ReminderRefusal.duplicate);
    }
    if (rows.length >= reminderLimit) {
      throw const ReminderRefused(ReminderRefusal.limit);
    }
    calls.add('add $slot $timeZone $locale');
    final row = _row('r${_ids++}', slot, null);
    rows.add(row);
    return row;
  }

  @override
  Future<ShoppingReminder> update(
    String id,
    ReminderSlot slot,
    String timeZone,
    String locale,
  ) async {
    await _gate();
    if (rows.any((r) => r.slot == slot && r.id != id)) {
      throw const ReminderRefused(ReminderRefusal.duplicate);
    }
    calls.add('update $id $slot $timeZone $locale');
    final at = rows.indexWhere((r) => r.id == id);
    final row = _row(id, slot, rows[at]);
    rows[at] = row;
    return row;
  }

  @override
  Future<void> delete(String id) async {
    await _gate();
    calls.add('delete $id');
    rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> refresh(String timeZone, String locale) async {
    calls.add('refresh $timeZone $locale');
  }
}

/// PushRegistration as SR1 sees it.
class FakeReminderPush() {
  var allowed = true;
  var on = true;
  var householdAdd = false;
  final calls = <String>[];

  /// What the weekday chips' clear waiting on the device saw: settled
  /// before each call, dropped after a save that worked.
  final clear = <String>[];

  ShoppingReminders service(
    FakeRemindersServer server, {
    DateTime Function()? now,
  }) => ShoppingReminders(
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
    now: now ?? () => thursday,
    settlePendingClear: () async => clear.add('settle'),
    dropPendingClear: () async => clear.add('drop'),
  );
}

/// A device clock a test can move.
final class TestClock(var DateTime now);

void main() {
  group('ReminderSlot', () {
    test('the day before a Monday shop fires on Sunday', () {
      expect(slot(1, before, 19).fireWeekday, 7);
      expect(slot(6, before, 19).fireWeekday, 5);
      expect(slot(6, onDay, 9).fireWeekday, 6);
    });

    test('next firing: the coming fire day at its time, a real date', () {
      expect(
        slot(6, before, 19).nextFire(thursday),
        DateTime(2026, 11, 27, 19),
      );
      expect(
        slot(6, onDay, 9, 15).nextFire(thursday),
        DateTime(2026, 11, 28, 9, 15),
      );
      // SR-Q11: the day before at 00:30 is Friday 00:30.
      expect(
        slot(6, before, 0, 30).nextFire(thursday),
        DateTime(2026, 11, 27, 0, 30),
      );
    });

    test("today's time passed: next week (SR-Q7)", () {
      final evening = DateTime(2026, 11, 27, 20);
      final saturday = slot(6, before, 19);
      expect(saturday.passedToday(evening), isTrue);
      expect(saturday.nextFire(evening), DateTime(2026, 12, 4, 19));
      expect(saturday.passedToday(thursday), isFalse);
      final now = DateTime(2026, 11, 27, 19);
      expect(saturday.passedToday(now), isTrue, reason: 'at the minute');
      expect(saturday.nextFire(now), DateTime(2026, 12, 4, 19));
    });

    test('a day that already went out is skipped', () {
      final early = DateTime(2026, 11, 27, 8);
      final sent = DateTime(2026, 11, 27);
      expect(
        slot(6, before, 19).nextFire(early, sentOn: sent),
        DateTime(2026, 12, 4, 19),
      );
    });
  });

  group('ShoppingReminders', () {
    test('opening with none: no prompt, no push call, no write (C2)', () async {
      final server = FakeRemindersServer();
      final push = FakeReminderPush();
      expect(await push.service(server).load('de'), isEmpty);
      expect(push.calls, isEmpty);
      expect(server.calls, ['read']);
    });

    test(
      'opening with reminders and push on refreshes the zone only',
      () async {
        final server = FakeRemindersServer(initial: [slot(6, before, 19)]);
        final push = FakeReminderPush();
        await push.service(server).load('en');
        await pumpEventQueue();
        expect(push.calls, ['resume']);
        expect(server.calls, ['read', 'refresh Europe/Berlin en']);
      },
    );

    test('a device without push leaves the zone alone', () async {
      final server = FakeRemindersServer(initial: [slot(6, before, 19)]);
      final push = FakeReminderPush()..on = false;
      await push.service(server).load('de');
      await pumpEventQueue();
      expect(server.calls, ['read']);
    });

    test('a save asks for push first, then saves with the zone', () async {
      final server = FakeRemindersServer();
      final push = FakeReminderPush();
      final (result, saved) = await push
          .service(server)
          .save(slot(6, before, 19), 'de');
      expect(result, ReminderSaved.saved);
      expect(saved?.slot, slot(6, before, 19));
      expect(push.calls, ['optIn']);
      expect(server.calls, ['add 6 dayBefore 1140 Europe/Berlin de']);
    });

    test('refused permission saves nothing on the server (SR-Q12)', () async {
      final server = FakeRemindersServer();
      final push = FakeReminderPush()..allowed = false;
      final (result, _) = await push
          .service(server)
          .save(slot(6, before, 19), 'de');
      expect(result, ReminderSaved.pushBlocked);
      expect(server.calls, isEmpty);
    });

    test("the server's refusals are told apart", () async {
      final server = FakeRemindersServer()..refuse = ReminderRefusal.limit;
      final service = FakeReminderPush().service(server);
      expect(
        (await service.save(slot(1, onDay, 8), 'de')).$1,
        ReminderSaved.limit,
      );
      server.refuse = ReminderRefusal.duplicate;
      expect(
        (await service.save(slot(1, onDay, 8), 'de')).$1,
        ReminderSaved.duplicate,
      );
      server.failing = true;
      expect(
        (await service.save(slot(1, onDay, 8), 'de')).$1,
        ReminderSaved.failed,
      );
    });

    test(
      'the last one deleted with the alert off forgets the device',
      () async {
        final server = FakeRemindersServer(initial: [slot(6, before, 19)]);
        final push = FakeReminderPush();
        expect(await push.service(server).delete('r0', last: true), isTrue);
        expect(push.calls, ['forget']);
        expect(server.rows, isEmpty);
      },
    );

    test('the alert still on, or one left: the device keeps push', () async {
      final server = FakeRemindersServer(
        initial: [slot(6, before, 19), slot(2, before, 18)],
      );
      final push = FakeReminderPush()..householdAdd = true;
      final service = push.service(server);
      await service.delete('r0', last: false);
      await service.delete('r1', last: true);
      expect(push.calls, isEmpty);
    });

    test('the server decides whether a delete was the last one', () async {
      final server = FakeRemindersServer(
        initial: [slot(6, before, 19), slot(2, before, 18)],
      );
      final push = FakeReminderPush();
      await push.service(server).delete('r1', last: true);
      expect(push.calls, isEmpty, reason: 'r0 is still on the server');
    });

    test("the page's guess only when the server cannot be read", () async {
      final server = FakeRemindersServer(initial: [slot(6, before, 19)])
        ..readFails = 1;
      final push = FakeReminderPush();
      await push.service(server).delete('r0', last: true);
      expect(push.calls, ['forget']);
    });

    test("the chips' clear waiting offline goes first; a save that works "
        'supersedes it', () async {
      final server = FakeRemindersServer();
      final push = FakeReminderPush();
      final service = push.service(server);
      await service.load('de');
      expect(push.clear, ['settle']);
      server.failing = true;
      await service.save(slot(6, before, 19), 'de');
      expect(push.clear, ['settle', 'settle'], reason: 'kept: not saved');
      server.failing = false;
      await service.save(slot(6, before, 19), 'de');
      expect(push.clear, ['settle', 'settle', 'settle', 'drop']);
      await service.delete('r100', last: true);
      expect(push.clear.last, 'settle');
    });

    test('a delete the server refused keeps the device on push', () async {
      final server = FakeRemindersServer(initial: [slot(6, before, 19)])
        ..failing = true;
      final push = FakeReminderPush();
      expect(await push.service(server).delete('r0', last: true), isFalse);
      expect(push.calls, isEmpty);
    });
  });

  group('the SR1 section', () {
    Future<(FakeRemindersServer, FakeReminderPush)> pump(
      WidgetTester tester, {
      List<ReminderSlot> initial = const [],
      Locale locale = const Locale('de'),
      bool flag = true,
      bool always24 = false,
      DateTime? now,
      TestClock? clock,
      DateTime? sentOn,
      void Function(FakeRemindersServer server)? seed,
      void Function(FakeReminderPush push)? before,
    }) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(390, 2400);
      addTearDown(tester.view.reset);
      final time = clock ?? TestClock(now ?? thursday);
      final server = FakeRemindersServer(
        initial: initial,
        clock: () => time.now,
        sentOn: sentOn,
      );
      seed?.call(server);
      final push = FakeReminderPush();
      before?.call(push);
      final shown = Flags(forced: {if (flag) shoppingRemindersFlag});
      addTearDown(shown.close);
      final popups = Popups();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [BlocProvider.value(value: shown)],
          child: RepositoryProvider<ShoppingReminders?>.value(
            value: push.service(server, now: () => time.now),
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: locale,
              navigatorObservers: [popups],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(alwaysUse24HourFormat: always24),
                child: NoticesHost(popups: popups, child: child!),
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: ShoppingRemindersSettings()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (server, push);
    }

    Finder key(String k) => find.byKey(ValueKey(k));
    Finder row(ReminderSlot s) => key('reminder-$s');

    Future<void> tap(WidgetTester tester, String k) async {
      await tester.ensureVisible(key(k));
      await tester.pumpAndSettle();
      await tester.tap(key(k));
      await tester.pumpAndSettle();
    }

    /// Opens the add sheet and picks [s]; Save is the caller's.
    Future<void> compose(WidgetTester tester, ReminderSlot s) async {
      await tap(tester, 'reminder-add');
      await tap(tester, 'reminder-day-${s.weekday}');
      await tap(
        tester,
        s.offset == before ? 'reminder-day-before' : 'reminder-on-the-day',
      );
      await tap(tester, 'reminder-hour-${s.minute ~/ 60}');
      await tap(tester, 'reminder-minute-${s.minute % 60}');
    }

    List<String> rowsShown(WidgetTester tester) => [
      for (final element
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'reminder-',
                    ) &&
                    w is ListTile,
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value,
    ];

    testWidgets('empty: the Legal hint, a short line and the add button; '
        'opening asks nothing and writes nothing (C2)', (tester) async {
      final (server, push) = await pump(tester);
      expect(find.text('EINKAUFSERINNERUNGEN'), findsOneWidget);
      expect(
        find.text(
          'Lege Erinnerungen für deine Einkaufstage an. Zur gewählten Uhrzeit '
          'in der Zeitzone deines Geräts schickt Snacklist dir einen Hinweis '
          'aufs Handy, mit der Zahl der offenen Einträge, nie mit '
          'Artikelnamen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
      expect(find.text('Erinnerung hinzufügen'), findsOneWidget);
      expect(push.calls, isEmpty, reason: 'no OS prompt, no token');
      expect(server.calls, ['read'], reason: 'no row');
    });

    testWidgets('nothing without the flag', (tester) async {
      final (server, _) = await pump(tester, flag: false);
      expect(key('shopping-reminders'), findsNothing);
      expect(server.calls, isEmpty);
    });

    testWidgets('the sheet starts at the day before, 19:00, with no day; '
        'closing it stores nothing (SR-Q3, C2)', (tester) async {
      final (server, push) = await pump(tester);
      await tap(tester, 'reminder-add');
      expect(find.text('Neue Erinnerung'), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(key('reminder-hour-19')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(key('reminder-minute-0')).selected,
        isTrue,
      );
      for (var day = 1; day <= 7; day++) {
        expect(
          tester.widget<ChoiceChip>(key('reminder-day-$day')).selected,
          isFalse,
        );
      }
      expect(
        tester.widget<FilledButton>(key('reminder-save')).onPressed,
        isNull,
        reason: 'no day picked yet',
      );
      await tap(tester, 'reminder-cancel');
      expect(key('reminder-sheet'), findsNothing);
      expect(push.calls, isEmpty);
      expect(server.calls, ['read']);
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
    });

    testWidgets('one reminder: shown at once, then saved; the first Save '
        'asks for push', (tester) async {
      final (server, push) = await pump(tester);
      server.hold = Completer();
      await compose(tester, slot(6, before, 19));
      expect(find.text('Nächste: Fr., 27. Nov., 19:00'), findsOneWidget);
      await tester.tap(key('reminder-save'));
      await tester.pumpAndSettle();
      expect(row(slot(6, before, 19)), findsOneWidget, reason: 'optimistic');
      expect(server.rows, isEmpty);
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(push.calls, ['optIn']);
      expect(server.calls, ['read', 'add 6 dayBefore 1140 Europe/Berlin de']);
      expect(find.text('Am Tag davor, 19:00'), findsOneWidget);
      expect(find.text('Samstag'), findsOneWidget);
      expect(find.text('Nächste: Fr., 27. Nov., 19:00'), findsOneWidget);
      expect(find.text('Noch keine Erinnerung.'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('three and more across days, in shopping-day order; the day '
        'before and on the day; two on one shopping day both shown', (
      tester,
    ) async {
      await pump(
        tester,
        initial: [
          slot(6, onDay, 9, 15),
          slot(2, before, 18),
          slot(6, before, 20),
          slot(4, onDay, 17, 30),
        ],
      );
      expect(rowsShown(tester), [
        'reminder-${slot(2, before, 18)}',
        'reminder-${slot(4, onDay, 17, 30)}',
        'reminder-${slot(6, before, 20)}',
        'reminder-${slot(6, onDay, 9, 15)}',
      ]);
      expect(find.text('Am Tag davor, 18:00'), findsOneWidget);
      expect(find.text('Nächste: Mo., 30. Nov., 18:00'), findsOneWidget);
      expect(find.text('Am Tag davor, 20:00'), findsOneWidget);
      expect(find.text('Am Einkaufstag, 09:15'), findsOneWidget);
      expect(find.text('Nächste: Sa., 28. Nov., 09:15'), findsOneWidget);
      expect(find.text('Am Einkaufstag, 17:30'), findsOneWidget);
      expect(find.text('Nächste: Do., 26. Nov., 17:30'), findsOneWidget);
      expect(find.textContaining('Vorabend'), findsNothing);
    });

    testWidgets('time already passed today: saved, today skipped, and said '
        'so (SR-Q7)', (tester) async {
      final (server, _) = await pump(
        tester,
        now: DateTime(2026, 11, 27, 20, 15),
      );
      await compose(tester, slot(6, before, 19));
      expect(find.text('Nächste: Fr., 4. Dez., 19:00'), findsOneWidget);
      await tap(tester, 'reminder-save');
      expect(server.rows.single.sentOn, DateTime(2026, 11, 27));
      expect(
        find.text(
          'Gespeichert. Heute ist 19:00 schon vorbei, die erste Erinnerung '
          'kommt am Fr., 4. Dez., 19:00.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nächste: Fr., 4. Dez., 19:00'), findsOneWidget);
    });

    testWidgets('refused permission: the row goes again, nothing is saved, '
        'and the blocked notice shows (SR-Q12, C2)', (tester) async {
      final (server, push) = await pump(
        tester,
        before: (push) => push.allowed = false,
      );
      await compose(tester, slot(6, before, 19));
      await tap(tester, 'reminder-save');
      expect(push.calls, ['optIn']);
      expect(server.calls, ['read']);
      expect(row(slot(6, before, 19)), findsNothing);
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
      expect(
        find.text(
          'Mitteilungen sind für Snacklist ausgeschaltet. Schalte sie in den '
          'Einstellungen deines Handys ein.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a duplicate is refused in the sheet, before the server '
        '(SR-Q6)', (tester) async {
      final (server, push) = await pump(tester, initial: [slot(6, before, 19)]);
      await compose(tester, slot(6, before, 19));
      await tap(tester, 'reminder-save');
      expect(key('reminder-sheet'), findsOneWidget, reason: 'stays open');
      expect(find.text('Diese Erinnerung hast du schon.'), findsOneWidget);
      expect(push.calls, isNot(contains('optIn')));
      expect(server.calls.where((c) => c.startsWith('add')), isEmpty);
      await tap(tester, 'reminder-hour-20');
      expect(find.text('Diese Erinnerung hast du schon.'), findsNothing);
      await tap(tester, 'reminder-save');
      expect(server.rows, hasLength(2), reason: 'same day, another time');
    });

    testWidgets("one another device made meanwhile: the server's refusal "
        'takes the row back, with the notice', (tester) async {
      final (server, _) = await pump(tester);
      server.refuse = ReminderRefusal.duplicate;
      await compose(tester, slot(3, onDay, 8));
      await tap(tester, 'reminder-save');
      expect(row(slot(3, onDay, 8)), findsNothing);
      expect(find.text('Diese Erinnerung hast du schon.'), findsOneWidget);
    });

    testWidgets('at 14 the add button is off and the cap is said (SR-Q9)', (
      tester,
    ) async {
      await pump(
        tester,
        initial: [
          for (var day = 1; day <= 7; day++) ...[
            slot(day, before, 19),
            slot(day, onDay, 8),
          ],
        ],
      );
      expect(rowsShown(tester), hasLength(14));
      expect(
        tester.widget<FilledButton>(key('reminder-add')).onPressed,
        isNull,
      );
      expect(
        find.text(
          'Das sind 14 Erinnerungen, mehr geht nicht. Lösch eine, um eine '
          'neue anzulegen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets("the server's cap takes a 14th made meanwhile back", (
      tester,
    ) async {
      final (server, _) = await pump(tester, initial: [slot(1, before, 19)]);
      server.refuse = ReminderRefusal.limit;
      await compose(tester, slot(2, before, 19));
      await tap(tester, 'reminder-save');
      expect(row(slot(2, before, 19)), findsNothing);
      expect(
        find.text(
          'Das sind 14 Erinnerungen, mehr geht nicht. Lösch eine, um eine '
          'neue anzulegen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row opens its sheet; a new time is saved to it', (
      tester,
    ) async {
      final (server, _) = await pump(tester, initial: [slot(6, before, 19)]);
      await tester.tap(row(slot(6, before, 19)));
      await tester.pumpAndSettle();
      expect(find.text('Erinnerung bearbeiten'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(key('reminder-day-6')).selected, isTrue);
      await tap(tester, 'reminder-hour-18');
      await tap(tester, 'reminder-minute-30');
      await tap(tester, 'reminder-save');
      expect(server.calls.last, 'update r0 6 dayBefore 1110 Europe/Berlin de');
      expect(find.text('Am Tag davor, 18:30'), findsOneWidget);
    });

    testWidgets('an edit the server refuses goes back to what it was', (
      tester,
    ) async {
      final (server, _) = await pump(tester, initial: [slot(6, before, 19)]);
      server.failing = true;
      await tester.tap(row(slot(6, before, 19)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-on-the-day');
      await tap(tester, 'reminder-save');
      expect(find.text('Am Tag davor, 19:00'), findsOneWidget);
      expect(find.text('Am Einkaufstag, 19:00'), findsNothing);
      expect(
        find.text('Die Änderung konnte nicht gespeichert werden.'),
        findsOneWidget,
      );
    });

    testWidgets('deleting the last one turns the feature off: no rows, and '
        'the device forgets push with the alert off (SR-Q4)', (tester) async {
      final (server, push) = await pump(tester, initial: [slot(6, before, 19)]);
      await tester.tap(row(slot(6, before, 19)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-delete');
      expect(server.rows, isEmpty);
      expect(push.calls, contains('forget'));
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
    });

    testWidgets('a delete the server refuses brings the row back', (
      tester,
    ) async {
      final (server, push) = await pump(tester, initial: [slot(6, before, 19)]);
      server.failing = true;
      await tester.tap(row(slot(6, before, 19)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-delete');
      expect(row(slot(6, before, 19)), findsOneWidget);
      expect(push.calls, isNot(contains('forget')));
      expect(
        find.text('Die Änderung konnte nicht gespeichert werden.'),
        findsOneWidget,
      );
    });

    testWidgets('a delete that failed, then the other one: the row that '
        'came back keeps the device on push', (tester) async {
      final (server, push) = await pump(
        tester,
        initial: [slot(6, before, 19), slot(2, before, 18)],
      );
      server.failNext = 1;
      await tester.tap(row(slot(6, before, 19)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-delete');
      expect(row(slot(6, before, 19)), findsOneWidget, reason: 'back');
      await tester.tap(row(slot(2, before, 18)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-delete');
      expect(server.rows.single.slot, slot(6, before, 19));
      expect(push.calls, isNot(contains('forget')));
    });

    testWidgets('a reminder that went out today, moved to another day that '
        'fires later today, still comes today', (tester) async {
      final (server, _) = await pump(
        tester,
        initial: [slot(4, onDay, 8)],
        sentOn: DateTime(2026, 11, 26),
      );
      expect(find.text('Nächste: Do., 3. Dez., 08:00'), findsOneWidget);
      await tester.tap(row(slot(4, onDay, 8)));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-hour-18');
      expect(
        find.text('Nächste: Do., 3. Dez., 18:00'),
        findsOneWidget,
        reason: 'the same days: today already went out',
      );
      await tap(tester, 'reminder-day-5');
      await tap(tester, 'reminder-day-before');
      expect(find.text('Nächste: Do., 26. Nov., 18:00'), findsOneWidget);
      await tap(tester, 'reminder-save');
      expect(server.rows.single.sentOn, isNull);
      expect(find.text('Nächste: Do., 26. Nov., 18:00'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a save that reached the server after its time says today '
        'is skipped, whatever the time of the tap', (tester) async {
      final clock = TestClock(DateTime(2026, 11, 27, 18, 58));
      final (server, _) = await pump(tester, clock: clock);
      await compose(tester, slot(6, before, 19));
      expect(find.text('Nächste: Fr., 27. Nov., 19:00'), findsOneWidget);
      server.hold = Completer();
      await tap(tester, 'reminder-save');
      clock.now = DateTime(2026, 11, 27, 19, 0, 30);
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(server.rows.single.sentOn, DateTime(2026, 11, 27));
      expect(
        find.text(
          'Gespeichert. Heute ist 19:00 schon vorbei, die erste Erinnerung '
          'kommt am Fr., 4. Dez., 19:00.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the sheet checks for a duplicate on Save, against the list '
        'as it is then', (tester) async {
      final (server, _) = await pump(tester);
      server.hold = Completer();
      await compose(tester, slot(3, onDay, 8));
      await tap(tester, 'reminder-save');
      expect(row(slot(3, onDay, 8)), findsOneWidget, reason: 'pending');
      await compose(tester, slot(3, onDay, 8));
      await tap(tester, 'reminder-save');
      expect(find.text('Diese Erinnerung hast du schon.'), findsOneWidget);
      server.failNext = 1;
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(row(slot(3, onDay, 8)), findsNothing, reason: 'failed, gone');
      // The failure's notice covers the sheet's buttons until it goes.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, 'reminder-save');
      expect(key('reminder-sheet'), findsNothing);
      expect(server.rows.single.slot, slot(3, onDay, 8));
    });

    testWidgets('a first read that fails is tried again', (tester) async {
      final (server, _) = await pump(
        tester,
        seed: (server) => server.readFails = 1,
      );
      expect(key('shopping-reminders'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Noch keine Erinnerung.'), findsOneWidget);
      expect(server.calls, ['read']);
    });

    testWidgets('English: the device clock decides 12 or 24 hours (SR-Q10)', (
      tester,
    ) async {
      await pump(
        tester,
        locale: const Locale('en'),
        initial: [slot(6, before, 19)],
      );
      expect(find.text('The day before, 7:00 PM'), findsOneWidget);
      expect(find.text('Next: Fri, Nov 27, 7:00 PM'), findsOneWidget);
      await tap(tester, 'reminder-add');
      expect(find.text('7 PM'), findsOneWidget);
      expect(find.text('12 AM'), findsOneWidget);
    });

    testWidgets('English on a 24-hour device; German always 24 hours', (
      tester,
    ) async {
      await pump(
        tester,
        locale: const Locale('en'),
        always24: true,
        initial: [slot(6, onDay, 9, 5)],
      );
      expect(find.text('On the day, 09:05'), findsOneWidget);
      await tap(tester, 'reminder-add');
      expect(find.text('19'), findsOneWidget);
    });
  });

  group('copy (Legal M1, M4)', () {
    Map<String, Object?> arb(String language) =>
        jsonDecode(File('l10n/app_$language.arb').readAsStringSync())
            as Map<String, Object?>;

    test('the SR1 hint is the hashed wording', () {
      String hash(Object? text) =>
          sha256.convert(utf8.encode(text! as String)).toString();
      expect(
        hash(arb('de')['remindersHint']),
        'ada69d1cc1deab772eec0915cd75047b1fea3d759e640987608c152151934dbd',
      );
      expect(
        hash(arb('en')['remindersHint']),
        'a1f9ddf84fc4f3f6b2e2ef2f8ef74a19ea0fd9fcbc51b71d1d3a243ccf5c1783',
      );
    });

    test('no SR1 string says Vorabend or evening before', () {
      for (final language in ['de', 'en']) {
        for (final MapEntry(:key, :value) in arb(language).entries) {
          if (key.startsWith('reminder') && value is String) {
            expect(
              value,
              isNot(matches(RegExp('Vorabend|evening', caseSensitive: false))),
              reason: key,
            );
          }
        }
      }
    });
  });
}
