import 'dart:math' as math;

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

sealed class const EditResult();

/// [changes] is never empty.
final class const EditSaved(final ItemChanges changes) extends EditResult;

final class const EditDeleted() extends EditResult;

/// Null when the user cancels, dismisses, or saves without a change.
Future<EditResult?> showEditItemSheet(
  BuildContext context, {
  required Item item,
  required Catalog catalog,
  required Future<Store?> Function(String name) onCreateStore,
}) => showModalBottomSheet<EditResult>(
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
    Navigator.of(context).pop(changes.isEmpty ? null : EditSaved(changes));
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
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  spacing: 4,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.editTitle(widget.item.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('edit-cancel'),
                      style: TextButton.styleFrom(
                        // Desktop defaults to compact density, which
                        // shrinks targets under 44 px.
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontFamily: HlFont.sans,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: 10,
                      children: [
                        Expanded(
                          child: _Field(
                            fieldKey: 'edit-brand',
                            label: l10n.fieldBrand,
                            hint: l10n.brandNone,
                            controller: _brand,
                            maxLength: 60,
                            onSubmitted: _save,
                          ),
                        ),
                        SizedBox(
                          width: 72,
                          child: _Field(
                            fieldKey: 'edit-quantity',
                            label: l10n.itemQuantity,
                            controller: _quantity,
                            maxLength: 40,
                            centered: true,
                            onSubmitted: _save,
                          ),
                        ),
                        ValueListenableBuilder(
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
                              spacing: 4,
                              children: [
                                _Stepper(
                                  key: const ValueKey('edit-quantity-minus'),
                                  icon: Icons.remove,
                                  tooltip: l10n.quantityMinus,
                                  onPressed: canLower
                                      ? () => _step(up: false)
                                      : null,
                                ),
                                _Stepper(
                                  key: const ValueKey('edit-quantity-plus'),
                                  icon: Icons.add,
                                  tooltip: l10n.quantityPlus,
                                  onPressed: () => _step(up: true),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: FoldoutChips(
                    catalog: _catalog,
                    storeId: _storeId,
                    categoryId: _categoryId,
                    storeLabel: l10n.noStore,
                    categoryLabel: l10n.categoryAuto,
                    storeChanged: _storeId != _originalStore,
                    categoryChanged: _categoryId != widget.item.categoryId,
                    onCreateStore: _createStore,
                    onStore: (id) => setState(() => _storeId = id),
                    onCategory: (id) => setState(() => _categoryId = id),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      key: const ValueKey('edit-delete'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        foregroundColor: scheme.error,
                        textStyle: const TextStyle(
                          fontFamily: HlFont.sans,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(const EditDeleted()),
                      child: Text(l10n.delete),
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
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  16 + math.max(0, media.padding.bottom - keyboard),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    l10n.editHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label above a 48 px field; the label names the field for screen
/// readers.
class const _Field({
  required final String fieldKey,
  required final String label,
  required final TextEditingController controller,
  required final int maxLength,
  required final VoidCallback onSubmitted,
  final String? hint,
  final bool bold = false,
  final bool centered = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Padding(
            // Over the field's text, not its tip.
            padding: const EdgeInsetsDirectional.only(start: hexFieldInset),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextField(
            key: ValueKey(fieldKey),
            controller: controller,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            textAlignVertical: TextAlignVertical.center,
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
              // Centred text in a narrow field clears the tips with less.
              contentPadding: centered
                  ? const EdgeInsets.symmetric(
                      horizontal: HlSpace.s3,
                      vertical: HlSpace.s2,
                    )
                  : null,
            ),
            onSubmitted: (_) => onSubmitted(),
          ),
        ],
      ),
    );
  }
}

class const _Stepper({
  required final IconData icon,
  required final String tooltip,
  required final VoidCallback? onPressed,
  super.key,
}) extends StatelessWidget {
  /// The theme's outlined button: a raised hex with the contour on its
  /// edge, sinking when pressed.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    // The icon names the button; the tooltip only shows it.
    excludeFromSemantics: true,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.standard,
        fixedSize: const Size(56, HlSize.target),
        minimumSize: const Size(56, HlSize.target),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Icon(icon, size: 22, semanticLabel: tooltip),
    ),
  );
}
