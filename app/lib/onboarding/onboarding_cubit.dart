import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:uuid/uuid.dart';

/// Where the guided start's draft is kept: `DeviceCache` in the app. One
/// JSON value, so a cut-off write leaves the previous draft.
abstract interface class OnboardingStore() {
  Future<String?> onboardingDraft();

  /// Null drops it.
  Future<void> saveOnboardingDraft(String? json);

  /// The kinds picked after the first, kept per user once their first
  /// household exists, for when a user can have several (job 169).
  Future<void> saveLaterKinds(String userId, List<HouseholdKind> kinds);
}

/// What the guided start needs from the server once there is an account.
abstract interface class OnboardingBackend() {
  /// Sets [householdId]'s kind (members may, like the name).
  Future<void> setKind(String householdId, HouseholdKind kind);

  /// Adds [items] to [householdId]'s list, each under its own id, so a
  /// second run adds nothing twice.
  Future<void> addItems(String householdId, List<DraftItem> items);
}

class SupabaseOnboardingBackend(final SupabaseClient _client)
    implements OnboardingBackend {
  @override
  Future<void> setKind(String householdId, HouseholdKind kind) => householdCall(
    () => _client.rest
        .from('households')
        .update({'kind': kind.name})
        .eq('id', householdId),
  );

  @override
  Future<void> addItems(String householdId, List<DraftItem> items) async {
    final repository = SupabaseListRepository(_client, householdId);
    for (final item in items) {
      final entry = parseEntry(item.text);
      final now = DateTime.now();
      await householdCall(() async {
        try {
          await repository.send(
            // Split as an offline add is: the server reads brand and details
            // off the name and picks the category.
            AddItem(
              Item(
                id: item.id,
                name: entry.name,
                quantity: entry.quantity,
                status: ItemStatus.active,
                createdAt: now,
                updatedAt: now,
              ),
              deviceParsed: true,
              autoCategory: true,
            ),
          );
        } on RejectedOp {
          // The server refuses this one for good (a name it cannot take):
          // the others still go on the list.
        }
      });
    }
  }
}

