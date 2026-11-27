import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/core/screen_reader.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/category_names.dart';
import 'package:family_groceries/list/chain_question.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

enum _Fold() {
  store,
  category,

  /// [FoldoutChips.fold]'s.
  more,
}

/// The options' height: a touch target.
const _height = 44.0;

/// The chips' height, face plus edge: the add sheet's close key beside them,
/// so the face alone stays a 44 px target.
const _chipHeight = HlSize.target;

/// Room from the edge of a hex [height] tall to a label in [style]:
/// [hexTextInset], and more at large text, where a tall line would reach
/// into the tips.
EdgeInsets _hexPadding(BuildContext context, TextStyle style, double height) =>
    EdgeInsets.symmetric(
      horizontal: math.max(
        hexTextInset(height),
        hexLabelInset(style, MediaQuery.textScalerOf(context)),
      ),
    );

/// The store and category chips. Tapping one folds its options out right
/// below; picking one folds them back.
class const FoldoutChips({
  required final Catalog catalog,
  required final String? storeId,
  required final String? categoryId,
  required final ValueChanged<String?> onStore,

  /// Null: no category chip (flag `hide-categories`).
  required final ValueChanged<String>? onCategory,

  /// The store chip and the no-store option without a store.
  required final String storeLabel,

  /// The category chip without a category.
  required final String categoryLabel,

  /// Snacklist picks the store until the user does (the add sheet): the
  /// chip shows its pick muted with the automatic mark, and no store means
  /// "not known yet", with no option selected.
  final bool storeAuto = false,

  /// Snacklist picks the category until the user does, like [storeAuto].
  final bool categoryAuto = false,

  /// Beside the chips on their first line (the add sheet's Schließen).
  final Widget? trailing,

  /// Offers "+ Neuer Laden" among the stores: the name typed there becomes
  /// a store of the household, or finds the one it already has, and is
  /// picked. Null when it could not be saved.
  final Future<Store?> Function(String name)? onCreateStore,

  /// Chains for a new store (job 313, flag `open-store-app`): suggested
  /// under its name while typing, asked about in place once a plain name
  /// that is a chain's is saved. Null: none.
  final StoreChains? chains,

  /// Shows the store options from the start (Widgetbook stories).
  final bool storesOpen = false,

  /// A store and a category icon before the chips' text. The automatic
  /// mark shows either way.
  final bool chipIcons = true,

  /// The drop-down arrow at each chip's end.
  final bool chipArrows = true,

  /// Opened options stand in one line that scrolls sideways, the selected
  /// one in view, instead of wrapping onto lines of their own (the compact
  /// add sheet, job 322): an open picker then takes one line at any text
  /// size.
  final bool optionsInLine = false,

  /// A chip of the caller's after the store's and the category's, which
  /// folds out its own panel below them; one of the three is open at a time.
  final ChipFold? fold,

  /// Outlines a chip whose value the user changed.
  final bool storeChanged = false,
  final bool categoryChanged = false,

  /// Puts the chips in one horizontally scrolling line between other
  /// controls instead of their own lines (the add sheet's details, job
  /// 288); the options still fold out below, across the whole width.
  final ChipLine? line,
  super.key,
}) extends StatefulWidget {
  @override
  State<FoldoutChips> createState() => _FoldoutChipsState();
}

/// [FoldoutChips.line]: the chips between [before] and [after], aligned to
/// their bottom edge, the line [side] in from either edge as it scrolls.
/// With [wrap] the line wraps onto more lines instead of scrolling, so
/// every control stays in view at any text size (job 322).
@immutable
class const ChipLine({
  required final List<Widget> before,
  required final List<Widget> after,
  final double side = 0,
  final bool wrap = false,
});

/// [FoldoutChips.fold]: a chip with [icon] and [label] (the icon alone
/// without one), read as [semanticsLabel], whose [panel] folds out below the
/// chips like their options. The panel gets the fold-back.
@immutable
class const ChipFold({
  required final Key chipKey,
  required final IconData icon,
  required final String? label,
  required final String semanticsLabel,
  required final Widget Function(VoidCallback foldBack) panel,
});

