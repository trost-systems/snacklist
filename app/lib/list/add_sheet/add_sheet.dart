import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart'
    show quantityLabel;
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The add bar's height above the tabs; the input never leaves it.
const addBarHeight = 72.0;

const _sheetDuration = HlDuration.medium;

/// Room between the open sheet's top and the screen's safe top.
const _topGap = 28.0;

/// Before anything is typed the sheet takes at most this share of the
/// screen, counting the bar and tabs below it.
const _firstOpenShare = 0.5;

/// Room for the header, the chips and a row; with less, all of it scrolls.
const _roomy = 200.0;

/// The rows the sheet shows: the suggestions for what is typed, or, before
/// typing, the usuals that are due. Alternatives already on the list are
/// left out; what was typed always stays first.
List<Suggestion> sheetRows(AddSheetState sheet, ListCubit list) {
  if (sheet.text.trim().isEmpty) {
    return [
      for (final usual in list.dueUsuals)
        Suggestion(
          SuggestionSource.due,
          ParsedEntry(name: usual.name, quantity: usual.quantity),
        ),
    ];
  }
  final onList = {
    for (final item in list.state.items.values)
      if (item.status == ItemStatus.active)
        Suggestion(
          SuggestionSource.typed,
          ParsedEntry(
            name: item.name,
            brand: item.brand,
            properties: item.properties,
          ),
        ).key,
  };
  return [
    for (final row in sheet.suggestions)
      if (row.source == SuggestionSource.typed || !onList.contains(row.key))
        row,
  ];
}

