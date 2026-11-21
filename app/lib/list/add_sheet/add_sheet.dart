import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/compact_details.dart';
import 'package:family_groceries/list/add_sheet/match_rows.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart'
    show quantityLabel;
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

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

  /// A match row's tap (flag `add-match-rows`, job 324).
  required final ValueChanged<MatchRow> onMatch,
  required final VoidCallback onClose,

  /// Folds, picks and Undo inside the sheet hand focus back to the input.
  required final VoidCallback onPicked,

  /// Takes the open sheet's height, the add bar not included: the list
  /// behind it keeps its last rows above it (flag `add-feedback-list`).
  final ValueNotifier<double>? extent,
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

  /// [Environment.addSheetTiming] only: the time from a key to the frame
  /// with its first rows, and to the frame with the server's answer, per
  /// text, and the device's time to make the rows. Logs the text's length,
  /// never the text.
  var _timedText = '';
  var _timedKey = '';
  var _timedRows = const <Suggestion>[];
  var _answerTimed = false;

  void _timeRows(AddSheetState sheet, AddSheetCubit cubit) {
    final text = sheet.text.trim();
    if (text.isEmpty) {
      _timedText = '';
      return;
    }
    final clock = cubit.clock;
    final String step;
    if (text != _timedText) {
      _timedText = text;
      final rank = clock.rank;
      _answerTimed = rank == null;
      step = rank == null ? 'cached' : 'rows rank=${_ms(rank)} ms';
    } else if (sheet.text != _timedKey) {
      // A space: the device's rows again, not the server's answer.
      _timedKey = sheet.text;
      _timedRows = sheet.suggestions;
      return;
    } else if (!_answerTimed && !identical(sheet.suggestions, _timedRows)) {
      _answerTimed = true;
      step = 'answer';
    } else {
      return;
    }
    _timedKey = sheet.text;
    _timedRows = sheet.suggestions;
    final line =
        '[add-sheet timing] stable=${cubit.stableRows ? 'on' : 'off'} '
        'catalog=${cubit.deviceRanked ? 'on' : 'off'} '
        'len=${text.length} $step';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_timedText == text) {
        debugPrint('$line ${_ms(clock.sinceKey.elapsed)} ms');
      }
    });
  }

  static String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);

  /// The system back closes the compact sheet, which has no close key. A
  /// field in it that holds the back (a new store's name) takes it first:
  /// this listener runs before the route's own pop.
  Future<bool> _back() async {
    if (ModalRoute.of(context)?.popDisposition ==
        RoutePopDisposition.doNotPop) {
      await Navigator.of(context).maybePop();
      return true;
    }
    widget.onClose();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final sheet = context.watch<AddSheetCubit>().state;
    final list = context.watch<ListCubit>().state;
    final open = sheet.open;
    return MultiBlocListener(
      listeners: [
        BlocListener<AddSheetCubit, AddSheetState>(
          listenWhen: (a, b) => a.open != b.open,
          listener: (_, s) => _openChanged(s.open, still),
        ),
        if (Environment.addSheetTiming)
          BlocListener<AddSheetCubit, AddSheetState>(
            listenWhen: (a, b) =>
                a.text != b.text ||
                a.suggestions != b.suggestions ||
                a.answered != b.answered,
            listener: (context, s) =>
                _timeRows(s, context.read<AddSheetCubit>()),
          ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final frame = ShoppingListView.frameFor(constraints.maxWidth, list);
          // The add bar floats over the list's bottom edge and comes in as
          // the bottom padding; the sheet stands on it.
          final bar = media.padding.bottom;
          final cubit = context.read<AddSheetCubit>();
          // Compact: the chips and an open picker may take the room up to
          // the status bar at a large text size on a small phone.
          final gap = cubit.compact ? 0 : _topGap;
          final max = constraints.maxHeight - bar - media.padding.top - gap;
          final content = _shown || open
              ? _ReportHeight(
                  to: open ? widget.extent : null,
                  child: _Content(
                    maxHeight: max < 0 ? 0 : max,
                    onTake: widget.onTake,
                    onMatch: widget.onMatch,
                    onClose: widget.onClose,
                    onPicked: widget.onPicked,
                  ),
                )
              : null;
          return Stack(
            children: [
              if (open && cubit.compact)
                BackButtonListener(
                  onBackButtonPressed: _back,
                  child: const SizedBox.shrink(),
                ),
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
              // RI2 (flag `add-feedback-list`): on the sheet's bottom edge,
              // right above the field the user types in.
              if (open && cubit.addFeedback)
                PositionedDirectional(
                  start: frame.side,
                  width: frame.columnWidth,
                  bottom: bar,
                  child: _LoadLine(loading: sheet.fetching),
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
  required final ValueChanged<MatchRow> onMatch,
  required final VoidCallback onClose,
  required final VoidCallback onPicked,
}) extends StatefulWidget {
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState() extends State<_Content> {
  /// The rows as last built, and those held while a finger is down on one
  /// of them (flag `input-stable-rows`): a row never changes under a
  /// finger, and its tap adds what was shown when it went down. A finger on
  /// a chip or a note holds nothing.
  var _built = const <Suggestion>[];
  List<Suggestion>? _held;
  final _pointers = <int>{};

  void _down(PointerDownEvent event) {
    if (context.read<AddSheetCubit>().stableRows) {
      _pointers.add(event.pointer);
      _held ??= _built;
    }
  }

  /// Lets go after the pointer's up has reached the rows: the tap
  /// recognizer fires in the arena sweep that follows this listener.
  void _up(PointerEvent event) {
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      scheduleMicrotask(() {
        if (mounted && _pointers.isEmpty && _held != null) {
          setState(() => _held = null);
        }
      });
    }
  }

  /// The chips and rows of the last build, each with the values it was
  /// made from. Typing rebuilt them all on every key; one made from the
  /// same values is handed back as it is, and Flutter does not build an
  /// identical widget again.
  var _made = <Object, (Object, Widget)>{};
  var _making = <Object, (Object, Widget)>{};

  /// The widget made for [slot] from [from], [make]'s or the last build's.
  Widget _reuse(Object slot, Object from, Widget Function() make) {
    final made = switch (_made[slot]) {
      (final last, final widget) when last == from => widget,
      _ => make(),
    };
    _making[slot] = (from, made);
    return made;
  }

  /// A [_SuggestionRow], the last build's when nothing it shows or adds
  /// changed: its tap adds a row equal in every field.
  Widget _row(
    Key key,
    Suggestion row, {
    required bool stale,
    required bool first,
    required ParsedEntry? base,
    required Catalog catalog,
    required Store? ownStore,
    required ValueChanged<Suggestion> onTake,
    bool plus = false,
    bool compact = false,
  }) {
    final Suggestion(:source, :entry) = row;
    return _reuse(
      key,
      (
        source,
        entry.name,
        entry.brand,
        entry.properties,
        entry.quantity,
        entry.storeId,
        entry.categoryId,
        entry.deviceParsed,
        stale,
        first,
        plus,
        compact,
        base?.brand,
        base?.properties,
        (catalog, ownStore, onTake),
      ),
      () => _SuggestionRow(
        key: key,
        suggestion: row,
        stale: stale,
        first: first,
        plus: plus,
        compact: compact,
        base: base,
        catalog: catalog,
        ownStore: ownStore,
        onTap: () => onTake(row),
        onPointerDown: _down,
        onPointerUp: _up,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _made..clear();
    _made = _making;
    _making = last;
    final _Content(:maxHeight, :onTake, :onMatch, :onClose, :onPicked) = widget;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.watch<AddSheetCubit>();
    final sheet = cubit.state;
    final list = context.watch<ListCubit>();
    final catalog = list.state.catalog;
    final chains = context.select<Flags?, bool>(
      (f) => f?.isOn(openStoreAppFlag) ?? false,
    );
    final rows = _held ?? sheetRows(sheet, list);
    _built = rows;
    final rowKeys = _rowKeys(rows, byContent: cubit.stableRows);
    final first = rows.firstOrNull?.entry;
    final pickedStore = sheet.store;
    // Flag `add-feedback-list`: right after an add the rows' room shows
    // that item's details, until the next letter.
    final details = cubit.detailsItem;
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
              // Flag `add-feedback-list`: the store and category are picked
              // in the added item's details (job 288), so the header keeps
              // one height in every state.
              if (cubit.addFeedback)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _CloseButton(onClose: onClose),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 4, 10),
                  child: _reuse(
                    #chips,
                    (
                      catalog,
                      storeId,
                      categoryId,
                      pickedStore,
                      sheet.category,
                      first?.storeId,
                      first?.categoryId,
                      l10n,
                      list,
                      onPicked,
                      onClose,
                      chains,
                    ),
                    () => FoldoutChips(
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
                      chains: chains ? StoreChains.of(list) : null,
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
                ),
            ],
          ),
        ),
      ),
    ];
    final compact = cubit.compact;
    final notes = <Widget>[
      if (sheet.taken case final taken?) _MatchNote(taken),
      // Compact: an add shows in the list behind the sheet and is undone
      // there; only "already on the list" stays a note.
      if (sheet.added case final added? when !compact || added is! Added)
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
    // RI1 (flag `add-feedback-list`): rows that answer an earlier text may
    // still change until the server's answer for this one lands.
    final stale = cubit.addFeedback && sheet.carried && sheet.loading;
    // Job 340: under match rows the first suggestion is the + row.
    final plusRow = compact && sheet.matches.isNotEmpty;
    final suggestions = <Widget>[
      for (final (i, row) in rows.indexed)
        _row(
          rowKeys[i],
          row,
          stale: stale && !(plusRow && i == 0),
          // Enter takes nothing before anything is typed, nor the first
          // suggestion when it takes a match row.
          first:
              i == 0 &&
              sheet.text.trim().isNotEmpty &&
              !(plusRow && cubit.enterMatch != null),
          plus: plusRow && i == 0,
          base: plusRow && i == 0 ? row.entry : first,
          catalog: catalog,
          // A row tells its own store only while the
          // chip doesn't decide it for every row.
          ownStore:
              !(plusRow && i == 0) &&
                  pickedStore == null &&
                  row.entry.storeId != storeId
              ? catalog.store(row.entry.storeId ?? '')
              : null,
          onTake: onTake,
          compact: compact,
        ),
      if (rows.isEmpty && sheet.added == null && !plusRow)
        Padding(
          key: const ValueKey('add-sheet-empty'),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Text(
            l10n.typeToSuggest,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
    ];
    final rowWidgets = [
      ...notes,
      if (details != null)
        _AddedDetails(
          key: ValueKey('added-details-${details.id}'),
          item: details,
          onDone: onPicked,
        )
      else
        ...suggestions,
    ];
    // Flag `add-feedback-list`: the rows, the details or the notes always
    // take the room of three rows, so the sheet doesn't jump when one gives
    // way to the other, and the list behind it keeps a steady view.
    final steady = cubit.addFeedback;
    // Before typing, a note (the last add, a duplicate hint or merge) sits
    // above the capped rows, so it never pushes them out of view.
    final firstOpen = sheet.text.trim().isEmpty;
    final scaler = MediaQuery.textScalerOf(context);
    final Widget body;
    if (compact) {
      body = _CompactBody(
        onClose: onClose,
        children: [
          ...notes,
          // After an add: its chips, as tall as they are. They fit above the
          // keyboard up to 310 % on a 390 px phone and 200 % on a 360 px
          // one; beyond that they scroll rather than overflow.
          if (details case final item?)
            Flexible(
              child: SingleChildScrollView(
                child: CompactDetails(
                  key: ValueKey('added-details-${item.id}'),
                  item: item,
                  onDone: onPicked,
                ),
              ),
            )
          // Job 324: a match row just taken leaves only its note.
          else if (sheet.taken != null)
            const SizedBox.shrink()
          // Typing, or opened: the rows, at most three, the others scroll.
          // Job 340 (flag `add-match-rows`): the match rows lead the same
          // list, then the + row and the other suggestions.
          else
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _firstOpenRows * _rowExtent(scaler),
                ),
                child: ListView(
                  key: const ValueKey('add-suggestions'),
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final match in sheet.matches)
                      _MatchTile(
                        key: ValueKey(
                          'match-${match.runtimeType}-${match.item.id}',
                        ),
                        row: match,
                        catalog: catalog,
                        onTap: () => onMatch(match),
                      ),
                    ...suggestions,
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      body = maxHeight < _roomy * scaler.scale(16) / 16
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
                if (firstOpen && !steady) ...notes,
                Flexible(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: ConstrainedBox(
                      constraints: steady
                          ? BoxConstraints.tightFor(
                              height: _firstOpenRows * _rowExtent(scaler),
                            )
                          : BoxConstraints(
                              maxHeight: firstOpen
                                  ? _firstOpenRows * _rowExtent(scaler)
                                  : double.infinity,
                            ),
                      child: ListView(
                        key: const ValueKey('add-suggestions'),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: firstOpen && !steady
                            ? suggestions
                            : rowWidgets,
                      ),
                    ),
                  ),
                ),
              ],
            );
    }
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
          child: body,
        ),
      ),
    );
  }
}

