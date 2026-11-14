import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/list/subtotals.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 14, 10);
const _lidl = Store(id: 'lidl', name: 'Lidl', sortOrder: 0);
const _dm = Store(id: 'dm', name: 'dm', sortOrder: 1);
const _catalog = Catalog(stores: [_dm, _lidl]);

var _ids = 0;

Item _item(
  String name, {
  String? store,
  int? cents,
  PricePer per = PricePer.piece,
  PriceBasis basis = PriceBasis.unit,
  String? quantity,
  DateTime? boughtAt,
  DateTime? pricedAt,
}) => Item(
  id: '${name.toLowerCase()}-${_ids++}',
  name: name,
  quantity: quantity,
  status: boughtAt == null ? ItemStatus.active : ItemStatus.bought,
  boughtAt: boughtAt,
  storeId: store,
  createdAt: _now.subtract(const Duration(days: 1)),
  updatedAt: _now,
  price: cents == null
      ? null
      : Price(
          unitMicros: cents * microsPerCent,
          basis: basis,
          per: per,
          currency: 'EUR',
          pricedAt: pricedAt ?? _now,
        ),
);

RunningTrip _trip(DateTime startedAt) => RunningTrip(
  id: 'trip',
  householdId: 'home',
  listId: null,
  startedAt: startedAt,
  source: TripSource.manual,
  snapshot: const {},
);

/// Job 237: what the summary block above „Zuletzt verwendet“ adds up.
void main() {
  Summary summary(Iterable<Item> items, {RunningTrip? trip}) =>
      summaryOf(items, _catalog, now: _now, trip: trip);

  test('without a trip only open items count: a ticked one drops out', () {
    final s = summary([
      _item('Milch', store: 'lidl', cents: 119),
      _item(
        'Brot',
        store: 'lidl',
        cents: 249,
        boughtAt: _now.subtract(const Duration(minutes: 5)),
      ),
    ]);
    expect(s.split, isFalse);
    expect(s.total, const Sum(cents: 119, priced: 1));
    expect(s.stores.single.bought, isNull);
  });

  test('a trip splits bought on it from open; a tick before it counts '
      'nowhere', () {
    final start = _now.subtract(const Duration(minutes: 30));
    final s = summary([
      _item('Milch', store: 'lidl', cents: 119),
      _item(
        'Brot',
        store: 'lidl',
        cents: 249,
        boughtAt: _now.subtract(const Duration(minutes: 5)),
      ),
      _item(
        'Seife',
        store: 'dm',
        cents: 95,
        boughtAt: start.subtract(const Duration(hours: 2)),
      ),
    ], trip: _trip(start));
    expect(s.split, isTrue);
    expect(s.bought, const Sum(cents: 249, priced: 1));
    expect(s.open, const Sum(cents: 119, priced: 1));
    expect(s.total.cents, 368);
    expect(s.stores.map((t) => t.store?.name), ['Lidl'], reason: 'dm: none');
  });

  test('a store bought in full on the trip stays, marked', () {
    final start = _now.subtract(const Duration(minutes: 30));
    final s = summary([
      _item('Milch', store: 'lidl', cents: 119),
      _item(
        'Seife',
        store: 'dm',
        cents: 95,
        boughtAt: _now.subtract(const Duration(minutes: 1)),
      ),
    ], trip: _trip(start));
    final dm = s.stores.firstWhere((t) => t.store == _dm);
    expect(dm.allBought, isTrue);
    expect(dm.sum.cents, 95);
    expect(s.stores.firstWhere((t) => t.store == _lidl).allBought, isFalse);
  });

  test("an item without today's price makes its sums a floor", () {
    final s = summary([
      _item('Milch', store: 'lidl', cents: 119),
      _item('Käse', store: 'lidl'),
      _item(
        'Butter',
        store: 'dm',
        cents: 229,
        pricedAt: _now.subtract(const Duration(days: 2)),
      ),
      _item('Seife', store: 'dm', cents: 95),
    ]);
    expect(s.total, const Sum(cents: 214, priced: 2, unpriced: 2));
    expect(s.total.floor, isTrue);
    final lidl = s.stores.firstWhere((t) => t.store == _lidl);
    expect(lidl.sum.floor, isTrue);
    expect(lidl.sum.unpriced, 1);
  });

  test('a price typed today in an earlier currency is left out: a floor, '
      'but not „ohne Preis“', () {
    final chf = _item('Milch', store: 'lidl', cents: 119);
    final s = summaryOf(
      [chf, _item('Brot', store: 'lidl')],
      const Catalog(stores: [_lidl], currency: 'CHF'),
      now: _now,
    );
    expect(s.total, const Sum(unpriced: 1, foreign: 1));
    expect(s.total.floor, isTrue);
  });

  test('a price per kg typed per kg on an open item is an estimate, and so '
      'is every sum holding it', () {
    final bananas = _item(
      'Bananen',
      store: 'lidl',
      cents: 179,
      per: PricePer.kg,
      quantity: '846 g',
    );
    expect(bananas.lineCentsNow, 151);
    expect(plannedWeight(bananas), isTrue);
    final s = summary([bananas, _item('Seife', store: 'dm', cents: 95)]);
    expect(s.stores.firstWhere((t) => t.store == _lidl).sum.estimate, isTrue);
    expect(s.stores.firstWhere((t) => t.store == _dm).sum.estimate, isFalse);
    expect(s.total.estimate, isTrue);
  });

  test("the label's total, a price per piece or a ticked item is no "
      'estimate', () {
    final label = _item(
      'Kartoffeln',
      cents: 180,
      per: PricePer.kg,
      basis: PriceBasis.line,
      quantity: '2 kg',
    );
    final weighed = _item(
      'Bananen',
      cents: 179,
      per: PricePer.kg,
      quantity: '846 g',
      boughtAt: _now,
    );
    final piece = _item('Milch', cents: 119, quantity: '2');
    expect([label, weighed, piece].map(plannedWeight), [false, false, false]);
  });

  test('„Ohne Laden“ is a line of its own, after the stores in their '
      'order; an item of a gone store counts there', () {
    final s = summary([
      _item('Pinsel', cents: 300),
      _item('Schrauben', store: 'baumarkt', cents: 450),
      _item('Milch', store: 'lidl', cents: 119),
      _item('Seife', store: 'dm', cents: 95),
    ]);
    expect(s.stores.map((t) => t.store?.name), ['Lidl', 'dm', null]);
    expect(s.stores.last.sum.cents, 750);
    expect(s.stores.last.key, 'none');
    expect(s.perStore, isTrue);
  });

  test('one store, or only „Ohne Laden“: no line per store', () {
    expect(
      summary([_item('Milch', store: 'lidl', cents: 119)]).perStore,
      isFalse,
    );
    expect(summary([_item('Pinsel', cents: 300)]).perStore, isFalse);
    expect(
      summary([
        _item('Milch', store: 'lidl', cents: 119),
        _item('Pinsel', cents: 300),
      ]).perStore,
      isTrue,
    );
  });

  test('the store lines add up to the total', () {
    final start = _now.subtract(const Duration(minutes: 30));
    final s = summary([
      _item('Milch', store: 'lidl', cents: 119),
      _item('Käse', store: 'lidl'),
      _item('Seife', store: 'dm', cents: 95, boughtAt: _now),
      _item('Pinsel', cents: 300),
    ], trip: _trip(start));
    expect(s.stores.fold(Sum.zero, (sum, t) => sum + t.sum), s.total);
  });
}
