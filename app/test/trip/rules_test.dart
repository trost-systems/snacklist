import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:flutter_test/flutter_test.dart';

final start = DateTime(2026, 11, 14, 10);
DateTime at(int minutes) => start.add(Duration(minutes: minutes));

RunningTrip trip({
  List<TripPause> pauses = const [],
  DateTime? resumedAt,
  Map<String, PlannedItem> snapshot = const {},
}) => RunningTrip(
  id: 't',
  householdId: 'h',
  listId: 'home',
  startedAt: start,
  source: TripSource.ask,
  snapshot: snapshot,
  pauses: pauses,
  resumedAt: resumedAt,
);

Item ticked(String id, DateTime? boughtAt, {bool bought = true}) => Item(
  id: id,
  name: id,
  status: bought ? ItemStatus.bought : ItemStatus.active,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  boughtAt: boughtAt,
);

void main() {
  test('the last tick is the newest one since the start, by anyone', () {
    expect(
      lastTick(trip(), [
        ticked('before', at(-5)),
        ticked('a', at(3)),
        ticked('b', at(9)),
        ticked('open again', at(20), bought: false),
      ]),
      at(9),
    );
    expect(lastTick(trip(), [ticked('before', at(-5))]), isNull);
  });

  test('a tick a little before the start counts, an end never comes '
      'before the start', () {
    final early = start.subtract(const Duration(minutes: 1));
    final open = trip(snapshot: const {'a': PlannedItem(name: 'a')});
    expect(lastTick(open, [ticked('a', early)]), early);
    expect(
      lastTick(trip(), [ticked('a', early)]),
      isNull,
      reason: 'not open at the start: ticked before the trip',
    );
    expect(quietEnd(trip(), early), start);
  });

  group('the long-running rule', () {
    test('runs on under 45 quiet minutes', () {
      expect(checkTrip(trip(), at(10), at(54)), isA<KeepTrip>());
    });

    test('pauses itself 45 minutes after the last tick', () {
      expect(
        checkTrip(trip(), at(10), at(56)),
        isA<AutoPauseAt>().having((c) => c.at, 'at', at(55)),
      );
    });

    test('counts quiet time from Weiter when that is later', () {
      final resumed = trip(
        pauses: [TripPause(from: at(20), to: at(60))],
        resumedAt: at(60),
      );
      expect(checkTrip(resumed, at(10), at(100)), isA<KeepTrip>());
      expect(
        checkTrip(resumed, at(10), at(106)),
        isA<AutoPauseAt>().having((c) => c.at, 'at', at(105)),
      );
    });

    test('a paused trip does not pause again', () {
      final paused = trip(pauses: [TripPause(from: at(12))]);
      expect(checkTrip(paused, at(10), at(120)), isA<KeepTrip>());
    });

    test('ends itself at the last tick after 4 hours, paused or not', () {
      expect(
        checkTrip(trip(), at(10), at(10 + 240)),
        isA<AutoEndAt>().having((c) => c.at, 'at', at(10)),
      );
      final paused = trip(pauses: [TripPause(from: at(55), auto: true)]);
      expect(
        checkTrip(paused, at(10), at(300 + 10)),
        isA<AutoEndAt>().having((c) => c.at, 'at', at(10)),
      );
    });

    test('a trip without a tick ends at its start', () {
      expect(
        checkTrip(trip(), null, at(241)),
        isA<AutoEndAt>().having((c) => c.at, 'at', start),
      );
    });

    test('a tick ends the pause the trip took itself, not the user', () {
      final auto = trip(pauses: [TripPause(from: at(55), auto: true)]);
      expect(
        checkTrip(auto, at(70), at(71)),
        isA<AutoResumeAt>().having((c) => c.at, 'at', at(70)),
      );
      final own = trip(pauses: [TripPause(from: at(55))]);
      expect(checkTrip(own, at(70), at(71)), isA<KeepTrip>());
    });
  });

  test('Beenden ends now, or auto-paused at the last tick', () {
    expect(endAt(trip(), at(10), at(30)), at(30));
    final auto = trip(pauses: [TripPause(from: at(55), auto: true)]);
    expect(endAt(auto, at(10), at(90)), at(10));
  });

  test('applying a pause, then a tick, then the end', () {
    var t = applyCheck(trip(), checkTrip(trip(), at(10), at(60)));
    expect(t.pauses, [TripPause(from: at(55), auto: true)]);
    expect(t.paused, isTrue);
    t = applyCheck(t, checkTrip(t, at(62), at(63)));
    expect(t.pauses, [TripPause(from: at(55), to: at(62), auto: true)]);
    expect(t.paused, isFalse);
  });

  group('the stopwatch', () {
    test('subtracts pauses, an open one up to the end', () {
      expect(
        activeTime(start, at(60), [
          TripPause(from: at(10), to: at(20)),
          TripPause(from: at(50)),
        ]),
        const Duration(minutes: 40),
      );
    });

    test('clips pauses to the trip', () {
      expect(
        activeTime(start, at(30), [
          TripPause(from: at(-10), to: at(5)),
          TripPause(from: at(25), to: at(90)),
        ]),
        const Duration(minutes: 20),
      );
    });

    test('closing pauses at an end drops later ones', () {
      expect(
        closePauses([
          TripPause(from: at(5), to: at(8)),
          TripPause(from: at(20), auto: true),
          TripPause(from: at(40), to: at(45)),
        ], at(30)),
        [
          TripPause(from: at(5), to: at(8)),
          TripPause(from: at(20), to: at(30), auto: true),
        ],
      );
    });
  });
}