/// The rows' keys: by position, or, with the flag `input-stable-rows`, by
/// what each row adds, so a row's element follows its content.
List<Key> _rowKeys(List<Suggestion> rows, {required bool byContent}) {
  final seen = <String, int>{};
  return [
    for (final (i, row) in rows.indexed)
      if (!byContent)
        ValueKey('suggestion-$i')
      else
        switch (seen.update(row.key, (n) => n + 1, ifAbsent: () => 0)) {
          0 => ValueKey('suggestion-${row.key}'),
          final n => ValueKey('suggestion-${row.key}#$n'),
        },
  ];
}

/// The compact sheet (flag `add-sheet-compact`, job 322): the grab handle
/// over [children], as tall as they are. A tap on the handle or a swipe
/// down closes it; for a screen reader the handle is Schließen.
class const _CompactBody({
  required final VoidCallback onClose,
  required final List<Widget> children,
}) extends StatefulWidget {
  @override
  State<_CompactBody> createState() => _CompactBodyState();
}

class _CompactBodyState() extends State<_CompactBody> {
  /// How far the current drag went down.
  var _dragged = 0.0;

  static const _closeDistance = 48.0;
  static const _closeVelocity = 700.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onClose = widget.onClose;
    return GestureDetector(
      onVerticalDragStart: (_) => _dragged = 0,
      onVerticalDragUpdate: (d) => _dragged += d.delta.dy,
      onVerticalDragEnd: (d) {
        if (_dragged > _closeDistance ||
            d.velocity.pixelsPerSecond.dy > _closeVelocity) {
          onClose();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Exposed like the rows: a tap on a web semantics button node
          // takes the add field's text input with it; this node only taps.
          Semantics(
            container: true,
            button: true,
            label: l10n.close,
            onTap: onClose,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('add-sheet-grabber'),
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              // As slim as it goes: at 200 % on a 360 px phone the chips and
              // an open picker need every pixel above the keyboard.
              child: const SizedBox(
                height: 12,
                child: Stack(children: [_GrabHandle(top: 4)]),
              ),
            ),
          ),
          ...widget.children,
        ],
      ),
    );
  }
}

