import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

/// Records what the app sends.
class Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add((event, properties));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fresh device store.
DeviceCache emptyCache() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  return DeviceCache(SharedPreferencesAsync());
}

/// Saturday 14 November 2026, 10:00.
final t0 = DateTime(2026, 11, 14, 10);

/// The server's trip sessions; [premium] false answers without lines, as
/// `trip_session` does for Free.
class FakeSessions() implements TripSessionRepository {
  final saved = <FinishedTrip>[];
  final marks = <(String, String, bool)>[];
  var fail = false;
  var premium = true;

  /// The server refuses every save for good (`22023`).
  var refuse = false;

  /// Marks of these line keys fail.
  final failMarks = <String>{};

  /// While set, a save waits for it before it answers.
  Completer<void>? hold;

  @override
  Future<FinishedTrip> save(FinishedTrip trip, {required bool log}) async {
    await hold?.future;
    if (fail) {
      throw Exception('offline');
    }
    if (refuse) {
      throw const TripRefused('too_many_lines');
    }
    saved.add(trip);
    return premium
        ? trip
        : FinishedTrip.fromJson({...trip.toJson(), 'lines': null});
  }

  @override
  Future<FinishedTrip> fetch(String id) =>
      throw UnimplementedError('not used by the cubit');

  @override
  Future<void> markPlanned(
    String id,
    String key, {
    required bool planned,
  }) async {
    if (fail || failMarks.contains(key)) {
      throw Exception('offline');
    }
    marks.add((id, key, planned));
  }

  final deleted = <String>[];

  @override
  Future<void> delete(String id) async {
    if (fail) {
      throw Exception('offline');
    }
    deleted.add(id);
  }
}

/// An open item from before the fake server's clock, so its answers win.
Item open(String id, {String? store, int n = 0}) => Item(
  id: id,
  name: id,
  status: ItemStatus.active,
  createdAt: DateTime.utc(2026, 10).add(Duration(minutes: n)),
  updatedAt: DateTime.utc(2026, 10),
  storeId: store,
  addedBy: 'peter',
);

/// One household's list and its trip cubit under fake time on [device]
/// (a fresh one by default). [jumped] moves the clock without running
/// timers, as a suspended app does.
class World(
  final FakeAsync async, {
  final DeviceCache? device,
  final String household = 'home-h',
}) {
  this {
    repo.rows.addAll({
      for (final i in [
        open('milk', store: 'lidl'),
        open('bread', n: 1),
        open('tea', n: 2),
      ])
        i.id: i,
    });
    list = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      clock: now,
      analytics: tracked,
    )..start();
    async.elapse(const Duration(seconds: 1));
    restart();
  }

  late final DeviceCache cache = device ?? emptyCache();
  final repo = FakeRepository();
  final sessions = FakeSessions();
  final tracked = Tracked();
  var flag = true;
  var jumped = Duration.zero;
  late final ListCubit list;
  late TripCubit trips;
  final states = <TripState>[];

  DateTime now() => t0.add(async.elapsed + jumped);

  /// A new trip cubit on the same device, as after an app restart.
  void restart() {
    trips = TripCubit(
      list,
      sessions,
      cache,
      userId: 'peter',
      householdId: household,
      enabled: () => flag,
      logs: () => true,
      clock: now,
      analytics: tracked,
    );
    trips.stream.listen(states.add);
    unawaited(trips.start());
    async.flushMicrotasks();
  }

  void close() {
    unawaited(trips.close());
    unawaited(list.close());
    async.flushMicrotasks();
  }

  void tick(String id) {
    list.tick(id);
    async.flushMicrotasks();
  }

  void elapse(Duration d) => async.elapse(d);

  TripState get state => trips.state;

  Running get running => state as Running;

  Ended get ended => state as Ended;

  /// The trip's events as `event {property: value}`.
  List<String> shopEvents() => [
    for (final (event, properties) in tracked.events)
      if (event.startsWith('shop_')) '$event $properties',
  ];
}

void run(void Function(World w) body, {DeviceCache? cache}) =>
    fakeAsync((async) {
      final w = World(async, device: cache);
      body(w);
      w.close();
    });

Duration min(int n) => Duration(minutes: n);

