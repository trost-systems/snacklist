import 'dart:async';

import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:family_groceries/list/store_layout_screen.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the stores screen on top of More.
Future<void> openStores(BuildContext context) {
  final cubit = context.read<ListCubit>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const StoresScreen()),
    ),
  );
}

/// The household's stores in list order, the same order the store
/// dividers' drag changes. A store opens its walking order; its menu
/// renames it in place or deletes it. "+ Neuer Laden" below adds one.
class const StoresScreen({super.key}) extends StatefulWidget {
  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState() extends State<StoresScreen> {
  /// The store whose name is being edited in its row.
  String? _renaming;

  Future<void> _delete(Store store) async {
    final cubit = context.read<ListCubit>();
    final open = cubit.state.items.values
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final stores = context.select<ListCubit, List<Store>>(
      (c) => c.state.catalog.stores,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storesTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: pageMaxWidth),
          child: ReorderableListView(
            key: const ValueKey('stores-screen'),
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                stores.isEmpty ? l10n.storesEmpty : l10n.storesHint,
                key: stores.isEmpty ? const ValueKey('stores-empty') : null,
              ),
            ),
            footer: const _AddStore(),
            onReorderItem: (from, to) {
              final ids = [for (final s in stores) s.id];
              ids.insert(to, ids.removeAt(from));
              unawaited(cubit.reorderStores(ids));
            },
            proxyDecorator: HexPill.lift,
            children: [
              for (final (i, store) in stores.indexed)
                if (store.id == _renaming)
                  Padding(
                    key: ValueKey('store-row-${store.id}'),
                    padding: HexPill.margin,
                    child: StoreNameField(
                      initial: store.name,
                      confirmLabel: l10n.save,
                      fieldKey: 'store-rename-field',
                      confirmKey: 'store-rename-confirm',
                      cancelKey: 'store-rename-cancel',
                      onConfirm: (name) async {
                        final unchanged = name.trim() == store.name;
                        final saved =
                            unchanged ||
                            await cubit.renameStore(store.id, name);
                        if (saved && mounted) {
                          setState(() => _renaming = null);
                        }
                        return saved;
                      },
                      onCancel: () => setState(() => _renaming = null),
                    ),
                  )
                else
                  HexPill(
                    key: ValueKey('store-row-${store.id}'),
                    onTap: () => unawaited(openStoreLayout(context, store.id)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: HlSpace.s1,
                            children: [
                              StoreBadge(store),
                              Text(
                                l10n.editStoreLayout,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        _StoreMenu(
                          store: store,
                          onRename: () => setState(() => _renaming = store.id),
                          onDelete: () => unawaited(_delete(store)),
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

enum _Action() {
  rename,
  delete,
}

class const _StoreMenu({
  required final Store store,
  required final VoidCallback onRename,
  required final VoidCallback onDelete,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_Action>(
      key: ValueKey('store-menu-${store.id}'),
      tooltip: l10n.storeMenu(store.name),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => switch (action) {
        _Action.rename => onRename(),
        _Action.delete => onDelete(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: ValueKey('store-rename-${store.id}'),
          value: _Action.rename,
          child: Semantics(
            label: l10n.storeRename(store.name),
            excludeSemantics: true,
            child: Text(l10n.storeRenameAction),
          ),
        ),
        PopupMenuItem(
          key: ValueKey('store-delete-${store.id}'),
          value: _Action.delete,
          child: Semantics(
            label: l10n.storeDelete(store.name),
            excludeSemantics: true,
            child: Text(l10n.delete),
          ),
        ),
      ],
    );
  }
}

/// "+ Neuer Laden" below the stores, a field in place while naming.
class const _AddStore() extends StatefulWidget {
  @override
  State<_AddStore> createState() => _AddStoreState();
}

class _AddStoreState() extends State<_AddStore> {
  final _row = FocusNode();
  var _naming = false;

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  void _close() {
    setState(() => _naming = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _row.requestFocus();
      }
    });
  }

  Future<bool> _add(String name) async {
    final cubit = context.read<ListCubit>();
    final existing = cubit.state.catalog.storeNamed(name);
    final store = existing ?? await cubit.addStore(name);
    if (store == null || !mounted) {
      return false;
    }
    if (existing == null) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).storeAdded(store.name),
          Directionality.of(context),
        ),
      );
    }
    _close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_naming) {
      return Padding(
        padding: HexPill.margin,
        child: StoreNameField(
          confirmLabel: l10n.storeCreateConfirm,
          onConfirm: _add,
          onCancel: _close,
        ),
      );
    }
    void open() => setState(() => _naming = true);
    return Semantics(
      label: l10n.storeNewLabel,
      button: true,
      onTap: open,
      excludeSemantics: true,
      child: HexPill(
        key: const ValueKey('store-option-new'),
        focusNode: _row,
        onTap: open,
        child: Row(
          children: [
            const Icon(Icons.add),
            const SizedBox(width: HlSpace.s3),
            Expanded(child: PillTitle(l10n.storeNew)),
          ],
        ),
      ),
    );
  }
}