/// The sheet's grab handle, centred over the chips.
class const _GrabHandle({final double top = 7}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Positioned(
    top: top,
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
    final t = SnacklistColors.of(Theme.of(context).brightness);
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

  /// Dimmed: it answers an earlier text and may still change (RI1).
  required final bool stale,
  required final bool first,

  /// The add sheet's + row under match rows (job 324): a + for its icon.
  required final bool plus,

  /// The compact sheet has no return key: Enter's row is only tinted.
  required final bool compact,
  required final ParsedEntry? base,
  required final Catalog catalog,
  required final Store? ownStore,
  required final VoidCallback onTap,
  required final PointerDownEventListener onPointerDown,
  required final ValueChanged<PointerEvent> onPointerUp,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = SnacklistColors.of(Theme.of(context).brightness);
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
      hint: stale ? l10n.suggestionStale : null,
      excludeSemantics: true,
      onTap: onTap,
      // A Listener paints nothing and adds no semantics node.
      child: Listener(
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerUp,
        child: Material(
          color: first ? scheme.secondaryContainer : Colors.transparent,
          // Still takes a tap: what it shows is what it adds.
          child: AnimatedOpacity(
            key: const ValueKey('suggestion-stale'),
            opacity: stale ? _staleOpacity : 1,
            duration: hlMotion(context, HlDuration.short),
            child: InkWell(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: _rowHeight),
                // The 48 px Enter hex, this and the border make the 60 px row.
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 24,
                      child: plus
                          ? Icon(Icons.add, size: 22, color: scheme.primary)
                          : suggestion.source == SuggestionSource.due &&
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
                                            !baseParts.contains(
                                              part.toLowerCase(),
                                            )
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
                    if (first && !compact)
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
        ),
      ),
    );
  }
}

