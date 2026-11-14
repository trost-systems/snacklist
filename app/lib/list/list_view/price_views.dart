import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The locale amounts are written in.
String moneyLocale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// What "pro ..." the unit [per] reads as.
String perLabel(AppLocalizations l10n, PricePer per) => switch (per) {
  PricePer.piece => l10n.pricePerPiece,
  PricePer.kg => l10n.pricePerKg,
  PricePer.l => l10n.pricePerLitre,
};

const _figures = [FontFeature.tabularFigures()];

/// A row's price (job 190): "+ Preis" without today's price, else the
/// line's total in the price's own currency. Its own button for screen
/// readers; the row around it still ticks.
class const PriceChip({
  required final Item item,
  required final DateTime now,
  required final VoidCallback onTap,

  /// Marks the line „≈“: its weight is the planned one (job 237).
  final bool estimate = false,
  super.key,
}) extends StatelessWidget {
  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final price = item.currentPrice(now);
    final line = price == null ? null : item.lineCentsNow;
    final money = price == null || line == null
        ? null
        : formatMoney(
            line,
            currency: price.currency,
            locale: moneyLocale(context),
          );
    final (amount, spoken) = switch (money) {
      final m? when estimate => (
        l10n.moneyEstimate(m),
        l10n.moneyEstimateSpoken(m),
      ),
      _ => (money, money),
    };
    final label = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: amount == null ? t.textMuted : t.text,
      fontFeatures: _figures,
    );
    return Semantics(
      container: true,
      button: true,
      label: spoken == null
          ? l10n.priceChipEmpty(item.name)
          : l10n.priceChipSet(item.name, spoken),
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The row's whole height is the tap target; the hex sits in it.
        child: Center(
          child: Container(
            key: ValueKey('price-chip-${item.id}'),
            height: height,
            padding: const EdgeInsets.symmetric(
              horizontal: HlHex.tip * height + HlSpace.s1,
            ),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: amount == null ? t.surface : t.surfaceRaised,
              shape: HexBorder(
                side: BorderSide(
                  color: amount == null ? t.textMuted : t.border,
                  width: HlBorder.width,
                ),
              ),
            ),
            child: amount == null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Icon(Icons.add, size: 16, color: t.textMuted),
                      Text(l10n.priceAdd, style: label),
                    ],
                  )
                : Text(amount, style: label),
          ),
        ),
      ),
    );
  }
}

/// The open row's price editor: the price, the scale weight or volume for
/// a price per kg or l or a stepper for pieces, whether the price is the
/// line's total or per unit, the unit, one line with the other value, the
/// total after it and last time's, and Fertig. Saved on Fertig or Enter;
/// the total moves only then. Escape or Abbrechen closes it.
class const PricePanel({
  required final Item item,

  /// The household's currency.
  required final String currency,
  required final DateTime now,

  /// The list's total as shown, in cents.
  required final int total,

  /// The household's items, for last time's price.
  required final Iterable<Item> household,

  /// The price to save (null clears it), and the quantity when it changes.
  required final void Function(Price? price, SetTo<String?>? quantity) onSave,
  required final VoidCallback onClose,
  super.key,
}) extends StatefulWidget {
  @override
  State<PricePanel> createState() => _PricePanelState();
}

class _PricePanelState() extends State<PricePanel> with WidgetsBindingObserver {
  final _price = TextEditingController();
  final _amount = TextEditingController();
  late final Measure _measure = measureOf(widget.item.quantity);
  late PricePer _per;
  late PriceBasis _basis;
  late int _count;
  var _tried = false;

  /// The price field as it opened, null before; saved unchanged, the
  /// stored unit price stays exact.
  String? _prefill;

  Price? get _today => switch (widget.item.currentPrice(widget.now)) {
    final p? when p.currency == widget.currency => p,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final today = _today;
    _per = today?.per ?? perFor(_measure);
    _basis = today?.basis ?? PriceBasis.unit;
    _count = switch (_measure) {
      Pieces(:final count) => count,
      _ => 1,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefill != null) {
      return;
    }
    final locale = moneyLocale(context);
    if (_measure
        case Grams(grams: final milli) || Millilitres(ml: final milli)) {
      _amount.text = milliText(milli, locale);
    }
    final today = _today;
    final line = widget.item.lineCentsNow;
    _price.text = switch ((today, _basis)) {
      (final p?, PriceBasis.unit) => amountText(
        microsToCents(p.unitMicros),
        locale,
      ),
      (_?, PriceBasis.line) when line != null => amountText(line, locale),
      _ => '',
    };
    _prefill = _price.text;
  }

  /// The keyboard rising shrinks the list: the editor stays in view.
  @override
  void didChangeMetrics() => _revealAfterFrame();

