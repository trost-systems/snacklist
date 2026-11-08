import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter/foundation.dart';

/// An item of the „Erste Schritte“ card (job 168b); [wire] is sent as
/// `checklist_step_done`'s `step`.
enum ChecklistStep(final String wire) {
  /// The list exists, or the user joined it: done from the start.
  started('started'),
  invite('invite'),
  firstShop('first_shop'),

  /// Clubs only: an AI assistant connected under More → Zugänge.
  assistant('assistant'),
}

typedef ChecklistEntry = ({ChecklistStep step, bool done});

/// The „Erste Schritte“ card: its items for a household of [kind], and
/// whether the user [joined] it rather than created it.
@immutable
class const Checklist(
  final List<ChecklistEntry> entries, {
  required final HouseholdKind? kind,
  required final bool joined,
}) {
  /// The invite only for the household's owner and not for one shopping
  /// alone, the assistant only for a club.
  factory of(
    UsageLog log, {
    required HouseholdKind? kind,
    required bool owner,
  }) => Checklist(
    [
      (step: ChecklistStep.started, done: true),
      if (owner && kind != HouseholdKind.solo)
        (step: ChecklistStep.invite, done: log.saw(Signal.memberJoined)),
      (step: ChecklistStep.firstShop, done: log.saw(Signal.shopDone)),
      if (kind == HouseholdKind.club)
        (
          step: ChecklistStep.assistant,
          done: log.saw(Signal.assistantConnected),
        ),
    ],
    kind: kind,
    joined: !owner,
  );

  int get open => entries.where((e) => !e.done).length;

  bool has(ChecklistStep step) => entries.any((e) => e.step == step);

  @override
  bool operator ==(Object other) =>
      other is Checklist &&
      other.kind == kind &&
      other.joined == joined &&
      listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(kind, joined, Object.hashAll(entries));
}
