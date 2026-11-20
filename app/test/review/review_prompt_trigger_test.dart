import 'dart:async';

import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/review_prompt_trigger.dart';
import 'package:family_groceries/review/trip_signals.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'fakes.dart';

void main() {
  late FakeStoreReview review;
  late ListCubit cubit;
  late FakeRepository repo;
  late Popups popups;
  late MemoryReviewStore store;
  late ReviewPrompt prompt;

  /// A store build's install that is due: only the trip is missing. [v2]
  /// is the flag `rating-triggers-v2`; [trips] trip mode, none by default.
  Future<void> pumpTrigger(
    WidgetTester tester, {
    bool listening = false,
    bool v2 = false,
    TripSignals? trips,
    DateTime Function() clock = DateTime.now,
  }) async {
    review = FakeStoreReview();
    final now = clock();
    store = MemoryReviewStore()
      ..json = ReviewCounters(
        firstLaunch: now.subtract(const Duration(days: 30)),
        activeDays: 5,
        completedTrips: 4,
        itemsAdded: 60,
      ).toJson();
    prompt = ReviewPrompt(
      store,
      review,
      channel: BuildChannel.store,
      version: Future.value('1.4.0'),
      clock: clock,
      v2: () => v2,
    );
    repo = FakeRepository();
    cubit = ListCubit(repo, MemoryListCache(), userId: 'peter', clock: clock)
      ..start();
    addTearDown(cubit.close);
    popups = Popups();
    addTearDown(popups.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prompt),
          if (trips != null) RepositoryProvider.value(value: trips),
        ],
        child: MaterialApp(
          navigatorObservers: [popups],
          builder: (_, child) => NoticesHost(popups: popups, child: child!),
          home: Scaffold(
            body: ReviewPromptTrigger(
              cubit: cubit,
              listening: listening,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Adds [count] items, then ticks them all off; their ids.
  Future<List<String>> shop(WidgetTester tester, int count) async {
    final ids = [
      for (var i = 0; i < count; i++)
        (cubit.addEntry(parseEntry('Ding $i')) as Added).item.id,
    ];
    await tester.pump();
    ids.forEach(cubit.tick);
    await tester.pump();
    return ids;
  }

  Future<void> idle(
    WidgetTester tester, [
    Duration time = ReviewPromptTrigger.idle,
  ]) async {
    await tester.pump(time);
    await tester.pump();
  }

  testWidgets('asks 3 s after a trip of three, left alone', (tester) async {
    await pumpTrigger(tester);
    await shop(tester, 3);
    await idle(tester, const Duration(milliseconds: 2900));
    expect(review.requests, 0);
    await idle(tester, const Duration(milliseconds: 100));
    expect(review.requests, 1);
  });

  /// Adds an item while the list is offline for [offline], then back
  /// online, sends it; the trip after that ticks it and three more off.
  Future<void> shopAfterOffline(WidgetTester tester, Duration offline) async {
    repo.online = false;
    final first = (cubit.addEntry(parseEntry('Ding')) as Added).item.id;
    await idle(tester, offline);
    expect(cubit.state.connection, ConnectionStatus.offline);
    repo.online = true;
    await tester.runAsync(cubit.resync);
    await idle(tester, const Duration(seconds: 1));
    expect(cubit.state.pending, isEmpty, reason: 'the add was sent');
    final ids = [
      first,
      for (var i = 0; i < 3; i++)
        (cubit.addEntry(parseEntry('Sache $i')) as Added).item.id,
    ];
    await tester.pump();
    ids.forEach(cubit.tick);
    await tester.pump();
  }

  testWidgets('an add sent after a short offline spell does not hold it '
      'back', (tester) async {
    await pumpTrigger(tester);
    await shopAfterOffline(tester, const Duration(seconds: 5));
    await idle(tester, ReviewPromptTrigger.offlineGrace);
    expect(review.requests, 1);
  });

  testWidgets('offline past the grace holds it back', (tester) async {
    await pumpTrigger(tester);
    await shopAfterOffline(tester, ReviewPromptTrigger.offlineGrace);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('offline in the background is no sync failure', (tester) async {
    await pumpTrigger(tester);
    repo.online = false;
    cubit.addEntry(parseEntry('Ding'));
    await tester.pump();
    void go(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);
    go([AppLifecycleState.inactive, AppLifecycleState.hidden]);
    await idle(tester, const Duration(seconds: 61));
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await idle(tester, const Duration(seconds: 5));
    repo.online = true;
    await tester.runAsync(cubit.resync);
    await idle(tester, const Duration(seconds: 1));
    await shop(tester, 3);
    cubit.state.items.keys.toList().forEach(cubit.tick);
    await idle(tester);
    expect(review.requests, 1);
  });

  testWidgets('offline with nothing to send is no sync failure', (
    tester,
  ) async {
    await pumpTrigger(tester);
    repo.online = false;
    await tester.runAsync(cubit.resync);
    await idle(tester, ReviewPromptTrigger.offlineGrace);
    expect(cubit.state.connection, ConnectionStatus.offline);
    repo.online = true;
    await tester.runAsync(cubit.resync);
    await idle(tester, const Duration(seconds: 1));
    await shop(tester, 3);
    await idle(tester);
    expect(review.requests, 1);
  });

  testWidgets('a queued write the server refused holds it back', (
    tester,
  ) async {
    await pumpTrigger(tester);
    repo.reject = true;
    cubit.addEntry(parseEntry('Ding'));
    await idle(tester, const Duration(seconds: 1));
    expect(cubit.state.items, isEmpty, reason: 'the refused add is gone');
    await shop(tester, 3);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('an order change refused offline up front is no sync failure', (
    tester,
  ) async {
    await pumpTrigger(tester);
    repo.online = false;
    await tester.runAsync(cubit.resync);
    await tester.runAsync(() => cubit.reorderStores(const []));
    repo.online = true;
    await tester.runAsync(cubit.resync);
    await idle(tester, const Duration(seconds: 1));
    await shop(tester, 3);
    await idle(tester);
    expect(review.requests, 1);
  });

  testWidgets('a server in trouble past the grace holds it back', (
    tester,
  ) async {
    await pumpTrigger(tester);
    repo.sendTrouble = true;
    final first = (cubit.addEntry(parseEntry('Ding')) as Added).item.id;
    await idle(tester, ReviewPromptTrigger.offlineGrace);
    expect(cubit.state.trouble, SyncTrouble.failing);
    repo.sendTrouble = false;
    await idle(tester, const Duration(seconds: 5));
    expect(cubit.state.pending, isEmpty);
    await shop(tester, 3);
    cubit.tick(first);
    await tester.pump();
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('a 503 that a later retry gets past does not', (tester) async {
    await pumpTrigger(tester);
    repo.sendTrouble = true;
    final first = (cubit.addEntry(parseEntry('Ding')) as Added).item.id;
    // Failing shows once the 3 s retry failed too (job 165).
    await idle(tester, const Duration(seconds: 4));
    expect(cubit.state.trouble, SyncTrouble.failing);
    repo.sendTrouble = false;
    await idle(tester, const Duration(seconds: 5));
    expect(cubit.state.pending, isEmpty);
    await shop(tester, 3);
    cubit.tick(first);
    await tester.pump();
    await idle(tester);
    expect(review.requests, 1);
  });

  testWidgets('a trip of two asks nothing', (tester) async {
    await pumpTrigger(tester);
    await shop(tester, 2);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('a tap within the 3 s cancels it, for good', (tester) async {
    await pumpTrigger(tester);
    await shop(tester, 3);
    await idle(tester, const Duration(seconds: 2));
    await tester.tapAt(const Offset(200, 300));
    await idle(tester, const Duration(seconds: 10));
    expect(review.requests, 0);
  });

  testWidgets('a key press within the 3 s cancels it', (tester) async {
    await pumpTrigger(tester);
    await shop(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('an open keyboard holds it back', (tester) async {
    await pumpTrigger(tester);
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await shop(tester, 3);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('an open dialog holds it back', (tester) async {
    await pumpTrigger(tester);
    await shop(tester, 3);
    final context = tester.element(find.byType(SizedBox).last);
    showDialog<void>(context: context, builder: (_) => const Text('Dialog'));
    await tester.pump();
    expect(popups.open, isTrue);
    await idle(tester);
    expect(review.requests, 0);
  });

  testWidgets('dictation listening holds it back', (tester) async {
    await pumpTrigger(tester, listening: true);
    await shop(tester, 3);
    await idle(tester);
    expect(review.requests, 0);
  });

  group('trip moments (job 326)', () {
    late FakeTripSignals trips;
    late DateTime now;

    Future<void> pumpTrips(WidgetTester tester, {bool v2 = true}) async {
      trips = FakeTripSignals();
      addTearDown(trips.close);
      now = DateTime(2026, 11, 20, 18);
      await pumpTrigger(tester, v2: v2, trips: trips, clock: () => now);
    }

    /// „Kaufst du gerade ein?“ comes up after the emptying tick, as the
    /// list's sheet on the root navigator.
    Future<void> question(WidgetTester tester) async {
      trips.asking = true;
      final context = tester.element(find.byType(SizedBox).last);
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        builder: (sheet) => TextButton(
          onPressed: () => Navigator.of(sheet).pop(),
          child: const Text('answer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(popups.open, isTrue);
    }

    /// The user taps an answer: the sheet closes and trip mode tells it.
    Future<void> answer(WidgetTester tester, {required bool declined}) async {
      await tester.tap(find.text('answer'));
      await tester.pumpAndSettle();
      trips
        ..asking = false
        ..tell(TripQuestionClosed(declined: declined));
      await tester.pump();
    }

    int completedTrips() => ReviewCounters.parse(store.json).completedTrips;

    testWidgets('the question after the emptying tick: „Nein“ asks 3 s '
        'later', (tester) async {
      await pumpTrips(tester);
      await shop(tester, 3);
      await question(tester);
      await idle(tester, const Duration(seconds: 5));
      expect(review.requests, 0, reason: 'not over the question');
      await answer(tester, declined: true);
      await idle(tester, const Duration(milliseconds: 2900));
      expect(review.requests, 0);
      await idle(tester, const Duration(milliseconds: 100));
      expect(review.requests, 1);
    });

    testWidgets('„Nein“ within the 3 s asks 3 s after it', (tester) async {
      await pumpTrips(tester);
      await shop(tester, 3);
      await question(tester);
      await idle(tester, const Duration(seconds: 1));
      await answer(tester, declined: true);
      await idle(tester);
      expect(review.requests, 1);
    });

    testWidgets('with the flag off the question loses the prompt, as '
        'before', (tester) async {
      await pumpTrips(tester, v2: false);
      await shop(tester, 3);
      await question(tester);
      await idle(tester, const Duration(seconds: 5));
      await answer(tester, declined: true);
      await idle(tester, const Duration(seconds: 10));
      expect(review.requests, 0);
    });

    testWidgets('„Ja“ asks nothing: the trip summary will', (tester) async {
      await pumpTrips(tester);
      await shop(tester, 3);
      await question(tester);
      await answer(tester, declined: false);
      trips.running = true;
      await idle(tester, const Duration(seconds: 10));
      expect(review.requests, 0);
    });

    testWidgets('„Zurücknehmen“ asks nothing, is no trip, and nothing asks '
        'until the next session', (tester) async {
      await pumpTrips(tester);
      final ids = await shop(tester, 3);
      expect(completedTrips(), 5);
      await question(tester);
      await tester.tap(find.text('answer'));
      await tester.pumpAndSettle();
      // TripCubit.takeBack: the tick's undo, then the answer.
      cubit.readd(ids.last);
      trips
        ..asking = false
        ..tell(const TripQuestionClosed(declined: false));
      await idle(tester, const Duration(seconds: 10));
      expect(review.requests, 0);
      expect(completedTrips(), 4);
      cubit.tick(ids.last);
      await tester.pump();

      Future<void> shopAgainAndDecline() async {
        now = now.add(const Duration(minutes: 11));
        await shop(tester, 3);
        await question(tester);
        await answer(tester, declined: true);
        await idle(tester);
      }

      await shopAgainAndDecline();
      expect(review.requests, 0, reason: 'the same session');
      unawaited(prompt.resumed());
      await tester.pump();
      await shopAgainAndDecline();
      expect(review.requests, 1);
    });

    testWidgets('a re-add right after the emptying tick holds it back', (
      tester,
    ) async {
      await pumpTrips(tester);
      final ids = await shop(tester, 3);
      cubit.readd(ids.first);
      await tester.pump();
      await idle(tester);
      expect(review.requests, 0);
    });

    testWidgets('a running trip: the list emptied asks nothing (SA1)', (
      tester,
    ) async {
      await pumpTrips(tester);
      trips.running = true;
      await shop(tester, 3);
      await idle(tester, const Duration(seconds: 10));
      expect(review.requests, 0);
    });

    testWidgets('with the flag off a running trip asks at the emptying, as '
        'before', (tester) async {
      await pumpTrips(tester, v2: false);
      trips.running = true;
      await shop(tester, 3);
      await idle(tester);
      expect(review.requests, 1);
    });

    group('a trip summary left (ST1)', () {
      Future<void> leave(
        WidgetTester tester, {
        int bought = 3,
        bool complete = true,
      }) async {
        trips.tell(TripSummaryLeft(bought: bought, complete: complete));
        await tester.pump();
      }

      testWidgets('complete with three bought asks 3 s later', (tester) async {
        await pumpTrips(tester);
        await leave(tester);
        await idle(tester, const Duration(milliseconds: 2900));
        expect(review.requests, 0);
        await idle(tester, const Duration(milliseconds: 100));
        expect(review.requests, 1);
      });

      testWidgets('not complete asks nothing', (tester) async {
        await pumpTrips(tester);
        await leave(tester, complete: false);
        await idle(tester, const Duration(seconds: 10));
        expect(review.requests, 0);
      });

      testWidgets('two bought asks nothing', (tester) async {
        await pumpTrips(tester);
        await leave(tester, bought: 2);
        await idle(tester, const Duration(seconds: 10));
        expect(review.requests, 0);
      });

      testWidgets('a tap within the 3 s cancels it', (tester) async {
        await pumpTrips(tester);
        await leave(tester);
        await idle(tester, const Duration(seconds: 2));
        await tester.tapAt(const Offset(200, 300));
        await idle(tester, const Duration(seconds: 10));
        expect(review.requests, 0);
      });

      testWidgets('with the flag off asks nothing', (tester) async {
        await pumpTrips(tester, v2: false);
        await leave(tester);
        await idle(tester, const Duration(seconds: 10));
        expect(review.requests, 0);
      });

      testWidgets('a failed trip save before holds it back (SA3)', (
        tester,
      ) async {
        await pumpTrips(tester);
        trips.tell(const TripSaveFailed());
        await tester.pump();
        await leave(tester);
        await idle(tester);
        expect(review.requests, 0);
      });
    });
  });
}
