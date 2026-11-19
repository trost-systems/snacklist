import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// What the list screen shows of other features; the shell provides it
/// (`ShellListParts`). Without it (tests, Widgetbook) the list shows none
/// of it ([listParts]).
abstract interface class ListParts() {
  /// Opens the households sheet; [openNow] counts the shown household's
  /// open items.
  Future<void> openHouseholds(BuildContext context, {int? openNow});

  /// Opens the switcher sheet (flag `list-declutter`).
  Future<void> openSwitcher(BuildContext context);

  /// Wraps the [list] in what trip mode asks and shows around it.
  Widget around(Widget list);

  /// The running trip's strip above the add bar; nothing while [hidden].
  Widget tripStrip({required bool hidden});

  /// The list's card after a trip ended on its own.
  Widget tripEnded();

  /// In build: counts an item as bought on the trip running on [listId];
  /// null when none runs.
  bool Function(Item item)? boughtOnTrip(BuildContext context, String? listId);
}

/// The [ListParts] above [context], or none of them.
ListParts listParts(BuildContext context) =>
    context.read<ListParts?>() ?? const _NoParts();

final class const _NoParts() implements ListParts {
  @override
  Future<void> openHouseholds(BuildContext context, {int? openNow}) async {}

  @override
  Future<void> openSwitcher(BuildContext context) async {}

  @override
  Widget around(Widget list) => list;

  @override
  Widget tripStrip({required bool hidden}) => const SizedBox.shrink();

  @override
  Widget tripEnded() => const SizedBox.shrink();

  @override
  bool Function(Item item)? boughtOnTrip(
    BuildContext context,
    String? listId,
  ) => null;
}
