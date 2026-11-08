import 'dart:async';

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The household's lists as tabs under the list's header (job 169b K), only
/// while it has two or more: a raised hex track like the tab pill below,
/// the shown list on the honey hex, "+" at the end. It scrolls sideways when
/// the lists are wider than the row and brings the shown one into view.
class const ListTabs({super.key}) extends StatefulWidget {
  /// The track's height.
  static const height = 44.0;

  /// Whether [lists] get tabs at all.
  static bool shownFor(List<HouseholdList> lists) => lists.length > 1;

  @override
  State<ListTabs> createState() => _ListTabsState();
}

class _ListTabsState() extends State<ListTabs> {
  final _shown = GlobalKey(debugLabel: 'shown-list-tab');
  final _scroll = ScrollController();
  String? _revealed;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// After the frame that shows another list, its tab scrolls into view.
  void _reveal(String id) {
    if (_revealed == id) {
      return;
    }
    _revealed = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shown.currentContext case final tab? when mounted) {
        Scrollable.ensureVisible(tab, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final t = HummlistColors.of(brightness);
    final l10n = AppLocalizations.of(context);
    final (lists, shown) = context
        .select<ListCubit, (List<HouseholdList>, String?)>(
          (c) => (c.state.catalog.lists, c.state.shownList?.id),
        );
    if (!ListTabs.shownFor(lists)) {
      return const SizedBox.shrink();
    }
    if (shown != null) {
      _reveal(shown);
    }
    final cubit = context.read<ListCubit>();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const HexBorder(),
          shadows: HlSticker.shadow(brightness, StickerDepth.s),
        ),
        child: Material(
          color: t.surfaceRaised,
          shape: HexBorder(
            side: BorderSide(color: t.border, width: HlBorder.width),
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            key: const ValueKey('list-tabs'),
            label: l10n.listsTitle,
            explicitChildNodes: true,
            container: true,
            child: SizedBox(
              height: ListTabs.height,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                // Clear of the track's tips.
                padding: const EdgeInsets.symmetric(
                  horizontal: HlHex.tip * ListTabs.height,
                ),
                child: Row(
                  children: [
                    Semantics(
                      role: SemanticsRole.tabBar,
                      explicitChildNodes: true,
                      container: true,
                      child: Row(
                        children: [
                          for (final list in lists)
                            _Tab(
                              key: list.id == shown ? _shown : null,
                              tabKey: ValueKey('list-tab-${list.id}'),
                              label: list.name,
                              selected: list.id == shown,
                              onTap: () => cubit.showList(list.id),
                            ),
                        ],
                      ),
                    ),
                    _Tab(
                      tabKey: const ValueKey('list-tab-new'),
                      icon: Icons.add,
                      label: l10n.listNew,
                      selected: false,
                      onTap: () => unawaited(addList(context)),
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

/// Asks for a name and adds the list, which then shows; a screen reader
/// hears that it was added.
Future<void> addList(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ListCubit>();
  final view = View.of(context);
  final direction = Directionality.of(context);
  return showNameDialog(
    context,
    title: l10n.listNew,
    confirm: l10n.create,
    label: l10n.listNameLabel,
    save: (name) async {
      final list = await cubit.createList(name);
      if (list == null) {
        return false;
      }
      unawaited(
        SemanticsService.sendAnnouncement(
          view,
          l10n.listAdded(list.name),
          direction,
        ),
      );
      return true;
    },
  );
}

/// One tab: a list's name, or the "+" ([icon] with [label] for screen
/// readers). The shown list sits on the honey hex.
class const _Tab({
  required final Key tabKey,
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
  final IconData? icon,
  super.key,
}) extends StatefulWidget {
  static const _indicatorHeight = 32.0;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState() extends State<_Tab> {
  var _focused = false;
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    final _Tab(:label, :selected, :onTap, :icon) = widget;
    final color = selected ? t.onHoney : t.text;
    final indicator = Container(
      height: _Tab._indicatorHeight,
      constraints: const BoxConstraints(minWidth: _Tab._indicatorHeight + 8),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        color: selected
            ? t.honey
            : _hovered || _pressed
            ? t.surfaceSunken
            : null,
        shape: HexBorder(
          side: selected
              ? BorderSide(color: t.border, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: switch (icon) {
        final icon? => Icon(icon, size: 20, color: color),
        null => Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      },
    );
    return MergeSemantics(
      child: Semantics(
        role: icon == null ? SemanticsRole.tab : null,
        selected: icon == null ? selected : null,
        button: true,
        label: icon == null ? null : label,
        child: InkWell(
          key: widget.tabKey,
          onTap: onTap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          onHover: (hovered) => setState(() => _hovered = hovered),
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: SizedBox(
            height: ListTabs.height,
            child: Center(
              child: CustomPaint(
                foregroundPainter: _focused ? _Ring(t.accent) : null,
                child: indicator,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The focus ring round a tab's hex, [HlFocus.ringGap] off it.
class const _Ring(final Color color) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      const HexBorder().pathFor(
        Offset.zero & size,
        outset: HlFocus.ringGap + HlFocus.ringWidth / 2,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HlFocus.ringWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) => oldDelegate.color != color;
}
