import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:family_groceries/trip/summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saturday 14 November 2026, 10:00: the trip's start.
final start = DateTime(2026, 11, 14, 10);
DateTime at(int minutes) => start.add(Duration(minutes: minutes));

const lidl = Store(id: 'lidl', name: 'Lidl', sortOrder: 20);
const rewe = Store(id: 'rewe', name: 'Rewe', sortOrder: 10);
const catalog = Catalog(
  stores: [lidl, rewe],
  lists: [HouseholdList(id: 'home', name: 'Zuhause', position: 0)],
);

/// [euros] per piece (or per kg / l with [per]), saved at [on].
Price price(double euros, DateTime on, {PricePer per = PricePer.piece}) =>
    Price(
      unitMicros: (euros * 1000000).round(),
      basis: PriceBasis.unit,
      per: per,
      currency: 'EUR',
      pricedAt: on,
    );

Item item(
  String id, {
  String? store,
  String? quantity,
  Price? price,
  DateTime? bought,
  DateTime? created,
  String? by = 'peter',
  String? list,
}) => Item(
  id: id,
  name: id,
  status: bought == null ? ItemStatus.active : ItemStatus.bought,
  boughtAt: bought,
  createdAt: created ?? DateTime(2026, 11, 13),
  updatedAt: DateTime(2026, 11, 13),
  storeId: store,
  quantity: quantity,
  price: price,
  addedBy: by,
  listId: list,
);

PlannedItem planned(Item i) => PlannedItem(
  name: i.name,
  quantity: i.quantity,
  storeId: i.storeId,
  price: i.price,
);

RunningTrip running(List<Item> snapshot, {String? startItem}) => RunningTrip(
  id: 't1',
  householdId: 'h',
  listId: 'home',
  startedAt: start,
  source: TripSource.ask,
  snapshot: {for (final i in snapshot) i.id: planned(i)},
  startItem: startItem,
);

FinishedTrip finish(
  List<Item> snapshot,
  List<Item> now, {
  DateTime? end,
  FinishedTrip? previous,
  String? startItem,
}) => finishTrip(
  running(snapshot, startItem: startItem),
  items: {for (final i in now) i.id: i},
  catalog: catalog,
  userId: 'peter',
  endedAt: end ?? at(25),
  end: TripEnd.user,
  previous: previous,
);

TripLine line(FinishedTrip t, String key) =>
    t.lines!.singleWhere((l) => l.key == key);

