import 'package:flutter/foundation.dart';

/// How a row of the list behind the open AE2 sheet (flag
/// `add-ae2-list-peeks`, job 490) is marked: [added] in this opening,
/// [raised] (merged into) in this opening, or the [match] of what is typed.
enum PeekMark() {
  added,
  raised,
  match,
}

/// The marks of the list behind the open AE2 sheet, as the add sheet's state
/// gives them. Equal when they show the same, so a key that changes nothing
/// on the list rebuilds nothing.
@immutable
final class const PeekMarks({
  /// Item id to its mark.
  final Map<String, PeekMark> marks = const {},

  /// The row kept in view: the match while typing, else the latest add or
  /// merge.
  final String? target,

  /// The match's Menge after a merge ("7×"), for its tag; null when it has
  /// no merge.
  final String? matchQuantity,
}) {
  @override
  bool operator ==(Object other) =>
      other is PeekMarks &&
      mapEquals(other.marks, marks) &&
      other.target == target &&
      other.matchQuantity == matchQuantity;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(marks.entries.map((e) => (e.key, e.value))),
    target,
    matchQuantity,
  );
}

/// The list behind the open AE2 sheet: the whole list, its rows [marks]ed,
/// its end padded by the sheet, [sheetExtent] tall; a tap on it [onTap]s.
@immutable
final class const SheetPeek({
  required final PeekMarks marks,
  required final ValueListenable<double> sheetExtent,
  required final VoidCallback onTap,
});
