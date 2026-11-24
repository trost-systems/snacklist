import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/join_cubit.dart';
import 'package:family_groceries/household/join_request_waiting.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Onboarding Step 2b, also for someone in a household (the switcher's and
/// More's "Mit Code beitreten", or an invite link): enter or keep the code,
/// see the household's name, then join. Joining adds the household beside
/// the user's others (job 169b) and shows it; a household that confirms
/// joins shows [JoinRequestWaiting] instead.
class const JoinScreen({
  super.key,

  /// The code of the invite link the user came with (`/join/<code>`).
  final String? link,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => JoinCubit(
      context.read<InviteRepository>(),
      context.read<SessionCubit>(),
      pendingInvite: context.read<PendingInvite>(),
      link: link,
      flags: context.read<Flags?>(),
      onboarding: context.read<OnboardingCubit?>(),
    ),
    child: _JoinView(link: link),
  );
}

class const _JoinView({final String? link}) extends StatefulWidget {
  @override
  State<_JoinView> createState() => _JoinViewState();
}

class _JoinViewState() extends State<_JoinView> {
  late final _code = TextEditingController(text: widget.link ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.link case final link?) {
      unawaited(context.read<JoinCubit>().check(link));
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Back where the user came from, or to the list, which is Step 1
  /// without a household. The link is answered.
  void _cancel() {
    context.read<PendingInvite>().clear();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      leaveStep(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inHousehold = context.watch<SessionCubit>().state is InHousehold;
    return BlocConsumer<JoinCubit, JoinState>(
      listenWhen: (before, now) => now.phase == JoinPhase.joined,
      // To the list, or to the MCP authorization this was on the way to.
      listener: (context, _) => leaveStep(context),
      builder: (context, state) {
        if (state case JoinState(
          phase: JoinPhase.requested,
          :final requested?,
        )) {
          return JoinRequestWaiting(
            householdId: requested,
            householdName: state.household ?? '',
          );
        }
        final cubit = context.read<JoinCubit>();
        final previewed =
            state.phase == JoinPhase.previewed ||
            state.phase == JoinPhase.joining;
        final problem = state.problem;
        final join = state.busy
            ? null
            : previewed
            ? () => unawaited(cubit.join())
            : () => unawaited(cubit.check(_code.text));
        final lifetime = state.lifetime;
        final accountLifetime = holdsAccountLifetime(context, listen: true);
        return OnboardingPage(
          title: inHousehold ? l10n.joinTitle : l10n.onboardingJoin,
          listKey: const ValueKey('join-screen'),
          onBack: _cancel,
          children: [
            LabeledField(
              label: l10n.inviteCode,
              field: TextField(
                autofillHints: null,
                key: const ValueKey('invite-code'),
                controller: _code,
                enabled: !state.busy,
                autofocus: widget.link == null,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: cubit.edited,
                onSubmitted: (_) => join?.call(),
              ),
            ),
            if (previewed && state.household != null) ...[
              const SizedBox(height: 16),
              Card.outlined(
                key: const ValueKey('invite-household'),
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: Text(l10n.invitePreview),
                  subtitle: Text(
                    state.household!,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              if (lifetime.targetUnlocked) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  child: ListTile(
                    key: const ValueKey('join-target-unlocked'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(l10n.joinTargetUnlocked),
                  ),
                ),
              ],
              if (lifetime.refundHelp && !accountLifetime)
                RefundHelpLink(
                  key: const ValueKey('join-refund-help'),
                  label: l10n.joinRefundLink,
                ),
            ],
            if (problem != null)
              ProblemText(
                householdProblemText(l10n, problem),
                key: const ValueKey('join-problem'),
                neutral: problem == HouseholdProblem.declinedRecently,
              ),
            if (state.busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            // JH2 joins a link without asking: no Join while it does.
            if (!cubit.joiningLink) ...[
              const SizedBox(height: 24),
              FilledButton(
                key: ValueKey(previewed ? 'join-confirm' : 'invite-check'),
                onPressed: join,
                child: Text(previewed ? l10n.joinHousehold : l10n.inviteCheck),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('join-cancel'),
              onPressed: _cancel,
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    );
  }
}