/// "10× Eier": a Menge and a name as the list writes them.
String _withQuantity(String? quantity, String name) =>
    [?quantityLabel(quantity), name].join(' ');

/// "Edeka · Weihenstephan · 1,5 %": the item's store, brand and details.
String _matchDetails(Item item, Catalog catalog) => [
  ?catalog.store(item.storeId ?? '')?.name,
  ?item.brand,
  ...splitProperties(item.properties),
].join(' · ');

/// Job 324 (AM2, flag `add-match-rows`): an item already on the list as
/// what a tap does with it. Merge in accent blue with the Menge it would
/// have, tick off in mint with the name struck through, back on the list in
/// grey with its own Menge; the store, brand and details below. Full width
/// and square like a [_SuggestionRow] (job 340).
class const _MatchTile({
  required final MatchRow row,
  required final Catalog catalog,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final item = row.item;
    final (action, icon, face, ink, text) = switch (row) {
      MergeRow(:final quantity) => (
        l10n.dedupeMerge,
        Icons.call_merge,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        _withQuantity(quantity, item.name),
      ),
      TickRow() => (
        l10n.addMatchTickOff,
        Icons.check_circle_outline,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        item.name,
      ),
      ReaddRow() => (
        l10n.readd,
        Icons.replay,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        _withQuantity(item.quantity, item.name),
      ),
    };
    final details = _matchDetails(item, catalog);
    return Semantics(
      container: true,
      button: true,
      label: [action, text, if (details.isNotEmpty) details].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: face,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: _rowHeight),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 20, color: ink),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 16,
                          height: _nameLeading,
                          fontWeight: FontWeight.w700,
                          color: ink,
                          decoration: row is TickRow
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the match row just taken did, until the next letter (job 324):
/// "Zusammengeführt: 2× Nudeln", "Nudeln abgehakt", "Wieder auf der Liste:
/// 10× Eier".
class const _MatchNote(final MatchRow taken) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final item = taken.item;
    final (icon, text) = switch (taken) {
      MergeRow(:final quantity) => (
        Icons.call_merge,
        l10n.dedupeMerged(_withQuantity(quantity, item.name)),
      ),
      TickRow() => (Icons.check_circle_outline, l10n.itemTicked(item.name)),
      ReaddRow() => (
        Icons.replay,
        l10n.addMatchReadded(_withQuantity(item.quantity, item.name)),
      ),
    };
    return Padding(
      key: const ValueKey('match-note'),
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                text,
                style: TextStyle(fontSize: 16, color: scheme.onSurface),
              ),
            ),
          ),
        ],
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

