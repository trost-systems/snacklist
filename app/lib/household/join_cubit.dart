import 'dart:async';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum JoinPhase() {
  /// The code is being typed (or was refused).
  entering,

  /// Looking at the code (`preview_invite`).
  checking,

  /// The code is good: [JoinState.household] waits for the confirmation.
  previewed,

  /// Joining (`accept_invite`).
  joining,

  /// In the household now (or already was): on to the list.
  joined,
}

@immutable
class const JoinState({
  final JoinPhase phase = JoinPhase.entering,

  /// The name of the household the code leads to, once previewed.
  final String? household,

  /// What Hummlist Lifetime means for this join, once previewed.
  final JoinLifetime lifetime = const JoinLifetime(),
  final HouseholdProblem? problem,
}) {
  bool get busy => phase == JoinPhase.checking || phase == JoinPhase.joining;

  /// Like [household], [lifetime] goes unless it is passed again.
  JoinState copyWith({
    JoinPhase? phase,
    String? household,
    JoinLifetime lifetime = const JoinLifetime(),
    HouseholdProblem? problem,
  }) => JoinState(
    phase: phase ?? this.phase,
    household: household,
    lifetime: lifetime,
    problem: problem,
  );
}

/// Onboarding Step 2b and More's join: look at a code (the household's
/// name), then join on the user's word. [link] is the code of the invite
/// link the user came with; it is checked at once. A refused code keeps
/// the field as typed, says why (one answer for made-up, expired, revoked
/// and used codes; the rate limit; no connection) and can be retried.
class JoinCubit(
  final InviteRepository _invites,
  final SessionCubit _session, {
  final PendingInvite? pendingInvite,
  final String? link,
}) extends Cubit<JoinState> {
  this : super(const JoinState());

  /// The code that was looked at last, so a join uses what was confirmed.
  String? _checked;

  /// The code changed after a preview: it has to be looked at again.
  void edited(String code) {
    if (_checked != null && normalizeInviteCode(code) != _checked) {
      _checked = null;
      emit(state.copyWith(phase: JoinPhase.entering));
    }
  }

  Future<void> check(String code) async {
    final normalized = normalizeInviteCode(code);
    if (state.busy || normalized.isEmpty) {
      return;
    }
    emit(state.copyWith(phase: JoinPhase.checking));
    try {
      switch (await _invites.preview(normalized)) {
        case InviteOpen(:final name, :final lifetime):
          _checked = normalized;
          emit(
            state.copyWith(
              phase: JoinPhase.previewed,
              household: name,
              lifetime: lifetime,
            ),
          );
        case InviteMember(:final name):
          // A link to one of their households: nothing to join, but it
          // shows. accept_invite answers its id (status member) and uses
          // up nothing.
          await _session.join(normalized, method: _methodOf(normalized));
          pendingInvite?.clear();
          emit(state.copyWith(phase: JoinPhase.joined, household: name));
      }
    } on HouseholdError catch (e) {
      _refused(normalized, e.problem);
    }
  }

  /// Joins the previewed household; the user's other households stay.
  Future<void> join() async {
    final code = _checked;
    if (state.busy || code == null) {
      return;
    }
    final household = state.household;
    final lifetime = state.lifetime;
    emit(
      state.copyWith(
        phase: JoinPhase.joining,
        household: household,
        lifetime: lifetime,
      ),
    );
    try {
      await _session.join(code, method: _methodOf(code));
      pendingInvite?.clear();
      emit(state.copyWith(phase: JoinPhase.joined, household: household));
    } on HouseholdError catch (e) {
      if (e.problem == HouseholdProblem.offline) {
        // Still the same good code: Join again once back online.
        emit(
          state.copyWith(
            phase: JoinPhase.previewed,
            household: household,
            lifetime: lifetime,
            problem: e.problem,
          ),
        );
      } else {
        _refused(code, e.problem);
      }
    }
  }

  JoinMethod _methodOf(String code) =>
      link != null && normalizeInviteCode(link!) == code
      ? JoinMethod.link
      : JoinMethod.code;

  @override
  void emit(JoinState state) {
    // The router may close the screen while a call is out (an MCP
    // authorization waiting after the join).
    if (!isClosed) {
      super.emit(state);
    }
  }

  void _refused(String code, HouseholdProblem problem) {
    _checked = null;
    if (problem == HouseholdProblem.invalidInvite) {
      // A link to a dead invite should not come back after the next start.
      pendingInvite?.refused(code);
    }
    emit(state.copyWith(phase: JoinPhase.entering, problem: problem));
  }
}