class _FoldoutChipsState() extends State<FoldoutChips> {
  late _Fold? _fold = widget.storesOpen ? _Fold.store : null;

  @override
  void didUpdateWidget(FoldoutChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The category chip went (flag `hide-categories` came on): its options
    // go with it.
    if (widget.onCategory == null && _fold == _Fold.category) {
      _fold = null;
    }
  }

  /// The chips, so an opened one can be scrolled to along the line.
  final _chips = {for (final fold in _Fold.values) fold: GlobalKey()};

  void _toggle(_Fold fold) {
    setState(() => _fold = _fold == fold ? null : fold);
    if (_fold != null && widget.line != null && !widget.line!.wrap) {
      // The line sits in a scrolling area of its own (the add sheet's
      // details): it and the options below it come into view, and the line
      // scrolls sideways to the opened chip, which a screen reader can open
      // while it is out of view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final duration = hlMotion(context, HlDuration.medium);
        if (_chips[fold]?.currentContext case final chip?) {
          if (chip.findRenderObject() case final box?) {
            Scrollable.maybeOf(
              chip,
              axis: Axis.horizontal,
            )?.position.ensureVisible(
              box,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              duration: duration,
              curve: HlEasing.standard,
            );
          }
        }
        Scrollable.ensureVisible(
          context,
          duration: duration,
          curve: HlEasing.standard,
        );
      });
    }
  }

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
    final (storeText, storeSemantics) = switch (store) {
      final s? when w.storeAuto => (s.name, l10n.storeAutoValue(s.name)),
      final s? => (s.name, l10n.chipStore(s.name)),
      null when w.storeAuto => (l10n.chipStoreShort, l10n.storeAuto),
      null => (w.storeLabel, l10n.chipStore(w.storeLabel)),
    };
    final (categoryText, categorySemantics) = switch (category) {
      final c? when w.categoryAuto => (
        categoryName(c, l10n),
        l10n.categoryAutoValue(categoryName(c, l10n)),
      ),
      final c? => (
        categoryName(c, l10n),
        l10n.chipCategory(categoryName(c, l10n)),
      ),
      null when w.categoryAuto => (l10n.chipCategoryShort, l10n.categoryAuto),
      null => (w.categoryLabel, w.categoryLabel),
    };
    final chips = [
      KeyedSubtree(
        key: _chips[_Fold.store],
        child: _Chip(
          key: const ValueKey('chip-store'),
          leading: w.chipIcons ? Icons.storefront_outlined : null,
          label: storeText,
          semanticsLabel: storeSemantics,
          auto: w.storeAuto,
          open: _fold == _Fold.store,
          arrow: w.chipArrows,
          changed: w.storeChanged,
          onTap: () => _toggle(_Fold.store),
        ),
      ),
      if (w.onCategory != null)
        KeyedSubtree(
          key: _chips[_Fold.category],
          child: _Chip(
            key: const ValueKey('chip-category'),
            leading: w.chipIcons ? Icons.category_outlined : null,
            label: categoryText,
            semanticsLabel: categorySemantics,
            auto: w.categoryAuto,
            open: _fold == _Fold.category,
            arrow: w.chipArrows,
            changed: w.categoryChanged,
            onTap: () => _toggle(_Fold.category),
          ),
        ),
      if (w.fold case final more?)
        KeyedSubtree(
          key: _chips[_Fold.more],
          child: _Chip(
            key: more.chipKey,
            leading: more.icon,
            label: more.label,
            semanticsLabel: more.semanticsLabel,
            auto: false,
            open: _fold == _Fold.more,
            arrow: w.chipArrows,
            changed: false,
            onTap: () => _toggle(_Fold.more),
          ),
        ),
    ];
    final line = w.line;
    final folded = switch (_fold) {
      null => const SizedBox(width: double.infinity),
      _Fold.store => _StoreOptions(
        catalog: w.catalog,
        storeId: w.storeId,
        noStoreLabel: w.storeLabel,
        undecided: w.storeAuto,
        onPick: (id) => _pick(() => w.onStore(id)),
        onSelect: w.onStore,
        onCreate: w.onCreateStore,
        chains: w.chains,
        inLine: w.optionsInLine,
      ),
      _Fold.category => switch (w.onCategory) {
        final onCategory? => Padding(
          padding: EdgeInsets.only(top: w.optionsInLine ? 4 : 10),
          child: _OptionsWrap(inLine: w.optionsInLine, [
            for (final c in w.catalog.categories)
              OptionChip(
                key: ValueKey('category-option-${c.id}'),
                label: categoryName(c, l10n),
                selected: c.id == w.categoryId,
                onTap: () => _pick(() => onCategory(c.id)),
              ),
          ]),
        ),
        null => const SizedBox(width: double.infinity),
      },
      _Fold.more => switch (w.fold) {
        final more? => more.panel(() => setState(() => _fold = null)),
        null => const SizedBox(width: double.infinity),
      },
    };
    final options = AnimatedSize(
      duration: hlMotion(context, HlDuration.medium),
      curve: HlEasing.standard,
      alignment: Alignment.topCenter,
      child: folded,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (line) {
        null => [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
              ?w.trailing,
            ],
          ),
          options,
        ],
        ChipLine(:final before, :final after, :final side, wrap: true) => [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            // A chip takes at most half the line, its name cut short: long
            // names at a large text size keep the row to two lines, which
            // leaves room for an open picker above the keyboard (job 322).
            child: LayoutBuilder(
              builder: (context, constraints) {
                final half = (constraints.maxWidth - 6) / 2;
                return Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    ...before,
                    for (final chip in chips)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: half),
                        child: chip,
                      ),
                    ...after,
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: folded,
          ),
        ],
        ChipLine(:final before, :final after, :final side) => [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 8,
              children: [...before, ...chips, ...after],
            ),
          ),
          // At their full height at once: the area scrolls them into view
          // (see _toggle), which a growing size would stop short of.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: folded,
          ),
        ],
      },
    );
  }
}

