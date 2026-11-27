import 'dart:math' as math;

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/compact_details.dart'
    show QuantityGroup, QuantitySemantics;
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/place_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// What the user changed in the edit sheet, never nothing: the item's
/// columns, its list (job 169b K) and their "Ich bringe das" (job 169b L).
@immutable
class const ItemEdit({
  final ItemChanges changes = const ItemChanges(),

  /// The list it goes to; null when it stays.
  final String? listId,

  /// Null when the user's claim stays as it was.
  final ClaimChange? claim,

  /// Its new place in its store's learned order (job 352); null when it
  /// stays.
  final Placement? place,
}) {
  bool get isEmpty =>
      changes.isEmpty && listId == null && claim == null && place == null;
}

/// The fields [editSaid] names.
enum _Said() {
  name,
  brand,
  quantity,
  details,
  store,
  category,
}

/// What a screen reader hears once the sheet saved [edit] (job 474): what
/// was set, „Name auf Kosmetiktücher, Menge auf 2 und Laden auf Edeka
/// geändert“, then what was emptied, „Marke entfernt“, in the sheet's order;
/// then a new place, „Neben Milch gesetzt“, and a new list, „Auf die Liste
/// Party verschoben“.
/// Nothing when only the claim changed, whose checkbox said it already.
/// [catalog] is the one after the save, with a store made in the sheet.
List<String> editSaid(
  AppLocalizations l10n,
  ItemEdit edit, {
  required Catalog catalog,
  List<Item>? placeRun,
}) {
  final ItemEdit(:changes, :listId, :place) = edit;
  final set = <String>[];
  final removed = <String>[];
  void said(_Said field, SetTo<String?>? change) {
    switch (change) {
      case SetTo(value: final value?):
        set.add(l10n.editSaidSet(field.name, value));
      case SetTo(value: null):
        removed.add(l10n.editSaidField(field.name));
      case null:
    }
  }

  said(_Said.name, switch (changes.name) {
    final name? => SetTo(name),
    null => null,
  });
  said(_Said.brand, changes.brand);
  said(_Said.quantity, changes.quantity);
  said(_Said.details, changes.properties);
  said(_Said.store, switch (changes.storeId) {
    SetTo(value: final id?) => switch (catalog.store(id)) {
      final store? => SetTo(store.name),
      null => null,
    },
    final cleared => cleared,
  });
  said(_Said.category, switch (catalog.categories
      .where((c) => c.id == changes.categoryId)
      .firstOrNull) {
    final category? => SetTo(category.name),
    null => null,
  });
  // Where it went has its own words: „Neben Milch gesetzt“, not „Platz
  // auf neben Milch“ (review 1).
  final placed = switch (place) {
    PlaceFirst() => l10n.editSaidPlaceFirst,
    PlaceAfter(:final anchorId) => switch (placeRun
        ?.where((i) => i.id == anchorId)
        .firstOrNull) {
      final anchor? => l10n.editSaidPlaceNextTo(anchor.name),
      null => null,
    },
    null => null,
  };
  final moved = switch (catalog.list(listId)) {
    final list? when listId != null => l10n.editSaidList(listName(list, l10n)),
    _ => null,
  };
  String and(List<String> parts) => parts.length == 1
      ? parts.single
      : l10n.editSaidAnd(
          parts.sublist(0, parts.length - 1).join(', '),
          parts.last,
        );
  return [
    if (set.isNotEmpty) l10n.editSaidChanged(and(set)),
    if (removed.isNotEmpty) l10n.editSaidRemoved(and(removed)),
    ?placed,
    ?moved,
  ];
}

/// The user's claim, said or taken back in the edit sheet.
sealed class const ClaimChange();

/// "Ich bringe das", with the amount or none.
final class const Claimed([final String? quantity]) extends ClaimChange;

final class const Unclaimed() extends ClaimChange;

