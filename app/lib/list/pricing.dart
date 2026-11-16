/// Prices on the list (job 190): what a price is, how a typed one is read,
/// what a line costs and what the shown list adds up to. Peter's rules
/// (t832u, t833u): a price never ticks an item; a line from -9999,00 to
/// 9999,00 in the household's currency, 0 and negative (deposit returns)
/// allowed; up to 50 kg or 50 l. The unit price is the source of truth: a
/// typed total becomes total / quantity at save, and a later quantity
/// change scales the line (2 packs at 1,38 €, then 3: 2,07 €).
library;

import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// A line's limits, in cents.
const minPriceCents = -999900;
const maxPriceCents = 999900;

/// The most a weight (g) or a volume (ml) may be: 50 kg, 50 l.
const maxMilli = 50000;

/// `items.price_unit_micros`' bounds on the server.
const maxUnitMicros = 999900000000;

/// Millionths of the currency unit per cent.
const microsPerCent = 10000;

/// How the shopper typed the price: per unit, or the line's total (the
/// shelf label, the scale sticker). It only reopens the editor the way it
/// was used; the unit price counts either way.
enum PriceBasis() {
  unit,
  line,
}

/// What a unit price is per: a piece, a kilogram or a litre (the German
/// Grundpreis units).
enum PricePer() {
  piece,
  kg,
  l,
}

/// An item's price: [unitMicros] (millionths of the currency unit, so a
/// third of 1,00 € stays exact enough to sum back) per [per] in
/// [currency] (ISO 4217), saved at [pricedAt] (the device's clock).
@immutable
class const Price({
  required final int unitMicros,
  required final PriceBasis basis,
  required final PricePer per,
  required final String currency,
  required final DateTime pricedAt,
}) {
  /// Null unless all five columns are set (`items_price_complete`).
  static Price? fromColumns(Map<String, Object?> json) {
    if (json case {
      'price_unit_micros': final int micros,
      'price_basis': final String basis,
      'price_per': final String per,
      'price_currency': final String currency,
      'priced_at': final String at,
    }) {
      final b = PriceBasis.values.asNameMap()[basis];
      final p = PricePer.values.asNameMap()[per];
      if (b != null && p != null) {
        return Price(
          unitMicros: micros,
          basis: b,
          per: p,
          currency: currency,
          pricedAt: DateTime.parse(at),
        );
      }
    }
    return null;
  }

  Map<String, Object?> toColumns() => {
    'price_unit_micros': unitMicros,
    'price_basis': basis.name,
    'price_per': per.name,
    'price_currency': currency,
    'priced_at': pricedAt.toUtc().toIso8601String(),
  };

  static const noColumns = <String, Object?>{
    'price_unit_micros': null,
    'price_basis': null,
    'price_per': null,
    'price_currency': null,
    'priced_at': null,
  };

  /// Saved on [now]'s local calendar day: it counts for the running total.
  /// An older one is last time's price.
  bool isCurrent(DateTime now) {
    final (a, b) = (pricedAt.toLocal(), now.toLocal());
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  bool operator ==(Object other) =>
      other is Price &&
      other.unitMicros == unitMicros &&
      other.basis == basis &&
      other.per == per &&
      other.currency == currency &&
      other.pricedAt.isAtSameMomentAs(pricedAt);

  @override
  int get hashCode => Object.hash(
    unitMicros,
    basis,
    per,
    currency,
    pricedAt.microsecondsSinceEpoch,
  );

  @override
  String toString() => 'Price(${toColumns()})';
}

sealed class const ParsedPrice();

final class const PriceOk(final int cents) extends ParsedPrice;

final class const PriceEmpty() extends ParsedPrice;

final class const PriceInvalid() extends ParsedPrice;

final class const PriceTooLarge() extends ParsedPrice;

/// A typed amount, "1,19", "1.19", "-0,25" or "12"; spaces ignored.
ParsedPrice parsePrice(String text) {
  final s = text.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) {
    return const PriceEmpty();
  }
  final match = RegExp(r'^(-?)(\d{0,9})(?:[.,](\d{0,2}))?$').firstMatch(s);
  final whole = match?[2] ?? '';
  final frac = match?[3] ?? '';
  if (match == null || (whole.isEmpty && frac.isEmpty)) {
    return const PriceInvalid();
  }
  final cents =
      (whole.isEmpty ? 0 : int.parse(whole)) * 100 +
      int.parse(frac.padRight(2, '0'));
  if (cents > maxPriceCents) {
    return const PriceTooLarge();
  }
  return PriceOk(match[1] == '-' ? -cents : cents);
}