void main() {
  test('every own tick asks while no trip runs, also after a no', () {
    run((w) {
      w.tick('milk');
      expect(w.state, isA<Asking>());
      final asking = w.state as Asking;
      expect(asking.item.id, 'milk');
      expect(asking.at, w.now());
      expect(asking.snapshot.keys.toSet(), {'milk', 'bread', 'tea'});
      w.trips.no();
      expect(w.state, isA<NoTrip>());
      w.tick('bread');
      expect(w.state, isA<Asking>());
      expect((w.state as Asking).snapshot.keys.toSet(), {'bread', 'tea'});
      expect(w.shopEvents(), ['shop_asked {answer: no}']);
    });
  });

  test('the flag off asks nothing', () {
    run((w) {
      w
        ..flag = false
        ..tick('milk');
      expect(w.state, isA<NoTrip>());
      w.trips.startByHand();
      expect(w.state, isA<NoTrip>());
    });
  });

  test('Zurücknehmen puts the item back as an undo and starts nothing', () {
    run((w) {
      w.tick('milk');
      w.trips.takeBack();
      w.elapse(const Duration(seconds: 1));
      expect(w.state, isA<NoTrip>());
      expect(w.list.state.allItems['milk']!.status, ItemStatus.active);
      expect(
        w.tracked.events.where((e) => e.$1 == 'item_added'),
        isEmpty,
        reason: 'an undo is no add',
      );
      expect(w.shopEvents(), ['shop_asked {answer: take_back}']);
    });
  });

  test('yes starts the trip at the tick with the list as it was', () {
    run((w) {
      final tickedAt = w.now();
      w
        ..tick('milk')
        ..elapse(const Duration(seconds: 20));
      w.trips.yes();
      final trip = w.running.trip;
      expect(trip.startedAt, tickedAt);
      expect(trip.source, TripSource.ask);
      expect(trip.householdId, 'home-h');
      expect(trip.snapshot.keys.toSet(), {'milk', 'bread', 'tea'});
      expect(trip.snapshot['milk']!.storeId, 'lidl');
      expect(w.running.lastTick, tickedAt);
      expect(w.trips.elapsed(w.now()), const Duration(seconds: 20));
      w.tick('bread');
      expect(w.state, isA<Running>(), reason: 'no question while it runs');
      expect(w.shopEvents(), [
        'shop_asked {answer: yes}',
        'shop_started {source: ask}',
      ]);
    });
  });

  test('a start by hand snapshots the shown list now', () {
    run((w) {
      w.trips.startByHand();
      expect(w.running.trip.source, TripSource.manual);
      expect(w.running.trip.startedAt, w.now());
      expect(w.running.trip.snapshot.keys.toSet(), {'milk', 'bread', 'tea'});
      expect(w.running.lastTick, isNull);
      expect(w.shopEvents(), ['shop_started {source: manual}']);
    });
  });

  test('a pause stops the stopwatch until Weiter', () {
    run((w) {
      w.trips.startByHand();
      final start = w.now();
      w.elapse(min(5));
      w.trips.pause();
      expect(w.running.trip.paused, isTrue);
      expect(autoPause(w.running.trip), isNull);
      w.elapse(min(10));
      w.trips.resume();
      expect(w.running.trip.resumedAt, w.now());
      w.elapse(min(5));
      expect(w.trips.elapsed(w.now()), min(10));
      expect(w.now().difference(start), min(20));
    });
  });

  test('Beenden ends now, saves, and the summary has the trip', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      w
        ..elapse(min(3))
        ..tick('bread')
        ..elapse(min(17));
      final end = w.now();
      unawaited(w.trips.finish());
      expect(w.ended.save, TripSave.saving);
      w.async.flushMicrotasks();
      expect(w.ended.saved, isTrue);
      expect(w.ended.auto, isFalse);
      final saved = w.sessions.saved.single;
      expect(saved.endedAt, end);
      expect(saved.end, TripEnd.user);
      expect(saved.active, min(20));
      expect(
        [for (final l in saved.lines!) (l.key, l.bought)],
        [('milk', true), ('bread', true), ('tea', false)],
      );
      expect(w.shopEvents().last, 'shop_ended {reason: user, minutes: 15to30}');
    });
  });

  test('without Premium the saved end shows without lines', () {
    run((w) {
      w.sessions.premium = false;
      w.trips.startByHand();
      w.tick('milk');
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      expect(w.ended.trip.lines, isNull);
      expect(w.ended.trip.bought, 1);
    });
  });

  test('45 quiet minutes pause the trip; Beenden then ends at the tick', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      final tickedAt = w.now();
      w.elapse(min(44));
      expect(autoPause(w.running.trip), isNull);
      w.elapse(min(1) + const Duration(seconds: 30));
      expect(autoPause(w.running.trip), isNotNull);
      expect(w.running.trip.pauses.single.from, tickedAt.add(min(45)));
      expect(endAt(w.running.trip, w.running.lastTick, w.now()), tickedAt);
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      expect(w.sessions.saved.single.endedAt, tickedAt);
      expect(w.sessions.saved.single.end, TripEnd.user);
    });
  });

  test('a tick ends the pause the trip took itself', () {
    run((w) {
      w.trips.startByHand();
      w.elapse(min(46));
      expect(autoPause(w.running.trip), isNotNull);
      w.tick('tea');
      expect(w.running.trip.paused, isFalse);
      expect(w.running.lastTick, w.now());
    });
  });

  test('4 quiet hours end the trip at the last tick', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      w
        ..elapse(min(10))
        ..tick('bread');
      final last = w.now();
      w.elapse(const Duration(hours: 4, seconds: 30));
      expect(w.ended.auto, isTrue);
      expect(w.ended.saved, isTrue);
      expect(w.ended.trip.endedAt, last);
      expect(w.ended.trip.end, TripEnd.auto);
      expect(w.ended.trip.active, min(10));
      expect(w.shopEvents().last, 'shop_ended {reason: auto, minutes: lt15}');
    });
  });

  test('back after 5 hours, the trip has ended at the last tick', () {
    run((w) {
      w.tick('milk');
      final last = w.now();
      w.trips.yes();
      w.jumped = const Duration(hours: 5);
      unawaited(w.trips.check());
      w.async.flushMicrotasks();
      expect(w.ended.auto, isTrue);
      expect(w.ended.trip.endedAt, last);
    });
  });

  test('a restart 5 hours later ends it too, and keeps the card', () {
    run((w) {
      w.tick('milk');
      final last = w.now();
      w.trips.yes();
      w.async.flushMicrotasks();
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w
        ..jumped = const Duration(hours: 5)
        ..restart();
      expect(w.ended.auto, isTrue);
      expect(w.ended.trip.endedAt, last);
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w.restart();
      expect(w.ended.auto, isTrue, reason: 'the card stays until dismissed');
      w.trips.dismissEnded();
      w.async.flushMicrotasks();
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w.restart();
      expect(w.state, isA<NoTrip>());
    });
  });

  test('Weiter einkaufen runs the same trip; the gap is a pause', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      w.elapse(min(20));
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      final first = w.ended.trip;
      w.elapse(min(10));
      w.trips.keepShopping();
      expect(w.running.trip.id, first.id);
      expect(w.running.trip.resumedAt, w.now());
      w
        ..elapse(min(5))
        ..tick('tea');
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      final [a, b] = w.sessions.saved;
      expect(b.id, a.id);
      expect(b.active, min(25));
      expect(b.lines!.where((l) => l.bought).length, 2);
    });
  });

  test('a trip survives a restart', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      w.elapse(min(2));
      w.trips.pause();
      final trip = w.running.trip;
      w.async.flushMicrotasks();
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w.restart();
      expect(w.running.trip, trip);
      expect(w.running.trip.paused, isTrue);
    });
  });

  test('an end that failed to save is retried after a restart', () {
    run((w) {
      w.sessions.fail = true;
      w.trips.startByHand();
      w.tick('milk');
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      expect(w.ended.save, TripSave.failed);
      final id = w.ended.trip.id;
      unawaited(w.trips.retry());
      w.async.flushMicrotasks();
      expect(w.ended.save, TripSave.failed);
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w.sessions.fail = false;
      w.restart();
      expect(w.sessions.saved.single.id, id);
      w.tick('bread');
      expect(w.state, isA<Asking>(), reason: 'nothing runs any more');
    });
  });

  test('Erneut versuchen saves a failed end', () {
    run((w) {
      w.sessions.fail = true;
      w.trips.startByHand();
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      w.sessions.fail = false;
      unawaited(w.trips.retry());
      w.async.flushMicrotasks();
      expect(w.ended.saved, isTrue);
      expect(w.sessions.saved, hasLength(1));
    });
  });

  test('War geplant before the save goes out with the save', () {
    run((w) {
      w.sessions.fail = true;
      w.trips.startByHand();
      w.repo.rows['coffee'] = open('coffee');
      unawaited(w.list.resync());
      w
        ..elapse(const Duration(seconds: 1))
        ..tick('coffee');
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      unawaited(w.trips.markPlanned('coffee', planned: true));
      w.async.flushMicrotasks();
      expect(w.sessions.marks, isEmpty);
      w.sessions.fail = false;
      unawaited(w.trips.retry());
      w.async.flushMicrotasks();
      final saved = w.sessions.saved.single;
      expect(
        saved.lines!.singleWhere((l) => l.key == 'coffee').markedPlanned,
        isTrue,
      );
    });
  });

  test('a trip of another household: no question and no strip here', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      w.async.flushMicrotasks();
      final other = World(w.async, device: w.cache, household: 'office-h');
      expect(other.state, isA<RunningElsewhere>());
      expect((other.state as RunningElsewhere).householdId, 'home-h');
      other.tick('bread');
      expect(other.state, isA<RunningElsewhere>());
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      w.trips.dismissEnded();
      w.async.flushMicrotasks();
      unawaited(other.trips.check());
      w.async.flushMicrotasks();
      expect(other.state, isA<NoTrip>());
      expect(w.state, isA<NoTrip>());
      other.close();
    });
  });

  bool markedIn(FinishedTrip t, String key) =>
      t.lines!.singleWhere((l) => l.key == key).markedPlanned;

  /// A trip by hand whose extras [extras] were ticked on it, ended.
  void endWithExtras(World w, List<String> extras) {
    w.trips.startByHand();
    for (final (n, id) in extras.indexed) {
      w.repo.rows[id] = open(id, n: n);
    }
    unawaited(w.list.resync());
    w.elapse(const Duration(seconds: 1));
    extras.forEach(w.tick);
    unawaited(w.trips.finish());
    w.async.flushMicrotasks();
  }

  test('War geplant during the first save is shown and saved again', () {
    run((w) {
      final hold = w.sessions.hold = Completer<void>();
      endWithExtras(w, ['coffee']);
      expect(w.ended.save, TripSave.saving);
      unawaited(w.trips.markPlanned('coffee', planned: true));
      w.async.flushMicrotasks();
      w.sessions.hold = null;
      hold.complete();
      w.async.flushMicrotasks();
      expect(markedIn(w.ended.trip, 'coffee'), isTrue);
      expect(w.ended.saved, isTrue);
      expect(w.sessions.saved, hasLength(2));
      expect(markedIn(w.sessions.saved.last, 'coffee'), isTrue);
    });
  });

  test('a refused War geplant takes back only its own line', () {
    run((w) {
      endWithExtras(w, ['coffee', 'juice']);
      expect(w.ended.saved, isTrue);
      w.sessions.failMarks.add('coffee');
      bool? ok;
      unawaited(
        w.trips.markPlanned('coffee', planned: true).then((v) => ok = v),
      );
      unawaited(w.trips.markPlanned('juice', planned: true));
      w.async.flushMicrotasks();
      expect(ok, isFalse);
      expect(markedIn(w.ended.trip, 'coffee'), isFalse);
      expect(markedIn(w.ended.trip, 'juice'), isTrue);
    });
  });

  test('with the flag off a trip neither pauses nor ends; on, it does', () {
    run((w) {
      w.tick('milk');
      w.trips.yes();
      final last = w.now();
      w
        ..flag = false
        ..elapse(const Duration(hours: 5));
      expect(w.running.trip.pauses, isEmpty);
      expect(w.sessions.saved, isEmpty);
      w.flag = true;
      unawaited(w.trips.check());
      w.async.flushMicrotasks();
      expect(w.ended.auto, isTrue);
      expect(w.ended.trip.endedAt, last);
    });
  });

  test('the 30 s rule runs again once the flag is back', () {
    run((w) {
      w.trips.startByHand();
      w
        ..flag = false
        ..elapse(min(1))
        ..flag = true;
      unawaited(w.trips.check());
      w.elapse(min(46));
      expect(autoPause(w.running.trip), isNotNull);
    });
  });

  test("a save answered after close leaves another household's trip", () {
    run((w) {
      final hold = w.sessions.hold = Completer<void>();
      w.trips.startByHand();
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      expect(w.trips.isClosed, isTrue);
      final other = World(w.async, device: w.cache, household: 'office-h');
      other.trips.startByHand();
      w.async.flushMicrotasks();
      w.sessions.hold = null;
      hold.complete();
      w.async.flushMicrotasks();
      unawaited(other.trips.close());
      w.async.flushMicrotasks();
      other.restart();
      expect(other.state, isA<Running>());
      other.close();
    });
  });

  test('a dismissed auto-end card stays away on a check right after', () {
    run((w) {
      w.trips.startByHand();
      w.elapse(const Duration(hours: 4, seconds: 30));
      expect(w.ended.auto, isTrue);
      w.trips.dismissEnded();
      unawaited(w.trips.check());
      w.async.flushMicrotasks();
      expect(w.state, isA<NoTrip>());
    });
  });

  test('an end the server refuses for good is not tried again', () {
    run((w) {
      w.sessions.refuse = true;
      w.trips.startByHand();
      unawaited(w.trips.finish());
      w.async.flushMicrotasks();
      expect(w.ended.save, TripSave.refused);
      w.sessions.refuse = false;
      unawaited(w.trips.retry());
      unawaited(w.trips.close());
      w.async.flushMicrotasks();
      w.restart();
      expect(w.sessions.saved, isEmpty);
    });
  });
}
