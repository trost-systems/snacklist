import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/match_rows.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

class _Tracked() implements Analytics {
  final events = <String>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The add sheet's state machine without its widgets: what is typed, the
/// rows that answer it, the match rows (flag `add-match-rows`) and the
/// details of the item just added (flag `add-feedback-list`).
void main() {
  late FakeRepository repo;
  late ListCubit list;
  late _Tracked tracked;

  Future<void> settle() => pumpEventQueue();

  setUp(() async {
    repo = FakeRepository();
    tracked = _Tracked();
    list = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      grace: Duration.zero,
      analytics: tracked,
    )..start();
    await settle();
  });

  tearDown(() => list.close());

  AddSheetCubit sheet({
    bool matchRows = false,
    bool feedback = false,
    bool stable = false,
  }) {
    final cubit = AddSheetCubit(
      list,
      debounce: Duration.zero,
      stableRows: () => stable,
      addFeedback: () => feedback || matchRows,
      compact: () => matchRows,
      matchRows: () => matchRows,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('a sheet just opened carries no rows and loads nothing', () {
    final cubit = sheet()..show();
    expect(cubit.state.open, isTrue);
    expect(cubit.state.carried, isFalse);
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.fresh, isFalse);
  });

  test(
    'rows load for what is typed, and older rows never answer newer text',
    () async {
      final cubit = sheet()..show();
      final answer = repo.suggestGate = Completer<void>();
      cubit.key('Milch');
      await settle();
      expect(cubit.state.loading, isTrue);
      expect(cubit.state.fetching, isTrue);
      answer.complete();
      repo.suggestGate = null;
      await settle();
      expect(cubit.state.fresh, isTrue);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.fetching, isFalse);

      repo.suggestGate = Completer<void>();
      cubit.key('Milchreis');
      expect(cubit.state.answered, 'Milch');
      expect(
        cubit.state.fresh,
        isFalse,
        reason: "Milch's rows wait for new ones",
      );
      expect(cubit.state.carried, isTrue);
      expect(cubit.state.loading, isTrue);
      repo.suggestGate!.complete();
      await settle();
      expect(cubit.state.fresh, isTrue);
      expect(cubit.state.carried, isFalse);

      cubit.key('');
      expect(cubit.state.loading, isFalse, reason: 'nothing typed');
    },
  );

  test('a close that settles after the sheet opened again leaves it open', () {
    final cubit = sheet()
      ..show()
      ..key('Milch')
      ..dismiss()
      ..show()
      ..key('Brot')
      ..settled();
    expect(cubit.state.open, isTrue);
    expect(cubit.state.text, 'Brot');

    cubit
      ..dismiss()
      ..settled();
    expect(cubit.state.open, isFalse);
    expect(cubit.state.text, isEmpty, reason: 'blank for the next opening');
  });

  test(
    'a text typed again shows its cached rows as its own, not carried',
    () async {
      final cubit = sheet()
        ..show()
        ..key('Milch');
      await settle();
      repo.suggestGate = Completer<void>();
      cubit.key('Milchreis');
      expect(cubit.state.carried, isTrue);
      cubit.key('Milch');
      expect(cubit.state.carried, isFalse);
      expect(cubit.state.fresh, isTrue);
      repo.suggestGate!.complete();
    },
  );

  test(
    'Enter while the rows load takes nothing once the text moved on',
    () async {
      final cubit = sheet()
        ..show()
        ..key('Milch');
      final answer = repo.suggestGate = Completer<void>();
      final enter = cubit.takeFirst();
      cubit.key('Milchreis');
      repo.suggestGate = null;
      answer.complete();
      expect(await enter, isNull);
      await settle();
      expect(repo.rows, isEmpty);
    },
  );

  test('offline rows name a usual the typed line already is once', () async {
    repo.usuals = [const Usual(name: 'Milch', due: false)];
    await list.resync();
    await settle();
    expect(list.state.usuals, isNotEmpty);
    repo.online = false;
    final cubit = sheet()
      ..show()
      ..key('Milch');
    await settle();
    expect([for (final s in cubit.state.suggestions) s.entry.name], ['Milch']);
  });

