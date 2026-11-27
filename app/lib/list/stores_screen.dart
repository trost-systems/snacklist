import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/screen_reader.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_question.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/shell/shell.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The bottom padding of a list under the [AddButton]: its height (edge
/// included) and a gap, so it never covers the last row's handle.
const fabClearance = HlSize.target + HlSpace.s4;

/// A page's add button, in the floating action button's slot: the theme's
/// main tactile button with a plus, on its edge like the rows it adds to.
class const AddButton({
  required final String label,
  required final VoidCallback onPressed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    // Desktop's compact density would shrink it under 48 px.
    style: FilledButton.styleFrom(visualDensity: VisualDensity.standard),
    onPressed: onPressed,
    icon: const Icon(Icons.add),
    label: Text(label),
  );
}

/// The List tab's Anpassen: the household's stores in list order, the same
/// order the store dividers show, and "Ohne Laden" where the section without
/// a store sits on the list (last). A row opens its details; the button
/// adds a store.
class const StoresScreen({super.key}) extends StatelessWidget {
  Future<void> _delete(BuildContext context, Store store) async {
    final cubit = context.read<ListCubit>();
    final open = cubit.state.allItems.values
        .where((i) => i.storeId == store.id && i.status == ItemStatus.active)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.storeDeleteTitle(store.name)),
          content: Text(l10n.storeDeleteBody(open)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('store-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await cubit.deleteStore(store.id);
    }
  }

  /// A name the household has already stays in the dialog, with why. With
  /// [chains] (job 313) matching chains show under the field, and a plain
  /// name that is a chain's is asked about once the dialog has closed.
  Future<void> _add(BuildContext context, {required bool chains}) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final reader = ScreenReader.of(context);
    final storeChains = StoreChains.of(cubit);
    // The plain name saved and its exact chains, looked up as it saves.
    (Store, Future<List<RetailerMatch>>)? asked;
    bool saved(Store? store) {
      if (store == null) {
        return false;
      }
      reader.announce(l10n.storeAdded(store.name));
      return true;
    }

    await showNameDialog(
      context,
      title: l10n.storeAdd,
      confirm: l10n.storeCreateConfirm,
      label: l10n.storeNameHint,
      maxLength: maxStoreNameLength,
      validate: (name) => switch (cubit.state.catalog.storeNamed(name)) {
        final existing? => l10n.storeNameTaken(existing.name),
        null => null,
      },
      save: (name) async {
        final matches = chains
            ? storeChains.match(name)
            : Future.value(const <RetailerMatch>[]);
        final store = await cubit.addStore(name);
        if (store != null) {
          asked = (store, matches);
        }
        return saved(store);
      },
      below: chains
          ? (text, submit) => ChainSuggestions(
              text: text,
              match: storeChains.match,
              onPick: (m) => submit(
                m.storeName(text),
                (name) async =>
                    saved(await storeChains.addLinked(name, m.retailer)),
              ),
            )
          : null,
    );
    if (asked case (final store, final matches)?) {
      final chainsOfName = exactChains(await matches);
      if (chainsOfName.isNotEmpty && context.mounted) {
        await askChain(context, store, chainsOfName, storeChains.answer);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final stores = context.select<ListCubit, List<Store>>(
      (c) => c.state.catalog.stores,
    );
    final chains = context.select<Flags?, bool>(
      (f) => f?.isOn(openStoreAppFlag) ?? false,
    );
    // Flag `hide-categories`: a store's screen orders no categories, so the
    // hint saying so and the section without a store, which is nothing but
    // its categories, go.
    final categories = context.select<Flags?, bool>(
      (f) => !(f?.isOn(hideCategoriesFlag) ?? false),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storesTitle)),
      floatingActionButton: AddButton(
        key: const ValueKey('store-add'),
        onPressed: () => unawaited(_add(context, chains: chains)),
        label: l10n.storeAdd,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: pageMaxWidth),
          child: ReorderableListView(
            key: const ValueKey('stores-screen'),
            buildDefaultDragHandles: false,
            // Clear of the button and the floating tab pill below it.
            padding: EdgeInsets.only(
              bottom: fabClearance + MediaQuery.paddingOf(context).bottom,
            ),
            // HexPill.margin adds s1: s4 to the first row, twice the gap
            // between rows, so the intro reads as its own group.
            header: stores.isNotEmpty && !categories
                ? const SizedBox(height: HlSpace.s3)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HlSpace.s4,
                      HlSpace.s3,
                      HlSpace.s4,
                      HlSpace.s3,
                    ),
                    child: Text(
                      stores.isEmpty ? l10n.storesEmpty : l10n.storesHint,
                      key: stores.isEmpty
                          ? const ValueKey('stores-empty')
                          : null,
                    ),
                  ),
            footer: categories ? const _NoStoreRow() : null,
            onReorderItem: (from, to) {
              final ids = [for (final s in stores) s.id];
              ids.insert(to, ids.removeAt(from));
              unawaited(cubit.reorderStores(ids));
            },
            proxyDecorator: HexPill.lift,
            children: [
              for (final (i, store) in stores.indexed)
                HexPill(
                  key: ValueKey('store-row-${store.id}'),
                  onTap: () => context.go(storeDetailsPath(store.id)),
                  child: Row(
                    children: [
                      Expanded(child: PillTitle(store.name)),
                      IconButton(
                        key: ValueKey('store-delete-${store.id}'),
                        tooltip: l10n.storeDelete(store.name),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => unawaited(_delete(context, store)),
                      ),
                      PillDragHandle(
                        index: i,
                        label: l10n.dragStore(store.name),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The section without a store, pinned: it cannot move, be renamed or go.
/// What it holds is said below it: no hint inside a hex (Peter, 2026-11-05).
class const _NoStoreRow() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HexPill(
          key: const ValueKey('store-row-none'),
          pinned: true,
          onTap: () => context.go(storeDetailsPath(null)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.noStore,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: t.textMuted),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: HlSpace.s4 + HlSpace.s5,
            end: HlSpace.s4,
          ),
          child: Text(
            l10n.noStoreRowHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: t.textMuted),
          ),
        ),
      ],
    );
  }
}