/// A row that may still change shows at this strength (RI1).
const _staleOpacity = 0.55;

/// How long a request for rows may take before the load line shows: a
/// quick answer never flashes it (RI2).
const loadLineDelay = Duration(milliseconds: 150);

/// RI2: a thin looping line while the server is asked for the rows of
/// what is typed, from [loadLineDelay] on. With reduced motion it stands
/// still.
class const _LoadLine({required final bool loading}) extends StatefulWidget {
  @override
  State<_LoadLine> createState() => _LoadLineState();
}

class _LoadLineState() extends State<_LoadLine> {
  Timer? _delay;
  var _shown = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_LoadLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      _follow();
    }
  }

  void _follow() {
    _delay?.cancel();
    if (!widget.loading) {
      _shown = false;
      return;
    }
    _delay = Timer(loadLineDelay, () {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final label = AppLocalizations.of(context).suggestionsLoading;
    return KeyedSubtree(
      key: const ValueKey('add-sheet-loading'),
      child: MediaQuery.disableAnimationsOf(context)
          ? Semantics(
              container: true,
              role: SemanticsRole.loadingSpinner,
              label: label,
              child: SizedBox(
                height: 2,
                child: ColoredBox(color: scheme.primary.withValues(alpha: 0.6)),
              ),
            )
          : LinearProgressIndicator(
              semanticsLabel: label,
              minHeight: 2,
              color: scheme.primary,
              backgroundColor: Colors.transparent,
            ),
    );
  }
}

/// Tells [to] its child's height after each layout that changed it.
class const _ReportHeight({
  required final ValueNotifier<double>? to,
  required super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(to);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.to = to;
}

class _RenderReportHeight(ValueNotifier<double>? to) extends RenderProxyBox {
  var to = to;

  @override
  void performLayout() {
    super.performLayout();
    final notifier = to;
    final height = size.height;
    if (notifier != null && notifier.value != height) {
      // Not during layout: the list behind the sheet builds on it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached && to == notifier) {
          notifier.value = height;
        }
      });
    }
  }
}