class const _Chip({
  required final IconData? leading,

  /// Null: the icon alone.
  required final String? label,

  /// Names the chip apart from the option of the same name.
  required final String semanticsLabel,

  /// Snacklist's pick, not the user's: muted, with the automatic mark.
  required final bool auto,
  required final bool open,
  required final bool changed,
  required final VoidCallback onTap,
  final bool arrow = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    // A value the user picked is their choice, honey like a selected chip;
    // an open chip is lit softly while its options show.
    final (face, edge, onFace) = switch ((changed, open)) {
      (true, _) => (t.honey, t.honeyEdge, t.onHoney),
      (false, true) => (t.honeySoft, t.honeyEdge, t.text),
      (false, false) => (
        t.surfaceRaised,
        t.surfaceEdge,
        auto ? t.textMuted : t.text,
      ),
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
        // A tactile face on its edge, like every button (job 148).
        style:
            tactileButtonStyle(
              colors: (_) => TactileColors(
                face: face,
                contour: t.border,
                edge: edge,
                focus: t.accent,
              ),
              foreground: WidgetStatePropertyAll(onFace),
              textStyle: _chipText,
            ).copyWith(
              // Desktop defaults to compact density, which shrinks targets
              // under 44 px.
              visualDensity: VisualDensity.standard,
              minimumSize: const WidgetStatePropertyAll(Size(0, _chipHeight)),
              padding: WidgetStatePropertyAll(
                _hexPadding(context, _chipText, _chipHeight),
              ),
            ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s1,
          children: [
            // Snacklist's pick wears the automatic mark where the chip's
            // icon goes; the user's pick brings the icon back.
            if (auto)
              Icon(autoMark, size: 18, color: t.accent)
            else if (leading != null)
              Icon(leading, size: 20),
            if (label case final label?)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (arrow)
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

const _chipText = TextStyle(
  fontFamily: HlFont.sans,
  fontSize: 14,
  fontWeight: FontWeight.w600,
);

const _optionText = TextStyle(
  fontFamily: HlFont.sans,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// Marks a chip whose value Snacklist picked.
const autoMark = Icons.hdr_auto_outlined;

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

  /// Picks a store and leaves the options open, for the chain question.
  required final ValueChanged<String?> onSelect,
  required final Future<Store?> Function(String name)? onCreate,
  required final StoreChains? chains,
  required final bool inLine,
}) extends StatefulWidget {
  @override
  State<_StoreOptions> createState() => _StoreOptionsState();
}

class _StoreOptionsState() extends State<_StoreOptions> {
  final _search = TextEditingController();
  final _newOption = FocusNode();

  /// The new store's first text while its field is open; null otherwise.
  String? _naming;

  /// The new store's text as typed, for the chain suggestions.
  var _typed = '';

  /// The new store just saved and the chains its name is, asked about in
  /// place of its field (job 313).
  (Store, List<Retailer>)? _asking;

  @override
  void dispose() {
    _search.dispose();
    _newOption.dispose();
    super.dispose();
  }

  void _startNaming(String text) {
    final name = text.trim();
    setState(() {
      _naming = name;
      _typed = name;
    });
  }

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
    final chains = existing == null ? widget.chains : null;
    final matches = chains?.match(name);
    final store = existing ?? await widget.onCreate!(name);
    if (store == null || !mounted) {
      return false;
    }
    final named = exactChains(await matches ?? const []);
    if (!mounted) {
      return false;
    }
    final l10n = AppLocalizations.of(context);
    _announce(
      store,
      existing,
      question: named.isEmpty
          ? null
          : chainQuestionTitle(l10n, store.name, named, existing: false),
    );
    if (named.isNotEmpty) {
      // Picked for the item already; the options stay open for the answer.
      // Focus goes back to the add field, so the question is announced.
      widget.onSelect(store.id);
      setState(() {
        _naming = null;
        _asking = (store, named);
      });
      return true;
    }
    widget.onPick(store.id);
    return true;
  }

  /// A suggested chain picked: the store named after it (or found by that
  /// name) is linked to it and picked.
  Future<void> _createLinked(RetailerMatch match, StoreChains chains) async {
    final name = match.storeName(_typed);
    final existing = widget.catalog.storeNamed(name);
    final store = await chains.addLinked(name, match.retailer);
    if (store == null || !mounted) {
      return;
    }
    _announce(store, existing);
    widget.onPick(store.id);
  }

  void _answer(Store store, Retailer? chain) {
    unawaited(widget.chains?.answer(store.id, chain));
    setState(() => _asking = null);
    widget.onPick(store.id);
  }

  void _announce(Store store, Store? existing, {String? question}) {
    final added = existing == null
        ? AppLocalizations.of(context).storeAddedAndSelected(store.name)
        : null;
    final text = [?added, ?question].join(' ');
    if (text.isNotEmpty) {
      ScreenReader.of(context).announce(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final l10n = AppLocalizations.of(context);
    final searching = w.catalog.stores.length > storeSearchThreshold;
    final query = nameKey(_search.text);
    final naming = _naming;
    final chains = w.chains;
    final asking = _asking;
    return Padding(
      padding: EdgeInsets.only(top: w.inLine ? 4 : 10),
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
          _OptionsWrap(inLine: w.inLine, [
            if (query.isEmpty)
              OptionChip(
                key: const ValueKey('store-option-none'),
                leading: const Icon(Icons.storefront_outlined, size: 22),
                label: w.noStoreLabel,
                selected: w.storeId == null && !w.undecided,
                onTap: () => w.onPick(null),
              ),
            for (final s in w.catalog.stores)
              if (nameKey(s.name).contains(query))
                OptionChip(
                  key: ValueKey('store-option-${s.id}'),
                  label: s.name,
                  selected: s.id == w.storeId,
                  onTap: () => w.onPick(s.id),
                ),
            if (w.onCreate != null && naming == null && asking == null)
              OptionChip(
                key: const ValueKey('store-option-new'),
                focusNode: _newOption,
                leading: const Icon(Icons.add, size: 22),
                label: l10n.storeNew,
                semanticsLabel: l10n.storeNewLabel,
                selected: false,
                onTap: () => _startNaming(_search.text),
              ),
          ]),
          if (naming != null)
            StoreNameField(
              initial: naming,
              confirmLabel: l10n.storeCreateConfirm,
              onConfirm: _create,
              onCancel: _cancelNaming,
              onChanged: chains == null
                  ? null
                  : (text) => setState(() => _typed = text),
            ),
          if (naming != null && chains != null)
            ChainSuggestions(
              text: _typed,
              match: chains.match,
              onPick: (m) => unawaited(_createLinked(m, chains)),
            ),
          if (asking case (final store, final named)?)
            ComesIntoView(
              key: ValueKey('chain-question-${store.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: HlSpace.s2),
                child: ChainQuestion(
                  storeName: store.name,
                  chains: named,
                  existing: false,
                  onAnswer: (chain) => _answer(store, chain),
                ),
              ),
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
      child: HintNamed(
        controller: controller,
        hint: l10n.storeSearch,
        field: TextField(
          autofillHints: null,
          key: const ValueKey('store-search'),
          controller: controller,
          maxLength: maxStoreNameLength,
          textInputAction: TextInputAction.search,
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
      ),
    );
  }
}

/// Options on lines of their own, or with [inLine] in one line that
/// scrolls sideways, opened with the selected one in view.
class const _OptionsWrap(
  final List<OptionChip> options, {
  required final bool inLine,
}) extends StatefulWidget {
  @override
  State<_OptionsWrap> createState() => _OptionsWrapState();
}

class _OptionsWrapState() extends State<_OptionsWrap> {
  final _selected = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.inLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final option = _selected.currentContext;
        if (!mounted || option == null) {
          return;
        }
        if (option.findRenderObject() case final box?) {
          // At once: the line opens with it in view.
          Scrollable.maybeOf(
            option,
            axis: Axis.horizontal,
          )?.position.ensureVisible(box, alignment: 0.5);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    if (!widget.inLine) {
      return SizedBox(
        width: double.infinity,
        child: Wrap(spacing: 6, runSpacing: 6, children: options),
      );
    }
    // An option is never wider than the line: a long store name at a large
    // text size ends in an ellipsis instead of running off both edges.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('options-line'),
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 6,
          children: [
            for (final option in options)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: option.selected
                    ? KeyedSubtree(key: _selected, child: option)
                    : option,
              ),
          ],
        ),
      ),
    );
  }
}

/// A pick among options: honey with the navy contour when [selected], a
/// sunken hex otherwise (the store and category options, the edit sheet's
/// lists).
class const OptionChip({
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
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: TextButton(
        focusNode: focusNode,
        onPressed: onTap,
        style: withFocusRing(
          TextButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(0, _height),
            padding: _hexPadding(context, _optionText, _height),
            // Lemon on the page needs the navy contour.
            shape: HexBorder(
              side: selected
                  ? BorderSide(color: t.edge, width: HlBorder.width)
                  : BorderSide.none,
            ),
            backgroundColor: selected ? t.honey : t.surfaceSunken,
            foregroundColor: selected ? t.onHoney : t.text,
            iconColor: selected ? t.onHoney : t.text,
            textStyle: _optionText,
          ),
          focusRingColor(t, honey: selected ? 1 : 0),
          contour: selected ? HlBorder.width : 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          // A long name at large text ends in an ellipsis inside the row.
          children: [
            ?leading,
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
