import 'dart:math' as math;

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the user changed, never empty; null when they cancel, dismiss, or
/// save without a change.
Future<ItemChanges?> showEditItemSheet(
  BuildContext context, {
  required Item item,
  required Catalog catalog,
  required Future<Store?> Function(String name) onCreateStore,
}) => showModalBottomSheet<ItemChanges>(
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
  ),
);

class const _EditItemSheet({
  required final Item item,
  required final Catalog catalog,
  required final Future<Store?> Function(String name) onCreateStore,
}) extends StatefulWidget {
  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState() extends State<_EditItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _brand = TextEditingController(text: widget.item.brand);
  late final _quantity = TextEditingController(text: widget.item.quantity);

  // The fields move between one row and two as the width changes (turning
  // the phone); global keys carry their focus across.
  final _brandField = GlobalKey();
  final _quantityField = GlobalKey();
  late final _properties = TextEditingController(text: widget.item.properties);

  /// A store that is gone from the catalog shows, and compares, as none.
  late final String? _originalStore = widget.catalog
      .store(widget.item.storeId ?? '')
      ?.id;
  late String? _storeId = _originalStore;
  late String? _categoryId = widget.item.categoryId;

  /// The catalog as opened, plus the stores made in the sheet.
  late Catalog _catalog = widget.catalog;

  Future<Store?> _createStore(String name) async {
    final store = await widget.onCreateStore(name);
    if (store != null && mounted && _catalog.store(store.id) == null) {
      setState(() => _catalog = _catalog.withStore(store));
    }
    return store;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _quantity.dispose();
    _properties.dispose();
    super.dispose();
  }

  /// What differs from the item, trimmed; an empty field is null.
  ItemChanges _changes() {
    final item = widget.item;
    String? orNull(String text) => text.trim().isEmpty ? null : text.trim();
    SetTo<String?>? changed(String? now, String? before) =>
        now == before ? null : SetTo(now);
    final name = _name.text.trim();
    return ItemChanges(
      name: name == item.name ? null : name,
      quantity: changed(orNull(_quantity.text), item.quantity),
      brand: changed(orNull(_brand.text), item.brand),
      properties: changed(orNull(_properties.text), item.properties),
      categoryId: _categoryId == item.categoryId ? null : _categoryId,
      storeId: changed(_storeId, _originalStore),
    );
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      return;
    }
    final changes = _changes();
    Navigator.of(context).pop(changes.isEmpty ? null : changes);
  }

  void _step({required bool up}) {
    if (stepQuantity(_quantity.text, up: up) case final next?) {
      _quantity.text = next;
    }
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final brand = KeyedSubtree(
                          key: _brandField,
                          child: _Field(
                            fieldKey: 'edit-brand',
                            label: l10n.fieldBrand,
                            hint: l10n.brandNone,
                            controller: _brand,
                            maxLength: 60,
                            onSubmitted: _save,
                          ),
                        );
                        final quantity = KeyedSubtree(
                          key: _quantityField,
                          child: _Field(
                            fieldKey: 'edit-quantity',
                            label: l10n.itemQuantity,
                            controller: _quantity,
                            maxLength: 40,
                            narrow: true,
                            onSubmitted: _save,
                          ),
                        );
                        final steppers = ValueListenableBuilder(
                          valueListenable: _quantity,
                          builder: (context, value, _) {
                            final text = value.text;
                            if (stepQuantity(text, up: true) == null) {
                              return const SizedBox.shrink();
                            }
                            final canLower =
                                stepQuantity(text, up: false) != null;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: _stepperGap,
                              children: [
                                _Stepper(
                                  key: const ValueKey('edit-quantity-minus'),
                                  icon: Icons.remove,
                                  label: l10n.quantityMinus,
                                  onPressed: canLower
                                      ? () => _step(up: false)
                                      : null,
                                ),
                                _Stepper(
                                  key: const ValueKey('edit-quantity-plus'),
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
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            spacing: _rowGap,
                            children: [
                              Expanded(child: brand),
                              SizedBox(width: _quantityWidth, child: quantity),
                              steppers,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: _rowGap,
                          children: [
                            brand,
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              spacing: _rowGap,
                              children: [
                                Expanded(child: quantity),
                                steppers,
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    _Field(
                      fieldKey: 'edit-properties',
                      label: l10n.fieldProperties,
                      hint: l10n.propertiesExample,
                      controller: _properties,
                      maxLength: 120,
                      onSubmitted: _save,
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
                    onStore: (id) => setState(() => _storeId = id),
                    onCategory: (id) => setState(() => _categoryId = id),
                  ),
                ),
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

const _rowGap = 10.0;
const _quantityWidth = 72.0;
const _stepperWidth = 56.0;
const _stepperGap = 4.0;

/// Room a brand needs, in ems of its scaled 18 px text: Weihenstephan
/// takes 7.8 in Inter, caret included.
const _brandEms = 8;

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
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.standard,
      fixedSize: const Size(_stepperWidth, HlSize.target),
      minimumSize: const Size(_stepperWidth, HlSize.target),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Icon(icon, size: 22, semanticLabel: label),
  );
}