void main() {
  final yesterday = DateTime(2026, 11, 13, 18);
  final morning = DateTime(2026, 11, 14, 8);

  group('finishTrip', () {
    test('planned lines in snapshot order, bought between start and end', () {
      final milk = item('milk', store: 'rewe');
      final bread = item('bread', store: 'lidl');
      final soap = item('soap');
      final t = finish(
        [milk, bread, soap],
        [
          item('milk', store: 'rewe', bought: at(5)),
          item('bread', store: 'lidl', bought: at(30)),
          soap,
        ],
      );
      expect(
        [for (final l in t.lines!) (l.key, l.planned, l.bought)],
        [('milk', true, true), ('bread', true, false), ('soap', true, false)],
      );
      expect(t.bought, 1);
      expect(t.stores, ['Rewe']);
      expect(t.active, const Duration(minutes: 25));
      expect(t.day, DateTime(2026, 11, 14));
      expect(t.currency, 'EUR');
    });

    test('a deleted item keeps its snapshot and is not bought', () {
      final milk = item('milk', store: 'rewe', quantity: '2');
      final t = finish([milk], const []);
      expect(line(t, 'milk').name, 'milk');
      expect(line(t, 'milk').quantity, '2');
      expect(line(t, 'milk').storeName, 'Rewe');
      expect(line(t, 'milk').bought, isFalse);
    });

    test('name, quantity and store come from the item at the end', () {
      final milk = item('milk', store: 'rewe');
      final t = finish(
        [milk],
        [
          Item(
            id: 'milk',
            name: 'Hafermilch',
            status: ItemStatus.bought,
            boughtAt: at(3),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            quantity: '2',
            storeId: 'gone',
          ),
        ],
      );
      expect(line(t, 'milk').name, 'Hafermilch');
      expect(line(t, 'milk').quantity, '2');
      expect(line(t, 'milk').storeId, isNull, reason: 'a store not kept');
      expect(t.stores, [null]);
    });

    test("extras: bought, or added since the start; others' adds named", () {
      final milk = item('milk');
      final t = finish(
        [milk],
        [
          milk,
          item('tea', created: at(3), by: 'lea'),
          item('coffee', created: at(4), bought: at(6)),
          item('old open', created: at(-60)),
          item('old bought', created: at(-60), bought: at(-30)),
          item('rebought', created: at(-60), bought: at(10)),
          item('other list', created: at(3), list: 'office'),
          item('after end', created: at(40)),
        ],
      );
      expect(
        [for (final l in t.lines!.skip(1)) l.key],
        ['rebought', 'tea', 'coffee'],
      );
      expect(line(t, 'tea').byOther, isTrue);
      expect(line(t, 'tea').addedBy, 'lea');
      expect(line(t, 'coffee').byOther, isFalse);
      expect(line(t, 'coffee').addedBy, isNull);
      expect(line(t, 'rebought').byOther, isFalse);
    });

    test('an item ticked again counts its last tick', () {
      final milk = item('milk');
      expect(
        line(finish([milk], [item('milk', bought: at(12))]), 'milk').bought,
        isTrue,
      );
      expect(
        line(finish([milk], [item('milk', bought: at(-5))]), 'milk').bought,
        isFalse,
        reason: 'ticked before the start',
      );
    });

    test('planned at the snapshot price; paid at the price at the end', () {
      final milk = item('milk', quantity: '2', price: price(1.15, yesterday));
      final t = finish(
        [milk],
        [item('milk', quantity: '3', price: price(1.20, at(5)), bought: at(5))],
      );
      expect(line(t, 'milk').plannedCents, 230);
      expect(line(t, 'milk').paidCents, 360);
    });

    test("a price of the trip's morning is paid; last time's is not", () {
      final t = finish(const [], [
        item('typed at home', price: price(2, morning), bought: at(3)),
        item('last time', price: price(2, yesterday), bought: at(4)),
      ]);
      expect(line(t, 'typed at home').paidCents, 200);
      expect(line(t, 'last time').paidCents, isNull);
    });

    test('a weighed line (PW1) pays the weighed amount', () {
      final apples = item(
        'apples',
        quantity: '1 kg',
        price: price(2.99, yesterday, per: PricePer.kg),
      );
      final t = finish(
        [apples],
        [
          item(
            'apples',
            quantity: '846 g',
            price: price(2.99, at(8), per: PricePer.kg),
            bought: at(8),
          ),
        ],
      );
      expect(line(t, 'apples').plannedCents, 299);
      expect(line(t, 'apples').paidCents, 253);
    });

    test('a price in another currency counts as none', () {
      final chf = Price(
        unitMicros: 1000000,
        basis: PriceBasis.unit,
        per: PricePer.piece,
        currency: 'CHF',
        pricedAt: at(2),
      );
      final milk = item('milk', price: chf);
      final t = finish([milk], [item('milk', price: chf, bought: at(2))]);
      expect(line(t, 'milk').plannedCents, isNull);
      expect(line(t, 'milk').paidCents, isNull);
    });

    test('no paid price on a line not bought', () {
      final milk = item('milk', price: price(1, at(1)));
      expect(line(finish([milk], [milk]), 'milk').paidCents, isNull);
    });

    test('ticks within the clock slack of either edge count', () {
      final names = ['milk', 'bread', 'egg', 'tea', 'soap'];
      final t = finish(
        [for (final n in names) item(n)],
        [
          item('milk', bought: at(-10)),
          item('bread', bought: start.subtract(tickSlack)),
          item('egg', bought: at(-5)),
          item('tea', bought: at(25).add(tickSlack)),
          item('soap', bought: at(28)),
        ],
        startItem: 'milk',
      );
      expect(
        [for (final n in names) line(t, n).bought],
        [true, true, false, true, false],
        reason: 'the starting item counts however far the clocks are apart',
      );
    });

    test('a tick just before the start of an item not open then is not '
        'on the trip', () {
      final t = finish(
        [item('milk')],
        [
          item('milk', bought: at(1)),
          item('apples', bought: at(-1)),
          item('pears', created: at(-1), bought: at(-1)),
          item('lemons', created: at(1), bought: start.subtract(tickSlack)),
        ],
      );
      expect(
        [for (final l in t.lines!) (l.key, l.bought)],
        [('milk', true), ('lemons', true)],
        reason:
            'apples and pears were ticked before the start („Nein“); '
            'lemons came in after it, its tick a clock apart',
      );
    });

    test('a trip keeps $maxTripLines lines: bought, then planned, then '
        'the rest', () {
      final snapshot = [for (var i = 0; i < 300; i++) item('p$i')];
      final now = [
        for (var i = 0; i < 300; i++)
          if (i.isEven) item('p$i', bought: at(1)) else item('p$i'),
        for (var i = 0; i < 200; i++)
          item('x$i', created: at(2), bought: i < 50 ? at(3) : null, by: 'lea'),
      ];
      final t = finish(snapshot, now);
      final lines = t.lines!;
      expect(lines, hasLength(maxTripLines));
      expect(lines.where((l) => l.bought), hasLength(200));
      expect(lines.where((l) => l.planned), hasLength(300));
      expect(lines.where((l) => !l.planned && !l.bought), hasLength(50));
      expect(t.bought, 200);
    });

    test('marks of the previous end carry over', () {
      final tea = item('tea', created: at(2), bought: at(3));
      final first = finish(const [], [tea]);
      final marked = FinishedTrip(
        id: first.id,
        householdId: first.householdId,
        startedAt: first.startedAt,
        endedAt: first.endedAt,
        active: first.active,
        end: first.end,
        source: first.source,
        currency: first.currency,
        lines: [for (final l in first.lines!) l.withMarked(true)],
        bought: first.bought,
        day: first.day,
      );
      expect(
        line(finish(const [], [tea], previous: marked), 'tea').markedPlanned,
        isTrue,
      );
    });
  });

  group('tripReport', () {
    TripLine row(
      String key, {
      String? store,
      String? storeName,
      bool planned = true,
      bool bought = true,
      bool marked = false,
      int? plan,
      int? paid,
    }) => TripLine(
      key: key,
      name: key,
      planned: planned,
      bought: bought,
      storeId: store,
      storeName: storeName,
      markedPlanned: marked,
      plannedCents: plan,
      paidCents: paid,
    );

    test('a section per store: store order, gone stores by name, none', () {
      final report = tripReport([
        row('a'),
        row('b', store: 'lidl', storeName: 'Lidl'),
        row('c', store: 'x', storeName: 'Netto'),
        row('d', store: 'rewe', storeName: 'Rewe'),
        row('e', store: 'y', storeName: 'Edeka'),
      ], catalog.stores);
      expect(
        [for (final s in report.sections) s.store],
        [
          const HouseholdStore(rewe),
          const HouseholdStore(lidl),
          const GoneStore('Edeka'),
          const GoneStore('Netto'),
          const NoStore(),
        ],
      );
    });

    test('planned part: snapshot and marked lines; extras the rest', () {
      final report = tripReport([
        row('milk'),
        row('bread', bought: false),
        row('tea', planned: false, marked: true),
        row('coffee', planned: false),
      ], const []);
      final section = report.sections.single;
      expect(
        [for (final l in section.planned) l.key],
        ['milk', 'bread', 'tea'],
      );
      expect([for (final l in section.extras) l.key], ['coffee']);
      expect(
        report.totals,
        const TripTotals(
          withoutPrice: 3,
          bought: 3,
          plannedCount: 3,
          plannedBought: 2,
          extraBought: 1,
        ),
      );
    });

    test('totals: paid, compared difference, without price or plan', () {
      final report = tripReport([
        row('milk', store: 'rewe', plan: 129, paid: 149),
        row('bread', store: 'rewe', plan: 250, paid: 199),
        row('soap', store: 'rewe', plan: 300, bought: false),
        row('tea', store: 'rewe', planned: false, paid: 400),
        row('salt', store: 'lidl', plan: 50),
        row('pepper', store: 'lidl', plan: 100, paid: 120),
      ], catalog.stores);
      final rewes = report.sections.first.totals;
      expect(
        rewes,
        const TripTotals(
          paid: 748,
          planned: 379,
          difference: -31,
          compared: 2,
          withoutPlan: 1,
          bought: 3,
          plannedCount: 3,
          plannedBought: 2,
          extraBought: 1,
        ),
      );
      expect(
        report.totals,
        const TripTotals(
          paid: 868,
          planned: 479,
          difference: -11,
          compared: 3,
          withoutPrice: 1,
          withoutPlan: 1,
          bought: 5,
          plannedCount: 5,
          plannedBought: 4,
          extraBought: 1,
        ),
      );
    });

    test('a trip without a list has no planned part', () {
      final report = tripReport([
        row('a', planned: false, paid: 100),
      ], const []);
      expect(report.totals.plannedCount, 0);
      expect(report.totals.extraBought, 1);
    });
  });
}
