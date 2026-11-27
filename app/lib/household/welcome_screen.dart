import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/brand_block.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/paste_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/delete_account_dialog.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Onboarding Step 1, after sign-in and the analytics consent, for someone
/// without a household: create one or accept an invite. An invite link
/// skips this step (the router opens the join screen).
class const WelcomeScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return OnboardingPage(
      title: l10n.onboardingTitle,
      listKey: const ValueKey('welcome'),
      actions: [
        IconButton(
          tooltip: l10n.signOut,
          icon: const Icon(Icons.logout),
          onPressed: () => unawaited(context.read<SessionCubit>().signOut()),
        ),
      ],
      children: [
        const BrandBlock(),
        const SizedBox(height: 16),
        Text(l10n.onboardingBody, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        _Choice(
          key: const ValueKey('onboarding-create'),
          icon: Icons.add_home_outlined,
          label: l10n.createHousehold,
          hint: l10n.onboardingCreateHint,
          // The router opens the guided start's first question.
          onTap: () => context.read<OnboardingCubit>().start(askUsage: false),
        ),
        const SizedBox(height: 12),
        _Choice(
          key: const ValueKey('onboarding-join'),
          icon: Icons.group_add_outlined,
          label: l10n.onboardingJoin,
          hint: l10n.onboardingJoinHint,
          onTap: () => context.go(_keepNext(context, joinCodePath)),
        ),
        // JH2 (job 271, JH-Q1) has no Einladung einfügen.
        if (!context.select<Flags?, bool>(
          (f) => f?.isOn(joinHouseholdJh2Flag) ?? false,
        )) ...[
          const SizedBox(height: 12),
          const Align(child: PasteInvite()),
        ],
        const SizedBox(height: 32),
        Align(
          child: TextButton(
            key: const ValueKey('account-delete'),
            style: withFocusRing(
              TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              focusRingColor(SnacklistColors.of(theme.brightness)),
            ),
            onPressed: () => unawaited(deleteAccount(context)),
            child: Text(l10n.accountDelete),
          ),
        ),
      ],
    );
  }
}

/// [path] with the MCP authorization this onboarding is on the way to, if
/// any (the router vetted it).
String _keepNext(BuildContext context, String path) => switch (GoRouterState.of(
  context,
).uri.queryParameters['next']) {
  final next? => Uri(path: path, queryParameters: {'next': next}).toString(),
  null => path,
};

/// One of Step 1's two ways, as a sticker-sized button.
class const _Choice({
  required final IconData icon,
  required final String label,
  required final String hint,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => HlSticker(
    child: Material(
      type: MaterialType.transparency,
      child: FocusRingTile(
        child: ListTile(
          minTileHeight: 72,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(hint),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    ),
  );
}
