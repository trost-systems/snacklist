import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'fakes.dart';

/// The list's analytics: one event per user action (AC3, AC9), never one
/// for an op's retry, a realtime echo or an undo.
void main() {
  late FakeRepository repo;
  late NativePostHog sink;
  late Analytics analytics;
  late ListCubit cubit;
  var now = DateTime.utc(2026, 10, 30, 9);

  Future<void> settle() => pumpEventQueue();

  /// Events sent since the setup's first_open.
  Future<List<Map<String, Object?>>> sent() async {
    await analytics.flush();
    return [
      for (final e in sink.events)
        if (e['event'] != 'first_open') e,
    ];
  }

  /// Forgets what was sent so far, the setup's adds included.
  Future<void> reset() async {
    await analytics.flush();
    sink.calls.clear();
  }

  Future<List<String>> names() async => [
    for (final e in await sent()) e['event']! as String,
  ];

  Map<String, Object?> props(Map<String, Object?> event) =>
      event['properties']! as Map<String, Object?>;

  Future<String> addedId(String name) async {
    final result = cubit.addEntry(parseEntry(name));
    await settle();
    return (result as Added).item.id;
  }

  setUp(() async {
    now = DateTime.utc(2026, 10, 30, 9);
    repo = FakeRepository()
      ..members = const [
        Member(id: 'peter', displayName: 'Peter', role: 'owner'),
        Member(id: 'lea', displayName: 'Lea', role: 'member'),
      ];
    sink = NativePostHog()..install();
    analytics = await loadedAnalytics(MemoryAnalyticsStore())
      ..setUser(customer);
    await analytics.decide(granted: true);
    cubit = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      analytics: analytics,
      clock: () => now,
    )..start();
    await settle();
  });

  tearDown(() async {
    await cubit.close();
    await analytics.close();
  });

  group('ticks', () {
    test('one tick, one item_ticked with role and size, no name', () async {
      final id = await addedId('Hafermilch');
      await reset();
      cubit.tick(id);
      await settle();
      // The realtime echo of the server row.
      repo.emitItem!(repo.rows[id]!);
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), ['item_ticked']);
      expect(props(events.single)['actor_role'], 'owner');
      expect(props(events.single)['household_size'], 2);
      expect(props(events.single)['household_id'], householdA);
      expect(jsonEncode(events), isNot(contains('Hafermilch')));
    });

    test('before the members are known a tick still counts, without role '
        'or size', () async {
      await cubit.close();
      repo.members = const [];
      cubit = ListCubit(
        repo,
        MemoryListCache(),
        userId: 'peter',
        analytics: analytics,
        clock: () => now,
      )..start();
      await settle();
      final id = await addedId('Brot');
      await reset();
      cubit.tick(id);
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), ['item_ticked']);
      expect(props(events.single), isNot(contains('household_size')));
      expect(props(events.single), isNot(contains('actor_role')));
    });

    test('a tick made offline and sent on reconnect is one event', () async {
      final id = await addedId('Brot');
      await reset();
      repo.online = false;
      cubit.tick(id);
      await settle();
      expect(repo.sent.whereType<SetStatus>(), isEmpty);
      repo.online = true;
      await cubit.resync();
      await settle();
      await cubit.resync();
      await settle();
      expect(repo.sent.whereType<SetStatus>(), hasLength(1));
      expect(await names(), ['item_ticked']);
    });

    test('undo sends nothing; ticking again is a new action', () async {
      final id = await addedId('Butter');
      await reset();
      cubit
        ..tick(id)
        ..untick(id);
      await settle();
      expect(await names(), ['item_ticked']);
      cubit.tick(id);
      await settle();
      expect(await names(), ['item_ticked', 'item_ticked']);
    });

    test('ticking an item that is not on the list sends nothing', () async {
      final id = await addedId('Käse');
      cubit.tick(id);
      await settle();
      await reset();
      cubit
        ..tick(id)
        ..tick('nope');
      await settle();
      expect(await names(), isEmpty);
    });
  });

  group('adds', () {
    test('each add says where it came from', () async {
      cubit.addEntry(parseEntry('Milch'));
      await cubit.addSpoken('Gurken und Tomaten', SpokenLanguage.de);
      cubit.addUsual(const Usual(name: 'Eier', due: true));
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), everyElement('item_added'));
      expect(events.map((e) => props(e)['source']), [
        'typed',
        'spoken',
        'spoken',
        'suggestion',
      ]);
      expect(jsonEncode(events), isNot(contains('Gurken')));
    });

    test(
      "the add sheet's typed row is typed, any other row a suggestion",
      () async {
        final sheet = AddSheetCubit(cubit);
        addTearDown(sheet.close);
        sheet
          ..take(
            const Suggestion(
              SuggestionSource.typed,
              ParsedEntry(name: 'Milch'),
            ),
          )
          ..take(
            const Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Hafermilch', brand: 'Oatly'),
            ),
          )
          ..take(
            const Suggestion(SuggestionSource.due, ParsedEntry(name: 'Eier')),
          );
        await settle();
        final events = await sent();
        expect(events.map((e) => props(e)['source']), [
          'typed',
          'suggestion',
          'suggestion',
        ]);
        expect(jsonEncode(events), isNot(contains('Oatly')));
      },
    );

    test('an item already on the list is no add', () async {
      await addedId('Milch');
      await reset();
      cubit.addEntry(parseEntry('milch'));
      await settle();
      expect(await names(), isEmpty);
    });

    test('a re-add from recently used is an add, a restore is not', () async {
      final bought = await addedId('Mehl');
      final deleted = await addedId('Zucker');
      cubit.tick(bought);
      await settle();
      now = now.add(ListCubit.undoWindow + const Duration(seconds: 1));
      final item = cubit.state.items[deleted]!;
      cubit.delete(deleted);
      await settle();
      await reset();
      cubit
        ..readd(bought)
        ..restore(item);
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), ['item_added']);
      expect(props(events.single)['source'], 'suggestion');
    });
  });

  group('duplicate hint (job 32b)', () {
    test('shown, merged and ignored carry only role and household size; an '
        'undo sends nothing', () async {
      repo.canonical.addAll({'Möhren': 'mohr', 'Karotten': 'mohr'});
      final hints = <DedupeHint>[];
      final sub = cubit.hints.listen(hints.add);
      addTearDown(sub.cancel);
      await addedId('500 g Möhren');
      await addedId('1 kg Karotten');
      await reset();
      cubit
        ..hintShown()
        ..hintIgnored()
        ..hintShown();
      final merge = cubit.merge(hints.single)!;
      await settle();
      cubit.unmerge(merge);
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), [
        'dedupe_hint_shown',
        'dedupe_hint_ignored',
        'dedupe_hint_shown',
        'dedupe_hint_merged',
      ]);
      for (final event in events) {
        expect(props(event)['actor_role'], 'owner');
        expect(props(event)['household_size'], 2);
      }
      expect(jsonEncode(events), isNot(contains('hren')));
      expect(jsonEncode(events), isNot(contains('Karotten')));
    });
  });

  group('categorized via (job 32a)', () {
    test('a confirmed add says how the server categorized it', () async {
      repo.categorizedVia = 'synonym';
      await reset();
      cubit.addEntry(parseEntry('Paradeiser'));
      await settle();
      final events = await sent();
      expect(events.map((e) => e['event']), ['item_added', 'item_categorized']);
      expect(props(events.last)['via'], 'synonym');
      expect(jsonEncode(events), isNot(contains('Paradeiser')));
    });

    test('an add whose answer was lost is categorized once', () async {
      repo
        ..categorizedVia = 'fuzzy'
        ..loseNextAnswer = true;
      await reset();
      cubit.addEntry(parseEntry('Kartofeln'));
      await settle();
      expect(await names(), ['item_added']);
      await cubit.resync();
      await settle();
      await cubit.resync();
      await settle();
      expect(repo.sent.whereType<AddItem>(), hasLength(2));
      expect(await names(), ['item_added', 'item_categorized']);
    });

    test('a restore, a realtime echo or an unknown via sends none', () async {
      repo.categorizedVia = 'exact';
      final id = await addedId('Zucker');
      final item = cubit.state.items[id]!;
      cubit.delete(id);
      await settle();
      await reset();
      cubit.restore(item);
      await settle();
      repo.emitItem!(repo.rows[id]!);
      await settle();
      repo.categorizedVia = 'Karotten';
      cubit.addEntry(parseEntry('Karotten'));
      await settle();
      expect(await names(), ['item_added']);
    });
  });

  group('the tick undone from recently used', () {
    test('a re-add within ten minutes of the tick sends nothing', () async {
      final id = await addedId('Butter');
      cubit.tick(id);
      await settle();
      await reset();
      now = now.add(ListCubit.undoWindow);
      cubit.readd(id);
      await settle();
      expect(cubit.state.items[id]!.status, ItemStatus.active);
      expect(await names(), isEmpty);
      cubit.tick(id);
      await settle();
      expect(await names(), ['item_ticked'], reason: 'a new action');
    });

    test('a tick of the partner is undone the same way', () async {
      final id = await addedId('Quark');
      final ticked = repo.rows[id] = repo.rows[id]!.copyWith(
        status: ItemStatus.bought,
        boughtAt: () => now.subtract(const Duration(minutes: 2)),
      );
      repo.emitItem!(ticked);
      await settle();
      await reset();
      cubit.readd(id);
      await settle();
      expect(cubit.state.items[id]!.status, ItemStatus.active);
      expect(await names(), isEmpty);
    });
  });

  group('reorders', () {
    test('a new route order is category_reordered, scope default', () async {
      await cubit.reorderCategories(['chilled', 'produce', 'other']);
      final events = await sent();
      expect(events.map((e) => e['event']), ['category_reordered']);
      expect(props(events.single)['scope'], 'default');
    });

    test("a store's new layout is category_reordered, scope store", () async {
      await cubit.setStoreLayout('lidl', ['chilled', 'other', 'produce'], {});
      final events = await sent();
      expect(events.map((e) => e['event']), ['category_reordered']);
      expect(props(events.single)['scope'], 'store');
    });

    test('hiding a category in a store is no reorder', () async {
      await cubit.setStoreLayout(
        'lidl',
        ['other', 'chilled', 'produce'],
        {'produce'},
      );
      expect(await names(), isEmpty);
    });

    test('a new store order is store_reordered', () async {
      await cubit.reorderStores(['lidl', 'dm']);
      expect(await names(), ['store_reordered']);
    });

    test(
      'the same order, an offline or a refused change send nothing',
      () async {
        await cubit.reorderCategories(['produce', 'chilled', 'other']);
        repo.reject = true;
        await cubit.reorderStores(['lidl', 'dm']);
        repo.online = false;
        await cubit.resync();
        await cubit.reorderCategories(['chilled', 'produce', 'other']);
        expect(await names(), isEmpty);
      },
    );
  });
}
