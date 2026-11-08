import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/join_approval_section.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/premium_dialogs.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// More's Haushalt (job 169b): the shown household's name (rename), its
/// members with their roles (the owner and admins remove members, the
/// owner names admins), "Leute einladen", whether Siri, Alexa and AI
/// assistants use it, and leaving it.
class const HouseholdPage({
  super.key,

  /// The last member of a household with Lifetime may archive it (job 43).
  final bool archiveOffered = Environment.householdArchive,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      switch (context.watch<SessionCubit>().state) {
        InHousehold(:final userId, :final household, :final households) =>
          _HouseholdView(
            // A switch or a leave shows another household: its own members.
            key: ValueKey(household.id),
            userId: userId,
            household: household,
            defaultHousehold: households.where((h) => h.isDefault).firstOrNull,
            archiveOffered: archiveOffered,
          ),
        _ => const SizedBox.shrink(),
      };
}

class const _HouseholdView({
  required final String userId,
  required final Household household,
  required final Household? defaultHousehold,
  required final bool archiveOffered,
  super.key,
}) extends StatefulWidget {
  @override
  State<_HouseholdView> createState() => _HouseholdViewState();
}

/// What the leave dialog answered.
enum _Leave() {
  leave,
  archive,
}

/// What a member's menu offers.
enum _MemberAction() {
  makeAdmin,
  removeAdmin,
  remove,
}

class _HouseholdViewState() extends State<_HouseholdView> {
  late Future<List<HouseholdMember>> _members = _loadMembers();
  var _busy = false;

  Future<List<HouseholdMember>> _loadMembers() =>
      context.read<InviteRepository>().members(widget.household.id);

  /// Runs a household call; a refusal is told in a snackbar.
  Future<bool> _run(Future<void> Function() call) async {
    final notices = Notices.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await call();
      return true;
    } on HouseholdError catch (e) {
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rename() async {
    final session = context.read<SessionCubit>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(widget.household.name),
    );
    if (name != null && name.trim() != widget.household.name && mounted) {
      await _run(() => session.rename(widget.household.id, name));
    }
  }

  Future<void> _leave() async {
    final session = context.read<SessionCubit>();
    final invites = context.read<InviteRepository>();
    final household = widget.household;
    final alone = await _members.then(
      (members) => members.every((m) => m.userId == widget.userId),
      onError: (_) => household.memberCount <= 1,
    );
    final unlocked =
        alone &&
        await invites
            .leavesUnlocked(household.id)
            .then<bool>((u) => u, onError: (_) => false);
    if (!mounted) {
      return;
    }
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (_) => _LeaveDialog(
        household: household.name,
        alone: alone,
        unlocked: unlocked,
        archiveOffered: widget.archiveOffered,
      ),
    );
    // A yearly plan keeps being billed: its subscriber hears so (H-85).
    if (choice == null ||
        !mounted ||
        !await confirmBillingContinues(
          context,
          account: false,
          household: household.id,
        ) ||
        !mounted) {
      return;
    }
    final router = GoRouter.of(context);
    if (await _run(
      () => session.leave(household.id, archive: choice == _Leave.archive),
    )) {
      router.go(listPath);
    }
  }

  /// What the user may do to [member]: the owner names and un-names
  /// admins and removes anyone; an admin removes members. Nobody acts on
  /// themselves (that is leaving) or on the owner.
  List<_MemberAction> _actionsFor(HouseholdMember member) => switch ((
    widget.household.role,
    member.role,
  )) {
    _ when member.userId == widget.userId => const [],
    (HouseholdRole.owner, HouseholdRole.member) => const [
      _MemberAction.makeAdmin,
      _MemberAction.remove,
    ],
    (HouseholdRole.owner, HouseholdRole.admin) => const [
      _MemberAction.removeAdmin,
      _MemberAction.remove,
    ],
    (HouseholdRole.admin, HouseholdRole.member) => const [_MemberAction.remove],
    _ => const [],
  };

  Future<void> _act(HouseholdMember member, _MemberAction action) async {
    final invites = context.read<InviteRepository>();
    final session = context.read<SessionCubit>();
    final analytics = context.read<Analytics>();
    final household = widget.household;
    final done = switch (action) {
      _MemberAction.makeAdmin => await _run(
        () => invites.setRole(household.id, member.userId, HouseholdRole.admin),
      ),
      _MemberAction.removeAdmin => await _run(
        () =>
            invites.setRole(household.id, member.userId, HouseholdRole.member),
      ),
      _MemberAction.remove =>
        await _confirmRemove(member) &&
            await _run(() => invites.removeMember(household.id, member.userId)),
    };
    if (!done || !mounted) {
      return;
    }
    if (action == _MemberAction.remove) {
      analytics.track('member_removed');
      // The household's member count in the switcher.
      unawaited(session.refresh().catchError((Object _) {}));
    }
    setState(() {
      _members = _loadMembers();
    });
  }

  Future<bool> _confirmRemove(HouseholdMember member) async {
    final name = _memberName(AppLocalizations.of(context), member);
    return await showDialog<bool>(
          context: context,
          builder: (dialog) {
            final l10n = AppLocalizations.of(dialog);
            return AlertDialog(
              key: const ValueKey('member-remove-dialog'),
              title: Text(l10n.memberRemoveTitle(name)),
              content: Text(l10n.memberRemoveBody(name, widget.household.name)),
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

  Widget _member(AppLocalizations l10n, HouseholdMember member) {
    final name = _memberName(l10n, member);
    final actions = _actionsFor(member);
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
              enabled: !_busy,
              onSelected: (action) => unawaited(_act(member, action)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final household = widget.household;
    final isDefault = household.isDefault;
    return ListView(
      key: const ValueKey('household-page'),
      padding: EdgeInsets.only(
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        HlSectionLabel(l10n.householdName),
        ListTile(
          key: const ValueKey('household-name'),
          minTileHeight: 56,
          leading: const Icon(Icons.home_outlined),
          title: Text(household.name, style: theme.textTheme.titleMedium),
          trailing: TextButton(
            key: const ValueKey('household-rename'),
            onPressed: _busy ? null : () => unawaited(_rename()),
            child: Text(l10n.householdRename),
          ),
        ),
        HlSectionLabel(l10n.householdMembersTitle),
        FutureBuilder(
          future: _members,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final data?) => Column(
              key: const ValueKey('household-members'),
              children: [for (final member in data) _member(l10n, member)],
            ),
            AsyncSnapshot(hasError: true) => ListTile(
              key: const ValueKey('household-members-failed'),
              title: Text(l10n.householdMembersFailed),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ),
        ListTile(
          key: const ValueKey('household-invite'),
          leading: const Icon(Icons.person_add_outlined),
          title: Text(l10n.inviteSheetTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(
            showInviteSheet(context, household, from: InviteContext.household),
          ),
        ),
        JoinApprovalSection(
          household: household,
          onApproved: () => setState(() {
            _members = _loadMembers();
          }),
        ),
        HlSectionLabel(l10n.voiceDefaultTitle),
        // There is always one default: another household's button moves
        // it here; this one's can't be turned off.
        if (isDefault)
          ListTile(
            key: const ValueKey('household-is-default'),
            leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            title: Text(l10n.voiceDefaultOn),
          )
        else
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(switch (widget.defaultHousehold) {
              final other? => l10n.voiceDefaultOff(other.name),
              null => l10n.voiceDefaultBody,
            }),
            trailing: TextButton(
              key: const ValueKey('household-default'),
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(
                        () => context.read<SessionCubit>().setDefault(
                          household.id,
                        ),
                      ),
                    ),
              child: Text(l10n.voiceDefaultMake),
            ),
          ),
        const SizedBox(height: 16),
        ListTile(
          key: const ValueKey('household-leave'),
          leading: const Icon(Icons.logout),
          iconColor: theme.colorScheme.error,
          textColor: theme.colorScheme.error,
          title: Text(l10n.leaveHousehold),
          enabled: !_busy,
          onTap: () => unawaited(_leave()),
        ),
      ],
    );
  }

  String _memberName(AppLocalizations l10n, HouseholdMember member) {
    final name = member.displayName.isEmpty
        ? l10n.householdMemberUnnamed
        : member.displayName;
    return member.userId == widget.userId
        ? l10n.householdMemberYou(name)
        : name;
  }
}

/// The new name, or null when cancelled.
class const _RenameDialog(final String name) extends StatefulWidget {
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState() extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);
  var _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!validHouseholdName(_name.text)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('household-rename-dialog'),
      title: Text(l10n.householdRenameTitle),
      content: TextField(
        key: const ValueKey('household-rename-field'),
        controller: _name,
        autofocus: true,
        maxLength: maxHouseholdName,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          errorText: _invalid ? l10n.householdNameInvalid : null,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('household-rename-save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// What leaving does: the others keep the list, or the household goes
/// with its last member; with Hummlist Lifetime it may be archived instead
/// (job 43), or its Lifetime ends.
class const _LeaveDialog({
  required final String household,
  required final bool alone,
  required final bool unlocked,
  required final bool archiveOffered,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final archive = alone && unlocked && archiveOffered;
    void answer(_Leave? choice) => Navigator.of(context).pop(choice);
    return AlertDialog(
      key: const ValueKey('household-leave-dialog'),
      title: Text(l10n.leaveTitle(household)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch ((alone, unlocked)) {
            (false, _) => l10n.leaveShared,
            (true, false) => l10n.leaveLast,
            (true, true) when archiveOffered => l10n.leaveArchiveOffer(
              household,
            ),
            (true, true) => l10n.leaveLifetimeEnds(household),
          }),
          if (alone && unlocked && !archiveOffered)
            RefundHelpLink(
              key: const ValueKey('household-leave-refund-help'),
              label: l10n.joinLifetimeRefundLink,
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('household-leave-cancel'),
          onPressed: () => answer(null),
          child: Text(l10n.cancel),
        ),
        if (archive) ...[
          OutlinedButton(
            key: const ValueKey('household-leave-delete'),
            onPressed: () => answer(_Leave.leave),
            child: Text(l10n.leaveDelete),
          ),
          FilledButton(
            key: const ValueKey('household-leave-archive'),
            onPressed: () => answer(_Leave.archive),
            child: Text(l10n.leaveArchive),
          ),
        ] else
          FilledButton(
            key: const ValueKey('household-leave-confirm'),
            style: dangerButtonStyle(context),
            onPressed: () => answer(_Leave.leave),
            child: Text(l10n.leaveHousehold),
          ),
      ],
    );
  }
}