/// The details of the item just added in place of the rows (flag
/// `add-feedback-list`): the edit sheet's fields under the name, which was
/// just picked; its store and category are the sheet's chips meanwhile.
/// A stepper saves at once, typing after a pause, the next letter in the
/// input or the sheet's closing (AddSheetCubit.editDetails).
class const _AddedDetails({
  required final Item item,
  required final VoidCallback onDone,
  super.key,
}) extends StatefulWidget {
  @override
  State<_AddedDetails> createState() => _AddedDetailsState();
}

class _AddedDetailsState() extends State<_AddedDetails> {
  late final _brand = TextEditingController(text: widget.item.brand);
  late final _quantity = TextEditingController(text: widget.item.quantity);
  late final _properties = TextEditingController(text: widget.item.properties);

  @override
  void initState() {
    super.initState();
    _follow(_brand, (value) => ItemChanges(brand: SetTo(value)));
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
    _brand.dispose();
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
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: ItemDetailFields(
        keyPrefix: 'added',
        brand: _brand,
        quantity: _quantity,
        properties: _properties,
        onStep: sheet.saveDetails,
        onSubmitted: () {
          sheet.saveDetails();
          widget.onDone();
        },
        inLine: (before, after) => FoldoutChips(
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
          onCategory: (id) {
            sheet.editDetails(ItemChanges(categoryId: id), now: true);
            widget.onDone();
          },
          // Narrower, so the category's chip peeks in on a phone and
          // tells that the line scrolls.
          chipIcons: false,
          line: ChipLine(before: before, after: after, side: 16),
        ),
      ),
    );
  }
}
