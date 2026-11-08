import 'dart:async';

import 'package:family_groceries/household/invite_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where the household's group link stands, as the invite sheet shows it.
sealed class const GroupLink();

/// No open group link: one can be made.
final class const GroupLinkNone() extends GroupLink;

/// Open, with room for more.
final class const GroupLinkActive(final Invite invite) extends GroupLink;

/// Open, but [Invite.maxUses] joined: a new one is needed.
final class const GroupLinkFull(final Invite invite) extends GroupLink;

/// Revoked in this sheet just now; who joined with it still shows.
final class const GroupLinkRevoked(final Invite invite) extends GroupLink;

@immutable
class const InvitesState({
  /// The open invites, person and group, newest first; null until loaded.
  final List<Invite>? invites,

  /// The group link revoked here, until another one is made.
  final Invite? revokedGroup,

  /// Who joined with the group link shown; null until loaded.
  final List<InviteJoin>? joins,

  /// Creating or revoking one: the buttons wait.
  final bool busy = false,
  final HouseholdProblem? problem,
}) {
  /// The open person invites, newest first.
  List<Invite> get people => [
    for (final i in invites ?? const <Invite>[])
      if (i.kind == InviteKind.person) i,
  ];

  GroupLink get group => switch ((invites ?? const <Invite>[])
      .where((i) => i.kind == InviteKind.group)
      .firstOrNull) {
    final open? when open.full => GroupLinkFull(open),
    final open? => GroupLinkActive(open),
    null => switch (revokedGroup) {
      final revoked? => GroupLinkRevoked(revoked),
      null => const GroupLinkNone(),
    },
  };

  InvitesState copyWith({
    List<Invite>? invites,
    List<InviteJoin>? joins,
    bool busy = false,
    HouseholdProblem? problem,
  }) => InvitesState(
    invites: invites ?? this.invites,
    revokedGroup: revokedGroup,
    joins: joins ?? this.joins,
    busy: busy,
    problem: problem,
  );
}

/// The invites of one household: onboarding's Step 3 makes the first, the
/// invite sheet and More's Einladungen list them, make person invites and
/// the group link, revoke, and show who joined with the group link. Used,
/// revoked and expired person invites are not listed.
class InvitesCubit(
  final InviteRepository _repository,
  final String _householdId, {

  /// Step 3 starts empty and makes one on the user's tap; the sheet lists.
  final bool load = true,

  /// Reloads who joined when realtime says someone did.
  final bool live = false,
}) extends Cubit<InvitesState> {
  this : super(InvitesState(invites: load ? null : const [])) {
    if (load) {
      unawaited(reload());
    }
    if (live) {
      _unwatch = _repository.watchJoins(
        _householdId,
        () => unawaited(reload()),
      );
    }
  }

  Future<void> Function()? _unwatch;

  /// The open invites, then who joined with the group link.
  Future<void> reload() async {
    try {
      final invites = await _repository.open(_householdId);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(invites: invites, busy: state.busy));
      await _loadJoins();
    } on HouseholdError catch (e) {
      if (!isClosed) {
        emit(state.copyWith(problem: e.problem, busy: state.busy));
      }
    }
  }

  /// Who joined with the group link shown; a failure keeps the last list.
  Future<void> _loadJoins() async {
    final link = switch (state.group) {
      GroupLinkActive(:final invite) ||
      GroupLinkFull(:final invite) ||
      GroupLinkRevoked(:final invite) => invite,
      GroupLinkNone() => null,
    };
    try {
      final joins = link == null
          ? const <InviteJoin>[]
          : await _repository.joins(link.id);
      if (!isClosed) {
        emit(state.copyWith(joins: joins, busy: state.busy));
      }
    } on HouseholdError catch (e) {
      if (!isClosed) {
        emit(state.copyWith(problem: e.problem, busy: state.busy));
      }
    }
  }

  /// Makes a new invite of [kind] and lists it; null when it failed (the
  /// state says why) or another call is running (a double tap). A group
  /// link replaces the one shown, and who joined starts empty.
  Future<Invite?> create({InviteKind kind = InviteKind.person}) async {
    if (state.busy) {
      return null;
    }
    emit(state.copyWith(busy: true));
    try {
      final invite = await _repository.create(_householdId, kind: kind);
      if (!isClosed) {
        final others = [
          for (final i in state.invites ?? const <Invite>[])
            if (i.id != invite.id &&
                (kind == InviteKind.person || i.kind != InviteKind.group))
              i,
        ];
        emit(
          InvitesState(
            invites: [invite, ...others],
            joins: kind == InviteKind.group ? null : state.joins,
          ),
        );
        if (kind == InviteKind.group) {
          await _loadJoins();
        }
      }
      return invite;
    } on HouseholdError catch (e) {
      if (!isClosed) {
        emit(state.copyWith(problem: e.problem));
      }
      return null;
    }
  }

  /// Revokes [invite]: its link and code stop working at once.
  Future<void> revoke(Invite invite) async {
    if (state.busy) {
      return;
    }
    emit(state.copyWith(busy: true));
    try {
      await _repository.revoke(invite.id);
      if (!isClosed) {
        emit(
          InvitesState(
            invites: [
              for (final i in state.invites ?? const <Invite>[])
                if (i.id != invite.id) i,
            ],
            revokedGroup: invite.kind == InviteKind.group
                ? invite
                : state.revokedGroup,
            joins: state.joins,
          ),
        );
      }
    } on HouseholdError catch (e) {
      if (!isClosed) {
        emit(state.copyWith(problem: e.problem));
      }
    }
  }

  /// A new group link in place of the open one, which stops working.
  Future<Invite?> renewGroup() async {
    if (state.group
        case GroupLinkActive(:final invite) || GroupLinkFull(:final invite)) {
      await revoke(invite);
      if (state.problem != null) {
        return null;
      }
    }
    return await create(kind: InviteKind.group);
  }

  @override
  Future<void> close() async {
    await _unwatch?.call();
    await super.close();
  }
}
