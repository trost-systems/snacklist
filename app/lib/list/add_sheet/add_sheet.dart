import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tactile.dart';
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

/// Before anything is typed the sheet shows at most this many suggestion
/// rows, whole; the others scroll. Wrapped chips on a narrow phone no
/// longer leave room for a single row cut by the input.
const _firstOpenRows = 3;

/// A suggestion row's height (its minimum; a larger text scale grows it).
const _rowHeight = 60.0;

const _nameSize = 18.0;
const _nameLeading = 1.2;
const _detailSize = 13.0;
const _detailLeading = 1.3;

/// The close button's and the Enter hex's size: a 44 px face on its edge,
/// as big as it looks, wide enough that the icon sits between the tips.
const _hexKey = Size(52, HlSize.target);

/// A suggestion row's height at [scaler], its name and details one line
/// each: 11 px padding, the 2 px gap and the border around the two lines.
double _rowExtent(TextScaler scaler) => math.max(
  _rowHeight,
  14 +
      scaler.scale(_nameSize) * _nameLeading +
      scaler.scale(_detailSize) * _detailLeading,
);

/// Room for the header, the chips and a row at text scale 1; with less, all
/// of it scrolls. The header and the chips grow with the text.
const _roomy = 200.0;

/// The rows the sheet shows: the suggestions for what is typed, or, before
/// typing, the usuals that are due, then those used lately. Alternatives
/// already on the list are left out; what was typed always stays first.
List<Suggestion> sheetRows(AddSheetState sheet, ListCubit list) {
  if (sheet.text.trim().isEmpty) {
    return [
      for (final usual in list.dueUsuals)
        Suggestion(
          SuggestionSource.due,
          ParsedEntry(name: usual.name, quantity: usual.quantity),
        ),
      for (final usual in list.recentUsuals)
        Suggestion(
          SuggestionSource.recent,
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
          // The add bar floats over the list's bottom edge and comes in as
          // the bottom padding; the sheet stands on it.
          final bar = media.padding.bottom;
          final max = constraints.maxHeight - bar - media.padding.top - _topGap;
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
                          child: const ColoredBox(color: sheetBarrier),
                        ),
                      ),
                    ),
                  ),
                ),
              // Over the list's first column, like the add field below it.
              PositionedDirectional(
                start: frame.side,
                width: frame.columnWidth,
                bottom: bar,
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
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Stack(
            children: [
              const _GrabHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 4, 10),
                child: FoldoutChips(
                  catalog: catalog,
                  storeId: storeId,
                  categoryId: categoryId,
                  storeLabel: l10n.noStore,
                  storeAuto: pickedStore == null,
                  categoryAuto: sheet.category == null,
                  categoryLabel: l10n.categoryAuto,
                  storeChanged:
                      pickedStore != null &&
                      pickedStore.value != first?.storeId,
                  categoryChanged:
                      sheet.category != null &&
                      sheet.category != first?.categoryId,
                  onCreateStore: list.addStore,
                  onStore: (id) {
                    context.read<AddSheetCubit>().pickStore(id);
                    onPicked();
                  },
                  onCategory: (id) {
                    context.read<AddSheetCubit>().pickCategory(id);
                    onPicked();
                  },
                  trailing: _CloseButton(onClose: onClose),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
    final notes = <Widget>[
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
    ];
    final suggestions = <Widget>[
      for (final (i, row) in rows.indexed)
        _SuggestionRow(
          key: ValueKey('suggestion-$i'),
          suggestion: row,
          // Enter takes nothing before anything is typed.
          first: i == 0 && sheet.text.trim().isNotEmpty,
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
    final rowWidgets = [...notes, ...suggestions];
    // Before typing, a note (the last add, a duplicate hint or merge) sits
    // above the capped rows, so it never pushes them out of view.
    final firstOpen = sheet.text.trim().isEmpty;
    final scaler = MediaQuery.textScalerOf(context);
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
          child: maxHeight < _roomy * scaler.scale(16) / 16
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
                    if (firstOpen) ...notes,
                    Flexible(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: firstOpen
                                ? _firstOpenRows * _rowExtent(scaler)
                                : double.infinity,
                          ),
                          child: ListView(
                            key: const ValueKey('add-suggestions'),
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: firstOpen ? suggestions : rowWidgets,
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

/// The sheet's grab handle, centred over the chips.
class const _GrabHandle() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Positioned(
    top: 7,
    left: 0,
    right: 0,
    child: Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(HlRadius.full),
        ),
      ),
    ),
  );
}

/// Schließen as an icon beside the chips. No title: adding happens on a
/// row or with Enter, and Peter read "Hinzufügen" up here as a button
/// (job 78).
class const _CloseButton({required final VoidCallback onClose})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    return FocusTraversalOrder(
      order: const NumericFocusOrder(4),
      // A tap on a web semantics button node takes the add field's text
      // input with it; this node only taps.
      child: Semantics(
        button: true,
        label: l10n.close,
        onTap: onClose,
        excludeSemantics: true,
        child: IconButton(
          key: const ValueKey('add-sheet-close'),
          tooltip: l10n.close,
          onPressed: onClose,
          // A tactile hex like the chips beside it (job 148).
          style:
              tactileButtonStyle(
                colors: (_) => TactileColors(
                  face: t.surfaceRaised,
                  contour: t.border,
                  edge: t.surfaceEdge,
                  focus: t.accent,
                ),
                foreground: WidgetStatePropertyAll(t.text),
                textStyle: const TextStyle(),
              ).copyWith(
                visualDensity: VisualDensity.standard,
                minimumSize: const WidgetStatePropertyAll(_hexKey),
                maximumSize: const WidgetStatePropertyAll(_hexKey),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
          icon: const Icon(Icons.close, size: 22),
        ),
      ),
    );
  }
}

/// "Windeln · 6" over "Wie getippt · Pampers · Größe 3"; what differs from
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
            constraints: const BoxConstraints(minHeight: _rowHeight),
            // The 48 px Enter hex, this and the border make the 60 px row.
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              spacing: 12,
              children: [
                SizedBox(
                  width: 24,
                  child:
                      suggestion.source == SuggestionSource.due &&
                          category == null
                      ? const Text(
                          '🔁',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontFamilyFallback: emojiFontFallback,
                          ),
                        )
                      : ItemIcon(entry.name, size: 20),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: entry.name),
                            // The Menge after the name, as typed at either
                            // end: "Karotten · 2".
                            if (quantityLabel(quantity) != null)
                              TextSpan(
                                text: ' · ${quantity!.trim()}',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: _nameSize,
                          height: _nameLeading,
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
                          fontSize: _detailSize,
                          height: _detailLeading,
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
                // The key Enter presses: a hex face on its edge, the size
                // of the close button.
                if (first)
                  SizedBox.fromSize(
                    size: _hexKey,
                    child: TactileFace(
                      states: const {},
                      colors: TactileColors(
                        face: t.surfaceRaised,
                        contour: t.border,
                        edge: t.surfaceEdge,
                        focus: t.accent,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: raisedFaces ? HlDepth.edge : 0,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.keyboard_return,
                            size: 20,
                            color: t.text,
                          ),
                        ),
                      ),
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
      child: _TextAndAction(
        text: Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            added ? '✓ $text' : text,
            style: TextStyle(fontSize: 16, color: scheme.onSurface),
          ),
        ),
        action: !added
            ? null
            :
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
                  child: Text(
                    l10n.undo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
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
      child: _TextAndAction(
        text: Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            text,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
        // Exposed like the added note's Rückgängig: a tap on a web
        // semantics button node takes the text input's connection with it.
        action: Semantics(
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
            child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

/// A note beside its action, Rückgängig or Zusammenführen. The action takes
/// at most half the width, so a large text scale doesn't squeeze the label
/// to a letter per line beside it.
class const _TextAndAction({required final Widget text, final Widget? action})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(child: text),
        ?(action == null
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: action,
              )),
      ],
    ),
  );
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
      SuggestionSource.recent => l10n.suggestionRecent,
    };

/// Eigenschaften are stored joined with ", "; a decimal comma ("1,5 %")
/// stays inside its part.
List<String> splitProperties(String? properties) => [
  for (final part in (properties ?? '').split(RegExp(r',\s+|\s*[·;]\s*')))
    if (part.trim().isNotEmpty) part.trim(),
];
