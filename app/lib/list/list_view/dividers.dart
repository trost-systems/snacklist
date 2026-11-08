import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/category_names.dart';
import 'package:family_groceries/list/list_view/hold.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter/material.dart';

/// A section's divider: the store's badge (its name), a brand-coloured
/// rule, the count and a caret. A tap folds or unfolds the section and does
/// nothing else; a hold is not an edit (Peter, job 171), the store's details
/// are under Liste → Anpassen.
class const StoreDivider({
  required final StoreSection section,

  /// Shows only the divider: folded by the user, or without items.
  required final bool folded,
  required final LeavingRows leaving,
  required final VoidCallback onToggle,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = section.store?.name ?? l10n.noStore;
    final divider = Semantics(
      container: true,
      button: true,
      expanded: !folded,
      label: l10n.storeSectionLabel(name, section.count),
      hint: folded ? l10n.expandSection : l10n.collapseSection,
      onTap: onToggle,
      excludeSemantics: true,
      // A hold, as long as a row's, claims the press, so its release is no
      // tap: a hold does nothing.
      child: Hold(
        onHold: () {},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: _Head(section: section, name: name, folded: folded),
        ),
      ),
    );
    return _ClosesWithRows(
      items: [for (final block in section.blocks) ...block.items],
      leaving: leaving,
      child: divider,
    );
  }
}

class const _Head({
  required final StoreSection section,
  required final String name,
  required final bool folded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.fromLTRB(18, 2, 10, 2),
    child: _row(context),
  );

  Widget _row(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final store = section.store;
    final t = HummlistColors.of(scheme.brightness);
    final tint = store == null ? scheme.outline : t.brand;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, outer) => Row(
        spacing: 10,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                spacing: 10,
                children: [
                  // The badge is the store's name; "no store" gets a neutral
                  // one of the same shape. The name comes before the line,
                  // which may shrink to nothing at large text.
                  StoreBadge(
                    store ?? Store(id: '', name: name, sortOrder: 0),
                    height: 32,
                    maxWidth: (constraints.maxWidth - 10).clamp(0, 1e9),
                  ),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(HlRadius.full),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // At most half the row, so large text wraps the count instead of
          // squeezing the store's badge to nothing.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: outer.maxWidth / 2),
            child: Text.rich(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              TextSpan(
                children: [
                  TextSpan(
                    text: '${section.count}',
                    style: TextStyle(
                      fontFamily: HlFont.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(text: ' ${l10n.itemsWord(section.count)}'),
                ],
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          // The fold key: a raised hex the size of a target, like the add
          // sheet's keys, so the control reads as one. The whole row taps.
          SizedBox.fromSize(
            size: const Size(52, HlSize.target),
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
                  child: AnimatedRotation(
                    turns: folded ? -0.25 : 0,
                    duration: reduce ? Duration.zero : HlDuration.short,
                    curve: HlEasing.standard,
                    child: Icon(Icons.expand_more, size: 24, color: t.text),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A category's quiet divider inside a section: its name in small faded
/// capitals and a hairline. It reacts to no press.
class const CategoryDivider({
  required final CategoryBlock block,
  required final LeavingRows leaving,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = block.category;
    final label = category == null
        ? l10n.sortingItem
        : categoryLabel(category, l10n);
    final divider = Semantics(
      container: true,
      header: true,
      // The category's full name, as the edit sheet's chip calls it.
      label: category == null ? label : categoryName(category, l10n),
      excludeSemantics: true,
      child: _Line(label: label),
    );
    return _ClosesWithRows(
      items: block.items,
      leaving: leaving,
      child: divider,
    );
  }
}

/// A store or category divider closes with its rows when they are all
/// ticked, so the last row and its heading leave as one motion, not a row
/// that closes and a heading that pops.
class const _ClosesWithRows({
  required final List<Item> items,
  required final LeavingRows leaving,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: leaving.ids,
    builder: (context, leaving, child) {
      final closing =
          items.isNotEmpty && items.every((i) => leaving.contains(i.id));
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: closing ? 1 : 0),
        duration: closing ? rowLeaveDuration : Duration.zero,
        builder: (context, t, child) => t == 0
            ? child!
            : ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 1 - rowLeaveClose.transform(t),
                  child: Opacity(
                    opacity: 1 - rowLeaveFade.transform(t),
                    child: child,
                  ),
                ),
              ),
        child: child,
      );
    },
    child: child,
  );
}

class const _Line({required final String label}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = Color.lerp(scheme.surface, scheme.onSurfaceVariant, 0.75)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 10,
          children: [
            // Large text wraps a long name instead of running it past the
            // row.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - 10).clamp(0, 1e9),
              ),
              child: Text(
                // German capitals spell ß as SS (SÜSSES), as CSS does.
                label.toUpperCase().replaceAll('ß', 'SS'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HlSectionLabel.overline(faded),
              ),
            ),
            Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
          ],
        ),
      ),
    );
  }
}
