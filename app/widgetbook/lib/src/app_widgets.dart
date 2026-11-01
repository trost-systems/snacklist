import 'dart:async';

import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/drag.dart';
import 'package:family_groceries/list/list_view/explainer.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hummlist_widgetbook/src/fixtures.dart' as fixtures;
import 'package:hummlist_widgetbook/src/story.dart';

const _path = 'Hummlist';

/// The app's own widgets from `lib/list`, built standalone.
final appComponents = [
  component(_path, 'StoreBadge', [
    plain('Ketten', (context) => const _Badges(fixtures.seededStores)),
    plain('Eigene Läden', (context) => const _Badges(fixtures.ownStores)),
    plain(
      'Langer Name',
      (context) => const StoreBadge(
        Store(
          id: 'long',
          name: 'Bioladen am Wochenmarkt Süd Großhandel',
          sortOrder: 0,
        ),
      ),
    ),
  ]),
  component(_path, 'ExplainerCard', [
    plain(
      'Hinweis',
      (context) => SizedBox(width: 390, child: ExplainerCard(onDismiss: () {})),
    ),
  ]),
  component(_path, 'FoldoutChips', [
    plain('Laden und Kategorie', (context) => const _Chips()),
    plain('Geändert', (context) => const _Chips(changed: true)),
    plain('Läden offen', (context) => const _Chips(storesOpen: true)),
    plain(
      'Viele Läden (Suche)',
      (context) => _Chips(storesOpen: true, catalog: fixtures.manyStores),
    ),
  ]),
  component(_path, 'StoreNameField', [
    plain(
      'Neuer Laden',
      (context) => SizedBox(
        width: 390,
        child: StoreNameField(
          initial: 'Rewe',
          confirmLabel: AppLocalizations.of(context).storeCreateConfirm,
          onConfirm: (_) async => false,
          onCancel: () {},
        ),
      ),
    ),
    plain(
      'Leer',
      (context) => SizedBox(
        width: 390,
        child: StoreNameField(
          confirmLabel: AppLocalizations.of(context).storeCreateConfirm,
          onConfirm: (_) async => false,
          onCancel: () {},
        ),
      ),
    ),
  ]),
  component(_path, 'Liste', [
    plain('Ausschnitt', (context) => const _ListExcerpt()),
    plain('Eintrag', (context) => _ListExcerpt(only: fixtures.items[2])),
    plain(
      'Neuer Eintrag',
      (context) => _ListExcerpt(only: fixtures.items[0], fresh: true),
    ),
    plain(
      'Laden zugeklappt',
      (context) => const _ListExcerpt(folded: {'lidl'}),
    ),
    plain('Abhaken (Animation)', (context) => const _TickLoop()),
    plain('Abgehakt', (context) => const _TickLoop(still: true)),
  ]),
];

class const _Badges(final List<Store> stores) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: HlSpace.s3,
    children: [
      for (final store in stores)
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s3,
          children: [StoreBadge(store)],
        ),
    ],
  );
}

class const _Chips({
  final bool changed = false,
  final bool storesOpen = false,
  final Catalog? catalog,
}) extends StatefulWidget {
  @override
  State<_Chips> createState() => _ChipsState();
}

class _ChipsState() extends State<_Chips> {
  String? _store = 'lidl';
  String? _category = 'produce';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 390,
      child: FoldoutChips(
        catalog: widget.catalog ?? fixtures.catalog,
        storeId: _store,
        categoryId: _category,
        storeLabel: l10n.noStore,
        categoryLabel: l10n.categoryAuto,
        storesOpen: widget.storesOpen,
        onCreateStore: (name) async =>
            Store(id: 'story-$name', name: name, sortOrder: 99),
        storeChanged: widget.changed,
        categoryChanged: widget.changed,
        onStore: (id) => setState(() => _store = id),
        onCategory: (id) => setState(() => _category = id),
      ),
    );
  }
}

/// The list as the app lays it out, from the app's own sections: store
/// dividers, category dividers and rows. A tap on a row ticks it off, a tap
/// on a store divider folds it; "Zurücksetzen" brings the items back.
class const _ListExcerpt({
  final Item? only,
  final bool fresh = false,
  final Set<String> folded = const {},
}) extends StatefulWidget {
  @override
  State<_ListExcerpt> createState() => _ListExcerptState();
}