/// A weight in kg or a volume in l as typed, in thousandths (g, ml).
sealed class const ParsedAmount();

final class const AmountOk(final int milli) extends ParsedAmount;

final class const AmountEmpty() extends ParsedAmount;

final class const AmountInvalid() extends ParsedAmount;

final class const AmountZero() extends ParsedAmount;

final class const AmountTooLarge() extends ParsedAmount;

/// Kilograms or litres as typed in the amount field: "0,846", "1.5", "2".
ParsedAmount parseAmount(String text) {
  final s = text.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) {
    return const AmountEmpty();
  }
  final match = RegExp(r'^(\d{0,6})(?:[.,](\d{0,3}))?$').firstMatch(s);
  final whole = match?[1] ?? '';
  final frac = match?[2] ?? '';
  if (match == null || (whole.isEmpty && frac.isEmpty)) {
    return const AmountInvalid();
  }
  final milli =
      (whole.isEmpty ? 0 : int.parse(whole)) * 1000 +
      int.parse(frac.padRight(3, '0'));
  return switch (milli) {
    0 => const AmountZero(),
    > maxMilli => const AmountTooLarge(),
    _ => AmountOk(milli),
  };
}

/// Lets through only what can still become a number: digits, one `,` or
/// `.` with at most [decimals] after it, and a leading `-` when [signed].
/// Anything else (letters, a second comma) leaves the field as it was.
class const DecimalInputFormatter({
  required final bool signed,
  required final int decimals,
  required final int digits,
}) extends TextInputFormatter {
  static const price = DecimalInputFormatter(
    signed: true,
    decimals: 2,
    digits: 7,
  );
  static const amount = DecimalInputFormatter(
    signed: false,
    decimals: 3,
    digits: 5,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sign = signed ? '-?' : '';
    final ok = RegExp('^$sign\\d{0,$digits}(?:[.,]\\d{0,$decimals})?\$')
        .hasMatch(newValue.text);
    return ok ? newValue : oldValue;
  }
}

/// How much of an item the list asks for, as far as a price multiplies it.
sealed class const Measure();

/// [count] pieces. [rest] is the text after the count as typed ("" for
/// "2", " Stück", " x 500 g", "er"), so a new count replaces the number
/// alone; null when the quantity names no count to change ("1/2", "1,5",
/// "Bund"): one piece, and the text stays as written.
final class const Pieces(final int count, {final String? rest = ''})
    extends Measure;

final class const Grams(final int grams) extends Measure;

final class const Millilitres(final int ml) extends Measure;

const _gramWords = {'g', 'gr', 'gramm'};
const _kiloWords = {'kg', 'kilo', 'kilogramm'};
const _mlWords = {'ml', 'milliliter'};
const _clWords = {'cl', 'zentiliter'};
const _litreWords = {'l', 'liter', 'litre'};

