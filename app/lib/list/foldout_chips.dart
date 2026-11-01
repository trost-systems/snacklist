import 'dart:async';

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/category_names.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

enum _Fold() {
  store,
  category,
}

/// The chips' and options' height: a touch target.
const _height = 44.0;

/// Room from the hex's edge to its content: the tip's depth, so the content
/// starts where the flat sides do.
const _hexPadding = EdgeInsets.symmetric(horizontal: HlHex.tip * _height);

/// The store and category chips. Tapping one folds its options out right
/// below; picking one folds them back.
class const FoldoutChips({
  required final Catalog catalog,
  required final String? storeId,
  required final String? categoryId,
  required final ValueChanged<String?> onStore,
  required final ValueChanged<String> onCategory,

  /// The store chip and the no-store option without a store.
  required final String storeLabel,

  /// The category chip without a category.
  required final String categoryLabel,

  /// When set, no store means "not decided yet": the chip shows this and
  /// no option is selected (the add sheet before a store is known).
  final String? storeAutoLabel,

  /// Offers "+ Neuer Laden" among the stores: the name typed there becomes
  /// a store of the household, or finds the one it already has, and is
  /// picked. Null when it could not be saved.
  final Future<Store?> Function(String name)? onCreateStore,

  /// Shows the store options from the start (Widgetbook stories).
  final bool storesOpen = false,

  /// Outlines a chip whose value the user changed.
  final bool storeChanged = false,
  final bool categoryChanged = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<FoldoutChips> createState() => _FoldoutChipsState();
}

class _FoldoutChipsState() extends State<FoldoutChips> {
  late _Fold? _fold = widget.storesOpen ? _Fold.store : null;

  void _toggle(_Fold fold) =>
      setState(() => _fold = _fold == fold ? null : fold);

  void _pick(VoidCallback pick) {
    setState(() => _fold = null);
    pick();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final store = switch (w.storeId) {
      final id? => w.catalog.store(id),
      null => null,
    };
    final category = w.catalog.categories
        .where((c) => c.id == w.categoryId)
        .firstOrNull;
    final l10n = AppLocalizations.of(context);
    final storeName = store?.name ?? w.storeAutoLabel ?? w.storeLabel;
    final shownCategory = switch (category) {
      final c? => categoryName(c, l10n),
      null => w.categoryLabel,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              key: const ValueKey('chip-store'),
              leading: const Icon(Icons.storefront_outlined, size: 20),
              label: storeName,
              // The automatic labels already say what the chip is.
              semanticsLabel: store == null && w.storeAutoLabel != null
                  ? storeName
                  : l10n.chipStore(storeName),
              open: _fold == _Fold.store,
              changed: w.storeChanged,
              onTap: () => _toggle(_Fold.store),
            ),
            _Chip(
              key: const ValueKey('chip-category'),
              leading: const Icon(Icons.category_outlined, size: 20),
              label: shownCategory,
              semanticsLabel: category == null
                  ? shownCategory
                  : l10n.chipCategory(shownCategory),
              open: _fold == _Fold.category,
              changed: w.categoryChanged,
              onTap: () => _toggle(_Fold.category),
            ),
          ],
        ),
        AnimatedSize(
          duration: hlMotion(context, HlDuration.medium),
          curve: HlEasing.standard,
          alignment: Alignment.topCenter,
          child: switch (_fold) {
            null => const SizedBox(width: double.infinity),
            _Fold.store => _StoreOptions(
              catalog: w.catalog,
              storeId: w.storeId,
              noStoreLabel: w.storeLabel,
              undecided: w.storeAutoLabel != null,
              onPick: (id) => _pick(() => w.onStore(id)),
              onCreate: w.onCreateStore,
            ),
            _Fold.category => _Options([
              for (final c in w.catalog.categories)
                _Option(
                  key: ValueKey('category-option-${c.id}'),
                  label: categoryName(c, l10n),
                  selected: c.id == w.categoryId,
                  onTap: () => _pick(() => w.onCategory(c.id)),
                ),
            ]),
          },
        ),
      ],
    );
  }
}

