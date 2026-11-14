import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/log/trip_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/model_test.dart' show item;

const catalog = Catalog(
  stores: [
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
    Store(id: 'rewe', name: 'Rewe', sortOrder: 10),
    Store(id: 'apo', name: 'APOTHEKE am Markt', sortOrder: 30),
  ],
  lists: [
    HouseholdList(id: 'home', name: 'Zuhause', position: 0),
    HouseholdList(id: 'office', name: 'Büro', position: 1),
  ],
);

/// A list showing [items] (by id); [shown] picks the list.
ListState listOf(List<Item> items, {String shown = 'home'}) => ListState(
  catalog: catalog,
  server: {for (final i in items) i.id: i},
  prefs: ListPrefs(shownList: shown),
);

Item bought(Item i) => i.copyWith(status: ItemStatus.bought);

void main() {
  final milk = item('milk', store: 'rewe');
  final bread = item('bread', store: 'rewe');
  final soap = item('soap', store: 'lidl');
  final tea = item('tea');

  /// Ticks [ticked] off one by one on a list of [items], the way the list
  /// screen's cubit hears them: the list changes, then the tick is told.
  TripTicks tickAll(List<Item> items, List<Item> ticked) {
    var list = listOf(items);
    var ticks = TripTicks(listId: list.shownList?.id);
    for (final t in ticked) {
      list = listOf([
        for (final i in list.server.values)
          if (i.id == t.id) bought(i) else i,
      ]);
      ticks = ticks.settle(list).tick(t, catalog).settle(list);
    }
    return ticks;
  }

  /// The prompts as `store: item, item`.
  List<String> shown(TripTicks ticks) => [
    for (final p in ticks.prompts(catalog))
      '${p.storeId}: ${p.items.map((i) => i.id).join(', ')}',
  ];

  test('no prompt on the first tick while the store has open items', () {
    expect(shown(tickAll([milk, bread, tea], [milk])), isEmpty);
  });

  test('the store whose section is ticked off offers its prompt', () {
    expect(shown(tickAll([milk, bread, tea], [milk, bread])), [
      'rewe: milk, bread',
    ]);
  });

  test('one prompt per store, in store order, no store last', () {
    expect(shown(tickAll([soap, tea, milk], [soap, tea, milk])), [
      'rewe: milk',
      'lidl: soap',
      'null: tea',
    ]);
  });

  test('an item put back leaves; a store left with nothing offers none', () {
    var ticks = tickAll([milk, bread], [milk]);
    ticks = ticks.settle(listOf([milk, bread]));
    expect(ticks.ticked, isEmpty);
    // Bread is ticked off; milk, put back, is open again.
    ticks = ticks
        .settle(listOf([milk, bought(bread)]))
        .tick(bread, catalog)
        .settle(listOf([milk, bought(bread)]));
    expect(shown(ticks), isEmpty);
  });

  test('an item put back after the prompt leaves it; the last one ends it', () {
    var ticks = tickAll([milk, bread], [milk, bread]);
    ticks = ticks.settle(listOf([milk, bought(bread)]));
    expect(shown(ticks), ['rewe: bread']);
    ticks = ticks.settle(listOf([milk, bread]));
    expect(shown(ticks), isEmpty);
  });

  test('a later tick at the store joins its prompt, which stays when '
      'something new goes on the list there', () {
    final eggs = item('eggs', store: 'rewe');
    var ticks = tickAll([milk], [milk]);
    var list = listOf([bought(milk), eggs]);
    ticks = ticks.settle(list);
    expect(shown(ticks), ['rewe: milk']);
    list = listOf([bought(milk), bought(eggs)]);
    ticks = ticks.settle(list).tick(eggs, catalog).settle(list);
    expect(shown(ticks), ['rewe: milk, eggs']);
  });

  test('a partner ticking a store off offers nothing without my ticks', () {
    final ticks = const TripTicks(listId: 'home')
        .settle(listOf([bought(milk), bought(bread)]));
    expect(shown(ticks), isEmpty);
  });

  test('logged or put off, the prompt goes with its ticks', () {
    final ticks = tickAll([milk, soap], [milk, soap]).without('rewe');
    expect(shown(ticks), ['lidl: soap']);
    expect(ticks.ticked.keys, ['lidl']);
  });

  test('another list starts over', () {
    final ticks = tickAll([milk], [milk]);
    expect(
      ticks.settle(listOf([bought(milk)], shown: 'office')).ticked,
      isEmpty,
    );
  });

  test('an item of a deleted store counts as no store', () {
    final gone = item('gone', store: 'edeka');
    expect(shown(tickAll([gone], [gone])), ['null: gone']);
  });

  test('Legal GL-2: a pharmacy ticked off offers no card', () {
    final aspirin = item('aspirin', store: 'apo');
    expect(shown(tickAll([aspirin, soap], [aspirin, soap])), ['lidl: soap']);
  });

  test("a trip's end forgets what it logged; earlier ticks stay", () {
    final ticks = tickAll(
      [milk, bread, soap],
      [milk, soap],
    ).forgetting({'soap'});
    expect(ticks.ticked.keys, ['rewe']);
    expect(shown(ticks), isEmpty, reason: 'bread is still open at rewe');
    expect(
      shown(
        ticks
            .settle(listOf([bought(milk), bought(bread), bought(soap)]))
            .tick(bread, catalog)
            .settle(listOf([bought(milk), bought(bread), bought(soap)])),
      ),
      ['rewe: milk, bread'],
    );
  });

  test('nothing changed: the same value', () {
    final ticks = tickAll([milk, bread], [milk]);
    final list = listOf([bought(milk), bread]);
    expect(identical(ticks.settle(list), ticks), isTrue);
  });
}
