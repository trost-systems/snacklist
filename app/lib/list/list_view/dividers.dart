import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/category_names.dart';
import 'package:family_groceries/list/list_view/hold.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:material_ui/material_ui.dart';

/// A section's divider, laid out like „Zuletzt verwendet“'s header: the
/// store's name as plain text, a brand-coloured rule, the count and a plain
/// caret. A tap folds or unfolds the section and does nothing else; a hold
/// is not an edit (Peter, job 171), the store's details are under Liste →
/// Anpassen. With [app] (flag `open-store-app`, job 313) a key after the
/// caret opens the store's app: its own target, outside the fold.
class const StoreDivider({
  required final StoreSection section,

  /// Shows only the divider: folded by the user, or without items.
  required final bool folded,
  required final LeavingRows leaving,
  required final VoidCallback onToggle,
  final RetailerApp? app,
  final VoidCallback? onOpenApp,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = section.store?.name ?? l10n.noStore;
    final app = this.app;
    final fold = Semantics(
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
          child: _Head(
            section: section,
            name: name,
            folded: folded,
            keyed: app != null,
          ),
        ),
      ),
    );
    return _ClosesWithRows(
      items: [for (final block in section.blocks) ...block.items],
      leaving: leaving,
      child: app == null
          ? fold
          : Row(
              children: [
                Expanded(child: fold),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 10,
                    end: HlSpace.s1,
                  ),
                  child: _AppKey(
                    key: ValueKey('store-app-${section.key}'),
                    app: app,
                    onOpen: onOpenApp ?? () {},
                  ),
                ),
              ],
            ),
    );
  }
}

/// The open-in-new key: a 48 px target with the app's name for screen
/// readers. A hold claims the press, as the header's does, so its release
/// opens nothing.
class const _AppKey({
  required final RetailerApp app,
  required final VoidCallback onOpen,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    // A label, not a tooltip: on the web a showing tooltip moves the
    // route's semantics.
    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context).storeAppOpen(app.name),
      excludeSemantics: true,
      onTap: onOpen,
      child: Hold(
        onHold: () {},
        child: SizedBox.square(
          dimension: HlSize.target,
          child: IconButton(
            onPressed: onOpen,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.open_in_new, size: 22, color: t.brand),
          ),
        ),
      ),
    );
  }
}

class const _Head({
  required final StoreSection section,
  required final String name,
  required final bool folded,

  /// The app key follows outside the fold area, with its own padding.
  required final bool keyed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: EdgeInsetsDirectional.fromSTEB(18, 2, keyed ? 0 : 24, 2),
    child: _row(context),
  );

  Widget _row(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final store = section.store;
    final t = SnacklistColors.of(scheme.brightness);
    final tint = store == null ? scheme.outline : t.brand;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // From 200 % the word would take the room the name needs; the
    // screen reader label keeps it.
    final numberOnly = MediaQuery.textScalerOf(context).scale(1) >= 2;
    return LayoutBuilder(
      builder: (context, outer) => Row(
        spacing: 10,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                spacing: 10,
                children: [
                  // The name as „Zuletzt verwendet“ shows its title (Peter,
                  // job 313): plain text in ListTile's title style. It comes
                  // before the line, which may shrink to nothing at large
                  // text, and wraps once before it is cut.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (constraints.maxWidth - 10).clamp(0, 1e9),
                    ),
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: store == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
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
          // squeezing the store's name to nothing.
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
                  if (!numberOnly)
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
          // ExpansionTile's caret: plain, in its collapsed colour. The whole
          // row taps.
          AnimatedRotation(
            turns: folded ? -0.25 : 0,
            duration: reduce ? Duration.zero : HlDuration.short,
            curve: HlEasing.standard,
            child: Icon(
              Icons.expand_more,
              size: 24,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-time tip under the first header with an app key (job 313):
/// the key's icon, what it does, and a close X. A line outside the
/// header, not a pill.
class const StoreAppTip({required final VoidCallback onClose, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = SnacklistColors.of(scheme.brightness);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 18, end: HlSpace.s1),
      child: Row(
        spacing: HlSpace.s2,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.open_in_new, size: 18, color: t.brand),
          ),
          Expanded(
            child: Text(
              l10n.storeAppTip,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            label: l10n.close,
            excludeSemantics: true,
            onTap: onClose,
            child: IconButton(
              key: const ValueKey('store-app-tip-close'),
              onPressed: onClose,
              icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
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
