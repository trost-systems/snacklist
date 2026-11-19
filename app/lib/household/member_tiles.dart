import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Runs a household call; a refusal is told in a snackbar. Whether it went
/// through.
Future<bool> tellRefusal(
  BuildContext context,
  Future<void> Function() call,
) async {
  final notices = Notices.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    await call();
    return true;
  } on HouseholdError catch (e) {
    notices.showSnackBar(
      SnackBar(content: Text(householdProblemText(l10n, e.problem))),
    );
    return false;
  }
}

/// What a member's menu offers.
enum _MemberAction() {
  makeAdmin,
  removeAdmin,
  remove,
}

/// [household]'s [members] with their roles (job 169b W2), each with a menu
/// of what the user may do to them: the owner names and un-names admins and
/// removes anyone; an admin removes members. Removing asks first. More's
/// Haushalt and the switcher sheet's members page (job 229) show them.
class const MemberTiles({
  required final String userId,
  required final Household household,
  required final List<HouseholdMember> members,

  /// Runs a member call while the page waits; whether it went through.
  required final Future<bool> Function(Future<void> Function() call) run,

  /// A member was removed or got another role: the page reads them again.
  required final VoidCallback onChanged,
  final bool enabled = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The user's role as the members list just read it, newer than the
    // session's after an owner made them admin on another device.
    final mine =
        members.where((m) => m.userId == userId).firstOrNull?.role ??
        household.role;
    return Column(
      key: const ValueKey('household-members'),
      children: [
        for (final member in members) _member(context, l10n, member, mine),
      ],
    );
  }

  /// What the user may do to [member]. Nobody acts on themselves (that is
  /// leaving) or on the owner.
  List<_MemberAction> _actionsFor(HouseholdMember member, HouseholdRole mine) =>
      switch ((mine, member.role)) {
        _ when member.userId == userId => const [],
        (HouseholdRole.owner, HouseholdRole.member) => const [
          _MemberAction.makeAdmin,
          _MemberAction.remove,
        ],
        (HouseholdRole.owner, HouseholdRole.admin) => const [
          _MemberAction.removeAdmin,
          _MemberAction.remove,
        ],
        (HouseholdRole.admin, HouseholdRole.member) => const [
          _MemberAction.remove,
        ],
        _ => const [],
      };

  Future<void> _act(
    BuildContext context,
    HouseholdMember member,
    _MemberAction action,
  ) async {
    final invites = context.read<InviteRepository>();
    final session = context.read<SessionCubit>();
    final analytics = context.read<Analytics>();
    if (action == _MemberAction.remove &&
        !await _confirmRemove(context, member)) {
      return;
    }
    final done = await run(switch (action) {
      _MemberAction.makeAdmin => () => invites.setRole(
        household.id,
        member.userId,
        HouseholdRole.admin,
      ),
      _MemberAction.removeAdmin => () => invites.setRole(
        household.id,
        member.userId,
        HouseholdRole.member,
      ),
      _MemberAction.remove => () => invites.removeMember(
        household.id,
        member.userId,
      ),
    });
    if (!done || !context.mounted) {
      return;
    }
    if (action == _MemberAction.remove) {
      analytics.track('member_removed');
      // The household's member count in the switcher.
      unawaited(session.refresh().catchError((Object _) {}));
    }
    onChanged();
  }

  Future<bool> _confirmRemove(
    BuildContext context,
    HouseholdMember member,
  ) async {
    final name = _memberName(AppLocalizations.of(context), member);
    return await showDialog<bool>(
          context: context,
          builder: (dialog) {
            final l10n = AppLocalizations.of(dialog);
            return AlertDialog(
              key: const ValueKey('member-remove-dialog'),
              title: Text(l10n.memberRemoveTitle(name)),
              content: Text(l10n.memberRemoveBody(name, household.name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  key: const ValueKey('member-remove-confirm'),
                  style: dangerButtonStyle(dialog),
                  onPressed: () => Navigator.of(dialog).pop(true),
                  child: Text(l10n.memberRemoveConfirm),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _member(
    BuildContext context,
    AppLocalizations l10n,
    HouseholdMember member,
    HouseholdRole mine,
  ) {
    final name = _memberName(l10n, member);
    final actions = _actionsFor(member, mine);
    final role = switch (member.role) {
      HouseholdRole.owner => l10n.householdRoleOwner,
      HouseholdRole.admin => l10n.householdRoleAdmin,
      HouseholdRole.member => null,
    };
    return ListTile(
      key: ValueKey('member-${member.userId}'),
      leading: const Icon(Icons.person_outline),
      title: Text(name),
      subtitle: role == null ? null : Text(role),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<_MemberAction>(
              key: ValueKey('member-actions-${member.userId}'),
              tooltip: l10n.memberActions(name),
              useRootNavigator: true,
              enabled: enabled,
              onSelected: (action) => unawaited(_act(context, member, action)),
              itemBuilder: (_) => [
                for (final action in actions)
                  PopupMenuItem(
                    key: ValueKey('member-${action.name}'),
                    value: action,
                    child: Text(switch (action) {
                      _MemberAction.makeAdmin => l10n.memberMakeAdmin,
                      _MemberAction.removeAdmin => l10n.memberRemoveAdmin,
                      _MemberAction.remove => l10n.memberRemove,
                    }),
                  ),
              ],
            ),
    );
  }

  String _memberName(AppLocalizations l10n, HouseholdMember member) {
    final name = member.displayName.isEmpty
        ? l10n.householdMemberUnnamed
        : member.displayName;
    return member.userId == userId ? l10n.householdMemberYou(name) : name;
  }
}