class _ListExcerptState() extends State<_ListExcerpt> {
  final _session = DragSession();
  late var _items = _initial;
  late final _folded = {...widget.folded};

  List<Item> get _initial => switch (widget.only) {
    final item? => [item],
    null => fixtures.items,
  };

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _tick(Item item) =>
      setState(() => _items = [..._items.where((i) => i.id != item.id)]);

  @override
  Widget build(BuildContext context) {
    final sections = sectionsOf(
      _items,
      fixtures.catalog,
    ).where((s) => s.count > 0);
    return SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections) ...[
            StoreDivider(
              section: section,
              folded: _folded.contains(section.key),
              session: _session,
              onToggle: () => setState(
                () => _folded.contains(section.key)
                    ? _folded.remove(section.key)
                    : _folded.add(section.key),
              ),
              onMenu: () {},
              onDropItem: (_, _) {},
              onDropStore: (_, _) {},
              onMoveUp: null,
              onMoveDown: null,
            ),
            if (!_folded.contains(section.key))
              for (final block in section.blocks) ...[
                CategoryDivider(
                  sectionKey: section.key,
                  storeId: section.store?.id,
                  block: block,
                  session: _session,
                  onMenu: () {},
                  onDropItem: (_, _) {},
                  onDropCategory: (_, _) {},
                  onMoveUp: null,
                  onMoveDown: null,
                ),
                for (final (i, item) in block.items.indexed)
                  ItemRow(
                    key: ValueKey(item.id),
                    item: item,
                    category: block.category,
                    block: block.items,
                    session: _session,
                    fresh: widget.fresh,
                    last: i == block.items.length - 1,
                    onVisible: (_) {},
                    onTick: _tick,
                    onEdit: (_) {},
                    onDelete: _tick,
                    onDrop: (_, _) {},
                  ),
              ],
          ],
          if (widget.only == null)
            Padding(
              padding: const EdgeInsets.only(top: HlSpace.s4),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _items = _initial),
                  child: const Text('Zurücksetzen'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three rows of the list; a synthetic finger taps the middle one, its line
/// draws, the row closes and the row below moves up; after a pause it is
/// back and the loop starts again. [still] shows the struck row instead:
/// reduced motion, so it stays struck and never leaves.
class const _TickLoop({final bool still = false}) extends StatefulWidget {
  @override
  State<_TickLoop> createState() => _TickLoopState();
}

class _TickLoopState() extends State<_TickLoop> {
  static const _rest = Duration(milliseconds: 900);
  // Its own pointer device, so the real mouse does not cancel its taps.
  static var _nextDevice = 0x5700;

  final _session = DragSession();
  final _device = _nextDevice++;
  final _target = GlobalKey();
  var _round = 0;
  Timer? _timer;

  List<Item> get _rows => [
    fixtures.items[0],
    fixtures.items[2],
    fixtures.items[3],
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer(_rest, _tap);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _tap() {
    final box = _target.currentContext?.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize) {
      return;
    }
    final at = box.localToGlobal(box.size.center(Offset.zero));
    final view = View.of(context).viewId;
    GestureBinding.instance
      ..handlePointerEvent(
        PointerDownEvent(
          viewId: view,
          pointer: _device,
          device: _device,
          position: at,
        ),
      )
      ..handlePointerEvent(
        PointerUpEvent(
          viewId: view,
          pointer: _device,
          device: _device,
          position: at,
        ),
      );
  }

  void _ticked(Item _) {
    if (widget.still) {
      return;
    }
    // The closed row stays gone for a beat before it is back.
    _timer = Timer(_rest, () {
      setState(() => _round++);
      _timer = Timer(_rest, _tap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    Category? category(Item item) =>
        fixtures.categories.where((c) => c.id == item.categoryId).firstOrNull;
    final list = SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, item) in rows.indexed)
            KeyedSubtree(
              key: i == 1 ? _target : null,
              child: ItemRow(
                key: ValueKey('${item.id}-$_round'),
                item: item,
                category: category(item),
                block: rows,
                session: _session,
                fresh: false,
                last: i == rows.length - 1,
                onVisible: (_) {},
                onTick: _ticked,
                onEdit: (_) {},
                onDelete: (_) {},
                onDrop: (_, _) {},
              ),
            ),
        ],
      ),
    );
    return widget.still
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: list,
          )
        : list;
  }
}
