import 'dart:async';

import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/create_household_screen.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/premium_dialogs.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Runs a household call the way the page does: busy while it runs, a
/// refusal told. Whether it went through.
typedef HouseholdRun = Future<bool> Function(Future<void> Function() call);

/// What the leave dialog answered.
enum _Leave() {
  leave,
  archive,
}

/// Asks for a new name and renames [household] (More's Haushalt page and
/// the switcher sheet share it).
Future<void> renameHousehold(
  BuildContext context,
  Household household, {
  required HouseholdRun run,
}) async {
  final session = context.read<SessionCubit>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(household.name),
  );
  if (name != null && name.trim() != household.name && context.mounted) {
    await run(() => session.rename(household.id, name));
  }
}

/// Leaving [household]: the dialog says whether it goes with the user, a
/// yearly plan's subscriber hears that billing continues (H-85), then the
/// list shows. [onMembers] hears the members fetched for the dialog.
/// Whether the user left.
Future<bool> leaveHousehold(
  BuildContext context, {
  required String userId,
  required Household household,
  required bool archiveOffered,
  required HouseholdRun run,
  ValueChanged<List<HouseholdMember>>? onMembers,
}) async {
  final session = context.read<SessionCubit>();
  final invites = context.read<InviteRepository>();
  // Asked again now: members may have left or joined since the page
  // opened, and the dialog says whether the household goes with the user.
  final alone = await invites.members(household.id).then((members) {
    if (context.mounted) {
      onMembers?.call(members);
    }
    return members.every((m) => m.userId == userId);
  }, onError: (_) => household.memberCount <= 1);
  final unlocked =
      alone &&
      await invites
          .leavesUnlocked(household.id)
          .then<bool>((u) => u, onError: (_) => false);
  if (!context.mounted) {
    return false;
  }
  final accountLifetime = holdsAccountLifetime(context);
  final choice = await showDialog<_Leave>(
    context: context,
    builder: (_) => _LeaveDialog(
      household: household.name,
      alone: alone,
      unlocked: unlocked,
      archiveOffered: archiveOffered,
      accountLifetime: accountLifetime,
    ),
  );
  if (choice == null ||
      !context.mounted ||
      !await confirmBillingContinues(
        context,
        account: false,
        household: household.id,
      ) ||
      !context.mounted) {
    return false;
  }
  final router = GoRouter.of(context);
  final left = await run(
    () => session.leave(household.id, archive: choice == _Leave.archive),
  );
  if (left) {
    router.go(listPath);
  }
  return left;
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
        autofillHints: null,
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
/// with its last member; with Snacklist Lifetime it may be archived instead
/// (job 43), or its Lifetime ends.
class const _LeaveDialog({
  required final String household,
  required final bool alone,
  required final bool unlocked,
  required final bool archiveOffered,

  /// The user's own Lifetime: no refund prompt for a household leftover.
  required final bool accountLifetime,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final archive = alone && unlocked && archiveOffered;
    void answer(_Leave? choice) => Navigator.of(context).pop(choice);
    return AlertDialog(
      key: const ValueKey('household-leave-dialog'),
      title: Text(l10n.leaveTitle(household)),
      content: SingleChildScrollView(
        child: Column(
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
            if (alone && unlocked && !archiveOffered && !accountLifetime)
              RefundHelpLink(
                key: const ValueKey('household-leave-refund-help'),
                label: l10n.joinLifetimeRefundLink,
              ),
          ],
        ),
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
