import 'package:family_groceries/analytics/events.dart' show JoinMethod;
import 'package:family_groceries/design/code_field.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/join_code_cubit.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Which of the join page's facts a typed code's preview shows (JH-Q9:
/// each can be turned off on its own until Legal approves them for the
/// app).
@immutable
class const InvitePreviewFields({
  final bool inviter = true,
  final bool household = true,
  final bool members = true,
  final bool openItems = true,
  final bool premium = true,
});

/// The preview's fields in this build: the join page's set.
const invitePreviewFields = InvitePreviewFields();

/// The guided start's „Bestehendem Haushalt beitreten“ (job 271, JH2): the
/// 8-character code, looked up the moment it is complete, the household it
/// leads to, and Join. Join keeps the code like an opened link and ends the
/// guided start: the router then signs in first (signed out) or opens the
/// join at `/join/<code>`, which joins without asking again.
class const JoinCodeScreen({
  final InvitePreviewFields fields = invitePreviewFields,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => JoinCodeCubit(context.read<InviteRepository>()),
    child: _JoinCodeView(fields: fields),
  );
}

class const _JoinCodeView({required final InvitePreviewFields fields})
    extends StatefulWidget {
  @override
  State<_JoinCodeView> createState() => _JoinCodeViewState();
}

class _JoinCodeViewState() extends State<_JoinCodeView> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join(String code) {
    context.read<PendingInvite>().remember(code, via: JoinMethod.code);
    // Gone before any join: the router must not set the draft up in the
    // joined household.
    context.read<OnboardingCubit>().discard();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<JoinCodeCubit>();
    final state = context.watch<JoinCodeCubit>().state;
    return OnboardingPage(
      title: l10n.joinTitle,
      listKey: const ValueKey('join-code-screen'),
      onBack: () => context.read<OnboardingCubit>().at(OnboardingStep.name),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.jh2JoinCodeHeading,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: HlSpace.s2),
        Text(l10n.jh2JoinCodeHelp),
        const SizedBox(height: HlSpace.s5),
        LabeledField(
          label: l10n.inviteCode,
          field: CodeField(
            controller: _code,
            autofocus: true,
            inputFormatters: const [InviteCodeFormatter()],
            onChanged: cubit.changed,
          ),
        ),
        const SizedBox(height: HlSpace.s4),
        switch (state) {
          CodeTyping() => const SizedBox.shrink(),
          CodeLookingUp() => const Center(
            child: Padding(
              padding: EdgeInsets.all(HlSpace.s2),
              child: CircularProgressIndicator(),
            ),
          ),
          CodeFound(:final invite) => InvitePreviewCard(
            invite: invite,
            fields: widget.fields,
          ),
          CodeUnavailable() => ProblemText(
            l10n.jh2CodeUnavailable,
            key: const ValueKey('join-code-problem'),
          ),
          CodeRateLimited() => ProblemText(
            l10n.jh2CodeRateLimited,
            key: const ValueKey('join-code-problem'),
          ),
          CodeLookupFailed(:final problem) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProblemText(
                householdProblemText(l10n, problem),
                key: const ValueKey('join-code-problem'),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('join-code-retry'),
                  onPressed: cubit.retry,
                  child: Text(l10n.retry),
                ),
              ),
            ],
          ),
        },
        const SizedBox(height: HlSpace.s5),
        FilledButton(
          key: const ValueKey('join-code-join'),
          onPressed: switch (state) {
            CodeFound(:final code) => () => _join(code),
            _ => null,
          },
          child: Text(l10n.jh2JoinCodeJoin),
        ),
      ],
    );
  }
}

/// What a code leads to, as the join page shows it: „Peter lädt dich zu
/// „Familie Trost“ ein“, „3 Mitglieder · 12 offene Einträge“ and Premium.
/// Only the [fields] that are on; the title reads well with either name
/// off.
class const InvitePreviewCard({
  required final PublicInviteOpen invite,
  final InvitePreviewFields fields = invitePreviewFields,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final inviter = fields.inviter ? invite.inviter : null;
    final household = fields.household ? invite.household : null;
    final title = switch ((inviter, household)) {
      (final inviter?, final household?) => l10n.jh2InvitedBy(
        inviter,
        household,
      ),
      (null, final household?) => l10n.jh2InvitedTo(household),
      (final inviter?, null) => l10n.jh2InvitedByInviter(inviter),
      (null, null) => l10n.jh2InvitedToHousehold,
    };
    final facts = [
      if (fields.members) l10n.jh2PreviewMembers(invite.members),
      if (fields.openItems) l10n.jh2PreviewOpenItems(invite.openItems),
    ];
    return HlSticker(
      key: const ValueKey('join-code-preview'),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(HlSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HlSpace.s2,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (facts.isNotEmpty)
                Text(
                  facts.join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: t.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
