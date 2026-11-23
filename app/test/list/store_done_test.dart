import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_done.dart';
import 'package:flutter_test/flutter_test.dart';

const _lidlChain = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [
    RetailerApp(
      name: 'Lidl Plus',
      android: 'com.lidl.eci.lidlplus',
      ios: '1238611143',
    ),
  ],
);

const _lidl = Store(
  id: 'lidl',
  name: 'Lidl',
  sortOrder: 10,
  retailer: _lidlChain,
);
const _rewe = Store(
  id: 'rewe',
  name: 'REWE',
  sortOrder: 20,
  retailer: _lidlChain,
);
const _markt = Store(id: 'markt', name: 'Wochenmarkt', sortOrder: 30);
const _catalog = Catalog(stores: [_lidl, _rewe, _markt]);

final _t0 = DateTime.utc(2026, 11, 22, 10);

var _ids = 0;

Item _item(
  String storeId, {
  DateTime? boughtAt,
  String? boughtBy,
  String addedBy = 'lea',
}) => Item(
  id: 'i${_ids++}',
  name: 'Milch',
  status: boughtAt == null ? ItemStatus.active : ItemStatus.bought,
  createdAt: _t0.subtract(const Duration(days: 1)),
  updatedAt: _t0,
  storeId: storeId,
  boughtAt: boughtAt,
  boughtBy: boughtBy,
  addedBy: addedBy,
);

Item _ticked(String storeId, Duration after, {String? by = 'peter'}) =>
    _item(storeId, boughtAt: _t0.add(after), boughtBy: by);

StoreDone? _card(
  List<Item> items, {
  Set<String> tickedHere = const {},
  Map<String, StoreDoneDismissal> dismissed = const {},
  Duration after = const Duration(minutes: 5),
}) => storeDoneCard(
  items: items,
  catalog: _catalog,
  userId: 'peter',
  tickedHere: tickedHere,
  dismissed: dismissed,
  now: _t0.add(after),
);

void main() {
  test('my tick finished a linked store: its card, at the last tick', () {
    final done = _card([
      _ticked('lidl', Duration.zero),
      _ticked('lidl', const Duration(minutes: 2), by: 'lea'),
    ]);
    expect(done, StoreDone(_lidl, _t0.add(const Duration(minutes: 2))));
  });

  test('a member who only added the items sees nothing', () {
    expect(
      _card([
        _item('lidl', boughtAt: _t0, boughtBy: 'lea', addedBy: 'peter'),
        _item('lidl', boughtAt: _t0, boughtBy: 'lea', addedBy: 'peter'),
      ]),
      isNull,
    );
  });

  test('my ticks in another store do not count', () {
    expect(
      _card([
        _ticked('lidl', Duration.zero, by: 'lea'),
        _ticked('rewe', Duration.zero),
        _item('rewe'),
      ]),
      isNull,
      reason: 'REWE is still open; Lidl was all Lea',
    );
  });

  test('my tick counts up to exactly 30 minutes before the last one', () {
    final last = _ticked('lidl', storeDoneTickWindow, by: 'lea');
    expect(
      _card([_ticked('lidl', Duration.zero), last]),
      isNotNull,
      reason: 'exactly 30 min before: inside',
    );
    expect(
      _card([_ticked('lidl', const Duration(seconds: -1)), last]),
      isNull,
      reason: '30 min and 1 s before: outside',
    );
  });

  test("this device's tick still waiting for the server is mine", () {
    final pending = _ticked('lidl', Duration.zero, by: null);
    expect(_card([pending]), isNull, reason: 'nobody known to have ticked');
    expect(_card([pending], tickedHere: {pending.id}), isNotNull);
  });

  test('a store without an app link gets no card', () {
    expect(_card([_ticked('markt', Duration.zero)]), isNull);
  });

  test('a store with an open item gets no card', () {
    expect(_card([_ticked('lidl', Duration.zero), _item('lidl')]), isNull);
  });

  test('the card shows for less than 60 minutes after the last tick', () {
    final items = [_ticked('lidl', Duration.zero)];
    expect(
      _card(items, after: storeDoneShowFor - const Duration(seconds: 1)),
      isNotNull,
    );
    expect(_card(items, after: storeDoneShowFor), isNull);
  });

  test('closed: gone until a new item finishes the store', () {
    final first = _ticked('lidl', Duration.zero);
    final closed = {
      'lidl': StoreDoneDismissal(_t0, {first.id}),
    };
    expect(_card([first], dismissed: closed), isNull);
    expect(
      _card([
        first.copyWith(boughtAt: () => _t0.add(const Duration(seconds: 4))),
      ], dismissed: closed),
      isNull,
      reason: "the server's own bought_at over a tick pending at the close",
    );
    final next = _ticked('lidl', const Duration(minutes: 20));
    expect(
      _card(
        [first, next],
        dismissed: closed,
        after: const Duration(minutes: 25),
      ),
      StoreDone(_lidl, next.boughtAt!),
    );
  });

  test('two finished stores: the later finish', () {
    final items = [
      _ticked('lidl', const Duration(minutes: 3)),
      _ticked('rewe', Duration.zero),
    ];
    expect(_card(items)?.store.id, 'lidl');
    expect(
      _card([...items, _ticked('rewe', const Duration(minutes: 4), by: 'lea')])
          ?.store
          .id,
      'rewe',
    );
  });
}
