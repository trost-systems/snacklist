import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/categories_screen.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/drag.dart';
import 'package:family_groceries/list/list_view/explainer.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_layout_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything between the header and the add bar: the explainer card, the
/// stores as sections with their categories and items in walk order, and
/// the recently used items. Ticking, editing, folding and drag and drop
/// happen here; it needs a [ListCubit] above it.
/// Where the list's columns sit: `side` from either edge, each
/// `columnWidth` wide.
typedef ListFrame = ({int columns, double side, double columnWidth});

class const ShoppingListView({
  /// Room under the last row for whatever covers the list's bottom edge
  /// (the add bar, job 17).
  final double bottomInset = 24,

  /// Called when the user acts on the list, so the add field can let go of
  /// the keyboard.
  final VoidCallback? onInteract,
  super.key,
}) extends StatefulWidget {
  /// From this width the sections go in two columns, and in three from
  /// [threeColumns].
  static const twoColumns = 840.0;
  static const threeColumns = 1200.0;

  /// The widest a single column gets; between 600 and [twoColumns] the one
  /// column is centred at this width.
  static const columnWidth = 640.0;

  /// The widest a column gets in the multi-column layouts.
  static const wideColumnWidth = 560.0;

  static const columnGap = 16.0;

  /// The list's frame at [width] showing [sections] stores: its columns,
  /// centred. The add bar and sheet line up with its first column.
  static ListFrame frameOf(double width, int sections) {
    final columns = math.min(
      width >= threeColumns
          ? 3
          : width >= twoColumns
          ? 2
          : 1,
      math.max(1, sections),
    );
    final content = columns == 1
        ? math.min(width, columnWidth)
        : math.min(
            width,
            columns * wideColumnWidth + (columns - 1) * columnGap,
          );
    return (
      columns: columns,
      side: width < 600 ? 0.0 : (width - content) / 2,
      columnWidth: (content - (columns - 1) * columnGap) / columns,
    );
  }

  /// [frameOf] for the list as [state] shows it at rest.
  static ListFrame frameFor(double width, ListState state) => frameOf(
    width,
    shownSections(
      sectionsOf(state.items.values, state.catalog),
      dropping: false,
    ).length,
  );

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState()
    extends State<ShoppingListView>
    with SingleTickerProviderStateMixin {
  final _session = DragSession();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  late final Ticker _scroller = createTicker((_) => _autoScroll());
  late final AppLifecycleListener _lifecycle;

  /// Pixels per frame the list scrolls by while a drag sits in an edge zone.
  var _scrollSpeed = 0.0;

  /// Fresh items on screen now, and the timers that mark them seen.
  final _visibleFresh = <String>{};
  final _seenTimers = <String, Timer>{};
  var _onScreen = _shows(WidgetsBinding.instance.lifecycleState);

  /// Inactive still shows the app: a web tab whose window lost focus, or an
  /// iOS app under the control center.
  static bool _shows(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _onScreen = _shows(state);
        if (_onScreen) {
          _visibleFresh.forEach(_armSeen);
        } else {
          _cancelSeenTimers();
        }
      },
    );
  }

  @override
  void dispose() {
    _cancelSeenTimers();
    _lifecycle.dispose();
    _scroller.dispose();
    _scroll.dispose();
    _session.dispose();
    super.dispose();
  }

  ListCubit get _cubit => context.read<ListCubit>();

  void _snack(String text, {VoidCallback? undo}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          persist: false,
          action: undo == null
              ? null
              : SnackBarAction(label: l10n.undo, onPressed: undo),
        ),
      );
  }

  /// A fresh item counts as seen after three seconds on screen while the
  /// app shows.
  void _freshVisible(String id, {required bool visible}) {
    if (!mounted) {
      return;
    }
    if (!visible) {
      _visibleFresh.remove(id);
      _seenTimers.remove(id)?.cancel();
      return;
    }
    if (_visibleFresh.add(id)) {
      _armSeen(id);
    }
  }

  void _armSeen(String id) {
    if (!_onScreen || _seenTimers.containsKey(id)) {
      return;
    }
    _seenTimers[id] = Timer(const Duration(seconds: 3), () {
      _seenTimers.remove(id);
      _visibleFresh.remove(id);
      if (mounted) {
        _cubit.markSeen({id});
      }
    });
  }

  void _cancelSeenTimers() {
    for (final timer in _seenTimers.values) {
      timer.cancel();
    }
    _seenTimers.clear();
  }

  /// No snackbar: a tap on the item under "Zuletzt verwendet" undoes a
  /// tick (job 29b).
  void _tick(Item item) {
    widget.onInteract?.call();
    _cubit.tick(item.id);
  }

  void _delete(Item item) {
    widget.onInteract?.call();
    final cubit = _cubit..delete(item.id);
    _snack(
      AppLocalizations.of(context).itemDeleted(item.name),
      undo: () => cubit.restore(item),
    );
  }

  void _readd(Item item) {
    widget.onInteract?.call();
    _cubit.readd(item.id);
    _snack(AppLocalizations.of(context).itemReadded(item.name));
  }

  Future<void> _edit(Item item) async {
    widget.onInteract?.call();
    final cubit = _cubit;
    final result = await showEditItemSheet(
      context,
      item: item,
      catalog: cubit.state.catalog,
      onCreateStore: cubit.addStore,
    );
    switch (result) {
      case EditSaved(:final changes):
        cubit.edit(item.id, changes);
      case EditDeleted():
        if (mounted) {
          _delete(item);
        }
      case null:
        break;
    }
  }

  void _drop(Item item, ItemDrop drop) {
    widget.onInteract?.call();
    switch (drop) {
      case PlaceDrop(:final anchorId, :final edge):
        _cubit.place(item.id, anchorId: anchorId, edge: edge);
      case MoveDrop(:final storeId, :final categoryId):
        _cubit.move(item.id, categoryId: categoryId, storeId: storeId);
    }
  }

  void _moveStore(String moved, String target, Edge edge) {
    final ids = [for (final s in _cubit.state.catalog.stores) s.id];
    final next = reordered(ids, moved, target, edge);
    if (!listEquals(next, ids)) {
      unawaited(_cubit.reorderStores(next));
    }
  }

  /// Within the section of [storeId] (null: no store, whose order is the
  /// route order).
  void _moveCategory(String? storeId, String moved, String target, Edge edge) {
    final catalog = _cubit.state.catalog;
    final stops = walkingOrder(catalog, storeId);
    final ids = [for (final s in stops) s.category.id];
    final next = reordered(ids, moved, target, edge);
    if (listEquals(next, ids)) {
      return;
    }
    if (storeId == null) {
      unawaited(_cubit.reorderCategories(next));
    } else {
      unawaited(
        _cubit.setStoreLayout(storeId, next, {
          for (final s in stops)
            if (s.hidden) s.category.id,
        }),
      );
    }
  }

  Future<void> _sectionMenu(
    StoreSection section, {
    Category? category,
    VoidCallback? up,
    VoidCallback? down,
  }) async {
    widget.onInteract?.call();
    final l10n = AppLocalizations.of(context);
    final store = section.store;
    final storeName = store?.name ?? l10n.noStore;
    final choice = await showModalBottomSheet<_MenuChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          key: const ValueKey('section-menu'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                category == null
                    ? storeName
                    : categoryLabel(category, AppLocalizations.of(context)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (up != null)
              ListTile(
                key: const ValueKey('section-menu-up'),
                leading: const Icon(Icons.arrow_upward),
                title: Text(
                  category == null ? l10n.moveStoreUp : l10n.moveCategoryUp,
                ),
                onTap: () => Navigator.pop(context, _MenuChoice.up),
              ),
            if (down != null)
              ListTile(
                key: const ValueKey('section-menu-down'),
                leading: const Icon(Icons.arrow_downward),
                title: Text(
                  category == null ? l10n.moveStoreDown : l10n.moveCategoryDown,
                ),
                onTap: () => Navigator.pop(context, _MenuChoice.down),
              ),
            ListTile(
              key: const ValueKey('section-menu-layout'),
              leading: const Icon(Icons.low_priority),
              title: Text(
                store == null ? l10n.manageCategories : l10n.editStoreLayout,
              ),
              onTap: () => Navigator.pop(context, _MenuChoice.layout),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (choice) {
      case _MenuChoice.up:
        up?.call();
      case _MenuChoice.down:
        down?.call();
      case _MenuChoice.layout when store == null:
        await openCategories(context);
      case _MenuChoice.layout:
        await openStoreLayout(context, store!.id);
      case null:
        break;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_session.active.value == null || !_session.moved.value) {
      _setScrollSpeed(0);
      return;
    }
    final box = _viewport.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final y = box.globalToLocal(event.position).dy;
    final height = box.size.height;
    final zone = height * 0.08;
    const fastest = 14.0;
    _setScrollSpeed(switch (y) {
      _ when y < zone => -fastest * (1 - (y / zone).clamp(0, 1)),
      _ when y > height - zone =>
        fastest * (1 - ((height - y) / zone).clamp(0, 1)),
      _ => 0,
    });
  }

  void _onPointerEnd(PointerEvent _) {
    _setScrollSpeed(0);
    // After the drop: the drag's own end callbacks run in this same event.
    scheduleMicrotask(() {
      if (_session.active.value != null) {
        _session.end();
      }
    });
  }

  void _setScrollSpeed(double speed) {
    _scrollSpeed = speed;
    if (speed == 0 && _scroller.isActive) {
      _scroller.stop();
    } else if (speed != 0 && !_scroller.isActive) {
      _scroller.start();
    }
  }

  void _autoScroll() {
    if (!_scroll.hasClients || _session.active.value == null) {
      _setScrollSpeed(0);
      return;
    }
    final position = _scroll.position;
    final to = (position.pixels + _scrollSpeed).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to != position.pixels) {
      position.jumpTo(to);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ListCubit>().state;
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder(
        valueListenable: _session.active,
        builder: (context, active, _) => ValueListenableBuilder(
          valueListenable: _session.moved,
          builder: (context, moved, _) => _scrollView(
            context,
            state,
            active,
            constraints.maxWidth,
            // Only once the item moves: a hold that stays put edits it, and
            // the list should not jump under the finger for that.
            dropping: active is DraggedItem && moved,
          ),
        ),
      ),
    );
    final listened = Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: list,
    );
    if (!kIsWeb) {
      return listened;
    }
    // A right click on a row opens the edit sheet, not the browser's menu.
    // Only over the list: text fields keep the browser's menu.
    return MouseRegion(
      onEnter: (_) => unawaited(BrowserContextMenu.disableContextMenu()),
      onExit: (_) => unawaited(BrowserContextMenu.enableContextMenu()),
      child: listened,
    );
  }

  Widget _scrollView(
    BuildContext context,
    ListState state,
    Dragged? active,
    double width, {
    required bool dropping,
  }) {
    final sections = sectionsOf(state.items.values, state.catalog);
    final used = recentlyUsed(state.items.values);
    // The list as it stands without a drag. Columns are cut from it, so no
    // store changes column under the finger, and never more columns than
    // it has sections: one store with items reads as one centred column.
    final resting = shownSections(sections, dropping: false);
    final shown = dropping ? shownSections(sections, dropping: true) : resting;
    final frame = ShoppingListView.frameOf(width, resting.length);
    final columnCount = frame.columns;
    final side = frame.side;
    bool folded(StoreSection s) =>
        s.count == 0 ||
        active is DraggedStore ||
        state.prefs.folded.contains(s.key);
    final balanced = columnsOf(
      resting,
      columnCount,
      (s) => state.prefs.folded.contains(s.key)
          ? 1
          : 1 + s.count + 0.6 * s.blocks.length,
    );
    // The empty sections that show only while an item is dragged join the
    // column of the section before them.
    final columns = dropping ? withDropTargets(balanced, shown) : balanced;
    final fresh = context.read<ListCubit>().fresh;
    SliverList column(List<StoreSection> run) {
      final entries = _entries(run, shown, state, active, folded, fresh);
      final index = {for (final (i, e) in entries.indexed) e.key: i};
      return SliverList.builder(
        itemCount: entries.length,
        findChildIndexCallback: (key) => index[key],
        itemBuilder: (context, i) => entries[i],
      );
    }

    // Every store empty: no section shows, the empty list says so.
    final body = shown.isEmpty
        ? const SliverToBoxAdapter(child: EmptyList())
        : columnCount == 1
        ? column(shown)
        : SliverCrossAxisGroup(
            slivers: [
              for (final (i, run) in columns.indexed) ...[
                if (i > 0)
                  const SliverConstrainedCrossAxis(
                    maxExtent: ShoppingListView.columnGap,
                    sliver: SliverToBoxAdapter(),
                  ),
                // One node per column, read before the next one: sorted by
                // geometry, a screen reader would mix the stores row by row.
                SliverCrossAxisExpanded(
                  flex: 1,
                  sliver: SliverSemantics(
                    container: true,
                    explicitChildNodes: true,
                    sortKey: OrdinalSortKey(i.toDouble()),
                    sliver: column(run),
                  ),
                ),
              ],
            ],
          );
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      key: _viewport,
      controller: _scroll,
      // The dragged row is kept alive but laid out only within the cache
      // extent; the empty stores that show above it must not push it past
      // that, or it cannot tell how far it moved (`ItemRow`).
      scrollCacheExtent: ScrollCacheExtent.pixels(
        RenderAbstractViewport.defaultCacheExtent +
            (shown.length - resting.length) * _dividerBound,
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (!state.prefs.hintDismissed)
                SliverToBoxAdapter(
                  child: ExplainerCard(
                    onDismiss: context.read<ListCubit>().dismissHint,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              body,
              if (used.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ExpansionTile(
                      key: const ValueKey('recently-used'),
                      title: Text(l10n.recentlyUsed),
                      children: [
                        for (final (i, item) in used.indexed)
                          _usedRow(
                            state,
                            item,
                            used,
                            last: i == used.length - 1,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
      ],
    );
  }

  /// A recently used item as the list's own row, icon included, faded: a
  /// tap puts it back on the list. The row's own gestures are off (no
  /// tick, swipe, hold or drop), and so are its semantics, which would
  /// tick and delete.
  Widget _usedRow(
    ListState state,
    Item item,
    List<Item> used, {
    required bool last,
  }) {
    final l10n = AppLocalizations.of(context);
    final category = state.catalog.categories
        .where((c) => c.id == item.categoryId)
        .firstOrNull;
    final details = [?item.brand, ?item.properties].join(' · ');
    return Semantics(
      key: ValueKey('used-${item.id}'),
      container: true,
      button: true,
      // The name leads, as on the list's rows; the action is part of the
      // label, so a used row is not taken for a row of the list.
      label: [
        item.name,
        if (details.isNotEmpty) details,
        ?item.quantity,
        l10n.readd,
      ].join('\n'),
      onTap: () => _readd(item),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _readd(item),
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.55,
            child: ItemRow(
              item: item,
              category: category,
              block: used,
              session: _session,
              fresh: false,
              last: last,
              onVisible: (_) {},
              onTick: _readd,
              onEdit: (_) {},
              onDelete: (_) {},
              onDrop: (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  /// More than a folded store divider is tall, with its gap.
  static const _dividerBound = 120.0;

  /// The dividers and rows of [run], top to bottom.
  List<Widget> _entries(
    List<StoreSection> run,
    List<StoreSection> shown,
    ListState state,
    Dragged? active,
    bool Function(StoreSection) folded,
    Set<String> fresh,
  ) {
    final entries = <Widget>[];
    final stores = [
      for (final s in shown)
        if (s.store != null) s.store!.id,
    ];
    for (final (i, section) in run.indexed) {
      final isFolded = folded(section);
      final storeId = section.store?.id;
      final at = storeId == null ? -1 : stores.indexOf(storeId);
      VoidCallback? storeStep(int by) {
        final to = at + by;
        if (storeId == null || to < 0 || to >= stores.length) {
          return null;
        }
        return () =>
            _moveStore(storeId, stores[to], by < 0 ? Edge.before : Edge.after);
      }

      entries.add(
        Padding(
          key: ValueKey('store-${section.key}'),
          padding: EdgeInsets.only(
            top: i == 0
                ? 0
                : folded(run[i - 1])
                ? 2
                : 20,
          ),
          child: StoreDivider(
            section: section,
            folded: isFolded,
            session: _session,
            onToggle: () => context.read<ListCubit>().toggleFold(section.key),
            onMenu: () => unawaited(
              _sectionMenu(section, up: storeStep(-1), down: storeStep(1)),
            ),
            onDropItem: _drop,
            onDropStore: (moved, edge) {
              if (storeId != null) {
                _moveStore(moved, storeId, edge);
              }
            },
            onMoveUp: storeStep(-1),
            onMoveDown: storeStep(1),
          ),
        ),
      );
      if (isFolded) {
        continue;
      }
      final reordering =
          active is DraggedCategory && active.sectionKey == section.key;
      final categories = [
        for (final b in section.blocks)
          if (b.category != null) b.category!.id,
      ];
      for (final block in section.blocks) {
        final category = block.category;
        final c = category == null ? -1 : categories.indexOf(category.id);
        VoidCallback? categoryStep(int by) {
          final to = c + by;
          if (category == null || to < 0 || to >= categories.length) {
            return null;
          }
          return () => _moveCategory(
            storeId,
            category.id,
            categories[to],
            by < 0 ? Edge.before : Edge.after,
          );
        }

        entries.add(
          CategoryDivider(
            key: ValueKey('category-${section.key}-${category?.id}'),
            sectionKey: section.key,
            storeId: storeId,
            block: block,
            session: _session,
            onMenu: () => unawaited(
              _sectionMenu(
                section,
                category: category,
                up: categoryStep(-1),
                down: categoryStep(1),
              ),
            ),
            onDropItem: _drop,
            onDropCategory: (moved, edge) {
              if (category != null) {
                _moveCategory(storeId, moved, category.id, edge);
              }
            },
            onMoveUp: categoryStep(-1),
            onMoveDown: categoryStep(1),
          ),
        );
        if (reordering) {
          continue;
        }
        for (final (j, item) in block.items.indexed) {
          entries.add(
            ItemRow(
              key: ValueKey(item.id),
              item: item,
              category: category,
              block: block.items,
              session: _session,
              fresh: fresh.contains(item.id),
              last: j == block.items.length - 1,
              onVisible: (visible) => _freshVisible(item.id, visible: visible),
              onTick: _tick,
              onEdit: (item) => unawaited(_edit(item)),
              onDelete: _delete,
              onDrop: _drop,
            ),
          );
        }
      }
    }
    return entries;
  }
}

enum _MenuChoice() {
  up,
  down,
  layout,
}
