import 'dart:async';

import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/list_tabs.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The household page's "Listen" (job 169b K): the household's lists in
/// their order, each with how much is open on it and a menu to rename,
/// move up or down, and delete it (not the last one), then "Neue Liste".
/// Nothing without the household's list above it, or while the server
/// names no lists.
class const ListsSection({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<ListCubit?>();
    final state = cubit?.state;
    if (cubit == null || state == null || state.catalog.lists.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final lists = state.catalog.lists;
    final items = state.allItems;
    int open(HouseholdList list) => state
        .onList(items, list.id)
        .values
        .where((i) => i.status == ItemStatus.active)
        .length;
    return Column(
      key: const ValueKey('household-lists'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(l10n.listsTitle),
        for (final (i, list) in lists.indexed)
          ListTile(
            key: ValueKey('list-row-${list.id}'),
            leading: const Icon(Icons.checklist),
            title: Text(
              listName(list, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(l10n.householdOpenItems(open(list))),
            trailing: PopupMenuButton<_ListAction>(
              key: ValueKey('list-actions-${list.id}'),
              tooltip: l10n.listActions(listName(list, l10n)),
              useRootNavigator: true,
              onSelected: (action) => unawaited(
                _act(context, cubit, list, action, open: open(list)),
              ),
              itemBuilder: (_) => [
                for (final action in _ListAction.values)
                  if (switch (action) {
                    _ListAction.up => i > 0,
                    _ListAction.down => i < lists.length - 1,
                    _ListAction.delete => lists.length > 1,
                    _ListAction.rename => true,
                  })
                    PopupMenuItem(
                      key: ValueKey('list-${action.name}'),
                      value: action,
                      child: Text(switch (action) {
                        _ListAction.rename => l10n.householdRename,
                        _ListAction.up => l10n.listMoveUp,
                        _ListAction.down => l10n.listMoveDown,
                        _ListAction.delete => l10n.delete,
                      }),
                    ),
              ],
            ),
          ),
        ListTile(
          key: const ValueKey('list-new'),
          leading: const Icon(Icons.add),
          title: Text(l10n.listNew),
          onTap: () => unawaited(addList(context)),
        ),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    ListCubit cubit,
    HouseholdList list,
    _ListAction action, {
    required int open,
  }) async {
    final at = cubit.state.catalog.lists.indexWhere((l) => l.id == list.id);
    switch (action) {
      case _ListAction.rename:
        await renameList(context, cubit, list);
      case _ListAction.up:
        await cubit.moveList(list.id, at - 1);
      case _ListAction.down:
        await cubit.moveList(list.id, at + 1);
      case _ListAction.delete:
        await deleteList(context, cubit, list, open: open);
    }
  }
}

/// Asks for [list]'s new name and saves it in [cubit].
Future<void> renameList(
  BuildContext context,
  ListCubit cubit,
  HouseholdList list,
) {
  final l10n = AppLocalizations.of(context);
  return showNameDialog(
    context,
    title: l10n.listRenameTitle,
    confirm: l10n.save,
    label: l10n.listNameLabel,
    initial: listName(list, l10n),
    save: (name) => name == listName(list, l10n)
        ? Future.value(true)
        : cubit.renameList(list.id, name),
  );
}

/// Asks whether to delete [list] with the [open] items on it, and does.
Future<void> deleteList(
  BuildContext context,
  ListCubit cubit,
  HouseholdList list, {
  required int open,
}) async {
  final delete =
      await showDialog<bool>(
        context: context,
        builder: (dialog) {
          final l10n = AppLocalizations.of(dialog);
          return AlertDialog(
            key: const ValueKey('list-delete-dialog'),
            title: Text(l10n.listDeleteTitle(listName(list, l10n))),
            content: Text(l10n.listDeleteBody(open)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('list-delete-confirm'),
                style: dangerButtonStyle(dialog),
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          );
        },
      ) ??
      false;
  if (delete) {
    await cubit.deleteList(list.id);
  }
}

enum _ListAction() {
  rename,
  up,
  down,
  delete,
}
