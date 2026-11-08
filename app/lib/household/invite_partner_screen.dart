import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Onboarding Step 3, right after creating the household: "Partner
/// einladen" makes an invite and opens the share sheet in the apps; on the
/// web the invite shows with Teilen (Web Share, where the browser has it),
/// Link kopieren and the code. "Später" goes to the list; More's
/// Einladungen does the same any time.
class const InvitePartnerScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      switch (context.read<SessionCubit>().state) {
        InHousehold(:final household) => BlocProvider(
          create: (_) => InvitesCubit(
            context.read<InviteRepository>(),
            household.id,
            load: false,
          ),
          child: _InvitePartnerView(household),
        ),
        // The router never shows this step without a household.
        _ => const SizedBox.shrink(),
      };
}

class const _InvitePartnerView(final Household household)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<InvitesCubit>().state;
    final invite = state.invites?.firstOrNull;
    final problem = state.problem;
    return OnboardingPage(
      title: l10n.inviteMember,
      listKey: const ValueKey('invite-partner-screen'),
      children: [
        Icon(
          Icons.person_add_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(l10n.invitePartnerBody, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        if (invite != null)
          InviteCard(
            invite: invite,
            household: household,
            origin: InviteContext.onboarding,
          )
        else
          FilledButton.icon(
            key: const ValueKey('invite-partner'),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(l10n.inviteMember),
            onPressed: state.busy
                ? null
                : () => unawaited(_invite(context, household)),
          ),
        if (problem != null)
          ProblemText(
            householdProblemText(l10n, problem),
            key: const ValueKey('invite-problem'),
          ),
        const SizedBox(height: 16),
        TextButton(
          key: const ValueKey('invite-later'),
          onPressed: () => context.go(listPath),
          child: Text(invite == null ? l10n.later : l10n.toTheList),
        ),
      ],
    );
  }

  /// Makes the invite; the apps open the share sheet at once. The web waits
  /// for a tap on Teilen: Web Share needs a fresh tap, which the server's
  /// answer outlasts. The sheet is anchored at the page: the button is
  /// gone by then.
  static Future<void> _invite(BuildContext page, Household household) async {
    final invite = await page.read<InvitesCubit>().create();
    if (invite != null &&
        !kIsWeb &&
        page.mounted &&
        page.read<InviteSharer>().canShare) {
      await shareInvite(page, invite, household, InviteContext.onboarding);
    }
  }
}
