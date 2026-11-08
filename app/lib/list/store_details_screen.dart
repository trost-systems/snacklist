import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/category_names.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/list/stores_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// One store, or with a null [storeId] the section without a store: the
/// categories in the order the list shows them there. A store is renamed
/// at the top. Reordering saves at once: for no store it is the route
/// order (also of stores without their own), for a store its walking order,
/// whose `hidden` flags stay as they are. Categories belong to the
/// household: a rename, add or delete here shows in every store.
class const StoreDetailsScreen({required final String? storeId, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final (catalog, loaded) = context.select<ListCubit, (Catalog, bool)>(
      (c) => (c.state.catalog, c.state.loaded),
    );
    final id = storeId;
    final store = id == null ? null : catalog.store(id);
    if (id != null && store == null) {
      if (loaded) {
        // Deleted on another device, or a stale link: back to the stores.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Once: the route stops being current as it leaves.
          if (!context.mounted ||
              !(ModalRoute.of(context)?.isCurrent ?? false)) {
            return;
          }
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(editPath);
          }
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final stops = walkingOrder(catalog, id);

    void reorder(int from, int to) {
      final next = [...stops];
      next.insert(to, next.removeAt(from));
      final ids = [for (final s in next) s.category.id];
      unawaited(
        id == null
            ? cubit.reorderCategories(ids)
            : cubit.setStoreLayout(id, ids, {
                for (final s in next)
                  if (s.hidden) s.category.id,
              }),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(store?.name ?? l10n.noStore)),
      floatingActionButton: AddButton(
        key: const ValueKey('category-add'),
        onPressed: () => unawaited(
          showNameDialog(
            context,
            title: l10n.addCategory,
            confirm: l10n.save,
            label: l10n.categoryName,
            validate: (name) => _categoryTaken(cubit.state.catalog, l10n, name),
            save: (name) async {
              unawaited(cubit.createCategory(name));
              return true;
            },
          ),
        ),
        label: l10n.addCategory,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: pageMaxWidth),
          child: ReorderableListView.builder(
            key: const ValueKey('store-details'),
            buildDefaultDragHandles: false,
            proxyDecorator: HexPill.lift,
            // Clear of the button and the floating tab pill below it.
            padding: EdgeInsets.only(
              bottom: fabClearance + MediaQuery.paddingOf(context).bottom,
            ),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (store != null) _StoreName(store),
                // With HexPill.margin's s1, s4 above and below the intro,
                // as on the stores screen.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HlSpace.s4,
                    HlSpace.s3,
                    HlSpace.s4,
                    HlSpace.s3,
                  ),
                  child: Text(
                    store == null ? l10n.categoriesHint : l10n.storeLayoutHint,
                  ),
                ),
              ],
            ),
            itemCount: stops.length,
            onReorderItem: reorder,
            itemBuilder: (context, index) => _CategoryRow(
              key: ValueKey(stops[index].category.id),
              category: stops[index].category,
              index: index,
              count: stops.length,
              catalog: catalog,
            ),
          ),
        ),
      ),
    );
  }
}

/// The store's name at the top; a tap renames it.
class const _StoreName(final Store store) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    final cubit = context.read<ListCubit>();
    void rename() => unawaited(
      showNameDialog(
        context,
        title: l10n.storeRename(store.name),
        confirm: l10n.save,
        label: l10n.storeNameHint,
        initial: store.name,
        maxLength: maxStoreNameLength,
        validate: (name) => switch (cubit.state.catalog.storeNamed(name)) {
          final other? when other.id != store.id => l10n.storeNameTaken(
            other.name,
          ),
          _ => null,
        },
        save: (name) async =>
            name == store.name || await cubit.renameStore(store.id, name),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: HlSpace.s2),
      child: Semantics(
        label: l10n.storeRename(store.name),
        button: true,
        onTap: rename,
        excludeSemantics: true,
        // Drawn as the app's flat hex field, like the edit sheet's, since
        // it shows a value to edit; the raised pills below are rows.
        child: GestureDetector(
          key: const ValueKey('store-rename'),
          behavior: HitTestBehavior.opaque,
          onTap: rename,
          child: Padding(
            // Lined up with the rows below.
            padding: HexPill.margin,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InputDecorator(
                decoration: InputDecoration(
                  constraints: const BoxConstraints.tightFor(
                    height: HlSize.target,
                  ),
                  suffixIcon: Icon(Icons.edit_outlined, color: t.textMuted),
                ),
                child: Text(
                  store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A category in its place: a tap renames it, the trash deletes it from the
/// household (not the fallback, which takes the items of deleted ones). The
/// order shows as the order; a screen reader hears the place („2 von 9“)
/// after the name.
class const _CategoryRow({
  required final Category category,
  required final int index,
  required final int count,
  required final Catalog catalog,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final name = categoryName(category, l10n);
    return HexPill(
      onTap: () => unawaited(
        showNameDialog(
          context,
          title: l10n.renameCategory,
          confirm: l10n.save,
          label: l10n.categoryName,
          initial: name,
          validate: (next) => _categoryTaken(
            cubit.state.catalog,
            l10n,
            next,
            except: category.id,
          ),
          // A taken name is caught by validate; any other refusal (offline)
          // closes the dialog so its snackbar is not hidden behind it.
          save: (next) async {
            if (next != name) {
              unawaited(cubit.renameCategory(category.id, next));
            }
            return true;
          },
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Text(
              categoryIcon(category),
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: HlSpace.s2),
          Expanded(
            // The place as a hint, read after the name: in the name it
            // would break "tap Kühlregal" for voice control.
            child: Semantics(
              hint: l10n.categoryPosition(index + 1, count),
              child: PillTitle(categoryLabel(category, l10n)),
            ),
          ),
          if (category.seedKey != 'other')
            IconButton(
              tooltip: l10n.deleteCategory(name),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final target = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      _DeleteDialog(category: category, catalog: catalog),
                );
                if (target != null) {
                  await cubit.deleteCategory(category.id, reassignTo: target);
                }
              },
            ),
          PillDragHandle(index: index, label: l10n.dragCategory(name)),
        ],
      ),
    );
  }
}

/// Where the deleted category's items go; pops null when cancelled.
class const _DeleteDialog({
  required final Category category,
  required final Catalog catalog,
}) extends StatefulWidget {
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState() extends State<_DeleteDialog> {
  late String? _target = widget.catalog.fallback?.id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = _target;
    return AlertDialog(
      title: Text(l10n.deleteCategory(categoryName(widget.category, l10n))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HlSpace.s4,
        children: [
          Text(l10n.deleteCategoryEverywhere),
          LabeledField(
            label: l10n.moveItemsTo,
            field: DropdownButtonFormField<String>(
              initialValue: target,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                for (final c in widget.catalog.categories)
                  if (c.id != widget.category.id)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(categoryName(c, l10n)),
                    ),
              ],
              onChanged: (id) => setState(() => _target = id),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: target == null
              ? null
              : () => Navigator.of(context).pop(target),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}

/// Why [name] cannot name a category: another one (not [except]) has it, in
/// any case or spacing, as stored or as shown (an English UI shows
/// „Getränke“ as Drinks). Null when it is free.
String? _categoryTaken(
  Catalog catalog,
  AppLocalizations l10n,
  String name, {
  String? except,
}) {
  final key = nameKey(name);
  for (final c in catalog.categories) {
    final shown = categoryName(c, l10n);
    if (c.id != except && (nameKey(c.name) == key || nameKey(shown) == key)) {
      return l10n.categoryNameTaken(shown);
    }
  }
  return null;
}