/// The item's quantity text as a [Measure]: "846 g" and "1,24 kg" weigh,
/// "500 ml" and "1,5 l" hold, "2", "2 Stück" and "3 Packungen" count;
/// anything else is one piece.
Measure measureOf(String? quantity) {
  final original = (quantity ?? '').trim();
  final s = original.toLowerCase();
  final measured = RegExp(r'^(\d{1,6})(?:[.,](\d{1,3}))?\s*([a-zäöü]+)\.?$')
      .firstMatch(s);
  if (measured != null) {
    final whole = int.parse(measured[1]!);
    final frac = measured[2] ?? '';
    final word = measured[3]!;
    int thousandths() => whole * 1000 + int.parse(frac.padRight(3, '0'));
    int rounded() =>
        whole + (frac.isNotEmpty && int.parse(frac[0]) >= 5 ? 1 : 0);
    final measure = switch (word) {
      _ when _gramWords.contains(word) => Grams(rounded()),
      _ when _kiloWords.contains(word) => Grams(thousandths()),
      _ when _mlWords.contains(word) => Millilitres(rounded()),
      _ when _clWords.contains(word) => Millilitres(rounded() * 10),
      _ when _litreWords.contains(word) => Millilitres(thousandths()),
      _ => null,
    };
    switch (measure) {
      case Grams(:final grams) when grams > 0:
        return measure;
      case Millilitres(:final ml) when ml > 0:
        return measure;
      case _:
    }
  }
  // A leading count not followed by more of a number: "2 x 500 g" counts
  // 2, "1,5" and "1/2" count nothing.
  final count = RegExp(r'^(\d{1,3})(?![\d.,/])(.*)$').firstMatch(original);
  if (count != null && int.parse(count[1]!) > 0) {
    return Pieces(int.parse(count[1]!), rest: count[2]);
  }
  return original.isEmpty ? const Pieces(1) : const Pieces(1, rest: null);
}

/// What a price for an item of [measure] is per: kg for a weight, l for a
/// volume, else a piece.
PricePer perFor(Measure measure) => switch (measure) {
  Grams() => PricePer.kg,
  Millilitres() => PricePer.l,
  Pieces() => PricePer.piece,
};

/// [measure] in what [per] counts: grams for kg, ml for l, pieces for a
/// piece. Null for a weight or volume price on a quantity without one; a
/// piece price on a weight or volume counts one piece.
int? amountFor(PricePer per, Measure measure) => switch ((per, measure)) {
  (PricePer.kg, Grams(:final grams)) => grams,
  (PricePer.l, Millilitres(:final ml)) => ml,
  (PricePer.kg || PricePer.l, _) => null,
  (PricePer.piece, Pieces(:final count)) => count,
  (PricePer.piece, _) => 1,
};

/// [a] / [b], rounded half away from zero. BigInt: the products pass
/// 2^53, where the web's ints stop being exact.
int _divRound(BigInt a, BigInt b) {
  final negative = a.isNegative != b.isNegative;
  final (x, y) = (a.abs(), b.abs());
  final q = (BigInt.two * x + y) ~/ (BigInt.two * y);
  return (negative ? -q : q).toInt();
}

/// What one [per] is in an amount's units: 1000 g, 1000 ml, one piece.
BigInt _perUnit(PricePer per) =>
    per == PricePer.piece ? BigInt.one : BigInt.from(1000);

/// The line in cents for [unitMicros] per [per] times [amount] (pieces,
/// grams or ml).
int lineCents(int unitMicros, PricePer per, int amount) => _divRound(
  BigInt.from(unitMicros) * BigInt.from(amount),
  _perUnit(per) * BigInt.from(microsPerCent),
);

/// The unit price in micros of a line of [line] cents for [amount].
int unitMicrosOf(int line, PricePer per, int amount) => _divRound(
  BigInt.from(line) * BigInt.from(microsPerCent) * _perUnit(per),
  BigInt.from(amount),
);

/// Micros to whole cents, for showing a unit price.
int microsToCents(int micros) =>
    _divRound(BigInt.from(micros), BigInt.from(microsPerCent));

/// A [typed] amount in cents read as [basis] for [amount] (pieces, grams
/// or ml): the unit price it stores and the line it makes. Null when the
/// line is beyond the limits (or the unit price beyond the server's).
({int unitMicros, int line})? priceSplit(
  int typed,
  PriceBasis basis,
  PricePer per,
  int amount,
) {
  final micros = basis == PriceBasis.unit
      ? typed * microsPerCent
      : unitMicrosOf(typed, per, amount);
  final line = lineCents(micros, per, amount);
  return micros.abs() <= maxUnitMicros &&
          line >= minPriceCents &&
          line <= maxPriceCents
      ? (unitMicros: micros, line: line)
      : null;
}

