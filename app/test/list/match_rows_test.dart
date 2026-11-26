import 'package:family_groceries/list/add_sheet/match_rows.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 324 (AM2): which items of the list are the same thing as a typed
/// name, and the rows the add sheet makes of them.
void main() {
  var minute = 0;
  Item item(
    String name, {
    String? quantity,
    String? brand,
    String? properties,
    ItemStatus status = ItemStatus.active,
    String? canonicalKey,
  }) {
    final at = DateTime.utc(2026, 11, 20, 8, minute++);
    return Item(
      id: 'i$minute',
      name: name,
      quantity: quantity,
      brand: brand,
      properties: properties,
      status: status,
      createdAt: at,
      updatedAt: at,
      boughtAt: status == ItemStatus.bought ? at : null,
      canonicalKey: canonicalKey,
    );
  }

  group('ItemMatcher, with the bundled catalog', () {
    final matcher = ItemMatcher(CatalogIndex.bundled);
    List<String> open(String typed, List<Item> items) => [
      for (final i in matcher.matches(typed, {
        for (final i in items) i.id: i,
      }).open)
        i.name,
    ];

    test('the same name', () {
      expect(open('Nudeln', [item('Nudeln'), item('Reis')]), ['Nudeln']);
    });

    test('a plural, in German and English', () {
      expect(open('Apfel', [item('Äpfel', quantity: '1 kg')]), ['Äpfel']);
      expect(open('Apple', [item('Apples')]), ['Apples']);
    });

    test('case and umlauts fold', () {
      expect(open('NUDELN', [item('nudeln')]), ['nudeln']);
      expect(open('apfel', [item('ÄPFEL')]), ['ÄPFEL']);
    });

    test('whatever the brand and details on the item', () {
      expect(
        open('Milch', [
          item('Milch', brand: 'Weihenstephan', properties: '1,5 %'),
        ]),
        ['Milch'],
      );
    });

    test('milk is not oat milk', () {
      expect(open('Milk', [item('Oat milk')]), isEmpty);
      expect(open('Milch', [item('Hafermilch')]), isEmpty);
      expect(open('Hafermilch', [item('Milch')]), isEmpty);
    });

    test('a synonym is the same thing', () {
      expect(open('Karotten', [item('Möhren')]), ['Möhren']);
    });

    test('a homograph is another thing: the typed spelling decides, as '
        'on the server (homograph_pick)', () {
      expect(open('Schäufele', [item('Schaufel')]), isEmpty);
      expect(open('Schaufel', [item('Schäufele')]), isEmpty);
      expect(open('Beeren', [item('beer')]), isEmpty);
      expect(open('beer', [item('Beeren')]), isEmpty);
      expect(open('sage', [item('Säge')]), isEmpty);
      expect(open('rolls', [item('Rolle')]), isEmpty);
    });

    test("a homograph's own spellings, plurals and synonyms still match", () {
      expect(open('Schäuferle', [item('Schäufele')]), ['Schäufele']);
      expect(open('Schaufeln', [item('Schaufel')]), ['Schaufel']);
      expect(open('Bier', [item('beer')]), ['beer']);
      expect(open('beers', [item('Bier')]), ['Bier']);
      expect(open('Saege', [item('Säge')]), ['Säge']);
      expect(open('Waldbeeren', [item('Waldbeere')]), ['Waldbeere']);
    });

    test('near-duplicates still match', () {
      expect(open('Tomaten', [item('Tomate')]), ['Tomate']);
      expect(open('Tomate', [item('Tomaten')]), ['Tomaten']);
    });

    test('nothing for a name without a key', () {
      expect(open('', [item('Nudeln')]), isEmpty);
    });

    test('open ones oldest first; ticked ones only when none is open', () {
      final older = item('Nudeln', quantity: '500 g');
      final bought = item(
        'Nudeln',
        status: ItemStatus.bought,
        canonicalKey: 'nudel',
      );
      final newer = item('Nudeln', brand: 'Barilla', canonicalKey: 'nudel');
      final both = matcher.matches('Nudeln', {
        for (final i in [newer, bought, older]) i.id: i,
      });
      expect(both.open, [older, newer]);
      expect(both.ticked, isEmpty, reason: 'recently used leaves it out');

      final eggs = item(
        'Eier',
        quantity: '10',
        status: ItemStatus.bought,
        canonicalKey: 'eier',
      );
      final ticked = matcher.matches('Eier', {eggs.id: eggs});
      expect(ticked.open, isEmpty);
      expect(ticked.ticked, [eggs]);
    });
  });

  group('matchRowsFor', () {
    test('the first open item merges and ticks off, then each further one '
        'merges, then the ticked ones; three at most', () {
      final a = item('Milch', quantity: '1');
      final b = item('Milch', brand: 'Weihenstephan');
      final c = item('Milch', status: ItemStatus.bought);
      expect(
        [
          for (final row in matchRowsFor([a, b], [c], null))
            (row.runtimeType, row.item),
        ],
        [(MergeRow, a), (TickRow, a), (MergeRow, b)],
      );
      expect(
        [
          for (final row in matchRowsFor([a], [c], null))
            (row.runtimeType, row.item),
        ],
        [(MergeRow, a), (TickRow, a), (ReaddRow, c)],
      );
    });

    test('a merge shows the merged Menge', () {
      final rows = matchRowsFor([item('Nudeln')], const [], null);
      expect((rows.first as MergeRow).quantity, '2');
      final kg = matchRowsFor(
        [item('Äpfel', quantity: '1 kg')],
        const [],
        null,
      );
      expect((kg.first as MergeRow).quantity, '1 kg');
      final sum = matchRowsFor(
        [item('Mehl', quantity: '500 g')],
        const [],
        '1 kg',
      );
      expect((sum.first as MergeRow).quantity, '1,5 kg');
    });

    test('no merge when the merged Menge would not fit; the tick stays', () {
      final long = item('Nudeln', quantity: '1 Packung + 2 Tüten + 3 Beutel');
      final rows = matchRowsFor([long], const [], '4 Schachteln groß');
      expect(rows.map((r) => r.runtimeType), [TickRow]);
    });

    test('only ticked ones: one row each', () {
      final c = item('Eier', status: ItemStatus.bought);
      expect(matchRowsFor(const [], [c], '6').single, isA<ReaddRow>());
    });
  });
}