  test('with stable rows a late answer is cached for its own text, not over '
      'the one typed since', () async {
    final cubit = sheet(stable: true)..show();
    final answer = repo.suggestGate = Completer<void>();
    cubit.key('Milch');
    await settle();
    cubit.key('Milchreis');
    repo.suggestGate = null;
    answer.complete();
    await settle();
    cubit.key('Milch');
    expect([
      for (final s in cubit.state.suggestions) s.entry.name,
    ], isNot(contains('Milchreis')));
  });

  test('a rename in the details of the item just added is saved', () async {
    final cubit = sheet(feedback: true)
      ..show()
      ..key('Milch');
    final added = cubit.take(cubit.state.suggestions.first) as Added;
    await settle();
    cubit.editDetails(const ItemChanges(name: 'Vollmilch'), now: true);
    await settle();
    expect(repo.rows[added.item.id]!.name, 'Vollmilch');
  });

  test('picking a store or category keeps the rows carried, the request '
      'pending and the note on the match just taken', () async {
    final cubit = sheet()
      ..show()
      ..key('Milch');
    await settle();
    repo.suggestGate = Completer<void>();
    cubit.key('Milchreis');
    await settle();
    expect((cubit.state.carried, cubit.state.fetching), (true, true));
    cubit.pickStore('rewe');
    expect((cubit.state.carried, cubit.state.fetching), (true, true));
    repo.suggestGate!.complete();
    repo.suggestGate = null;
    await settle();

    final brot = (list.addEntry(parseEntry('Brot')) as Added).item;
    await settle();
    final matching = sheet(matchRows: true)
      ..show()
      ..key('Brot');
    expect(matching.takeMatch(TickRow(list.state.items[brot.id]!)), isTrue);
    matching.pickCategory('bakery');
    expect(matching.state.taken, isA<TickRow>());
    matching.key('E');
    expect(matching.state.taken, isNull);
  });

