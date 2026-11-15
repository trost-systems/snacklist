import 'dart:async';

import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where the code typed on the guided start's join step is (job 271), each
/// state with the code in the field (normalized, up to 8 characters).
@immutable
sealed class const JoinCodeState(final String code);

/// Fewer than 8 characters, or the start.
final class const CodeTyping(super.code) extends JoinCodeState;

/// All 8 are in: `preview_invite_public` is asked.
final class const CodeLookingUp(super.code) extends JoinCodeState;

/// The code leads to [invite]: Join is on.
final class const CodeFound(super.code, final PublicInviteOpen invite)
    extends JoinCodeState;

/// Made up, expired, revoked, used or full: one answer for all.
final class const CodeUnavailable(super.code) extends JoinCodeState;

/// Too many lookups in the hour.
final class const CodeRateLimited(super.code) extends JoinCodeState;

/// No answer, or one the app cannot read ([problem]): the lookup can be
/// tried again.
final class const CodeLookupFailed(super.code, final HouseholdProblem problem)
    extends JoinCodeState;

/// The join step's code: looks it up the moment the 8th character is in
/// (typed or pasted), with no tap. An edit after a lookup starts over, and
/// an answer for a code no longer in the field is dropped.
class JoinCodeCubit(final InviteRepository _invites)
    extends Cubit<JoinCodeState> {
  this : super(const CodeTyping(''));

  /// The field holds [code] now (normalized by its formatter).
  void changed(String code) {
    if (code == state.code) {
      return;
    }
    if (code.length < inviteCodeLength) {
      emit(CodeTyping(code));
      return;
    }
    unawaited(_lookUp(code));
  }

  /// Asks again after a failed lookup.
  void retry() {
    if (state case CodeLookupFailed(:final code)) {
      unawaited(_lookUp(code));
    }
  }

  Future<void> _lookUp(String code) async {
    final asked = CodeLookingUp(code);
    emit(asked);
    final JoinCodeState answer;
    try {
      answer = switch (await _invites.previewPublic(code)) {
        final PublicInviteOpen open => CodeFound(code, open),
        PublicInviteUnavailable() => CodeUnavailable(code),
        PublicInviteRateLimited() => CodeRateLimited(code),
      };
    } on HouseholdError catch (e) {
      if (identical(state, asked)) {
        emit(CodeLookupFailed(code, e.problem));
      }
      return;
    }
    if (identical(state, asked)) {
      emit(answer);
    }
  }

  @override
  void emit(JoinCodeState state) {
    if (!isClosed) {
      super.emit(state);
    }
  }
}