  void _revealAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());

  /// Scrolls the whole editor into view: below the pinned header and above
  /// the bars over the list's bottom (the total), which the list's
  /// bottom padding tells.
  void _reveal() {
    if (!mounted) {
      return;
    }
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (box == null || scrollable == null) {
      return;
    }
    final viewport = RenderAbstractViewport.of(box);
    final position = scrollable.position;
    final covered = MediaQuery.paddingOf(scrollable.context).bottom;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final end = viewport.getOffsetToReveal(box, 1).offset + covered;
    // Too tall for the room: its top (the name and the price) wins.
    final to = (top < end ? top : position.pixels.clamp(end, top)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((to - position.pixels).abs() >= 1) {
      position.jumpTo(to);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _price.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _measured => _per != PricePer.piece;

  /// The quantity is a count the stepper may change.
  bool get _steppable => switch (_measure) {
    Pieces(rest: _?) => true,
    _ => false,
  };

  /// Pieces, or g or ml for a price per kg or l; null for no valid amount.
  int? get _quantity => _measured
      ? switch (parseAmount(_amount.text)) {
          AmountOk(:final milli) => milli,
          _ => null,
        }
      : _count;

  ({int unitMicros, int line})? get _split {
    final quantity = _quantity;
    if (quantity == null) {
      return null;
    }
    final today = _today;
    // Opened and saved as it was: the stored unit price, not one read back
    // from rounded cents.
    if (today != null &&
        _price.text == _prefill &&
        today.basis == _basis &&
        today.per == _per) {
      final line = lineCents(today.unitMicros, _per, quantity);
      return (unitMicros: today.unitMicros, line: line);
    }
    return switch (parsePrice(_price.text)) {
      PriceOk(:final cents) => priceSplit(cents, _basis, _per, quantity),
      _ => null,
    };
  }

  /// A total reopened untouched follows a new quantity: the unit price
  /// stays (t833u), so the field shows the line it now makes.
  void _followQuantity() {
    final today = _today;
    final quantity = _quantity;
    if (today == null ||
        quantity == null ||
        _basis != PriceBasis.line ||
        today.basis != PriceBasis.line ||
        today.per != _per ||
        _price.text != _prefill) {
      return;
    }
    _price.text = amountText(
      lineCents(today.unitMicros, _per, quantity),
      moneyLocale(context),
    );
    _prefill = _price.text;
  }

  void _setPer(PricePer per) => setState(() {
    if (per != _per) {
      _amount.text = switch ((per, _measure)) {
        (PricePer.kg, Grams(:final grams)) => milliText(
          grams,
          moneyLocale(context),
        ),
        (PricePer.l, Millilitres(:final ml)) => milliText(
          ml,
          moneyLocale(context),
        ),
        _ => '',
      };
      if (per == PricePer.piece && _measure is! Pieces) {
        _count = 1;
      }
    }
    _per = per;
    _tried = false;
  });

  void _save() {
    setState(() => _tried = true);
    final split = _split;
    final quantity = _quantity;
    if (split == null || quantity == null) {
      return;
    }
    final text = _measured
        ? measureQuantity(_per, quantity)
        : switch (_measure) {
            Pieces(:final count) when count == quantity => widget.item.quantity,
            // The stepper changes the number alone: "2 x 500 g" becomes
            // "3 x 500 g".
            Pieces(:final rest?) => '$quantity$rest',
            // No count to change ("500 g" priced per piece, "1/2"): no
            // stepper, and the quantity stays as written.
            _ => widget.item.quantity,
          };
    widget.onSave(
      Price(
        unitMicros: split.unitMicros,
        basis: _basis,
        per: _per,
        currency: widget.currency,
        pricedAt: widget.now,
      ),
      text == widget.item.quantity ? null : SetTo(text),
    );
  }

  String _money(int cents) => formatMoney(
    cents,
    currency: widget.currency,
    locale: moneyLocale(context),
  );

  String? _priceError(AppLocalizations l10n) {
    if (!_tried) {
      return null;
    }
    return switch (parsePrice(_price.text)) {
      PriceEmpty() || PriceInvalid() => l10n.priceErrorEmpty,
      PriceTooLarge() => l10n.priceErrorTooLarge(
        _money(minPriceCents),
        _money(maxPriceCents),
      ),
      PriceOk() when _quantity != null && _split == null =>
        l10n.priceErrorTooLarge(_money(minPriceCents), _money(maxPriceCents)),
      PriceOk() => null,
    };
  }

  String? _amountError(AppLocalizations l10n) {
    if (!_tried || !_measured) {
      return null;
    }
    final litres = _per == PricePer.l;
    return switch (parseAmount(_amount.text)) {
      AmountEmpty() ||
      AmountInvalid() => litres ? l10n.volumeErrorEmpty : l10n.weightErrorEmpty,
      AmountZero() => litres ? l10n.volumeErrorZero : l10n.weightErrorZero,
      AmountTooLarge() =>
        litres ? l10n.volumeErrorTooLarge : l10n.weightErrorTooLarge,
      AmountOk() => null,
    };
  }

  /// The other value than the typed one, the total after it and last
  /// time's.
  String? _hint(AppLocalizations l10n) {
    final split = _split;
    if (split == null) {
      return null;
    }
    final item = widget.item;
    final before = item.summedCents(widget.currency, widget.now) ?? 0;
    final last = lastPrice(
      item,
      widget.household,
      currency: widget.currency,
      per: _per,
      now: widget.now,
    );
    final change = last == null ? null : compareToLast(split.unitMicros, last);
    return [
      if (_basis == PriceBasis.unit)
        l10n.priceTogether(_money(split.line))
      else
        l10n.priceUnitIs(
          _money(microsToCents(split.unitMicros)),
          perLabel(l10n, _per),
        ),
      l10n.priceTotalAfter(_money(widget.total - before + split.line)),
      if (change != null)
        switch (change.trend) {
          Trend.dearer => l10n.priceDearer(_money(change.cents)),
          Trend.cheaper => l10n.priceCheaper(_money(change.cents)),
          Trend.same => l10n.priceSame,
        },
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // A hint or an error line may have made it taller.
    _revealAfterFrame();
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final priceError = _priceError(l10n);
    final amountError = _amountError(l10n);
    final hint = _hint(l10n);
    final symbol = currencySymbol(widget.currency, moneyLocale(context));
    Widget field({
      required String label,
      required TextEditingController controller,
      required TextInputFormatter formatter,
      required String suffix,
      required String? error,
      required bool signed,
      bool autofocus = false,
      Key? key,
    }) => Semantics(
      label: label,
      hint: error ?? '',
      child: TextField(
        key: key,
        autofillHints: null,
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: signed,
        ),
        inputFormatters: [formatter],
        textInputAction: TextInputAction.done,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: t.text,
          fontFeatures: _figures,
        ),
        decoration: InputDecoration(
          isDense: true,
          suffixText: suffix,
          error: error == null ? null : FieldError(error),
        ),
        onChanged: (_) => setState(() {
          _tried = false;
          _followQuantity();
        }),
        onSubmitted: (_) => _save(),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      // Named after the item, so a screen reader announces whose price the
      // controls set, not the hint line's text.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.priceChipEmpty(widget.item.name),
        child: ColoredBox(
          key: ValueKey('price-panel-${widget.item.id}'),
          color: t.honeySoft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HlSpace.s4,
              HlSpace.s1,
              HlSpace.s4,
              HlSpace.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: HlSpace.s2,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: HlSpace.s2,
                  children: [
                    Expanded(
                      child: field(
                        key: const ValueKey('price-field'),
                        label: l10n.priceField,
                        controller: _price,
                        formatter: DecimalInputFormatter.price,
                        suffix: symbol,
                        error: priceError,
                        signed: true,
                        autofocus: true,
                      ),
                    ),
                    if (_measured)
                      SizedBox(
                        width: 128,
                        child: field(
                          key: const ValueKey('amount-field'),
                          label: _per == PricePer.l
                              ? l10n.volumeField
                              : l10n.weightField,
                          controller: _amount,
                          formatter: DecimalInputFormatter.amount,
                          suffix: _per == PricePer.l
                              ? l10n.priceUnitLitre
                              : l10n.priceUnitKg,
                          error: amountError,
                          signed: false,
                        ),
                      )
                    else if (_steppable)
                      _Stepper(
                        count: _count,
                        onChanged: (count) => setState(() {
                          _count = count;
                          _followQuantity();
                        }),
                      ),
                  ],
                ),
                Row(
                  spacing: HlSpace.s2,
                  children: [
                    Expanded(
                      child: HexSegmented<PriceBasis>(
                        key: const ValueKey('price-basis'),
                        label: l10n.priceBasisLabel,
                        value: _basis,
                        onChanged: (basis) => setState(() => _basis = basis),
                        segments: [
                          HexSegment(
                            value: PriceBasis.line,
                            label: l10n.priceLine,
                          ),
                          HexSegment(
                            value: PriceBasis.unit,
                            label: perLabel(l10n, _per),
                          ),
                        ],
                      ),
                    ),
                    _UnitMenu(per: _per, onChanged: _setPer),
                  ],
                ),
                if (hint != null)
                  Text(
                    hint,
                    key: const ValueKey('price-hint'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textMuted,
                      fontFeatures: _figures,
                    ),
                  ),
                // Large text puts the buttons on two lines, never off screen.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: HlSpace.s2,
                  runSpacing: HlSpace.s2,
                  children: [
                    // An icon: three labelled buttons do not fit 358 px.
                    if (widget.item.price != null)
                      IconButton(
                        key: const ValueKey('price-remove'),
                        onPressed: () => widget.onSave(null, null),
                        icon: Icon(
                          Icons.delete_outline,
                          semanticLabel: l10n.priceRemove,
                        ),
                      ),
                    OutlinedButton(
                      key: const ValueKey('price-cancel'),
                      onPressed: widget.onClose,
                      child: Text(l10n.cancel),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('price-done'),
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.done),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _Stepper({
  required final int count,
  required final ValueChanged<int> onChanged,
}) extends StatelessWidget {
  static const _most = 99;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Container(
      height: HlSize.target,
      decoration: ShapeDecoration(
        color: t.surfaceRaised,
        shape: HexBorder(
          side: BorderSide(color: t.border, width: HlBorder.width),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('price-count-less'),
            tooltip: l10n.priceCountLess,
            icon: const Icon(Icons.remove),
            onPressed: count > 1 ? () => onChanged(count - 1) : null,
          ),
          Semantics(
            label: l10n.priceCount(count),
            excludeSemantics: true,
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: t.text,
                fontFeatures: _figures,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('price-count-more'),
            tooltip: l10n.priceCountMore,
            icon: const Icon(Icons.add),
            onPressed: count < _most ? () => onChanged(count + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Stück, kg or l: what the price is per.
class const _UnitMenu({
  required final PricePer per,
  required final ValueChanged<PricePer> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    String name(PricePer per) => switch (per) {
      PricePer.piece => l10n.priceUnitPiece,
      PricePer.kg => l10n.priceUnitKg,
      PricePer.l => l10n.priceUnitLitre,
    };
    return PopupMenuButton<PricePer>(
      key: const ValueKey('price-unit'),
      // No tooltip: the label below names the menu, and a web Tooltip
      // re-parents the route's semantics and blurs the price field.
      tooltip: '',
      useRootNavigator: true,
      initialValue: per,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in PricePer.values)
          PopupMenuItem(value: option, child: Text(name(option))),
      ],
      child: Semantics(
        label: '${l10n.priceUnitLabel}: ${name(per)}',
        excludeSemantics: true,
        child: Container(
          height: HlSize.target,
          padding: const EdgeInsetsDirectional.only(
            start: HlHex.tip * HlSize.target + HlSpace.s1,
            end: HlHex.tip * HlSize.target,
          ),
          decoration: ShapeDecoration(
            color: t.surfaceRaised,
            shape: HexBorder(
              side: BorderSide(color: t.border, width: HlBorder.width),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name(per),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: t.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list's running total under the list (job 190): "Einkaufssumme",
/// how many items have a price and how many open ones have none, and the
/// sum in the household's currency. With `list-declutter` the list's
/// `SummaryBlock` shows it instead (jobs 229, 237).
class const TotalBar({super.key}) extends StatelessWidget {
  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final cubit = context.watch<ListCubit>();
    final trip = cubit.trip;
    if (trip.priced > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          cubit.totalViewed();
        }
      });
    }
    final amount = formatMoney(
      trip.cents,
      currency: cubit.state.catalog.currency,
      locale: moneyLocale(context),
    );
    return Semantics(
      key: const ValueKey('total-bar'),
      container: true,
      label: l10n.tripTotalLabel(amount, trip.priced, trip.open),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: TotalBar.height),
        padding: const EdgeInsets.symmetric(
          horizontal: HlSpace.s4,
          vertical: HlSpace.s1,
        ),
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          border: Border(
            top: BorderSide(color: t.border, width: HlBorder.width),
          ),
        ),
        child: Row(
          spacing: HlSpace.s3,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tripTotal,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                    ),
                  ),
                  Text(
                    l10n.tripCounts(trip.priced, trip.open),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: t.textMuted,
                      fontFeatures: _figures,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              amount,
              key: const ValueKey('total-amount'),
              style: TextStyle(
                fontFamily: HlFont.display,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: t.text,
                fontFeatures: _figures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A store section's sum at its end: "Summe Lidl 6,06 €".
class const StoreSubtotal({
  required final String store,
  required final int cents,
  required final String currency,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HlSpace.s4, HlSpace.s2, HlSpace.s4, 0),
      child: Text(
        l10n.storeSubtotal(
          store,
          formatMoney(cents, currency: currency, locale: moneyLocale(context)),
        ),
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: t.textMuted,
          fontFeatures: _figures,
        ),
      ),
    );
  }
}