extension ItemPrice on Item {
  /// The line this item's [price] makes at its current quantity, in the
  /// price's own currency; null without a price, or for a per-kg price on a
  /// quantity that has no weight.
  int? get lineCentsNow {
    final p = price;
    if (p == null) {
      return null;
    }
    final amount = amountFor(p.per, measureOf(quantity));
    return amount == null ? null : lineCents(p.unitMicros, p.per, amount);
  }

  /// The price that counts on [now]'s day, any currency.
  Price? currentPrice(DateTime now) => switch (price) {
    final p? when p.isCurrent(now) => p,
    _ => null,
  };

  /// What this item adds to the total in [currency] on [now]'s day.
  int? summedCents(String currency, DateTime now) =>
      currentPrice(now)?.currency == currency ? lineCentsNow : null;
}

/// Last time's price of [item] for the comparison: the newest price from
/// an earlier day in [currency] per [per], among the item itself and the
/// household's other items ([items]) of the same thing (`canonical_key`,
/// else the folded name).
Price? lastPrice(
  Item item,
  Iterable<Item> items, {
  required String currency,
  required PricePer per,
  required DateTime now,
}) {
  String thing(Item i) => i.canonicalKey ?? foldName(i.name);
  final key = thing(item);
  Price? best;
  for (final other in [item, ...items.where((i) => i.id != item.id)]) {
    final p = other.price;
    if (p == null ||
        p.isCurrent(now) ||
        p.currency != currency ||
        p.per != per ||
        thing(other) != key) {
      continue;
    }
    if (best == null || p.pricedAt.isAfter(best.pricedAt)) {
      best = p;
    }
  }
  return best;
}

enum Trend() {
  cheaper,
  dearer,
  same,
}

/// [unitMicros] against [last]'s unit price, and by how much in cents.
({Trend trend, int cents}) compareToLast(int unitMicros, Price last) {
  final diff = microsToCents(unitMicros) - microsToCents(last.unitMicros);
  return (
    trend: diff < 0
        ? Trend.cheaper
        : diff > 0
        ? Trend.dearer
        : Trend.same,
    cents: diff.abs(),
  );
}

/// [cents] in [currency] the way [locale] writes money: "2,38 €",
/// "2,38 CHF", "$2.38". Always two decimals, as every price is in cents
/// (intl would round forint to whole ones).
String formatMoney(
  int cents, {
  required String currency,
  required String locale,
}) => NumberFormat.simpleCurrency(
  locale: locale,
  name: currency,
  decimalDigits: 2,
).format(cents / 100);

/// The sign or code [currency] shows with in [locale]: "€", "CHF".
String currencySymbol(String currency, String locale) =>
    NumberFormat.simpleCurrency(locale: locale, name: currency).currencySymbol;

/// [cents] for an editable field, without a sign or grouping: "1,19".
String amountText(int cents, String locale) =>
    NumberFormat('0.00', locale).format(cents / 100);

/// Thousandths (g, ml) for the amount field, in kg or l: "0,846".
String milliText(int milli, String locale) =>
    NumberFormat('0.###', locale).format(milli / 1000);

/// [milli] g or ml as the item's quantity text: "846 g", "1,24 kg",
/// "500 ml", "1,5 l".
String measureQuantity(PricePer per, int milli) {
  final (small, big) = per == PricePer.l ? ('ml', 'l') : ('g', 'kg');
  if (milli < 1000) {
    return '$milli $small';
  }
  final whole = (milli / 1000)
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  return '${whole.replaceAll('.', ',')} $big';
}

/// The common ISO 4217 codes the household page offers, EUR first.
const currencies = [
  'EUR',
  'CHF',
  'GBP',
  'USD',
  'PLN',
  'CZK',
  'SEK',
  'DKK',
  'NOK',
  'HUF',
  'RON',
  'BGN',
  'TRY',
  'CAD',
  'AUD',
];