/// The guided start (job 168b): what the user answered before and right
/// after the sign-in, kept on the device across app kills until the
/// household exists and the invite step is left. Null: no guided start is
/// under way. The router reads [state] synchronously, so [load] runs before
/// the first frame.
class OnboardingCubit(
  final OnboardingStore _store, {
  OnboardingDraft? initial,
  final Analytics? analytics,
}) extends Cubit<OnboardingDraft?> {
  this : super(initial);

  static Future<OnboardingCubit> load(
    OnboardingStore store, {
    Analytics? analytics,
  }) async {
    final json = await store.onboardingDraft();
    OnboardingDraft? draft;
    try {
      draft = json == null
          ? null
          : OnboardingDraft.fromJson(jsonDecode(json) as Object?);
    } on FormatException {
      draft = null;
    }
    return OnboardingCubit(store, initial: draft, analytics: analytics);
  }

  /// Saves run one after the other, so the last change is the one kept.
  Future<void> _saving = Future.value();

  /// Whether the last session [sessionChanged] saw was signed in: a
  /// sign-out, not a start signed out, parks the draft.
  var _signedIn = false;

  /// „Los geht's“ (signed out) or „Haushalt erstellen“ (signed in, no
  /// household): a new draft at the first step, the usage-data question when
  /// this install has not answered it yet. A draft under way is kept, and
  /// one a sign-out parked goes on.
  void start({required bool askUsage, String? ownHouseholdFor}) {
    switch (state) {
      case final draft? when draft.parked:
        emit(
          draft.copyWith(
            parked: false,
            ownHouseholdFor: ownHouseholdFor ?? draft.ownHouseholdFor,
          ),
        );
      case null:
        emit(
          OnboardingDraft(
            step: askUsage ? OnboardingStep.usage : OnboardingStep.who,
            ownHouseholdFor: ownHouseholdFor,
            requestId: const Uuid().v4(),
          ),
        );
      case final draft
          when ownHouseholdFor != null &&
              draft.ownHouseholdFor != ownHouseholdFor:
        emit(draft.copyWith(ownHouseholdFor: ownHouseholdFor));
      case _:
    }
  }

  /// Applies [change] to the draft under way.
  void update(OnboardingDraft Function(OnboardingDraft draft) change) {
    if (state case final draft?) {
      emit(change(draft));
    }
  }

  /// Now at [step]: where a restart resumes.
  void at(OnboardingStep step) => update((d) => d.copyWith(step: step));

  /// Adds [text] as a thing the user needs, unless it is there already (any
  /// case or spacing).
  void addItem(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) {
      return;
    }
    update(
      (d) => d.items.any((i) => _same(i.text, trimmed))
          ? d
          : d.copyWith(
              items: [
                ...d.items,
                DraftItem(id: const Uuid().v4(), text: trimmed),
              ],
            ),
    );
  }

  void removeItem(String text) => update(
    (d) => d.copyWith(items: [...d.items.where((i) => !_same(i.text, text))]),
  );

  bool hasItem(String text) =>
      state?.items.any((i) => _same(i.text, text)) ?? false;

  static bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// The user dropped the guided start, or it is done.
  void discard() => emit(null);

  /// Makes the draft the user's household: creates it with the name and
  /// stores (signed in without one), sets its kind and adds the items. A
  /// user who turns out to be in a household already (they signed in to an
  /// existing account, or joined one) gets the items there and no invite
  /// step. Every part can run again after a failure or an app kill: the
  /// server answers a second create with the household there is, and the
  /// items keep their ids. Throws [HouseholdError].
  Future<void> setUp(
    SessionCubit session,
    OnboardingBackend backend, {
    required String defaultName,
  }) async {
    var draft = state;
    if (draft == null) {
      return;
    }
    final create = switch (session.state) {
      NeedsHousehold() => true,
      // A join request approved during the questions: still its own.
      InHousehold(:final userId) => draft.ownFor(userId),
      _ => false,
    };
    if (create && !draft.beforeSignIn) {
      final name = draft.name?.trim();
      await session.createHousehold(
        name == null || name.isEmpty ? defaultName : name,
        stores: draft.stores,
        // With the create, not after it: the server turns join approval on
        // for a new club household (job 169b W3) only from the create's kind.
        kind: draft.kind?.name,
        requestId: draft.requestId,
      );
      if (session.state case InHousehold(:final userId, :final household)) {
        draft = draft.copyWith(userId: userId, householdId: household.id);
        emit(draft);
      }
    }
    final current = session.state;
    if (current is! InHousehold) {
      return;
    }
    final household = current.household;
    final ours = draft.householdId == household.id;
    // A household made before the kind went with the create (job 168c).
    if (ours && household.kind == null) {
      if (draft.kind case final kind?) {
        try {
          await backend.setKind(household.id, kind);
          await householdCall(session.refresh);
        } on HouseholdError catch (e) {
          // Only the answer's echo: a server that refuses the kind (one
          // without „other“, say) must not stop the setup. Offline retries.
          if (e.problem == HouseholdProblem.offline) {
            rethrow;
          }
        }
      }
    }
    await backend.addItems(household.id, draft.items);
    if (state == null) {
      return;
    }
    if (!ours) {
      discard();
      return;
    }
    if (draft.laterKinds.isNotEmpty) {
      await _store.saveLaterKinds(current.userId, draft.laterKinds);
    }
    // „Nur ich“ alone has no one to invite.
    if (listEquals(draft.kinds, const [HouseholdKind.solo])) {
      emit(draft);
      finish(invited: false);
      return;
    }
    emit(draft.copyWith(step: OnboardingStep.invite));
  }

  /// The invite step is left: the guided start is done.
  void finish({required bool invited}) {
    if (state case final draft?) {
      analytics?.track('onboarding_completed', {
        'kind': draft.kind?.name ?? 'skipped',
        'kind_count': draft.kinds.length,
        'item_count': draft.items.length,
        'store_count': draft.stores.length,
        'invited': invited,
      });
    }
    discard();
  }

  /// Follows the session: a draft whose household exists belongs to that
  /// user and household only, so a sign-out, an account deletion or
  /// another household drops it. A draft without a household stays: it
  /// waits for a sign-in on this device, parked by a sign-out (job 486) so
  /// that the start screen shows; signed in again, it goes on.
  void sessionChanged(Session session) {
    final draft = state;
    final signedOut = _signedIn && session is SignedOut;
    _signedIn = session is NeedsHousehold || session is InHousehold;
    if (draft == null) {
      return;
    }
    if (!draft.created) {
      if (signedOut || (_signedIn && draft.parked)) {
        emit(draft.copyWith(parked: signedOut));
      }
      return;
    }
    final keep = switch (session) {
      InHousehold(:final userId, :final household) =>
        userId == draft.userId && household.id == draft.householdId,
      SessionLoading() => true,
      NeedsHousehold() || SignedOut() => false,
    };
    if (!keep) {
      discard();
    }
  }

  /// Saves each change, the null that ends the guided start too.
  @override
  void onChange(Change<OnboardingDraft?> change) {
    super.onChange(change);
    final json = switch (change.nextState) {
      final draft? => jsonEncode(draft.toJson()),
      null => null,
    };
    _saving = _saving.then((_) => _store.saveOnboardingDraft(json));
  }

  /// Waits for the saves so far; for tests.
  Future<void> get saved => _saving;
}
