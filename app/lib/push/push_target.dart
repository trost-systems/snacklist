import 'package:flutter/foundation.dart';

/// What a tap on a notification opens (docs/PUSH.md, "The message"): the
/// list [listId] of the household [householdId].
@immutable
class const PushTarget({
  required final String householdId,
  required final String listId,
}) {
  @override
  bool operator ==(Object other) =>
      other is PushTarget &&
      other.householdId == householdId &&
      other.listId == listId;

  @override
  int get hashCode => Object.hash(householdId, listId);

  @override
  String toString() => 'PushTarget($householdId, $listId)';
}

/// The target of a message's `data`; null for a `kind` this app does not
/// know or without both ids. A newer `v` counts while its ids are there.
PushTarget? pushTargetOf(Map<String, Object?> data) => switch (data) {
  {
    'kind': 'list',
    'household_id': final String householdId,
    'list_id': final String listId,
  }
      when householdId.isNotEmpty && listId.isNotEmpty =>
    PushTarget(householdId: householdId, listId: listId),
  _ => null,
};
