import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/list/subtotals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _now = DateTime(2026, 11, 13, 18);

/// A price of [cents] per unit.
Price _price(
  int cents, {
  PricePer per = PricePer.piece,
  PriceBasis basis = PriceBasis.unit,
  String currency = 'EUR',
  DateTime? at,
}) => Price(
  unitMicros: cents * microsPerCent,
  basis: basis,
  per: per,
  currency: currency,
  pricedAt: at ?? _now.subtract(const Duration(hours: 1)),
);

Item _item(
  String name, {
  String id = '',
  String? quantity,
  Price? price,
  String? storeId,
  String? listId,
  ItemStatus status = ItemStatus.active,
  String? canonicalKey,
}) => Item(
  id: id.isEmpty ? name : id,
  name: name,
  quantity: quantity,
  status: status,
  createdAt: DateTime.utc(2026, 11),
  updatedAt: DateTime.utc(2026, 11),
  storeId: storeId,
  listId: listId,
  price: price,
  canonicalKey: canonicalKey,
);

void main() {
  setUpAll(initializeDateFormatting);

  group('price limits (t832u)', () {
    test('-9999,00, 0 and 9999,00 are prices; one cent beyond is not', () {
      expect(parsePrice('-9999,00'), isA<PriceOk>());
      expect((parsePrice('-9999,00') as PriceOk).cents, -999900);
      expect((parsePrice('0') as PriceOk).cents, 0);
      expect((parsePrice('9999') as PriceOk).cents, 999900);
      expect(parsePrice('9999,01'), isA<PriceTooLarge>());
      expect(parsePrice('-9999,01'), isA<PriceTooLarge>());
      expect(parsePrice('10000'), isA<PriceTooLarge>());
    });

    test('a deposit return is a negative price, written either way', () {
      expect((parsePrice('-0,25') as PriceOk).cents, -25);
      expect((parsePrice('-0.25') as PriceOk).cents, -25);
      expect((parsePrice('1,5') as PriceOk).cents, 150);
      expect((parsePrice(' 2, ') as PriceOk).cents, 200);
    });

    test('empty and half-typed input is not a price', () {
      expect(parsePrice(''), isA<PriceEmpty>());
      expect(parsePrice('  '), isA<PriceEmpty>());
      expect(parsePrice('-'), isA<PriceInvalid>());
      expect(parsePrice(','), isA<PriceInvalid>());
      expect(parsePrice('1,234'), isA<PriceInvalid>());
    });

    test('50 kg or 50 l are amounts; 0 and more than 50 are not', () {
      expect((parseAmount('50') as AmountOk).milli, 50000);
      expect((parseAmount('0,846') as AmountOk).milli, 846);
      expect((parseAmount('1.5') as AmountOk).milli, 1500);
      expect(parseAmount('50,001'), isA<AmountTooLarge>());
      expect(parseAmount('0'), isA<AmountZero>());
      expect(parseAmount('0,000'), isA<AmountZero>());
      expect(parseAmount(''), isA<AmountEmpty>());
      expect(parseAmount(','), isA<AmountInvalid>());
    });

    test('a line over the limit is refused, also from a fine unit price', () {
      expect(priceSplit(500000, PriceBasis.unit, PricePer.piece, 2), isNull);
      expect(priceSplit(999900, PriceBasis.unit, PricePer.piece, 1), (
        unitMicros: 9999000000,
        line: 999900,
      ));
      expect(priceSplit(-999900, PriceBasis.line, PricePer.piece, 3), (
        unitMicros: -3333000000,
        line: -999900,
      ));
      // 9999 € per kg for 50 kg.
      expect(priceSplit(999900, PriceBasis.unit, PricePer.kg, 50000), isNull);
      // A label total on a gram: a unit price beyond the server's bounds.
      expect(priceSplit(999900, PriceBasis.line, PricePer.kg, 1), isNull);
      expect(priceSplit(0, PriceBasis.line, PricePer.kg, 846), (
        unitMicros: 0,
        line: 0,
      ));
    });
  });

  group('the price field takes only numbers', () {
    TextEditingValue type(DecimalInputFormatter f, String old, String next) =>
        f.formatEditUpdate(
          TextEditingValue(text: old),
          TextEditingValue(text: next),
        );

    test('letters, a second comma and a third decimal are refused', () {
      const f = DecimalInputFormatter.price;
      expect(type(f, '1', '1a').text, '1');
      expect(type(f, '', 'abc').text, '');
      expect(type(f, '1,5', '1,5,').text, '1,5');
      expect(type(f, '1,59', '1,599').text, '1,59');
      expect(type(f, '1', '1€').text, '1');
      expect(type(f, '', '-').text, '-');
      expect(type(f, '-', '-0,2').text, '-0,2');
      expect(type(f, '1', '1.').text, '1.');
    });

    test('the weight and volume field takes no sign', () {
      const f = DecimalInputFormatter.amount;
      expect(type(f, '', '-').text, '');
      expect(type(f, '0,84', '0,846').text, '0,846');
      expect(type(f, '0,846', '0,8461').text, '0,846');
      expect(type(f, '0', '0kg').text, '0');
    });
  });

  group('the unit follows the item', () {
    test('counts, weights and volumes are read from the quantity text', () {
      expect(measureOf(null), isA<Pieces>().having((p) => p.count, 'n', 1));
      expect(measureOf('2'), isA<Pieces>().having((p) => p.count, 'n', 2));
      expect(
        measureOf('2 Stück'),
        isA<Pieces>()
            .having((p) => p.count, 'n', 2)
            .having((p) => p.rest, 'rest', ' Stück'),
      );
      expect(
        measureOf('2 Packungen'),
        isA<Pieces>().having((p) => p.count, 'n', 2),
      );
      expect(measureOf('846 g'), isA<Grams>().having((g) => g.grams, 'g', 846));
      expect(
        measureOf('1,24 kg'),
        isA<Grams>().having((g) => g.grams, 'g', 1240),
      );
      expect(
        measureOf('500 ml'),
        isA<Millilitres>().having((v) => v.ml, 'ml', 500),
      );
      expect(
        measureOf('1,5 l'),
        isA<Millilitres>().having((v) => v.ml, 'ml', 1500),
      );
      expect(measureOf('Bund'), isA<Pieces>().having((p) => p.count, 'n', 1));
    });

    test('only a leading count can change; the rest stays as typed', () {
      Matcher pieces(int count, String? rest) => isA<Pieces>()
          .having((p) => p.count, 'count', count)
          .having((p) => p.rest, 'rest', rest);
      expect(measureOf('2 x 500 g'), pieces(2, ' x 500 g'));
      expect(measureOf('6er'), pieces(6, 'er'));
      expect(measureOf('2'), pieces(2, ''));
      expect(measureOf(null), pieces(1, ''));
      // More of a number after the digits: no count the stepper may change.
      expect(measureOf('1,5'), pieces(1, null));
      expect(measureOf('1/2'), pieces(1, null));
      expect(measureOf('Bund'), pieces(1, null));
      expect(measureOf('0'), pieces(1, null));
    });

    test('g and kg are priced per kg, ml and l per l, the rest per piece', () {
      expect(perFor(measureOf('846 g')), PricePer.kg);
      expect(perFor(measureOf('1,24 kg')), PricePer.kg);
      expect(perFor(measureOf('500 ml')), PricePer.l);
      expect(perFor(measureOf('2 l')), PricePer.l);
      expect(perFor(measureOf('2 Packungen')), PricePer.piece);
      expect(perFor(measureOf('3')), PricePer.piece);
      expect(perFor(measureOf(null)), PricePer.piece);
    });

    test('weights and volumes go back as the quantity text', () {
      expect(measureQuantity(PricePer.kg, 846), '846 g');
      expect(measureQuantity(PricePer.kg, 1240), '1,24 kg');
      expect(measureQuantity(PricePer.kg, 1000), '1 kg');
      expect(measureQuantity(PricePer.kg, 50000), '50 kg');
      expect(measureQuantity(PricePer.l, 500), '500 ml');
      expect(measureQuantity(PricePer.l, 1500), '1,5 l');
    });
  });

  group('LQ2 (t833u): the unit price stays, the line scales', () {
    test('a typed total, then a quantity change, scales the line', () {
      final split = priceSplit(138, PriceBasis.line, PricePer.piece, 2)!;
      expect(split, (unitMicros: 690000, line: 138));
      final item = _item(
        'Wasser',
        quantity: '2',
        price: Price(
          unitMicros: split.unitMicros,
          basis: PriceBasis.line,
          per: PricePer.piece,
          currency: 'EUR',
          pricedAt: _now,
        ),
      );
      expect(item.lineCentsNow, 138);
      expect(item.copyWith(quantity: () => '3').lineCentsNow, 207);
    });

    test('a typed unit price scales the line', () {
      final item = _item('Joghurt', quantity: '2', price: _price(69));
      expect(item.lineCentsNow, 138);
      expect(item.copyWith(quantity: () => '4').lineCentsNow, 276);
    });

    test('a third stays exact enough to sum back', () {
      final split = priceSplit(100, PriceBasis.line, PricePer.piece, 3)!;
      expect(split, (unitMicros: 333333, line: 100));
      expect(lineCents(split.unitMicros, PricePer.piece, 6), 200);
    });

    test('rounding is half away from zero', () {
      expect(unitMicrosOf(1, PricePer.piece, 3), 3333);
      expect(lineCents(5000, PricePer.piece, 1), 1);
      expect(lineCents(-5000, PricePer.piece, 1), -1);
      expect(lineCents(2450000, PricePer.kg, 846), 207);
      expect(microsToCents(-695000), -70);
    });
  });

  group('PW1 (t833u): weight and volume', () {
    test(
      'per-kg and label entry give the same weight, unit price and line',
      () {
        final perKg = priceSplit(199, PriceBasis.unit, PricePer.kg, 846)!;
        final label = priceSplit(168, PriceBasis.line, PricePer.kg, 846)!;
        expect(perKg.line, 168);
        expect(label.line, 168);
        expect(microsToCents(label.unitMicros), 199);
      },
    );

    test('a per-kg price follows the scale weight in the quantity', () {
      final item = _item(
        'Bananen',
        quantity: '846 g',
        price: _price(199, per: PricePer.kg),
      );
      expect(item.lineCentsNow, 168);
      expect(item.copyWith(quantity: () => '1,24 kg').lineCentsNow, 247);
      // A count has no weight to multiply.
      expect(item.copyWith(quantity: () => '2').lineCentsNow, isNull);
    });

    test('a per-litre price follows the volume', () {
      final item = _item(
        'Apfelsaft',
        quantity: '1,5 l',
        price: _price(180, per: PricePer.l),
      );
      expect(item.lineCentsNow, 270);
      expect(item.copyWith(quantity: () => '500 ml').lineCentsNow, 90);
    });
  });

  group('the total', () {
    const lidl = 'lidl';
    const dm = 'dm';

    test('sums one list across stores, open and bought, with subtotals', () {
      final items = [
        _item('Milch', quantity: '3', price: _price(119), storeId: lidl),
        _item(
          'Butter',
          price: _price(249),
          storeId: lidl,
          status: ItemStatus.bought,
        ),
        _item('Shampoo', price: _price(-25), storeId: dm),
        _item('Brot', price: _price(0)),
        _item('Joghurt', storeId: lidl),
        _item('Seife', storeId: dm, status: ItemStatus.bought),
      ];
      final total = tripTotal(
        items,
        currency: 'EUR',
        now: _now,
        stores: {lidl, dm},
      );
      expect(total.cents, 357 + 249 - 25 + 0);
      expect(total.priced, 4);
      // Joghurt; the bought Seife is not open.
      expect(total.open, 1);
      expect(total.byStore, {lidl: 606, dm: -25, null: 0});
    });

    test("a price from an earlier day is last time's, not today's", () {
      final yesterday = _now.subtract(const Duration(days: 1));
      final total = tripTotal(
        [_item('Milch', price: _price(119, at: yesterday))],
        currency: 'EUR',
        now: _now,
      );
      expect((total.cents, total.priced, total.open), (0, 0, 1));
      // Midnight local time starts a new day.
      final lateLastNight = DateTime(2026, 11, 12, 23, 59);
      expect(_price(1, at: lateLastNight).isCurrent(_now), isFalse);
      expect(_price(1, at: DateTime(2026, 11, 13)).isCurrent(_now), isTrue);
    });

    test('a price in another currency is neither summed nor open', () {
      final total = tripTotal(
        [
          _item('Milch', price: _price(119, currency: 'CHF')),
          _item('Brot', price: _price(200)),
        ],
        currency: 'EUR',
        now: _now,
      );
      expect((total.cents, total.priced, total.open), (200, 1, 0));
    });

    test('an item of a deleted store counts without a store', () {
      final total = tripTotal(
        [_item('Milch', price: _price(119), storeId: 'gone')],
        currency: 'EUR',
        now: _now,
        stores: {lidl},
      );
      expect(total.byStore, {null: 119});
    });
  });

  group('last price', () {
    final earlier = DateTime(2026, 11, 6, 10);
    final earliest = DateTime(2026, 10, 30, 10);

    test('the newest earlier price of the same thing, currency and unit', () {
      final milk = _item('Milch', canonicalKey: 'milch', price: _price(119));
      final household = [
        milk,
        _item(
          'Vollmilch',
          id: 'a',
          canonicalKey: 'milch',
          price: _price(109, at: earlier),
          status: ItemStatus.bought,
        ),
        _item(
          'Milch',
          id: 'b',
          canonicalKey: 'milch',
          price: _price(99, at: earliest),
          status: ItemStatus.bought,
        ),
        _item(
          'Milch',
          id: 'c',
          canonicalKey: 'milch',
          price: _price(89, at: earlier, currency: 'CHF'),
        ),
        _item(
          'Milch',
          id: 'd',
          canonicalKey: 'milch',
          price: _price(79, at: earlier, per: PricePer.kg),
        ),
        _item(
          'Butter',
          id: 'e',
          canonicalKey: 'butter',
          price: _price(69, at: earlier.add(const Duration(days: 1))),
        ),
      ];
      final last = lastPrice(
        milk,
        household,
        currency: 'EUR',
        per: PricePer.piece,
        now: _now,
      );
      expect(last?.unitMicros, 1090000);
    });

    test('without a canonical key the folded name matches', () {
      final item = _item('Äpfel');
      final last = lastPrice(
        item,
        [
          item,
          _item(
            'äpfel ',
            id: 'x',
            price: _price(250, at: earlier),
          ),
        ],
        currency: 'EUR',
        per: PricePer.piece,
        now: _now,
      );
      expect(last?.unitMicros, 2500000);
    });

    test('compared by unit price', () {
      final last = _price(89, at: earlier);
      expect(compareToLast(1190000, last), (trend: Trend.dearer, cents: 30));
      expect(compareToLast(790000, last), (trend: Trend.cheaper, cents: 10));
      expect(compareToLast(890000, last), (trend: Trend.same, cents: 0));
    });
  });

  group('money follows the currency code', () {
    test('EUR, CHF and USD in German and English', () {
      expect(formatMoney(238, currency: 'EUR', locale: 'de'), '2,38\u00a0€');
      expect(formatMoney(238, currency: 'CHF', locale: 'de'), '2,38\u00a0CHF');
      expect(formatMoney(238, currency: 'USD', locale: 'de'), '2,38\u00a0\$');
      expect(formatMoney(238, currency: 'USD', locale: 'en'), r'$2.38');
      expect(formatMoney(-30, currency: 'EUR', locale: 'de'), '-0,30\u00a0€');
      expect(currencySymbol('CHF', 'de'), 'CHF');
    });

    test('every offered currency formats with cents', () {
      for (final code in currencies) {
        expect(
          formatMoney(1234, currency: code, locale: 'de'),
          contains('12,34'),
          reason: code,
        );
      }
    });

    test('field text', () {
      expect(amountText(119, 'de'), '1,19');
      expect(amountText(-25, 'de'), '-0,25');
      expect(amountText(119, 'en'), '1.19');
      expect(milliText(846, 'de'), '0,846');
      expect(milliText(1500, 'de'), '1,5');
    });
  });

  group('stored', () {
    test('the five columns round-trip, all or none', () {
      final price = _price(-25, per: PricePer.kg, basis: PriceBasis.line);
      final item = _item('Pfand', price: price);
      final back = Item.fromJson(item.toJson());
      expect(back.price, price);
      expect(Item.fromJson(_item('Brot').toJson()).price, isNull);
      expect(
        Price.fromColumns({...price.toColumns(), 'price_per': null}),
        isNull,
      );
      expect(
        Price.fromColumns({...price.toColumns(), 'price_per': 'pack'}),
        isNull,
      );
    });
  });
}
