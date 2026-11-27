import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:flutter/foundation.dart';

/// The steps of the guided start (job 168b), in order. Each has its own
/// screen; [setup] is the moment after sign-in when the draft becomes the
/// household, and [invite] the first step with an account. [join] is the
/// name step's way out to an existing household (job 271), no step of the
/// progress. Stored by name: never rename one.
enum OnboardingStep() {
  usage,
  who,
  name,
  join,
  stores,
  need,
  account,
  setup,
  invite;

  static OnboardingStep? parse(Object? name) =>
      values.where((s) => s.name == name).firstOrNull;

  /// A step that needs no account: everything before the sign-in.
  bool get beforeAccount => index < account.index;
}

/// One thing the user said they need, kept until the household exists. The
/// [id] is the item's id on the server, so moving it there twice (a retry,
/// a crash in between) adds it once.
@immutable
class const DraftItem({required final String id, required final String text}) {
  @override
  bool operator ==(Object other) =>
      other is DraftItem && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// Everything the guided start has collected, kept on the device until the
/// household exists (across an app kill), then moved to the server. One per
/// device: before sign-in there is no user to file it under.
@immutable
class const OnboardingDraft({
  /// The step to resume at.
  final OnboardingStep step = OnboardingStep.usage,

  /// Who the user shops with, in the order picked. The first becomes the
  /// household; the others wait for multiple households (job 169).
  final List<HouseholdKind> kinds = const [],

  /// The words typed for „Andere“; empty without.
  final String otherKind = '',

  /// The household name as typed; null keeps the one [kinds] suggests.
  final String? name,

  /// The stores picked, in that order.
  final List<NewStore> stores = const [],

  /// What the user needs right now, in the order added.
  final List<DraftItem> items = const [],

  /// Set once the household exists: whose it is, and which. A draft of
  /// another user (someone else signed in on this device) is dropped.
  final String? userId,
  final String? householdId,

  /// The user who started it while a join request waited (its „Eigenen
  /// Haushalt anlegen“, job 168c): for them it makes a household of its
  /// own even when the request is approved first, instead of putting its
  /// items on the joined list. Anyone else signing in gets the existing
  /// household rule.
  final String? ownHouseholdFor,

  /// The create request's id, kept so that a setup run again after an app
  /// kill gets the household the first run made (job 168c); null for
  /// drafts from before.
  final String? requestId,

  /// A sign-out left it (job 486): signed out, the start screen shows
  /// instead of its step until „Los geht's“ takes it up again.
  final bool parked = false,
}) {
  /// The first household's kind: the first one picked.
  HouseholdKind? get kind => kinds.firstOrNull;

  /// The kinds picked after the first: households to offer once a user can
  /// have several (job 169).
  List<HouseholdKind> get laterKinds => kinds.skip(1).toList();

  /// Whether the user is still before the sign-in step.
  bool get beforeSignIn => step.beforeAccount;

  /// Whether the household exists on the server and only the invite step is
  /// left.
  bool get created => householdId != null;

  /// Whether [userId] started it as a household of their own, not made
  /// yet.
  bool ownFor(String userId) => !created && ownHouseholdFor == userId;

  OnboardingDraft copyWith({
    OnboardingStep? step,
    List<HouseholdKind>? kinds,
    String? otherKind,
    String? Function()? name,
    List<NewStore>? stores,
    List<DraftItem>? items,
    String? userId,
    String? householdId,
    String? ownHouseholdFor,
    String? requestId,
    bool? parked,
  }) => OnboardingDraft(
    step: step ?? this.step,
    kinds: kinds ?? this.kinds,
    otherKind: otherKind ?? this.otherKind,
    name: name == null ? this.name : name(),
    stores: stores ?? this.stores,
    items: items ?? this.items,
    userId: userId ?? this.userId,
    householdId: householdId ?? this.householdId,
    ownHouseholdFor: ownHouseholdFor ?? this.ownHouseholdFor,
    requestId: requestId ?? this.requestId,
    parked: parked ?? this.parked,
  );

  Map<String, Object?> toJson() => {
    'step': step.name,
    'kinds': [for (final k in kinds) k.name],
    'other_kind': otherKind,
    'name': name,
    'stores': [for (final s in stores) s.toJson()],
    'items': [
      for (final i in items) {'id': i.id, 'text': i.text},
    ],
    'user_id': userId,
    'household_id': householdId,
    'own_household_for': ownHouseholdFor,
    'request_id': requestId,
    'parked': parked,
  };

  /// The draft in [json], or null when it is not one (a newer build's, a
  /// cut-off write): a guided start that cannot be read starts over.
  static OnboardingDraft? fromJson(Object? json) {
    if (json case {
      'step': final String stepName,
      'kinds': final List<Object?> kinds,
      'other_kind': final String otherKind,
      'name': final String? name,
      'stores': final List<Object?> stores,
      'items': final List<Object?> items,
      'user_id': final String? userId,
      'household_id': final String? householdId,
    }) {
      if (OnboardingStep.parse(stepName) case final step?) {
        return OnboardingDraft(
          step: step,
          kinds: [...kinds.map(HouseholdKind.parse).nonNulls],
          otherKind: otherKind,
          name: name,
          stores: [...stores.map(NewStore.fromJson).nonNulls],
          items: [
            for (final item in items)
              if (item case {'id': final String id, 'text': final String text})
                DraftItem(id: id, text: text),
          ],
          userId: userId,
          householdId: householdId,
          // Drafts from before job 168c have none.
          ownHouseholdFor: switch (json) {
            {'own_household_for': final String user} => user,
            _ => null,
          },
          requestId: switch (json) {
            {'request_id': final String id} => id,
            _ => null,
          },
          parked: json['parked'] == true,
        );
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingDraft &&
      other.step == step &&
      listEquals(other.kinds, kinds) &&
      other.otherKind == otherKind &&
      other.name == name &&
      listEquals(other.stores, stores) &&
      listEquals(other.items, items) &&
      other.userId == userId &&
      other.householdId == householdId &&
      other.ownHouseholdFor == ownHouseholdFor &&
      other.requestId == requestId &&
      other.parked == parked;

  @override
  int get hashCode => Object.hash(
    step,
    Object.hashAll(kinds),
    otherKind,
    name,
    Object.hashAll(stores),
    Object.hashAll(items),
    userId,
    householdId,
    ownHouseholdFor,
    requestId,
    parked,
  );
}
