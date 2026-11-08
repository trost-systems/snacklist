import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/hints_cubit.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../analytics/fakes.dart';
import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

class MemoryHintStore() implements HintStore {
  final logs = <String, String>{};

  @override
  Future<String?> hintLog(String userId) async => logs[userId];

  @override
  Future<void> saveHintLog(String userId, String json) async =>
      logs[userId] = json;

  UsageLog of(String userId) =>
      UsageLog.parse(logs[userId], now: DateTime(2000));
}

/// The properties the hint and checklist events carry.
const _keys = ['hint_id', 'step', 'open_steps'];

void main() {
  late FakeRepository repo;
  late MemoryListCache cache;
  late MemoryHintStore store;
  late DateTime now;
  final cubits = <Object>[];

  setUp(() {
    repo = FakeRepository()
      ..members = const [
        Member(id: 'peter', displayName: 'Peter', role: 'owner'),
      ];
    cache = MemoryListCache()..prefs = const ListPrefs(hintDismissed: true);
    store = MemoryHintStore();
    now = DateTime(2026, 11, 8, 9);
  });

  tearDown(() async {
    for (final cubit in cubits.reversed) {
      if (cubit is HintsCubit) {
        await cubit.close();
      } else if (cubit is ListCubit) {
        await cubit.close();
      }
    }
    cubits.clear();
  });

  /// A list and its hints as a session starting at [now]; [after] moves the
  /// clock past the quiet start before the log is read.
  Future<(ListCubit, HintsCubit)> session({
    Duration after = const Duration(seconds: 11),
    HintPlatform platform = HintPlatform.android,
    HouseholdKind? kind,
    HintHost host = const HintHost(),
    Analytics? analytics,
  }) async {
    final list = ListCubit(repo, cache, userId: 'peter', clock: () => now)
      ..start();
    await pumpEventQueue();
    final hints = HintsCubit(
      store,
      list,
      platform: platform,
      kind: kind,
      host: host,
      analytics: analytics,
      clock: () => now,
    );
    cubits.addAll([list, hints]);
    now = now.add(after);
    await hints.load();
    await pumpEventQueue();
    return (list, hints);
  }

  void seed(int items) {
    for (var i = 0; i < items; i++) {
      repo.remoteAdd('Artikel $i');
    }
  }

  test('the first session on an empty list shows the checklist only', () async {
    cache.prefs = const ListPrefs();
    final (_, hints) = await session();
    expect(hints.state.checklist?.entries.map((e) => e.step), [
      ChecklistStep.started,
      ChecklistStep.invite,
      ChecklistStep.firstShop,
    ]);
    expect(hints.state.hint, isNull);
  });

  test('the open checklist holds every hint back', () async {
    cache.prefs = const ListPrefs();
    seed(6);
    store.logs['peter'] = UsageLog(since: now).toJson();
    final (list, hints) = await session();
    expect(hints.state.checklist, isNotNull);
    expect(hints.state.hint, isNull);
    hints.dismissChecklist();
    await pumpEventQueue();
    expect(list.state.prefs.hintDismissed, isTrue);
    expect(hints.state.checklist, isNull);
    expect(
      hints.state.hint,
      isNull,
      reason: 'one pick per session, and it was blocked',
    );
  });

  test('a hint shows after 10 s and is kept as shown', () async {
    seed(6);
    store.logs['peter'] = UsageLog(since: now).toJson();
    final (_, early) = await session(after: const Duration(seconds: 3));
    expect(early.state.hint, isNull, reason: 'the quiet start');
    await early.close();

    final (_, hints) = await session();
    expect(hints.state.hint?.id, HintId.editLongPress);
    expect(store.of('peter').of(HintId.editLongPress).shown, 1);
  });

  test('X hides the hint for good and no other comes this session', () async {
    repo.members = const [
      Member(id: 'peter', displayName: 'Peter', role: 'owner'),
      Member(id: 'lea', displayName: 'Lea', role: 'member'),
    ];
    seed(6);
    for (var i = 0; i < 5; i++) {
      repo.remoteAdd('mehr $i');
    }
    store.logs['peter'] = UsageLog(since: now).toJson();
    final (list, hints) = await session();
    expect(hints.state.hint?.id, HintId.editLongPress);
    hints.dismiss();
    await pumpEventQueue();
    expect(hints.state.hint, isNull);
    for (var i = 0; i < 5; i++) {
      list.addEntry(parseEntry('Neu $i'));
    }
    await pumpEventQueue();
    expect(hints.state.hint, isNull, reason: 'quick-add-amounts waits');
    expect(store.of('peter').of(HintId.editLongPress).dismissed, isTrue);

    await hints.close();
    now = now.add(const Duration(days: 2));
    final (_, next) = await session();
    expect(next.state.hint?.id, HintId.quickAddAmounts);
  });

  test('the list tells the log what the user did', () async {
    store.logs['peter'] = UsageLog(since: now).toJson();
    final (list, hints) = await session();
    list
      ..addEntry(parseEntry('Brot'))
      ..addEntry(parseEntry('2 Gurken'));
    await pumpEventQueue();
    final id = list.state.items.values.firstWhere((i) => i.name == 'Brot').id;
    list.edit(id, const ItemChanges(quantity: SetTo('1')));
    for (final item in [...list.state.items.values]) {
      list.tick(item.id);
    }
    await pumpEventQueue();
    final log = store.of('peter');
    expect(log.count(Signal.typedAdd), 2);
    expect(log.count(Signal.plainTypedAdd), 1);
    expect(log.count(Signal.amountAdd), 1);
    expect(log.saw(Signal.itemEdited), isTrue);
    expect(log.saw(Signal.shopDone), isTrue);
    expect(
      log.saw(Signal.storeAdded),
      isTrue,
      reason: 'the household has stores',
    );
    expect(log.saw(Signal.householdOwned), isTrue);
    expect(log.saw(Signal.memberJoined), isFalse);
    expect(log.activeDays, 1);
    expect(hints.isClosed, isFalse);
  });

  test('using the feature takes its hint away at once', () async {
    seed(6);
    store.logs['peter'] = UsageLog(since: now).toJson();
    final (list, hints) = await session();
    expect(hints.state.hint?.id, HintId.editLongPress);
    list.edit(
      list.state.items.keys.first,
      const ItemChanges(quantity: SetTo('3')),
    );
    await pumpEventQueue();
    expect(hints.state.hint, isNull);
    expect(store.of('peter').of(HintId.editLongPress).dismissed, isFalse);
  });

  test('nothing is picked while something covers the list', () async {
    seed(6);
    store.logs['peter'] = UsageLog(since: now).toJson();
    final list = ListCubit(repo, cache, userId: 'peter', clock: () => now)
      ..start();
    await pumpEventQueue();
    final hints = HintsCubit(
      store,
      list,
      platform: HintPlatform.android,
      clock: () => now,
    )..screen(covered: true, listHidden: false, kind: null);
    cubits.addAll([list, hints]);
    now = now.add(const Duration(seconds: 11));
    await hints.load();
    expect(hints.state.hint, isNull);
    hints.screen(covered: false, listHidden: false, kind: null);
    expect(hints.state.hint?.id, HintId.editLongPress);
  });

  test(
    "a club's checklist asks the host whether an assistant is connected",
    () async {
      cache.prefs = const ListPrefs();
      var asked = 0;
      final (_, hints) = await session(
        kind: HouseholdKind.club,
        host: HintHost(
          assistantConnected: () async {
            asked++;
            return true;
          },
        ),
      );
      expect(asked, 1);
      final assistant = hints.state.checklist?.entries.firstWhere(
        (e) => e.step == ChecklistStep.assistant,
      );
      expect(assistant?.done, isTrue);
    },
  );

  test('the host is not asked for what no hint waits for', () async {
    var asked = 0;
    await session(
      platform: HintPlatform.web,
      host: HintHost(
        widgetPlaced: () async {
          asked++;
          return true;
        },
      ),
    );
    expect(asked, 0, reason: 'no widget hint on the web');
  });

  test("job 80's dismissed tip stays hidden", () async {
    seed(6);
    store.logs['peter'] = '{"dismissed": ["edit-long-press"]}';
    final (_, hints) = await session();
    expect(hints.state.hint?.id, isNot(HintId.editLongPress));
  });

  group('analytics', () {
    late NativePostHog sink;
    late Analytics analytics;

    setUp(() async {
      sink = NativePostHog()..install();
      analytics = await loadedAnalytics(MemoryAnalyticsStore())
        ..setUser(customer);
      await analytics.decide(granted: true);
    });

    tearDown(() => analytics.close());

    /// The hint and checklist events as `name {properties}`, without the
    /// context every event carries.
    Future<List<String>> sent() async {
      await analytics.flush();
      return [
        for (final event in sink.events)
          if (event['event'] case final String name
              when name.startsWith('hint_') || name.startsWith('checklist_'))
            '$name ${{for (final key in _keys) key: ?propsOf(event)[key]}}',
      ];
    }

    test(
      'hint_shown, hint_acted and hint_dismissed carry the id only',
      () async {
        seed(3);
        repo.members = const [
          Member(id: 'peter', displayName: 'Peter', role: 'owner'),
        ];
        store.logs['peter'] = UsageLog(
          since: now.subtract(const Duration(days: 2)),
        ).toJson();
        final (_, hints) = await session(analytics: analytics);
        expect(hints.state.hint?.id, HintId.invitePartner);
        hints.act();
        await hints.close();
        now = now.add(const Duration(days: 2));
        seed(3);
        final (_, next) = await session(analytics: analytics);
        expect(next.state.hint?.id, HintId.editLongPress);
        next.dismiss();
        expect(await sent(), [
          'hint_shown {hint_id: invite-partner}',
          'hint_acted {hint_id: invite-partner}',
          'hint_shown {hint_id: edit-long-press}',
          'hint_dismissed {hint_id: edit-long-press}',
        ]);
      },
    );

    test('checklist steps are sent once, the X with the open count', () async {
      cache.prefs = const ListPrefs();
      final (list, hints) = await session(analytics: analytics);
      list.addEntry(parseEntry('Brot'));
      await pumpEventQueue();
      list.tick(list.state.items.keys.first);
      await pumpEventQueue();
      list.addEntry(parseEntry('Milch'));
      await pumpEventQueue();
      list.tick(
        list.state.items.values.firstWhere((i) => i.name == 'Milch').id,
      );
      await pumpEventQueue();
      hints.dismissChecklist();
      await pumpEventQueue();
      expect(await sent(), [
        'checklist_step_done {step: first_shop}',
        'checklist_dismissed {open_steps: 1}',
      ]);
    });
  });
}
