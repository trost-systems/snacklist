import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/shell/app.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../feedback/fakes.dart';
import '../household/harness.dart'
    show FakeInvites, FakeOnboardingBackend, FakeSharer, MemoryPendingStore;
import '../more/more_harness.dart' show FakeSession, fakeSupabase;
import '../purchases/fakes.dart';
import '../report/fakes.dart';
import '../review/fakes.dart';
import '../session/fake_auth.dart';
import '../session/fake_your_name.dart';
import '../settings/fake_account.dart';

/// `App` holds the rating prompt back on a household switch and a sent bug
/// note (job 326, SA3): its own subscriptions call the prompt.
void main() {
  const home = Household(id: 'home', name: 'Zuhause', isDefault: true);
  const work = Household(id: 'work', name: 'Büro');
  const inHome = InHousehold('peter', home, [home, work]);
  const inWork = InHousehold('peter', work, [home, work]);
  final now = DateTime.utc(2026, 11, 20, 9);

  setUpAll(fakeSupabase);

  /// The real `App` in Zuhause; [sessions] are the states after it.
  Future<MemoryReviewStore> pumpApp(
    WidgetTester tester,
    StreamController<Session> sessions,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final cache = DeviceCache(SharedPreferencesAsync());
    final analytics = Analytics.off(cache);
    addTearDown(analytics.close);
    final session = FakeSession();
    whenListen(session, sessions.stream, initialState: inHome);
    when(session.refresh).thenAnswer((_) async {});
    when(() => session.lostHouseholds).thenAnswer((_) => const Stream.empty());
    when(() => session.joinDecisions).thenAnswer((_) => const Stream.empty());
    final purchases = TestPurchases(session: session);
    addTearDown(purchases.close);
    final yourName = idleYourName();
    addTearDown(yourName.close);
    final auth = FakeAuth();
    addTearDown(auth.close);
    final store = MemoryReviewStore();
    final prompt = ReviewPrompt(
      store,
      FakeStoreReview(),
      channel: BuildChannel.store,
      version: Future.value('1.2.3'),
      clock: () => now,
    );
    await tester.pumpWidget(
      App(
        session: session,
        social: SocialSignIn(auth, flows: const {}, native: FakeNativeSignIn()),
        cache: cache,
        account: FakeAccountRepository(),
        analytics: analytics,
        feedback: FakeFeedbackRepository(),
        reviewPrompt: prompt,
        storeReview: FakeStoreReview(),
        invites: FakeInvites(),
        entitlements: purchases.entitlements,
        purchases: purchases.purchases,
        premium: purchases.premium,
        storePrices: purchases.storePrices,
        pendingInvite: PendingInvite(MemoryPendingStore()),
        yourName: yourName,
        onboardingBackend: FakeOnboardingBackend(),
        sharer: FakeSharer(),
        feedbackDevice: FakeFeedbackDevice(),
        report: FakeReportRepository(),
      ),
    );
    await prompt.load();
    await tester.pump();
    return store;
  }

  /// Unmounts `App` and lets the list's realtime channel close: its
  /// disconnect waits 50 s.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  ReviewCounters counters(MemoryReviewStore store) =>
      ReviewCounters.parse(store.json);

  /// Sends a note of [category] through the cubit `App` provides.
  Future<void> sendNote(WidgetTester tester, FeedbackCategory category) async {
    final cubit = tester.element(find.byType(MaterialApp)).read<FeedbackCubit>()
      ..pick(category)
      ..edit('Die Liste lädt nicht');
    expect(await cubit.send(sampleContext), isTrue);
    await tester.pump();
  }

  testWidgets('a household switch holds the prompt back, a start does not', (
    tester,
  ) async {
    final sessions = StreamController<Session>();
    addTearDown(sessions.close);
    final store = await pumpApp(tester, sessions);
    expect(counters(store).lastSetbackAt, isNull);

    sessions.add(inWork);
    await tester.pump();

    expect(counters(store).lastSetbackAt, now);
    await unmount(tester);
  });

  testWidgets('a sent bug note holds the prompt back, an idea does not', (
    tester,
  ) async {
    final sessions = StreamController<Session>();
    addTearDown(sessions.close);
    final store = await pumpApp(tester, sessions);

    await sendNote(tester, FeedbackCategory.idea);
    expect(counters(store).lastBugNoteAt, isNull);

    tester
        .element(find.byType(MaterialApp))
        .read<FeedbackCubit>()
        .open(userId: 'peter');
    await sendNote(tester, FeedbackCategory.bug);
    expect(counters(store).lastBugNoteAt, now);
    await unmount(tester);
  });
}
