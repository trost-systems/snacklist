import 'dart:async';

import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/log/log_cubit.dart';
import 'package:family_groceries/log/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

void main() {
  late DeviceCache cache;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    cache = DeviceCache(SharedPreferencesAsync());
  });

  Future<LogCubit> started(FakeTrips trips) async {
    final log = LogCubit(trips, cache, clock: clock);
    addTearDown(log.close);
    await log.start();
    return log;
  }

  test('without a saved choice the journal shows; the toggle cycles and is '
      'kept for the next start', () async {
    final first = await started(FakeTrips());
    expect(first.state.view, LogView.journal);
    first.toggleView();
    expect(first.state.view, LogView.stores);
    await pumpEventQueue();
    final second = await started(FakeTrips());
    expect(second.state.view, LogView.stores, reason: 'kept on the device');
    second.toggleView();
    expect(second.state.view, LogView.journal);
    await pumpEventQueue();
    expect((await started(FakeTrips())).state.view, LogView.journal);
  });

  test('loads the trips newest first, today and its month', () async {
    final older = trip(2026, 11, 2, store: 'lidl');
    final newer = trip(2026, 11, 10, store: 'rewe');
    final log = await started(FakeTrips([older, newer]));
    expect(log.state.load, LogLoad.ready);
    expect(log.state.trips, [newer, older]);
    expect(log.state.today, DateTime(2026, 11, 12));
    expect(log.state.month, DateTime(2026, 11));
  });

  test('a failed first load fails; retry loads', () async {
    final trips = FakeTrips([trip(2026, 11, 2)])..fail = true;
    final log = await started(trips);
    expect(log.state.load, LogLoad.failed);
    trips.fail = false;
    await log.retry();
    expect(log.state.load, LogLoad.ready);
    expect(log.state.trips, hasLength(1));
  });

  test('a failed refresh keeps the trips shown', () async {
    final trips = FakeTrips([trip(2026, 11, 2)]);
    final log = await started(trips);
    trips.fail = true;
    await log.refresh();
    expect(log.state.load, LogLoad.ready);
    expect(log.state.trips, hasLength(1));
  });

  test('picking a day narrows to it, picking it again widens; a future day '
      'is not picked', () async {
    final tue = trip(2026, 11, 10, store: 'lidl');
    final log = await started(FakeTrips([tue, trip(2026, 11, 9)]));
    log.pickDay(DateTime(2026, 11, 10));
    expect(log.state.shown, [tue]);
    log.pickDay(DateTime(2026, 11, 10));
    expect(log.state.day, isNull);
    expect(log.state.shown, hasLength(2));
    log.pickDay(DateTime(2026, 11, 13));
    expect(log.state.day, isNull, reason: 'tomorrow');
    log
      ..pickDay(DateTime(2026, 11, 9))
      ..clearDay();
    expect(log.state.day, isNull);
  });

  test("Premium: the calendar goes back to the oldest trip's month, not "
      'past this one', () async {
    final log = await started(FakeTrips([trip(2026, 9, 3), trip(2026, 11, 2)]));
    expect(log.state.canGoForward, isFalse);
    log.showMonth(1);
    expect(log.state.month, DateTime(2026, 11));
    log
      ..showMonth(-1)
      ..showMonth(-1)
      ..showMonth(-1);
    expect(log.state.month, DateTime(2026, 9));
    expect(log.state.canGoBack, isFalse);
    expect(log.state.canGoForward, isTrue);
    log.showMonth(1);
    expect(log.state.month, DateTime(2026, 10));
  });

  test('Free: only the 4 weeks up to today, the older trips counted; the '
      "calendar stops at the window's month and its older days are not "
      'picked', () async {
    final recent = trip(2026, 10, 16);
    final older = trip(2026, 10, 15);
    final log = await started(FakeTrips([recent, older], false));
    expect(log.state.trips, [recent]);
    expect(
      log.state.window,
      RecentHistory(since: DateTime(2026, 10, 16), locked: 1),
    );
    log
      ..showMonth(-1)
      ..showMonth(-1);
    expect(log.state.month, DateTime(2026, 10));
    log.pickDay(DateTime(2026, 10, 15));
    expect(log.state.day, isNull, reason: 'a locked day');
    log.pickDay(DateTime(2026, 10, 16));
    expect(log.state.day, DateTime(2026, 10, 16));
  });

  test('a change of Premium reads the window again', () async {
    final changes = StreamController<Object?>();
    addTearDown(changes.close);
    final trips = FakeTrips([trip(2026, 9, 3), trip(2026, 11, 2)], false);
    final log = LogCubit(
      trips,
      cache,
      clock: clock,
      premiumChanges: changes.stream,
    );
    addTearDown(log.close);
    await log.start();
    expect(log.state.trips, hasLength(1));
    trips.premium = true;
    changes.add(null);
    await pumpEventQueue();
    expect(log.state.trips, hasLength(2));
    expect(log.state.window, const AllHistory());

    log
      ..showMonth(-1)
      ..showMonth(-1);
    expect(log.state.month, DateTime(2026, 9));
    trips.premium = false;
    changes.add(null);
    await pumpEventQueue();
    expect(
      log.state.month,
      DateTime(2026, 10),
      reason: 'the calendar follows the window back in',
    );
  });
}
