import 'package:flutter/foundation.dart';

/// What an app link asks of the list (job 66): `/add` opens the add sheet,
/// `/stores/<id>` shows that store's section. A tapped notification asks
/// for a list ([ShowListLink], job 376).
sealed class const ListLink();

final class const AddLink() extends ListLink;

final class const StoreLink(final String storeId) extends ListLink;

/// Shows the household's list [listId]; one it does not have (gone, or
/// another household's) leaves the shown one.
final class const ShowListLink(final String listId) extends ListLink;

/// The [ListLink] of a location, or null for any other.
ListLink? listLinkOf(Uri uri) => switch (uri.pathSegments) {
  ['add'] => const AddLink(),
  ['stores', final id] when id.isNotEmpty => StoreLink(id),
  _ => null,
};

/// The link waiting for the list: the router puts it, the list takes it
/// once, when it is built (a cold start) or later. Not a [Listenable]
/// itself, so that it can be provided as a plain value.
class ListLinks() {
  final _pending = ValueNotifier<ListLink?>(null);

  /// Notifies when a link comes (and when one is taken).
  Listenable get changes => _pending;

  /// The link waiting, if any.
  ListLink? get pending => _pending.value;

  set pending(ListLink? link) => _pending.value = link;

  /// The pending link if it is a [T], which is then gone.
  T? take<T extends ListLink>() {
    if (_pending.value case final T link) {
      _pending.value = null;
      return link;
    }
    return null;
  }

  void dispose() => _pending.dispose();
}