/// What the user changed; null when they cancel, dismiss, or save without
/// a change. With two or more lists in [catalog] the sheet offers them,
/// [listId] picked. [myClaim] is the user's own claim on the item, if any;
/// [othersBring] says who else brings it.
Future<ItemEdit?> showEditItemSheet(
  BuildContext context, {
  required Item item,
  required Catalog catalog,
  required Future<Store?> Function(String name) onCreateStore,
  String? listId,
  Claim? myClaim,
  String? othersBring,

  /// A new store's chain, offered and asked as in the add sheet (job 313,
  /// flag open-store-app); null without the flag.
  StoreChains? chains,

  /// The add sheet's − Menge + in one hex (job 340, flag add-sheet-compact).
  bool hexQuantity = false,

  /// The category chip; off with flag `hide-categories`.
  bool categories = true,

  /// The learned order (job 352): the item's section, its open items in walk
  /// order, the item among them. The place chip („Neben …“) then stands
  /// where the category chip would; null without it.
  List<Item>? placeRun,
}) => showModalBottomSheet<ItemEdit>(
  context: context,
  // Over the whole app, tabs included: the sheet stands on the bottom edge.
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          curve: HlEasing.standard,
          reverseCurve: HlEasing.exit,
          duration: HlDuration.medium,
          reverseDuration: HlDuration.short,
        ),
  builder: (_) => _EditItemSheet(
    item: item,
    catalog: catalog,
    onCreateStore: onCreateStore,
    listId: listId,
    myClaim: myClaim,
    othersBring: othersBring,
    chains: chains,
    hexQuantity: hexQuantity,
    categories: categories,
    placeRun: placeRun,
  ),
);