class const _Chip({
  required final Widget leading,
  required final String label,

  /// Names the chip apart from the option of the same name.
  required final String semanticsLabel,
  required final bool open,
  required final bool changed,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    // A value the user picked is their choice, honey like a selected chip;
    // an open chip is lit softly while its options show.
    final (face, onFace) = switch ((changed, open)) {
      (true, _) => (t.honey, t.onHoney),
      (false, true) => (t.honeySoft, t.text),
      (false, false) => (t.surfaceRaised, t.text),
    };
    // The button's own web semantics node would take the add field's text
    // input with it on a tap; this node only taps.
    return Semantics(
      button: true,
      expanded: open,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          // Desktop defaults to compact density, which shrinks targets
          // under 44 px.
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(0, _height),
          padding: _hexPadding,
          shape: const HexBorder(),
          side: BorderSide(color: t.border, width: HlBorder.width),
          backgroundColor: face,
          foregroundColor: onFace,
          iconColor: onFace,
          textStyle: const TextStyle(
            fontFamily: HlFont.sans,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s1,
          children: [
            leading,
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: hlMotion(context, HlDuration.short),
              curve: HlEasing.standard,
              child: const Icon(Icons.arrow_drop_down, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// More stores than this get a search field above them: two rows of
/// options on a phone.
const storeSearchThreshold = 5;

/// The store options: "Ohne Laden", the household's stores and, with
/// [onCreate], "+ Neuer Laden", which turns into a field in place. Over
/// [storeSearchThreshold] stores a search field filters them; Enter there
/// picks the store of that name or starts a new one with it.
class const _StoreOptions({
  required final Catalog catalog,
  required final String? storeId,
  required final String noStoreLabel,

  /// No store means "not decided yet": nothing is selected.
  required final bool undecided,
  required final ValueChanged<String?> onPick,
  required final Future<Store?> Function(String name)? onCreate,
}) extends StatefulWidget {
  @override
  State<_StoreOptions> createState() => _StoreOptionsState();
}

class _StoreOptionsState() extends State<_StoreOptions> {
  final _search = TextEditingController();
  final _newOption = FocusNode();

  /// The new store's first text while its field is open; null otherwise.
  String? _naming;

  @override
  void dispose() {
    _search.dispose();
    _newOption.dispose();
    super.dispose();
  }

  void _startNaming(String text) => setState(() => _naming = text.trim());

  void _cancelNaming() {
    setState(() => _naming = null);
    // The option is back in the tree after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _newOption.requestFocus();
      }
    });
  }

  void _submitSearch(String text) {
    if (widget.catalog.storeNamed(text) case final store?) {
      widget.onPick(store.id);
    } else if (widget.onCreate != null && text.trim().isNotEmpty) {
      _startNaming(text);
    }
  }

  Future<bool> _create(String name) async {
    final existing = widget.catalog.storeNamed(name);
    final store = existing ?? await widget.onCreate!(name);
    if (store == null || !mounted) {
      return false;
    }
    if (existing == null) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).storeAddedAndSelected(store.name),
          Directionality.of(context),
        ),
      );
    }
    widget.onPick(store.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final l10n = AppLocalizations.of(context);
    final searching = w.catalog.stores.length > storeSearchThreshold;
    final query = storeNameKey(_search.text);
    final naming = _naming;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (searching)
            _SearchField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              onSubmitted: _submitSearch,
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (query.isEmpty)
                _Option(
                  key: const ValueKey('store-option-none'),
                  leading: const Icon(Icons.storefront_outlined, size: 22),
                  label: w.noStoreLabel,
                  selected: w.storeId == null && !w.undecided,
                  onTap: () => w.onPick(null),
                ),
              for (final s in w.catalog.stores)
                if (storeNameKey(s.name).contains(query))
                  _Option(
                    key: ValueKey('store-option-${s.id}'),
                    label: s.name,
                    selected: s.id == w.storeId,
                    onTap: () => w.onPick(s.id),
                  ),
              if (w.onCreate != null && naming == null)
                _Option(
                  key: const ValueKey('store-option-new'),
                  focusNode: _newOption,
                  leading: const Icon(Icons.add, size: 22),
                  label: l10n.storeNew,
                  semanticsLabel: l10n.storeNewLabel,
                  selected: false,
                  onTap: () => _startNaming(_search.text),
                ),
            ],
          ),
          if (naming != null)
            StoreNameField(
              initial: naming,
              confirmLabel: l10n.storeCreateConfirm,
              onConfirm: _create,
              onCancel: _cancelNaming,
            ),
        ],
      ),
    );
  }
}

class const _SearchField({
  required final TextEditingController controller,
  required final ValueChanged<String> onChanged,
  required final ValueChanged<String> onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      // Hardware Enter: see StoreNameField.
      onKeyEvent: (_, event) {
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          onSubmitted(controller.text);
        }
        return KeyEventResult.handled;
      },
      child: TextField(
        key: const ValueKey('store-search'),
        controller: controller,
        maxLength: maxStoreNameLength,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: 16, color: scheme.onSurface),
        onChanged: onChanged,
        onEditingComplete: () {},
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: l10n.storeSearch,
          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          prefixIcon: const Icon(Icons.search, size: 20),
          counterText: '',
          constraints: const BoxConstraints.tightFor(height: HlSize.target),
        ),
      ),
    );
  }
}

class const _Options(final List<Widget> options) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SizedBox(
      width: double.infinity,
      child: Wrap(spacing: 6, runSpacing: 6, children: options),
    ),
  );
}

class const _Option({
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
  final Widget? leading,
  final String? semanticsLabel,
  final FocusNode? focusNode,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: TextButton(
        focusNode: focusNode,
        onPressed: onTap,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(0, _height),
          padding: _hexPadding,
          // Lemon on the page needs the navy contour.
          shape: HexBorder(
            side: selected
                ? BorderSide(color: t.edge, width: HlBorder.width)
                : BorderSide.none,
          ),
          backgroundColor: selected ? t.honey : t.surfaceSunken,
          foregroundColor: selected ? t.onHoney : t.text,
          iconColor: selected ? t.onHoney : t.text,
          textStyle: const TextStyle(
            fontFamily: HlFont.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [?leading, Text(label)],
        ),
      ),
    );
  }
}
