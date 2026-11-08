import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The joiner's wait (job 169b W3 M): the household confirms joins, so the
/// invite made a request an owner or admin decides on. "Anfrage gesendet:
/// Ein Admin von „Sommerfest“ bestätigt deinen Beitritt.", the request can
/// be withdrawn, and the user goes on: to the list when in a household,
/// else to creating their own instead of waiting.
///
/// Self-contained for onboarding's rebuild (job 168b): it needs the
/// household's id and name and a [SessionCubit] above, nothing else. Once
/// the session no longer lists the request (approved, declined or
/// withdrawn) it leaves by itself ([leaveStep]); `JoinDecisionNotices`
/// tells the decision. The join screen shows it after the answer;
/// [joinWaitingPath] ([PendingJoinScreen]) shows it to someone without a
/// household, who the router sends there instead of Step 1.
class const JoinRequestWaiting({
  required final String householdId,
  required final String householdName,
  super.key,
}) extends StatefulWidget {
  @override
  State<JoinRequestWaiting> createState() => _JoinRequestWaitingState();
}

class _JoinRequestWaitingState() extends State<JoinRequestWaiting> {
  var _busy = false;
  HouseholdProblem? _problem;

  bool _waits(Session session) => switch (session) {
    NeedsHousehold(:final requests) || InHousehold(:final requests) =>
      requests.any((r) => r.householdId == widget.householdId),
    _ => false,
  };

  Future<void> _withdraw() async {
    final session = context.read<SessionCubit>();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await session.withdrawJoinRequest(widget.householdId);
    } on HouseholdError catch (e) {
      if (mounted) {
        setState(() => _problem = e.problem);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    // Withdrawn before the server listed it: nothing to wait for.
    if (mounted && _problem == null && !_waits(session.state)) {
      leaveStep(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = HummlistColors.of(theme.brightness);
    final session = context.watch<SessionCubit>();
    final inHousehold = session.state is InHousehold;
    final problem = _problem;
    return BlocListener<SessionCubit, Session>(
      listenWhen: (before, now) => _waits(before) && !_waits(now),
      listener: (context, _) => leaveStep(context),
      child: OnboardingPage(
        title: inHousehold ? l10n.joinTitle : l10n.onboardingJoin,
        listKey: const ValueKey('join-request-waiting'),
        onBack: inHousehold ? () => leaveStep(context) : null,
        actions: [
          if (!inHousehold)
            IconButton(
              tooltip: l10n.signOut,
              icon: const Icon(Icons.logout),
              onPressed: () => unawaited(session.signOut()),
            ),
        ],
        children: [
          const SizedBox(height: HlSpace.s4),
          Center(
            child: PointyHex(
              face: t.honey,
              size: 72,
              child: Icon(
                Icons.hourglass_top_outlined,
                size: 28,
                color: t.onHoney,
              ),
            ),
          ),
          const SizedBox(height: HlSpace.s5),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.joinRequestSent(widget.householdName),
              key: const ValueKey('join-request-sent'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (problem != null)
            ProblemText(
              householdProblemText(l10n, problem),
              key: const ValueKey('join-request-problem'),
            ),
          const SizedBox(height: HlSpace.s6),
          FilledButton(
            key: const ValueKey('join-request-go-on'),
            onPressed: inHousehold
                ? () => leaveStep(context)
                : () => context.go(createHouseholdPath),
            child: Text(
              inHousehold ? l10n.joinRequestToList : l10n.joinRequestCreateOwn,
            ),
          ),
          const SizedBox(height: HlSpace.s2),
          TextButton(
            key: const ValueKey('join-request-withdraw'),
            onPressed: _busy ? null : () => unawaited(_withdraw()),
            child: Text(l10n.joinRequestWithdraw),
          ),
        ],
      ),
    );
  }
}

/// [joinWaitingPath]: the wait for the oldest of the user's join requests,
/// for someone without a household. Nothing once there is none (the router
/// moves on).
class const PendingJoinScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      switch (context.watch<SessionCubit>().state) {
        NeedsHousehold(requests: [final request, ...]) ||
        InHousehold(requests: [final request, ...]) => JoinRequestWaiting(
          householdId: request.householdId,
          householdName: request.householdName,
        ),
        _ => const SizedBox.shrink(),
      };
}
