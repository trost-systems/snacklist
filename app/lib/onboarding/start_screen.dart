import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/brand_block.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/paste_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The first screen signed out (job 168b): the app icon and wordmark, what
/// Snacklist is, „Los geht's“ into the guided start (the usage-data question
/// first, unless this install answered it), „Schon ein Konto? Anmelden“
/// and „Einladung einfügen“ for a join link copied before the install. With
/// JH2 (job 271) only „Los geht's“ and „Schon ein Konto“: joining is the
/// name step's. The router moves on once the draft exists.
class const StartScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final jh2 = context.select<Flags?, bool>(
      (f) => f?.isOn(joinHouseholdJh2Flag) ?? false,
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView(
                    key: const ValueKey('start-screen'),
                    padding: const EdgeInsets.all(HlSpace.s5),
                    shrinkWrap: true,
                    children: [
                      const BrandBlock(),
                      const SizedBox(height: HlSpace.s3),
                      Text(
                        l10n.startTagline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: HlSpace.s4),
                      Text(
                        l10n.startWelcome,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(height: HlSpace.s6),
                      FilledButton(
                        key: const ValueKey('start-go'),
                        onPressed: () => context.read<OnboardingCubit>().start(
                          askUsage: context.read<Analytics>().asksConsent,
                        ),
                        child: Text(l10n.startGo),
                      ),
                      const SizedBox(height: HlSpace.s2),
                      TextButton(
                        key: const ValueKey('start-log-in'),
                        onPressed: () => goToSignIn(context),
                        child: Text(
                          jh2 ? l10n.jh2StartHaveAccount : l10n.startLogIn,
                        ),
                      ),
                      if (!jh2) ...[
                        const SizedBox(height: HlSpace.s2),
                        // Job 169b W2: a join link the store did not carry
                        // over, pasted before the sign-in.
                        const Align(child: PasteInvite()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SafeArea(top: false, child: LegalFooter()),
          ],
        ),
      ),
    );
  }
}
