import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Back out of an onboarding step: to the list, which the router turns
/// into Step 1 without a household. An MCP authorization the onboarding is
/// on the way to (`next`) rides along.
void leaveStep(BuildContext context) {
  final next = GoRouterState.of(context).uri.queryParameters['next'];
  context.go(
    Uri(
      path: listPath,
      queryParameters: next == null ? null : {'next': next},
    ).toString(),
  );
}

/// The frame of every onboarding step: a title bar and one centred list,
/// at most 420 wide. One list, like the analytics consent before it: a
/// layout with pinned buttons moved the web engine's text fields
/// (DECISIONS 19.20).
class const OnboardingPage({
  required final String title,
  required final List<Widget> children,
  final List<Widget>? actions,

  /// The app bar's back button; none when null and nothing to pop.
  final VoidCallback? onBack,
  final Key? listKey,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      automaticallyImplyLeading: false,
      leading: onBack == null ? null : BackButton(onPressed: onBack),
      actions: actions,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          key: listKey,
          // Clear of the home indicator, and in the More tab of the
          // floating tab pill.
          padding: const EdgeInsets.all(
            24,
          ).add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)),
          shrinkWrap: true,
          children: children,
        ),
      ),
    ),
  );
}

/// What the user reads for [problem].
String householdProblemText(AppLocalizations l10n, HouseholdProblem problem) =>
    switch (problem) {
      HouseholdProblem.invalidInvite => l10n.invalidInvite,
      HouseholdProblem.tooManyAttempts => l10n.tooManyAttempts,
      HouseholdProblem.offline => l10n.householdOffline,
      HouseholdProblem.archiveDisabled => l10n.householdArchiveDisabled,
      HouseholdProblem.tooManyHouseholds => l10n.tooManyHouseholds,
      HouseholdProblem.notMember ||
      HouseholdProblem.other => l10n.genericError(problem.name),
    };

/// A problem line under a form: error colour, announced to screen readers.
class const ProblemText(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
