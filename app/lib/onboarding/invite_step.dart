import 'dart:async';

import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/onboarding_frame.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The invites made on the invite step, oldest first, and who accepted
/// which.
@immutable
class const StepInvites({
  final List<Invite> invites = const [],

  /// Accepted invites by id: who joined, empty without a name.
  final Map<String, String> joined = const {},
  final bool busy = false,
  final HouseholdProblem? problem,
}) {
  StepInvites copyWith({
    List<Invite>? invites,
    Map<String, String>? joined,
    bool? busy,
    HouseholdProblem? Function()? problem,
  }) => StepInvites(
    invites: invites ?? this.invites,
    joined: joined ?? this.joined,
    busy: busy ?? this.busy,
    problem: problem == null ? this.problem : problem(),
  );
}

/// The invite step's invites: one more per tap, each marked as soon as it
/// is accepted (realtime on `invites`, and a read once subscribed for what
/// came before).
class StepInvitesCubit(final InviteRepository _repo, final String _householdId)
    extends Cubit<StepInvites> {
  this : super(const StepInvites()) {
    _unwatch = _repo.watch(_householdId, () => unawaited(_refresh()));
  }

  late final Future<void> Function() _unwatch;

  /// Makes one more invite; null when it failed (the problem shows).
  Future<Invite?> create() async {
    if (state.busy) {
      return null;
    }
    emit(state.copyWith(busy: true, problem: () => null));
    try {
      final invite = await _repo.create(_householdId);
      if (!isClosed) {
        emit(state.copyWith(invites: [...state.invites, invite], busy: false));
      }
      return invite;
    } on HouseholdError catch (e) {
      if (!isClosed) {
        emit(state.copyWith(busy: false, problem: () => e.problem));
      }
      return null;
    }
  }

  Future<void> _refresh() async {
    final open = [
      for (final i in state.invites)
        if (!state.joined.containsKey(i.id)) i.id,
    ];
    if (open.isEmpty) {
      return;
    }
    try {
      final accepted = await _repo.accepted(open);
      if (accepted.isNotEmpty && !isClosed) {
        emit(state.copyWith(joined: {...state.joined, ...accepted}));
      }
    } on HouseholdError {
      // Offline: the next change or subscription asks again.
    }
  }

  @override
  Future<void> close() async {
    await _unwatch();
    await super.close();
  }
}

/// The guided start's last step, the household made: invite as many people
/// as the user likes, one link each, and see who joined while the screen is
/// open. „Später“ or „Weiter zur Liste“ ends the guided start.
class const InviteStep({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      switch (context.read<SessionCubit>().state) {
        InHousehold(:final household) => BlocProvider(
          create: (_) =>
              StepInvitesCubit(context.read<InviteRepository>(), household.id),
          child: _InviteStepView(household),
        ),
        // The router shows this step only in the household.
        _ => const SizedBox.shrink(),
      };
}

class const _InviteStepView(final Household household) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<StepInvitesCubit>().state;
    final draft = context.watch<OnboardingCubit>().state;
    final kind = draft?.kind;
    final count = draft?.items.length ?? 0;
    final problem = state.problem;
    final title = switch (kind) {
      HouseholdKind.partner => l10n.inviteStepPartner,
      HouseholdKind.family => l10n.inviteStepFamily,
      HouseholdKind.flat => l10n.inviteStepFlat,
      HouseholdKind.club => l10n.inviteStepClub,
      HouseholdKind.solo || HouseholdKind.other || null => l10n.inviteStepOther,
    };
    return OnboardingStepPage(
      step: OnboardingStep.invite,
      title: title,
      exit: false,
      children: [
        Icon(
          Icons.person_add_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: HlSpace.s4),
        Text(
          kind == HouseholdKind.club
              ? l10n.inviteStepBodyClub
              : l10n.inviteStepBody,
          textAlign: TextAlign.center,
        ),
        if (count > 0) ...[
          const SizedBox(height: HlSpace.s2),
          Text(
            l10n.inviteStepWaiting(count),
            key: const ValueKey('invite-step-waiting'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
        ],
        const SizedBox(height: HlSpace.s2),
        const InviteJoinPageHint(textAlign: TextAlign.center),
        const SizedBox(height: HlSpace.s5),
        for (final invite in state.invites) ...[
          InviteCard(
            invite: invite,
            household: household,
            origin: InviteContext.onboarding,
            joinedBy: state.joined[invite.id],
          ),
          const SizedBox(height: HlSpace.s3),
        ],
        if (state.invites.isEmpty)
          FilledButton.icon(
            key: const ValueKey('invite-partner'),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(title),
            onPressed: state.busy
                ? null
                : () => unawaited(_invite(context, household)),
          )
        else
          OutlinedButton.icon(
            key: const ValueKey('invite-another'),
            icon: const Icon(Icons.add),
            label: Text(l10n.inviteAnother),
            onPressed: state.busy
                ? null
                : () => unawaited(_invite(context, household)),
          ),
        if (problem != null)
          ProblemText(
            householdProblemText(l10n, problem),
            key: const ValueKey('invite-problem'),
          ),
        const SizedBox(height: HlSpace.s4),
        TextButton(
          key: const ValueKey('invite-later'),
          onPressed: () => context.read<OnboardingCubit>().finish(
            invited: state.invites.isNotEmpty,
          ),
          child: Text(state.invites.isEmpty ? l10n.later : l10n.toTheList),
        ),
      ],
    );
  }

  /// Makes an invite; the apps open the share sheet at once. The web waits
  /// for a tap on Teilen: Web Share needs a fresh tap, which the server's
  /// answer outlasts. The sheet is anchored at the page: the button may be
  /// gone by then.
  static Future<void> _invite(BuildContext page, Household household) async {
    final invite = await page.read<StepInvitesCubit>().create();
    if (invite != null &&
        !kIsWeb &&
        page.mounted &&
        page.read<InviteSharer>().canShare) {
      await shareInvite(page, invite, household, InviteContext.onboarding);
    }
  }
}
