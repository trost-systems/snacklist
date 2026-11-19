import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_names.dart';

/// Opens the list of a household that is not shown, for as long as it is
/// held: the switcher sheet shows any household's lists (job 229). Each
/// [hold] needs its [release].
abstract interface class ListHolds() {
  /// The list of [householdId], opened if it is not open.
  ListCubit hold(String householdId);

  /// Lets go of one [hold] of [householdId]: once none is left and it is
  /// not shown, it closes as a list switched away from does, once its
  /// queue reached the server.
  void release(String householdId);
}

/// What a refused write tells the user.
String rejectionText(AppLocalizations l10n, Rejected rejection) =>
    switch (rejection) {
      ItemRejected(:final itemName) => l10n.syncFailed(itemName),
      NameTaken(:final name) => l10n.categoryNameTaken(name),
      CatalogRejected() => l10n.catalogSaveFailed,
      TooManyLists() => l10n.tooManyLists,
      NeedsConnection() => l10n.reorderNeedsConnection,
      StoreNameTaken(:final name) => l10n.storeNameTaken(name),
      StoreNeedsConnection() => l10n.storesNeedConnection,
      ListsNeedConnection() => l10n.listsNeedConnection,
      OnListAlready(:final name, :final list) => l10n.onListAlready(
        name,
        listName(list, l10n),
      ),
      MergeRefused(:final name) => l10n.mergeRefused(name),
      RenameTaken(:final name) => l10n.alreadyOnList(name),
    };

/// Where the List tab tells refused writes while it shows; elsewhere
/// `ListScope` tells them in the app's messenger, above the tabs.
class RejectionNotices() {
  /// Shows `text` in the List tab and returns true, or returns false when
  /// the tab is not on screen.
  bool Function(String text)? listTab;
}
