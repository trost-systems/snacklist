import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/review_prompt_trigger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'fakes.dart';

void main() {
  late FakeStoreReview review;
  late ListCubit cubit;
  late FakeRepository repo;
  late Popups popups;

  /// A store build's install that is due: only the trip is missing.
  Future<void> pumpTrigger(
    WidgetTester tester, {
    bool listening = false,
  }) async {
    review = FakeStoreReview();
    final now = DateTime.now();
    final store = MemoryReviewStore()
      ..json = ReviewCounters(
        firstLaunch: now.subtract(const Duration(days: 30)),
        activeDays: 5,
        completedTrips: 4,
        itemsAdded: 60,
      ).toJson();
    final prompt = ReviewPrompt(
      store,
      review,
      channel: BuildChannel.store,
      version: Future.value('1.4.0'),
    );
    repo = FakeRepository();
    cubit = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    addTearDown(cubit.close);
    popups = Popups();
    addTearDown(popups.dispose);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prompt,
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

  /// Adds [count] items, then ticks them all off.
  Future<void> shop(WidgetTester tester, int count) async {
    final ids = [
      for (var i = 0; i < count; i++)
        (cubit.addEntry(parseEntry('Ding $i')) as Added).item.id,
    ];
    await tester.pump();
    ids.forEach(cubit.tick);
    await tester.pump();
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
    unawaited(
      showDialog<void>(context: context, builder: (_) => const Text('Dialog')),
    );
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
}
