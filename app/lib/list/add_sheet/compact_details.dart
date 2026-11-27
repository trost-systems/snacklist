import 'dart:math' as math;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/edit_item_sheet.dart' show fieldValue;
import 'package:family_groceries/list/entry.dart' show stepQuantity;
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The item just added in the compact sheet (flag `add-sheet-compact`, job
/// 322, AS1): one row of chips that wraps, never scrolls: Menge between its
/// steppers, the store, the category and the details, whose options or
/// field fold out below it, one at a time. The brand is not edited here
/// (AS-Q1); the details chip shows it with the details. A stepper or a pick
/// saves at once, typing after a pause (AddSheetCubit.editDetails).
class const CompactDetails({
  required final Item item,

  /// A pick, or Enter in a field: focus goes back to the add field.
  required final VoidCallback onDone,
  super.key,
}) extends StatefulWidget {
  @override
  State<CompactDetails> createState() => _CompactDetailsState();
}

class _CompactDetailsState() extends State<CompactDetails> {
  late final _quantity = TextEditingController(text: widget.item.quantity);
  late final _properties = TextEditingController(text: widget.item.properties);

  @override
  void initState() {
    super.initState();
    _follow(_quantity, (value) => ItemChanges(quantity: SetTo(value)));
    _follow(_properties, (value) => ItemChanges(properties: SetTo(value)));
  }

  /// Hands [field]'s text to the sheet whenever it changes; a move of the
  /// caret alone is no change.
  void _follow(
    TextEditingController field,
    ItemChanges Function(String? value) change,
  ) {
    var text = field.text;
    field.addListener(() {
      if (field.text != text) {
        text = field.text;
        context.read<AddSheetCubit>().editDetails(
          change(fieldValue(field.text)),
        );
      }
    });
  }

  @override
  void dispose() {
    _quantity.dispose();
    _properties.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = context.watch<ListCubit>();
    final catalog = list.state.catalog;
    final sheet = context.read<AddSheetCubit>();
    final item = widget.item;
    final chains = context.select<Flags?, bool>(
      (f) => f?.isOn(openStoreAppFlag) ?? false,
    );
    final categories = context.select<Flags?, bool>(
      (f) => !(f?.isOn(hideCategoriesFlag) ?? false),
    );
    final details = [?item.brand, ?item.properties].join(', ');
    void submitted() {
      sheet.saveDetails();
      widget.onDone();
    }

    return FoldoutChips(
      catalog: catalog,
      storeId: catalog.store(item.storeId ?? '')?.id,
      categoryId: item.categoryId,
      storeLabel: l10n.noStore,
      categoryLabel: l10n.categoryAuto,
      onCreateStore: list.addStore,
      chains: chains ? StoreChains.of(list) : null,
      onStore: (id) {
        sheet.editDetails(ItemChanges(storeId: SetTo(id)), now: true);
        widget.onDone();
      },
      onCategory: categories
          ? (id) {
              sheet.editDetails(ItemChanges(categoryId: id), now: true);
              widget.onDone();
            }
          : null,
      chipIcons: false,
      chipArrows: false,
      optionsInLine: true,
      fold: ChipFold(
        chipKey: const ValueKey('chip-details'),
        icon: Icons.notes,
        label: details.isEmpty ? null : details,
        semanticsLabel: [
          l10n.fieldProperties,
          if (details.isNotEmpty) details,
        ].join(', '),
        panel: (foldBack) => _PropertiesField(
          controller: _properties,
          onSubmitted: () {
            foldBack();
            submitted();
          },
        ),
      ),
      line: ChipLine(
        before: [
          QuantityGroup(
            controller: _quantity,
            onStep: sheet.saveDetails,
            onSubmitted: submitted,
          ),
        ],
        after: const [],
        side: 12,
        wrap: true,
      ),
    );
  }
}

/// − Menge + in one hex (also the edit sheet's, job 340), 44 px high,
/// without a label: for screen readers one adjustable Menge
/// ([QuantitySemantics]). The steppers step a number in it (and its unit)
/// and are off where it holds none.
class const QuantityGroup({
  required final TextEditingController controller,
  required final VoidCallback onStep,
  required final VoidCallback onSubmitted,

  /// Starts the keys: `added-quantity`, `added-quantity-minus`, …
  final String keyPrefix = 'added',
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final scaler = MediaQuery.textScalerOf(context);
    const size = 16.0;
    final height = math.max(HlSize.target, scaler.scale(size) * 1.2 + 8);
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    void step({required bool up}) {
      if (stepQuantity(controller.text, up: up) case final next?) {
        controller.text = next;
        onStep();
      }
    }

    // Stepped with the group's adjust actions, not focused one by one; on
    // the web they stay buttons (QuantitySemantics).
    Widget stepper(Key key, IconData icon, String label, VoidCallback? tap) =>
        ExcludeSemantics(
          excluding: !kIsWeb,
          child: IconButton(
            key: key,
            onPressed: tap,
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: Size(_stepperWidth, height),
              fixedSize: Size(_stepperWidth, height),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            // No tooltip: its overlay moves the web semantics tree (job 122).
            icon: Icon(icon, size: 20, semanticLabel: label),
          ),
        );
    return QuantitySemantics(
      controller: controller,
      onStep: step,
      identifier: '$keyPrefix-quantity-stepper',
      child: Container(
        key: ValueKey('$keyPrefix-quantity-group'),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: HlSpace.s1),
        decoration: ShapeDecoration(
          color: t.surfaceRaised,
          shape: HexBorder(
            side: BorderSide(color: t.border, width: HlBorder.width),
          ),
        ),
        child: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, field) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              stepper(
                ValueKey('$keyPrefix-quantity-minus'),
                Icons.remove,
                l10n.quantityMinus,
                stepQuantity(value.text, up: false) == null
                    ? null
                    : () => step(up: false),
              ),
              SizedBox(
                width: _fieldWidth(context, value.text, style),
                child: field,
              ),
              stepper(
                ValueKey('$keyPrefix-quantity-plus'),
                Icons.add,
                l10n.quantityPlus,
                stepQuantity(value.text, up: true) == null
                    ? null
                    : () => step(up: true),
              ),
            ],
          ),
          // Its own node, after the group's adjustable one: typed into,
          // not stepped.
          child: Semantics(
            container: true,
            label: l10n.itemQuantity,
            // The hex around it draws the field; the app's field theme must
            // not reach it (as the add bar's).
            child: InputDecorationTheme(
              data: const InputDecorationThemeData(),
              child: TextField(
                autofillHints: null,
                key: ValueKey('$keyPrefix-quantity'),
                controller: controller,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                style: style,
                decoration: InputDecoration(
                  // Empty is one, as the steppers count it.
                  hintText: '1',
                  hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menge for a screen reader: one adjustable node that reads "Menge, 2"
/// and steps with a swipe up or down (TalkBack: the volume keys), so the
/// value comes first and − and + are no stops of their own: [child] has
/// none. An empty Menge reads 1, as the steppers count it; one without a
/// number („eine Packung“) only reads. The node lies under [child], beside
/// the field, not around it. Not on the web, whose adjustable node is a range
/// input that a pointer moves too: a click on + stepped up and back down, and
/// a field inside it took no typing. There − and + stay buttons.
class const QuantitySemantics({
  required final TextEditingController controller,
  required final void Function({required bool up}) onStep,
  required final Widget child,

  /// Where tests and the web's e2e find it.
  final String? identifier,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return child;
    }
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final text = value.text.trim();
              final more = stepQuantity(text, up: true);
              final less = stepQuantity(text, up: false);
              return Semantics(
                container: true,
                sortKey: const OrdinalSortKey(0),
                identifier: identifier,
                label: l10n.itemQuantity,
                value: text.isEmpty ? '1' : text,
                increasedValue: more,
                decreasedValue: less,
                onIncrease: more == null ? null : () => onStep(up: true),
                onDecrease: less == null ? null : () => onStep(up: false),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
        // After the value: their rects overlap, so the order is set.
        Semantics(
          container: true,
          sortKey: const OrdinalSortKey(1),
          child: child,
        ),
      ],
    );
  }
}

/// Menge's width: as wide as its text, so "2" keeps the chips on one line
/// and "500 g" still shows whole; longer text scrolls in the field.
double _fieldWidth(BuildContext context, String text, TextStyle style) {
  final scaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    text: TextSpan(
      text: text.isEmpty ? '1' : text,
      // The field's own: the theme's input text under [style].
      style: Theme.of(context).textTheme.titleMedium?.merge(style) ?? style,
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  final em = scaler.scale(style.fontSize ?? 16);
  return width.clamp(1.7 * em, 5 * em) + 4;
}

/// A stepper's width: narrower than a target, so Menge, the store, the
/// category and the details fit one line on a phone; still 44 px high.
const _stepperWidth = 34.0;

/// The details chip's field, below the chips: the details only, focused as
/// it opens.
class const _PropertiesField({
  required final TextEditingController controller,
  required final VoidCallback onSubmitted,
}) extends StatefulWidget {
  @override
  State<_PropertiesField> createState() => _PropertiesFieldState();
}

class _PropertiesFieldState() extends State<_PropertiesField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Not autofocus: that waits while the add field holds the focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final _PropertiesField(:controller, :onSubmitted) = widget;
    return Padding(
      padding: const EdgeInsets.only(top: HlSpace.s3),
      child: Semantics(
        label: l10n.fieldProperties,
        child: TextField(
          autofillHints: null,
          key: const ValueKey('added-properties'),
          controller: controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(120)],
          // As big as the chips' Menge, so it fits at a large text size too.
          style: TextStyle(fontSize: 16, color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: l10n.propertiesExample,
            hintStyle: TextStyle(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            constraints: const BoxConstraints(minHeight: HlSize.target),
          ),
          onSubmitted: (_) => onSubmitted(),
        ),
      ),
    );
  }
}