class const _EditItemSheet({
  required final Item item,
  required final Catalog catalog,
  required final Future<Store?> Function(String name) onCreateStore,
  required final String? listId,
  required final Claim? myClaim,
  required final String? othersBring,
  required final StoreChains? chains,
  required final bool hexQuantity,
  required final bool categories,
  required final List<Item>? placeRun,
}) extends StatefulWidget {
  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState() extends State<_EditItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _brand = TextEditingController(text: widget.item.brand);
  late final _quantity = TextEditingController(text: widget.item.quantity);
  late final _properties = TextEditingController(text: widget.item.properties);
  late final _claimAmount = TextEditingController(
    text: widget.myClaim?.quantity,
  );
  late var _claiming = widget.myClaim != null;
  late String? _listId = widget.listId;

  /// A store that is gone from the catalog shows, and compares, as none.
  late final String? _originalStore = widget.catalog
      .store(widget.item.storeId ?? '')
      ?.id;
  late String? _storeId = _originalStore;
  late String? _categoryId = widget.item.categoryId;

  late final Placement? _placedAt = switch (widget.placeRun) {
    final run? => placementIn(run, widget.item.id),
    null => null,
  };

  /// The place picked in the sheet; null while it stays.
  Placement? _place;

  /// The catalog as opened, plus the stores made in the sheet.
  late Catalog _catalog = widget.catalog;

  Future<Store?> _createStore(String name) async {
    final store = await widget.onCreateStore(name);
    if (store != null && mounted && _catalog.store(store.id) == null) {
      setState(() => _catalog = _catalog.withStore(store));
    }
    return store;
  }

  /// The chains passed in, with a linked store made here added to the sheet's
  /// catalog like [_createStore]'s.
  late final StoreChains? _chains = switch (widget.chains) {
    final chains? => StoreChains(
      match: chains.match,
      addLinked: (name, retailer) async {
        final store = await chains.addLinked(name, retailer);
        if (store != null && mounted && _catalog.store(store.id) == null) {
          setState(() => _catalog = _catalog.withStore(store));
        }
        return store;
      },
      link: chains.link,
      decline: chains.decline,
    ),
    null => null,
  };

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _quantity.dispose();
    _properties.dispose();
    _claimAmount.dispose();
    super.dispose();
  }

  /// What differs from the item, trimmed; an empty field is null.
  ItemChanges _changes() {
    final item = widget.item;
    SetTo<String?>? changed(String? now, String? before) =>
        now == before ? null : SetTo(now);
    final name = _name.text.trim();
    return ItemChanges(
      name: name == item.name ? null : name,
      quantity: changed(fieldValue(_quantity.text), item.quantity),
      brand: changed(fieldValue(_brand.text), item.brand),
      properties: changed(fieldValue(_properties.text), item.properties),
      categoryId: _categoryId == item.categoryId ? null : _categoryId,
      storeId: changed(_storeId, _originalStore),
    );
  }

  /// The claim as the user left it, if it differs from [_EditItemSheet.
  /// myClaim].
  ClaimChange? _claim() {
    final amount = _claimAmount.text.trim();
    final quantity = amount.isEmpty ? null : amount;
    return switch ((widget.myClaim, _claiming)) {
      (null, false) => null,
      (_?, false) => const Unclaimed(),
      (final mine?, true) when mine.quantity == quantity => null,
      (_, true) => Claimed(quantity),
    };
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      return;
    }
    final edit = ItemEdit(
      changes: _changes(),
      listId: _listId == widget.listId ? null : _listId,
      claim: _claim(),
      // Placed in its old store's order: a new store gives it its place
      // there.
      place: _storeId == _originalStore && _place != _placedAt ? _place : null,
    );
    Navigator.of(context).pop(edit.isEmpty ? null : edit);
  }

  /// The place chip and its options, in the item's section as opened; none
  /// once another store is picked.
  ChipFold? _placeFold(AppLocalizations l10n) {
    final run = widget.placeRun;
    final at = _place ?? _placedAt;
    if (run == null || at == null || _storeId != _originalStore) {
      return null;
    }
    final label = placementLabel(l10n, at, run);
    return ChipFold(
      chipKey: const ValueKey('chip-place'),
      icon: Icons.swap_vert,
      label: label,
      semanticsLabel: l10n.chipPlace(label),
      panel: (foldBack) => PlaceOptions(
        others: [
          for (final i in run)
            if (i.id != widget.item.id) i,
        ],
        selected: at,
        onPick: (place) {
          setState(() => _place = place);
          foldBack();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.editSheet,
        child: SingleChildScrollView(
          child: Column(
            key: const ValueKey('edit-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(HlRadius.full),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    _Field(
                      fieldKey: 'edit-name',
                      label: l10n.fieldName,
                      controller: _name,
                      maxLength: 120,
                      bold: true,
                      onSubmitted: _save,
                    ),
                    ItemDetailFields(
                      brand: _brand,
                      quantity: _quantity,
                      properties: _properties,
                      onSubmitted: _save,
                      hexQuantity: widget.hexQuantity,
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HlSpace.s4,
                    HlSpace.s2,
                    HlSpace.s4,
                    10,
                  ),
                  child: FoldoutChips(
                    catalog: _catalog,
                    storeId: _storeId,
                    categoryId: _categoryId,
                    storeLabel: l10n.noStore,
                    categoryLabel: l10n.categoryAuto,
                    chipIcons: false,
                    storeChanged: _storeId != _originalStore,
                    categoryChanged: _categoryId != widget.item.categoryId,
                    onCreateStore: _createStore,
                    chains: _chains,
                    onStore: (id) => setState(() => _storeId = id),
                    onCategory: widget.categories && widget.placeRun == null
                        ? (id) => setState(() => _categoryId = id)
                        : null,
                    fold: _placeFold(l10n),
                  ),
                ),
              ),
              if (widget.catalog.lists.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: LabeledField(
                    label: l10n.editList,
                    field: Wrap(
                      key: const ValueKey('edit-list'),
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final list in widget.catalog.lists)
                          OptionChip(
                            key: ValueKey('edit-list-${list.id}'),
                            label: listName(list, l10n),
                            selected: list.id == _listId,
                            onTap: () => setState(() => _listId = list.id),
                          ),
                      ],
                    ),
                  ),
                ),
              if (widget.item.status == ItemStatus.active)
                _ClaimArea(
                  claiming: _claiming,
                  amount: _claimAmount,
                  othersBring: widget.othersBring,
                  onClaiming: (on) => setState(() => _claiming = on),
                  onSubmitted: _save,
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  HlSpace.s4,
                  10,
                  HlSpace.s4,
                  HlSpace.s4 + math.max(0, media.padding.bottom - keyboard),
                ),
                // Large text stacks Fertig over Abbrechen.
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowDirection: VerticalDirection.up,
                  children: [
                    TextButton(
                      key: const ValueKey('edit-cancel'),
                      style: TextButton.styleFrom(
                        // Desktop defaults to compact density, which
                        // shrinks targets under 44 px.
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        textStyle: const TextStyle(
                          fontFamily: HlFont.sans,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _name,
                      builder: (context, value, _) => FilledButton(
                        key: const ValueKey('edit-done'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.standard,
                          minimumSize: const Size(132, 52),
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          textStyle: const TextStyle(
                            fontFamily: HlFont.sans,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: value.text.trim().isEmpty ? null : _save,
                        child: Text(l10n.done),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The value an item's text field stands for: trimmed, an empty field is
/// none. The edit sheet and the add sheet's details read their fields so.
String? fieldValue(String text) => text.trim().isEmpty ? null : text.trim();

/// Marke, Menge with its steppers, and Eigenschaften: the edit sheet's
/// fields under the name, also the add sheet's details of the item just
/// added (job 276). [onStep] follows a stepper's change of [quantity].
class const ItemDetailFields({
  required final TextEditingController brand,
  required final TextEditingController quantity,
  required final TextEditingController properties,
  required final VoidCallback onSubmitted,
  final VoidCallback? onStep,

  /// Menge as the compact add sheet's hex group instead of the field with
  /// side steppers (job 340).
  final bool hexQuantity = false,

  /// Starts the fields' keys: `edit-brand`, `edit-quantity`, ….
  final String keyPrefix = 'edit',

  /// Lays the fields out in one line instead (the add sheet's details, job
  /// 288): Menge and its steppers, what [inLine] puts between them and the
  /// rest (the store and category chips), then Marke and Eigenschaften. It
  /// gets the controls before and after and returns the line.
  final Widget Function(List<Widget> before, List<Widget> after)? inLine,
  super.key,
}) extends StatefulWidget {
  @override
  State<ItemDetailFields> createState() => _ItemDetailFieldsState();
}

class _ItemDetailFieldsState() extends State<ItemDetailFields> {
  // The fields move between one row and two as the width changes (turning
  // the phone); global keys carry their focus across.
  final _brandField = GlobalKey();
  final _quantityField = GlobalKey();

  void _step({required bool up}) {
    if (stepQuantity(widget.quantity.text, up: up) case final next?) {
      widget.quantity.text = next;
      widget.onStep?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ItemDetailFields(
      :brand,
      :quantity,
      :properties,
      :onSubmitted,
      :keyPrefix,
      :inLine,
      :hexQuantity,
    ) = widget;
    if (inLine != null) {
      return _line(context, l10n, inLine);
    }
    Widget adjustable(Widget child) => QuantitySemantics(
      controller: quantity,
      onStep: _step,
      identifier: '$keyPrefix-quantity-stepper',
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (hexQuantity) ...[
          _Field(
            fieldKey: '$keyPrefix-brand',
            label: l10n.fieldBrand,
            hint: l10n.brandNone,
            controller: brand,
            maxLength: 60,
            onSubmitted: onSubmitted,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: QuantityGroup(
              keyPrefix: keyPrefix,
              controller: quantity,
              onStep: widget.onStep ?? () {},
              onSubmitted: onSubmitted,
            ),
          ),
        ] else
          LayoutBuilder(
            builder: (context, constraints) {
              final brandField = KeyedSubtree(
                key: _brandField,
                child: _Field(
                  fieldKey: '$keyPrefix-brand',
                  label: l10n.fieldBrand,
                  hint: l10n.brandNone,
                  controller: brand,
                  maxLength: 60,
                  onSubmitted: onSubmitted,
                ),
              );
              final quantityField = KeyedSubtree(
                key: _quantityField,
                child: _Field(
                  fieldKey: '$keyPrefix-quantity',
                  label: l10n.itemQuantity,
                  controller: quantity,
                  maxLength: 40,
                  narrow: true,
                  onSubmitted: onSubmitted,
                ),
              );
              final steppers = ValueListenableBuilder(
                valueListenable: quantity,
                builder: (context, value, _) {
                  final text = value.text;
                  if (stepQuantity(text, up: true) == null) {
                    return const SizedBox.shrink();
                  }
                  final canLower = stepQuantity(text, up: false) != null;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: _stepperGap,
                    children: [
                      _Stepper(
                        key: ValueKey('$keyPrefix-quantity-minus'),
                        icon: Icons.remove,
                        label: l10n.quantityMinus,
                        onPressed: canLower ? () => _step(up: false) : null,
                      ),
                      _Stepper(
                        key: ValueKey('$keyPrefix-quantity-plus'),
                        icon: Icons.add,
                        label: l10n.quantityPlus,
                        onPressed: () => _step(up: true),
                      ),
                    ],
                  );
                },
              );
              if (_fitsOneRow(
                context,
                constraints.maxWidth,
                l10n.itemQuantity,
              )) {
                final menge = SizedBox(
                  width: _quantityWidth,
                  child: quantityField,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: _rowGap,
                  children: [
                    Expanded(child: brandField),
                    adjustable(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: _rowGap,
                        children: [menge, steppers],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _rowGap,
                children: [
                  brandField,
                  adjustable(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: _rowGap,
                      children: [
                        Expanded(child: quantityField),
                        steppers,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        _Field(
          fieldKey: '$keyPrefix-properties',
          label: l10n.fieldProperties,
          hint: l10n.propertiesExample,
          controller: properties,
          maxLength: 120,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }

  Widget _line(
    BuildContext context,
    AppLocalizations l10n,
    Widget Function(List<Widget> before, List<Widget> after) inLine,
  ) {
    final ItemDetailFields(
      :brand,
      :quantity,
      :properties,
      :onSubmitted,
      :keyPrefix,
    ) = widget;
    final ems = MediaQuery.textScalerOf(context).scale(18);
    final menge = SizedBox(
      width: _quantityWidth,
      child: _Field(
        fieldKey: '$keyPrefix-quantity',
        label: l10n.itemQuantity,
        controller: quantity,
        maxLength: 40,
        narrow: true,
        onSubmitted: onSubmitted,
      ),
    );
    return inLine(
      [
        // One control with its steppers, so none leaves a gap while they
        // are away.
        QuantitySemantics(
          controller: quantity,
          onStep: _step,
          identifier: '$keyPrefix-quantity-stepper',
          child: ValueListenableBuilder(
            valueListenable: quantity,
            builder: (context, value, menge) => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                menge!,
                if (stepQuantity(value.text, up: true) != null) ...[
                  const SizedBox(width: _rowGap),
                  _Stepper(
                    key: ValueKey('$keyPrefix-quantity-minus'),
                    icon: Icons.remove,
                    label: l10n.quantityMinus,
                    onPressed: stepQuantity(value.text, up: false) != null
                        ? () => _step(up: false)
                        : null,
                  ),
                  const SizedBox(width: _stepperGap),
                  _Stepper(
                    key: ValueKey('$keyPrefix-quantity-plus'),
                    icon: Icons.add,
                    label: l10n.quantityPlus,
                    onPressed: () => _step(up: true),
                  ),
                ],
              ],
            ),
            child: menge,
          ),
        ),
      ],
      [
        SizedBox(
          width: 2 * hexFieldInset + ems * _lineBrandEms,
          child: _Field(
            fieldKey: '$keyPrefix-brand',
            label: l10n.fieldBrand,
            hint: l10n.brandNone,
            controller: brand,
            maxLength: 60,
            onSubmitted: onSubmitted,
          ),
        ),
        SizedBox(
          width: 2 * hexFieldInset + ems * _linePropertiesEms,
          child: _Field(
            fieldKey: '$keyPrefix-properties',
            label: l10n.fieldProperties,
            hint: l10n.propertiesExample,
            controller: properties,
            maxLength: 120,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

/// "Ich bringe das" with who else brings it under it, and once ticked, how
/// much the user brings (optional).
class const _ClaimArea({
  required final bool claiming,
  required final TextEditingController amount,
  required final String? othersBring,
  required final ValueChanged<bool> onClaiming,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: HexCheckboxListTile(
              key: const ValueKey('edit-claim'),
              contentPadding: const EdgeInsetsDirectional.only(
                start: 4,
                end: 8,
              ),
              value: claiming,
              onChanged: onClaiming,
              title: Text(l10n.claimMine),
              subtitle: switch (othersBring) {
                final others? => Text(
                  others,
                  key: const ValueKey('edit-claim-others'),
                ),
                null => null,
              },
            ),
          ),
          if (claiming)
            SizedBox(
              width: 112,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _Field(
                  fieldKey: 'edit-claim-amount',
                  label: l10n.claimAmount,
                  hint: l10n.claimAmountHint,
                  controller: amount,
                  maxLength: 40,
                  narrow: true,
                  onSubmitted: onSubmitted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _rowGap = 10.0;
const _quantityWidth = 72.0;
const _stepperWidth = 56.0;
const _stepperGap = 4.0;

/// Room a brand needs, in ems of its scaled 18 px text: Weihenstephan
/// takes 7.8 in Inter, caret included.
const _brandEms = 8;

/// Marke's and Eigenschaften's widths in the add sheet's line, in ems of
/// their scaled 18 px text: Bärenmarke, and "e.g. organic, 1 l". Longer
/// text scrolls in its field.
const _lineBrandEms = 6;
const _linePropertiesEms = 9;

/// Whether Marke, Menge and its steppers fit one row of [width] at the
/// user's text size: Menge's label within its 72 px, and a brand like
/// Weihenstephan unclipped. Otherwise Marke goes above Menge. The steppers
/// count even while hidden, so typing never moves the fields.
bool _fitsOneRow(BuildContext context, double width, String quantityLabel) {
  final scaler = MediaQuery.textScalerOf(context);
  final label = TextPainter(
    text: TextSpan(
      text: quantityLabel,
      style: DefaultTextStyle.of(context).style.merge(LabeledField.labelStyle),
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final labelFits = label.width <= _quantityWidth - hexFieldInset;
  label.dispose();
  final brandWidth =
      width - _quantityWidth - 2 * _stepperWidth - _stepperGap - 2 * _rowGap;
  final brandFits =
      brandWidth - 2 * hexFieldInset >= scaler.scale(18) * _brandEms;
  return labelFits && brandFits;
}

/// A 48 px field with its label above it.
class const _Field({
  required final String fieldKey,
  required final String label,
  required final TextEditingController controller,
  required final int maxLength,
  required final VoidCallback onSubmitted,
  final String? hint,
  final bool bold = false,

  /// Menge, 72 px wide: its text starts nearer the tip, which the slant
  /// beside a line of text still clears.
  final bool narrow = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LabeledField(
      label: label,
      field: TextField(
        autofillHints: null,
        key: ValueKey(fieldKey),
        controller: controller,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
        style: TextStyle(
          fontSize: 18,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          constraints: const BoxConstraints.tightFor(height: HlSize.target),
          contentPadding: narrow
              ? const EdgeInsets.symmetric(
                  horizontal: HlSpace.s3,
                  vertical: HlSpace.s2,
                )
              : null,
        ),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

/// − or + beside Menge, stepped by screen readers through
/// [QuantitySemantics] instead; on the web a button named [label].
class const _Stepper({
  required final IconData icon,
  required final String label,
  required final VoidCallback? onPressed,
  super.key,
}) extends StatelessWidget {
  /// The theme's outlined button: a raised hex with the contour on its
  /// edge, sinking when pressed. No [Tooltip]: while one shows, its overlay
  /// joins the semantics tree, and on the web that moves the sheet's DOM, so
  /// a click into Menge right after hovering a stepper lost its focus
  /// (job 122).
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !kIsWeb,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.standard,
        fixedSize: const Size(_stepperWidth, HlSize.target),
        minimumSize: const Size(_stepperWidth, HlSize.target),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Icon(icon, size: 22, semanticLabel: label),
    ),
  );
}
