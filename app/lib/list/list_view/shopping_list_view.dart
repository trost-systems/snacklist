import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/explainer.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/tips/tip_card.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything between the header and the add bar: the explainer card, the
/// stores as sections with their categories and items in walk order, and
/// the recently used items. Ticking, editing and folding happen here; the
/// order is changed in Anpassen. It needs a [ListCubit] above it.
/// Where the list's columns sit: `side` from either edge, each
/// `columnWidth` wide.
typedef ListFrame = ({int columns, double side, double columnWidth});

class const ShoppingListView({
  /// Called when the user acts on the list, so the add field can let go of
  /// the keyboard.
  final VoidCallback? onInteract,

  /// The bar pinned over the list's top (job 148), [PreferredSizeWidget.
  /// preferredSize] tall below the top safe area. The rows scroll on under
  /// it, and a row brought into view (focus, a screen reader) stops below
  /// it: the viewport counts a pinned sliver as covering the rows.
  final PreferredSizeWidget? header,
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
    shownSections(sectionsOf(state.items.values, state.catalog)).length,
  );

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState() extends State<ShoppingListView> {
  final _leaving = LeavingRows();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  late final AppLifecycleListener _lifecycle;

  /// Fresh items on screen now, and the timers that mark them seen.
  final _visibleFresh = <String>{};
  final _seenTimers = <String, Timer>{};
  var _onScreen = _shows(WidgetsBinding.instance.lifecycleState);
  ListLinks? _links;

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
    _links = context.read<ListLinks?>()?..changes.addListener(_linked);
    // A cold start's link came before this list was built.
    _linked();
  }

  @override
  void dispose() {
    _links?.changes.removeListener(_linked);
    _cancelSeenTimers();
    _lifecycle.dispose();
    _scroll.dispose();
    _leaving.dispose();
    super.dispose();
  }

  ListCubit get _cubit => context.read<ListCubit>();

  /// A `/stores/<id>` link, once the list is loaded ([build] asks again
  /// then, and once the first resync is over). A store the device's copy
  /// lacks waits for that resync; without open items then (an unknown
  /// store, an empty one, or no answer from the server) the list stays as
  /// it is. After the frame: the router asks during its own work.
  void _linked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cubit.state.loaded) {
        return;
      }
      if (_links?.pending case StoreLink(:final storeId)) {
        final section = _sectionOf(storeId);
        if (section == null && !_cubit.state.resynced) {
          return;
        }
        _links?.take<StoreLink>();
        if (section != null) {
          unawaited(_reveal(section));
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// The section of [storeId] with open items, if any.
  StoreSection? _sectionOf(String storeId) {
    final state = _cubit.state;
    return shownSections(sectionsOf(state.items.values, state.catalog))
        .where((s) => s.store?.id == storeId && s.count > 0)
        .firstOrNull;
  }

  /// Scrolls the divider of [section] to the top, unfolding it. The rows
  /// are built lazily, so a far divider may not be there yet: the list
  /// jumps toward it and looks again, a few frames at most.
  Future<void> _reveal(StoreSection section) async {
    if (_cubit.state.prefs.folded.contains(section.key)) {
      _cubit.toggleFold(section.key);
    }
    // Until the divider is there and stays at the top: rows laid out for
    // the first time correct the list's estimated extent.
    for (var attempt = 0; attempt < 6; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      final divider = _built(ValueKey('store-${section.key}'))
          ?.findRenderObject();
      if (divider == null) {
        _jumpToward(section.key);
        continue;
      }
      final position = _scroll.position;
      final to = RenderAbstractViewport.of(divider)
          .getOffsetToReveal(divider, 0)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((to - position.pixels).abs() < 1) {
        return;
      }
      position.jumpTo(to);
    }
  }

  /// The element of [key] if the list has built it.
  Element? _built(Key key) {
    Element? found;
    void visit(Element element) {
      if (element.widget.key == key) {
        found = element;
      } else if (found == null) {
        element.visitChildren(visit);
      }
    }

    _viewport.currentContext?.visitChildElements(visit);
    return found;
  }

  /// Jumps to where the section of [key] about starts: its share of its
  /// column, by the weights the columns are balanced with.
  void _jumpToward(String key) {
    final width = _viewport.currentContext?.size?.width;
    if (width == null) {
      return;
    }
    final state = _cubit.state;
    final resting = shownSections(
      sectionsOf(state.items.values, state.catalog),
    );
    final weight = _weightIn(state);
    final column = columnsOf(
      resting,
      ShoppingListView.frameOf(width, resting.length).columns,
      weight,
    ).firstWhere((c) => c.any((s) => s.key == key), orElse: () => resting);
    double sum(Iterable<StoreSection> sections) =>
        sections.fold(0, (total, s) => total + weight(s));
    final share =
        sum(column.takeWhile((s) => s.key != key)) / math.max(1, sum(column));
    final position = _scroll.position;
    position.jumpTo(
      (share * position.maxScrollExtent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// How tall a section stands in its column, roughly: a folded one a
  /// divider, an open one its rows and category dividers too.
  static double Function(StoreSection section) _weightIn(ListState state) =>
      (s) => state.prefs.folded.contains(s.key)
      ? 1
      : 1 + s.count + 0.6 * s.blocks.length;

  void _snack(String text, {VoidCallback? undo}) {
    final l10n = AppLocalizations.of(context);
    Notices.of(context)
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
  }

  Future<void> _edit(Item item) async {
    widget.onInteract?.call();
    final cubit = _cubit;
    final changes = await showEditItemSheet(
      context,
      item: item,
      catalog: cubit.state.catalog,
      onCreateStore: cubit.addStore,
    );
    if (changes != null) {
      cubit.edit(item.id, changes);
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<ListCubit, ListState>(
    listenWhen: (a, b) => a.loaded != b.loaded || a.resynced != b.resynced,
    listener: (_, _) => _linked(),
    child: _list(context),
  );

  Widget _list(BuildContext context) {
    final state = context.watch<ListCubit>().state;
    if (!state.loaded) {
      // The bar stays while the list loads: its sync icon says offline.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?widget.header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    final list = LayoutBuilder(
      builder: (context, constraints) =>
          _scrollView(context, state, constraints.maxWidth),
    );
    if (!kIsWeb) {
      return list;
    }
    // A right click on a row opens the edit sheet, not the browser's menu.
    // Only over the list: text fields keep the browser's menu.
    return MouseRegion(
      onEnter: (_) => unawaited(BrowserContextMenu.disableContextMenu()),
      onExit: (_) => unawaited(BrowserContextMenu.enableContextMenu()),
      child: list,
    );
  }

  Widget _scrollView(BuildContext context, ListState state, double width) {
    final used = recentlyUsed(state.items.values);
    // Never more columns than sections: one store with items reads as one
    // centred column.
    final shown = shownSections(sectionsOf(state.items.values, state.catalog));
    final frame = ShoppingListView.frameOf(width, shown.length);
    final columnCount = frame.columns;
    final side = frame.side;
    bool folded(StoreSection s) => state.prefs.folded.contains(s.key);
    final columns = columnsOf(shown, columnCount, _weightIn(state));
    final fresh = context.read<ListCubit>().fresh;
    SliverList column(List<StoreSection> run) {
      final entries = _entries(run, state, folded, fresh);
      final index = {for (final (i, e) in entries.indexed) e.key: i};
      return SliverList.builder(
        itemCount: entries.length,
        findChildIndexCallback: (key) => index[key],
        itemBuilder: (context, i) => entries[i],
      );
    }

    // The bottom padding the add field comes in as (below).
    final bottom = MediaQuery.paddingOf(context).bottom + HlSpace.s5;
    // Every store empty: no section shows, the empty list says so. Alone,
    // it is centred in the room above the add field; with recently used
    // items it stays on top, so their tile shows below it.
    final body = shown.isEmpty && used.isNotEmpty
        ? const SliverToBoxAdapter(child: EmptyList())
        : shown.isEmpty
        ? SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.viewportMainAxisExtent -
                        constraints.precedingScrollExtent -
                        bottom,
                  ),
                ),
                child: const Center(child: EmptyList()),
              ),
            ),
          )
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
      slivers: [
        if (widget.header case final header?)
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeader(
              header,
              MediaQuery.paddingOf(context).top + header.preferredSize.height,
            ),
          ),
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
              const SliverToBoxAdapter(child: ListTips()),
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
                          _usedRow(state, item, last: i == used.length - 1),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // The add field floats over the list's bottom edge (job 135) and
        // comes in as the bottom padding: the last row scrolls clear of it.
        SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    );
  }

  /// A recently used item as the list's own row, icon included, faded: a
  /// tap puts it back on the list. The row's own gestures are off (no
  /// tick or hold), and so are its semantics, which would tick and
  /// delete.
  Widget _usedRow(ListState state, Item item, {required bool last}) {
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
              leaving: _leaving,
              fresh: false,
              last: last,
              onVisible: (_) {},
              onTick: _readd,
              onEdit: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  /// The dividers and rows of [run], top to bottom.
  List<Widget> _entries(
    List<StoreSection> run,
    ListState state,
    bool Function(StoreSection) folded,
    Set<String> fresh,
  ) {
    final entries = <Widget>[];
    for (final (i, section) in run.indexed) {
      final isFolded = folded(section);
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
            leaving: _leaving,
            onToggle: () => context.read<ListCubit>().toggleFold(section.key),
          ),
        ),
      );
      if (isFolded) {
        continue;
      }
      for (final block in section.blocks) {
        final category = block.category;
        entries.add(
          CategoryDivider(
            key: ValueKey('category-${section.key}-${category?.id}'),
            block: block,
            leaving: _leaving,
          ),
        );
        for (final (j, item) in block.items.indexed) {
          entries.add(
            ItemRow(
              key: ValueKey(item.id),
              item: item,
              category: category,
              leaving: _leaving,
              fresh: fresh.contains(item.id),
              last: j == block.items.length - 1,
              onVisible: (visible) => _freshVisible(item.id, visible: visible),
              onTick: _tick,
              onEdit: (item) => unawaited(_edit(item)),
              onDelete: _delete,
            ),
          );
        }
      }
    }
    return entries;
  }
}

class _PinnedHeader(final Widget child, final double extent)
    extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  /// Rows scrolled up under the bar fade out over its whole height, the
  /// status bar included, behind the bar's buttons. It grows in as they
  /// scroll in, so an unscrolled list shows the bar alone. The fade takes
  /// no taps: they reach the bar or the rows as before.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final strength = shrinkOffset / extent;
    final top = MediaQuery.paddingOf(context).top;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: strength == 0
              ? const SizedBox.shrink()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        for (final alpha in const [1.0, 1.0, 0.9, 0.0])
                          surface.withValues(alpha: alpha * strength),
                      ],
                      stops: [
                        0,
                        top / extent,
                        (top + (extent - top) / 2) / extent,
                        1,
                      ],
                    ),
                  ),
                ),
        ),
        child,
      ],
    );
  }

  @override
  bool shouldRebuild(_PinnedHeader oldDelegate) =>
      oldDelegate.child != child || oldDelegate.extent != extent;
}