  test("the device's ranking counts what the list bought since the "
      "household's index was read, back a year", () async {
    final now = DateTime.now().toUtc();
    HistoryRow indexed(String name, int daysAgo) => (
      name: name,
      brand: null,
      properties: null,
      quantity: null,
      normalizedName: normalizeItemName(name),
      at: now.subtract(Duration(days: daysAgo)),
    );
    Item bought(String name, int daysAgo) {
      final at = now.subtract(Duration(days: daysAgo));
      return Item(
        id: 'bought-$name',
        name: name,
        status: ItemStatus.bought,
        createdAt: at,
        updatedAt: at,
        boughtAt: at,
      );
    }

    repo
      ..householdIndex = HouseholdIndex(
        history: [indexed('Haferdrink', 30), indexed('Hafermilch', 10)],
      )
      ..rows.addAll({
        for (final item in [bought('Haferdrink', 2), bought('Haferkekse', 400)])
          item.id: item,
      });
    final ranked = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      grace: Duration.zero,
      householdIndex: () => true,
    )..start();
    addTearDown(ranked.close);
    await settle();
    final cubit = AddSheetCubit(ranked, onDeviceCatalog: () => true)
      ..show()
      ..key('Hafer');
    addTearDown(cubit.close);
    expect(
      [
        for (final s in cubit.state.suggestions)
          if (s.source == SuggestionSource.history) s.entry.name,
      ],
      ['Haferdrink', 'Hafermilch'],
      reason:
          'bought 2 days ago on the list, not 30 as indexed; '
          'Haferkekse more than a year ago',
    );
  });

  test('a text whose rows failed to load asks the server again when typed '
      'again', () async {
    final cubit = sheet()..show();
    repo.online = false;
    cubit.key('Milch');
    await settle();
    repo.online = true;
    cubit
      ..key('Milchr')
      ..key('Milch');
    await settle();
    expect(repo.suggestCalls.where((t) => t == 'Milch'), hasLength(2));
  });

  group('the duplicate hint in the note', () {
    late AddSheetCubit cubit;
    late Item moehren;
    late Item karotten;

    setUp(() async {
      moehren = (list.addEntry(parseEntry('Möhren')) as Added).item;
      await settle();
      cubit = sheet()
        ..show()
        ..key('Karotten');
      karotten = (cubit.take(cubit.state.suggestions.first) as Added).item;
      await settle();
    });

    test('is taken only while the sheet is open', () {
      final hint = DedupeHint(karotten, moehren);
      cubit.dismiss();
      expect(cubit.offer(hint), isFalse);
      expect(cubit.state.hint, isNull);
    });

    test('goes only when that hint goes, and not once merged', () {
      final hint = DedupeHint(karotten, moehren);
      expect(cubit.offer(hint), isTrue);
      cubit.drop(DedupeHint(karotten, karotten));
      expect(cubit.state.hint, hint);
      cubit.drop(hint);
      expect(cubit.state.hint, isNull);
      expect(cubit.offer(hint), isTrue);
      cubit.mergeHint();
      expect(cubit.state.merge, isNotNull);
      expect(cubit.offer(hint), isFalse, reason: 'the note shows the merge');
      cubit.drop(hint);
      expect(cubit.state.merge, isNotNull);
    });

    test('handed over to the list is not ignored; a later one typed past '
        'is', () {
      expect(cubit.offer(DedupeHint(karotten, moehren)), isTrue);
      expect(cubit.handOver().$1, isNotNull);
      expect(tracked.events, isNot(contains('dedupe_hint_ignored')));

      expect(cubit.offer(DedupeHint(karotten, moehren)), isTrue);
      cubit.key('E');
      expect(
        tracked.events.where((e) => e == 'dedupe_hint_ignored'),
        hasLength(1),
      );
    });
  });

  group('the details of the item just added', () {
    test('show only with the flag and until the next letter', () async {
      for (final (feedback, name) in [(false, 'Butter'), (true, 'Käse')]) {
        final cubit = sheet(feedback: feedback)
          ..show()
          ..key(name);
        final added = cubit.take(cubit.state.suggestions.first);
        await settle();
        expect(added, isA<Added>());
        expect(
          cubit.detailsItem?.name,
          feedback ? name : isNull,
          reason: 'flag ${feedback ? 'on' : 'off'}',
        );
        cubit.key('K');
        expect(cubit.detailsItem, isNull);
        await cubit.close();
      }
    });
  });

  group('a match row', () {
    test("ticks the open item as the add sheet's tick, with no trip "
        'question over it', () async {
      final brot = (list.addEntry(parseEntry('Brot')) as Added).item;
      await settle();
      final ticks = <OwnItemTicked>[];
      final sub = list.activity.listen((a) {
        if (a is OwnItemTicked) {
          ticks.add(a);
        }
      });
      addTearDown(sub.cancel);
      final cubit = sheet(matchRows: true)
        ..show()
        ..key('Brot');
      expect(cubit.state.matches.whereType<TickRow>(), isNotEmpty);

      expect(cubit.takeMatch(TickRow(list.state.items[brot.id]!)), isTrue);
      await settle();
      expect(ticks.single.inAddSheet, isTrue);
      expect(list.state.items[brot.id]!.status, ItemStatus.bought);
      expect(cubit.state.text, isEmpty, reason: 'ready for the next item');
    });

    test('of an item ticked meanwhile is refused and the text stays', () async {
      final brot = (list.addEntry(parseEntry('Brot')) as Added).item;
      await settle();
      final cubit = sheet(matchRows: true)
        ..show()
        ..key('Brot');
      final row = TickRow(list.state.items[brot.id]!);
      list.tick(brot.id);
      await settle();
      expect(cubit.takeMatch(row), isFalse);
      expect(cubit.state.text, 'Brot');
    });

    test('follow the list while text is typed, not once the sheet is '
        'closing', () async {
      final cubit = sheet(matchRows: true)
        ..show()
        ..key('Brot');
      expect(cubit.state.matches, isEmpty);
      repo.remoteAdd('Brot');
      await list.resync();
      await settle();
      expect(cubit.state.matches.whereType<TickRow>(), hasLength(1));

      cubit.dismiss();
      final brot = repo.rows.values.single;
      repo.rows[brot.id] = brot.copyWith(status: ItemStatus.bought);
      await list.resync();
      await settle();
      expect(
        cubit.state.matches.whereType<TickRow>(),
        hasLength(1),
        reason: 'the content stays as it was while the sheet slides away',
      );
    });
  });
}