/// The add sheet above the add bar: a scrim over the list and a surface
/// that grows upwards to the height of its content, up to the top of the
/// screen, where its rows scroll. Laid over the whole list area.
class const AddSheet({
  required final ValueChanged<Suggestion> onTake,
  required final VoidCallback onClose,

  /// Folds, picks and Undo inside the sheet hand focus back to the input.
  required final VoidCallback onPicked,

  /// Room below the sheet that the bar and tabs take on the screen.
  required final double bandHeight,
  super.key,
}) extends StatefulWidget {
  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState() extends State<AddSheet> {
  /// The content stays while the sheet shrinks away, then clears.
  var _shown = false;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _openChanged(bool open, bool still) {
    _settle?.cancel();
    if (open) {
      setState(() => _shown = true);
      return;
    }
    final cubit = context.read<AddSheetCubit>();
    _settle = Timer(
      still ? Duration.zero : _sheetDuration + const Duration(milliseconds: 40),
      () {
        if (mounted) {
          setState(() => _shown = false);
          cubit.settled();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final sheet = context.watch<AddSheetCubit>().state;
    final list = context.watch<ListCubit>().state;
    final open = sheet.open;
    return BlocListener<AddSheetCubit, AddSheetState>(
      listenWhen: (a, b) => a.open != b.open,
      listener: (_, s) => _openChanged(s.open, still),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final frame = ShoppingListView.frameFor(constraints.maxWidth, list);
          var max = constraints.maxHeight - media.padding.top - _topGap;
          // A duplicate hint or merge note (job 32b) needs its row in
          // view, so the sheet may grow for it.
          if (sheet.text.trim().isEmpty &&
              sheet.hint == null &&
              sheet.merge == null) {
            final first =
                media.size.height * _firstOpenShare - widget.bandHeight;
            // Never below the room the header and chips need.
            max = math.min(max, math.max(first, _roomy));
          }
          final content = _shown || open
              ? _Content(
                  maxHeight: max < 0 ? 0 : max,
                  onTake: widget.onTake,
                  onClose: widget.onClose,
                  onPicked: widget.onPicked,
                )
              : null;
          return Stack(
            children: [
              // A tap target for the pointer only: Schließen and Escape
              // close the sheet for everyone else.
              if (open || _shown)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !open,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        key: const ValueKey('add-sheet-scrim'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: AnimatedOpacity(
                          opacity: open ? 1 : 0,
                          duration: hlMotion(context, _sheetDuration),
                          curve: open ? HlEasing.standard : HlEasing.exit,
                          child: const ColoredBox(color: Color(0x66000000)),
                        ),
                      ),
                    ),
                  ),
                ),
              // Over the list's first column, like the add field below it.
              PositionedDirectional(
                start: frame.side,
                width: frame.columnWidth,
                bottom: 0,
                child: _Surface(open: open, still: still, child: content),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The sheet's background, sized to its content. Only the surface's size
/// animates: the content is laid out once at its own height and is clipped
/// while the surface catches up, so its rows don't reflow every frame.
class const _Surface({
  required final bool open,
  required final bool still,
  required final Widget? child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = child;
    final sized = switch (content) {
      null => const SizedBox(width: double.infinity),
      // Closing: no height of its own, so the surface shrinks while the
      // content keeps hanging from its top edge.
      _ when !open => Align(
        alignment: Alignment.topCenter,
        heightFactor: 0,
        child: content,
      ),
      _ => content,
    };
    return DecoratedBox(
      key: const ValueKey('add-sheet-surface'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HlRadius.l),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HlRadius.l),
        ),
        // Reduced motion: the surface takes its size at once.
        child: still
            ? sized
            : AnimatedSize(
                duration: _sheetDuration,
                curve: open ? HlEasing.standard : HlEasing.exit,
                alignment: Alignment.topCenter,
                child: sized,
              ),
      ),
    );
  }
}

class const _Content({
  required final double maxHeight,
  required final ValueChanged<Suggestion> onTake,
  required final VoidCallback onClose,
  required final VoidCallback onPicked,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sheet = context.watch<AddSheetCubit>().state;
    final list = context.watch<ListCubit>();
    final catalog = list.state.catalog;
    final rows = sheetRows(sheet, list);
    final first = rows.firstOrNull?.entry;
    final pickedStore = sheet.store;
    final storeId = pickedStore == null ? first?.storeId : pickedStore.value;
    final categoryId = sheet.category ?? first?.categoryId;
    final fixed = <Widget>[
      _Header(onClose: onClose),
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: FoldoutChips(
              catalog: catalog,
              storeId: storeId,
              categoryId: categoryId,
              storeLabel: l10n.noStore,
              storeAutoLabel: pickedStore == null && storeId == null
                  ? l10n.storeAuto
                  : null,
              categoryLabel: l10n.categoryAuto,
              storeChanged:
                  pickedStore != null && pickedStore.value != first?.storeId,
              categoryChanged:
                  sheet.category != null && sheet.category != first?.categoryId,
              onCreateStore: list.addStore,
              onStore: (id) {
                context.read<AddSheetCubit>().pickStore(id);
                onPicked();
              },
              onCategory: (id) {
                context.read<AddSheetCubit>().pickCategory(id);
                onPicked();
              },
            ),
          ),
        ),
      ),
    ];
    final rowWidgets = <Widget>[
      if (sheet.added case final added?)
        _AddedNote(
          added,
          catalog: catalog,
          onUndo: () {
            context.read<AddSheetCubit>().undo();
            onPicked();
          },
        ),
      if (sheet.merge case final merge?)
        _DedupeNote(
          key: const ValueKey('dedupe-merged'),
          text: l10n.dedupeMerged(
            [?merge.result.quantity, merge.result.name].join(' '),
          ),
          action: l10n.undo,
          actionKey: const ValueKey('dedupe-undo'),
          onAction: () {
            context.read<AddSheetCubit>().undoMerge();
            onPicked();
          },
        )
      else if (sheet.hint case final hint?)
        _DedupeNote(
          key: const ValueKey('dedupe-hint'),
          text: l10n.alreadyOnList(hint.onList.name),
          action: l10n.dedupeMerge,
          actionKey: const ValueKey('dedupe-merge'),
          onAction: () {
            context.read<AddSheetCubit>().mergeHint();
            onPicked();
          },
        ),
      for (final (i, row) in rows.indexed)
        _SuggestionRow(
          key: ValueKey('suggestion-$i'),
          suggestion: row,
          first: i == 0,
          base: first,
          catalog: catalog,
          // A row tells its own store only while the
          // chip doesn't decide it for every row.
          ownStore: pickedStore == null && row.entry.storeId != storeId
              ? catalog.store(row.entry.storeId ?? '')
              : null,
          onTap: () => onTake(row),
        ),
      if (rows.isEmpty && sheet.added == null)
        Padding(
          key: const ValueKey('add-sheet-empty'),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Text(
            l10n.typeToSuggest,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
    ];
    return AnimatedOpacity(
      opacity: sheet.open ? 1 : 0,
      duration: hlMotion(context, HlDuration.short),
      curve: sheet.open ? HlEasing.standard : HlEasing.exit,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Semantics(
          key: const ValueKey('add-sheet'),
          container: true,
          explicitChildNodes: true,
          label: l10n.addButton,
          child: maxHeight < _roomy
              // Too little room to keep the chips put: everything scrolls.
              ? ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [...fixed, ...rowWidgets],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...fixed,
                    Flexible(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: ListView(
                          key: const ValueKey('add-suggestions'),
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: rowWidgets,
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

class const _Header({required final VoidCallback onClose})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: 7,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
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
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.addButton,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                // A tap on a web semantics button node takes the add
                // field's text input with it; this node only taps.
                child: Semantics(
                  button: true,
                  label: l10n.close,
                  onTap: onClose,
                  excludeSemantics: true,
                  child: TextButton(
                    key: const ValueKey('add-sheet-close'),
                    onPressed: onClose,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontFamily: HlFont.sans,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.close),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "6× Windeln" over "Wie getippt · Pampers · Größe 3"; what differs from
/// the first row is bold. The first row is what Enter takes.
class const _SuggestionRow({
  required final Suggestion suggestion,
  required final bool first,
  required final ParsedEntry? base,
  required final Catalog catalog,
  required final Store? ownStore,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = HummlistColors.of(Theme.of(context).brightness);
    final entry = suggestion.entry;
    final category = catalog.categories
        .where((c) => c.id == entry.categoryId)
        .firstOrNull;
    final source = sourceLabel(l10n, suggestion.source);
    final baseParts = {
      ?base?.brand?.toLowerCase(),
      ...splitProperties(base?.properties).map((p) => p.toLowerCase()),
    };
    final parts = [?entry.brand, ...splitProperties(entry.properties)];
    final store = entry.storeId == null ? null : catalog.store(entry.storeId!);
    final quantity = entry.quantity;
    final label = [
      [?quantityLabel(quantity), entry.name].join(' '),
      source,
      ...parts,
      ?store?.name,
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: first ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              spacing: 12,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    suggestion.source == SuggestionSource.due &&
                            category == null
                        ? '🔁'
                        : nameIcon(entry.name, category),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            if (quantityLabel(quantity) case final q?)
                              TextSpan(
                                text: '$q ',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            TextSpan(text: entry.name),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: source),
                            for (final part in parts) ...[
                              const TextSpan(text: ' · '),
                              TextSpan(
                                text: part,
                                style:
                                    !first &&
                                        !baseParts.contains(part.toLowerCase())
                                    ? TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      )
                                    : null,
                              ),
                            ],
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                ?(ownStore == null
                    ? null
                    : StoreBadge(ownStore!, height: 24, maxWidth: 120)),
                if (first)
                  Container(
                    width: 36,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      shape: HexBorder(side: BorderSide(color: t.textMuted)),
                    ),
                    child: Icon(
                      Icons.keyboard_return,
                      size: 16,
                      color: t.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "✓ Hinzugefügt: Milch → Edeka" with Rückgängig, or that it is already
/// on the list: where the eyes are, until the next keystroke.
class const _AddedNote(
  final AddResult result, {
  required final Catalog catalog,
  required final VoidCallback onUndo,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (text, added) = switch (result) {
      Added(:final item) => (
        switch (item.storeId == null ? null : catalog.store(item.storeId!)) {
          final store? => l10n.addedTo(item.name, store.name),
          null => l10n.addedItem(item.name),
        },
        true,
      ),
      AlreadyOnList(:final item) => (l10n.alreadyOnList(item.name), false),
      NothingToAdd() => ('', false),
    };
    return Padding(
      key: const ValueKey('added-note'),
      padding: const EdgeInsets.fromLTRB(24, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                added ? '✓ $text' : text,
                style: TextStyle(fontSize: 16, color: scheme.onSurface),
              ),
            ),
          ),
          if (added)
            // Exposed like the rows: a tap on a web semantics button node
            // takes the text input's connection with it.
            Semantics(
              container: true,
              button: true,
              label: l10n.undo,
              excludeSemantics: true,
              onTap: onUndo,
              child: TextButton(
                key: const ValueKey('added-undo'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.standard,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: onUndo,
                child: Text(l10n.undo),
              ),
            ),
        ],
      ),
    );
  }
}

/// Job 32b, under the added note while the sheet is open: "Möhren steht
/// schon auf der Liste" with Zusammenführen, then "Zusammengeführt: 1,5 kg
/// Möhren" with Rückgängig.
class const _DedupeNote({
  required final String text,
  required final String action,
  required final Key actionKey,
  required final VoidCallback onAction,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                text,
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          // Exposed like the added note's Rückgängig: a tap on a web
          // semantics button node takes the text input's connection with it.
          Semantics(
            container: true,
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: onAction,
            child: TextButton(
              key: actionKey,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.standard,
                minimumSize: const Size(0, 44),
              ),
              onPressed: onAction,
              child: Text(action),
            ),
          ),
        ],
      ),
    );
  }
}

String sourceLabel(AppLocalizations l10n, SuggestionSource source) =>
    switch (source) {
      SuggestionSource.typed => l10n.suggestionTyped,
      SuggestionSource.history => l10n.suggestionHistory,
      SuggestionSource.pack => l10n.suggestionPack,
      SuggestionSource.variant => l10n.suggestionVariant,
      SuggestionSource.size => l10n.suggestionSize,
      SuggestionSource.brand => l10n.suggestionBrand,
      SuggestionSource.catalog => l10n.suggestionCatalog,
      SuggestionSource.due => l10n.suggestionDue,
    };

/// Eigenschaften are stored joined with ", "; a decimal comma ("1,5 %")
/// stays inside its part.
List<String> splitProperties(String? properties) => [
  for (final part in (properties ?? '').split(RegExp(r',\s+|\s*[·;]\s*')))
    if (part.trim().isNotEmpty) part.trim(),
];
