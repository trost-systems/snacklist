import 'dart:async';

import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The steps the progress counts: every screen of the guided start a user
/// can see, in order.
const _counted = [
  OnboardingStep.usage,
  OnboardingStep.who,
  OnboardingStep.name,
  OnboardingStep.stores,
  OnboardingStep.need,
  OnboardingStep.account,
  OnboardingStep.invite,
];

/// One step of the guided start (job 168b): [OnboardingPage] titled with
/// the progress („Schritt 3 von 7“, which always fits the bar), the bar,
/// the step's question as the page's heading (it wraps), a back button to
/// [back] (none on the first question), and the X that leaves the guided
/// start ([OnboardingExitButton]).
class const OnboardingStepPage({
  required final OnboardingStep step,
  required final List<Widget> children,

  /// The question; none where [children] bring their own heading.
  final String? title,

  /// The step „Zurück“ returns to; none when null.
  final OnboardingStep? back,

  /// The X; the invite step has „Später“ instead.
  final bool exit = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => OnboardingPage(
    title: onboardingProgressText(context, step),
    listKey: ValueKey('onboarding-${step.name}'),
    onBack: switch (back) {
      final back? => () => context.read<OnboardingCubit>().at(back),
      null => null,
    },
    actions: [if (exit) const OnboardingExitButton()],
    children: [
      OnboardingProgress(step: step),
      const SizedBox(height: HlSpace.s5),
      if (title case final title?) ...[
        OnboardingHeading(title),
        const SizedBox(height: HlSpace.s3),
      ],
      ...children,
    ],
  );
}

/// „Schritt 3 von 7“.
String onboardingProgressText(BuildContext context, OnboardingStep step) =>
    AppLocalizations.of(context)
        .onboardingProgress(_counted.indexOf(step) + 1, _counted.length);

/// The bar under „Schritt 3 von 7“ (the app bar's title, which screen
/// readers read).
class const OnboardingProgress({required final OnboardingStep step, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LinearProgressIndicator(
      value: (_counted.indexOf(step) + 1) / _counted.length,
      borderRadius: BorderRadius.circular(HlRadius.s),
    ),
  );
}

/// A step's question, the page's heading.
class const OnboardingHeading(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// What the leave dialog chose.
enum _Leave() {
  signIn,
  signOut,
  discard,
}

/// The X on every step of the guided start: leave it to sign in instead
/// (signed out; the progress stays on the device), sign out (signed in),
/// or drop the progress.
class const OnboardingExitButton({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('onboarding-exit'),
    tooltip: AppLocalizations.of(context).onboardingExit,
    icon: const Icon(Icons.close),
    onPressed: () => unawaited(_leave(context)),
  );

  Future<void> _leave(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final session = context.read<SessionCubit>();
    final onboarding = context.read<OnboardingCubit>();
    final signedIn = session.state is! SignedOut;
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const ValueKey('onboarding-exit-dialog'),
        title: Text(l10n.onboardingExitTitle),
        content: Text(l10n.onboardingExitBody),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: HlSpace.s2,
        actions: [
          TextButton(
            key: const ValueKey('onboarding-exit-discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialog).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, _Leave.discard),
            child: Text(l10n.onboardingExitDiscard),
          ),
          if (signedIn)
            TextButton(
              key: const ValueKey('onboarding-exit-sign-out'),
              onPressed: () => Navigator.pop(dialog, _Leave.signOut),
              child: Text(l10n.signOut),
            )
          else
            TextButton(
              key: const ValueKey('onboarding-exit-sign-in'),
              onPressed: () => Navigator.pop(dialog, _Leave.signIn),
              child: Text(l10n.onboardingExitLogIn),
            ),
          FilledButton.tonal(
            key: const ValueKey('onboarding-exit-stay'),
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.onboardingExitStay),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case _Leave.signIn:
        goToSignIn(context);
      case _Leave.signOut:
        await session.signOut();
      case _Leave.discard:
        onboarding.discard();
      case null:
        break;
    }
  }
}
