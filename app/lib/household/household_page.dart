import 'dart:async';

import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/household/currency_section.dart';
import 'package:family_groceries/household/default_list.dart';
import 'package:family_groceries/household/household_actions.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/join_approval_section.dart';
import 'package:family_groceries/household/lists_section.dart';
import 'package:family_groceries/household/member_tiles.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// More's Haushalt (job 169b): the shown household's name (rename), its
/// members with their roles (the owner and admins remove members, the
/// owner names admins), "Leute einladen", its lists ([ListsSection]), its
/// currency ([CurrencySection]),
/// whether Siri, Alexa and AI assistants use it and which of its lists
/// they add to ([DefaultListPicker]), and leaving it.
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

class _HouseholdViewState() extends State<_HouseholdView> {
  late Future<List<HouseholdMember>> _members = _loadMembers();
  var _busy = false;

  /// Set while leaving is being asked: a second tap opens no second dialog.
  var _asking = false;

  Future<List<HouseholdMember>> _loadMembers() =>
      context.read<InviteRepository>().members(widget.household.id);

  /// Runs a household call; a refusal is told in a snackbar.
  Future<bool> _run(Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      return await tellRefusal(context, call);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rename() =>
      renameHousehold(context, widget.household, run: _run);

  Future<void> _leave() async {
    if (_asking) {
      return;
    }
    _asking = true;
    try {
      await leaveHousehold(
        context,
        userId: widget.userId,
        household: widget.household,
        archiveOffered: widget.archiveOffered,
        run: _run,
        onMembers: (members) => setState(() {
          _members = Future.value(members);
        }),
      );
    } finally {
      _asking = false;
    }
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
            AsyncSnapshot(:final data?) => MemberTiles(
              userId: widget.userId,
              household: household,
              members: data,
              run: _run,
              enabled: !_busy,
              onChanged: () => setState(() {
                _members = _loadMembers();
              }),
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
        FocusRingTile(
          key: const ValueKey('household-invite'),
          child: ListTile(
            leading: const Icon(Icons.person_add_outlined),
            title: Text(l10n.inviteSheetTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(
              showInviteSheet(
                context,
                household,
                from: InviteContext.household,
              ),
            ),
          ),
        ),
        const ListsSection(),
        const CurrencySection(),
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
        DefaultListPicker(
          householdId: household.id,
          lists: context.select<ListCubit?, List<HouseholdList>>(
            (list) => list?.state.catalog.lists ?? const [],
          ),
          builder: (context, list, pick) => FocusRingTile(
            key: const ValueKey('household-default-list'),
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(l10n.defaultListTitle),
              subtitle: Text(
                list,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.expand_more),
              onTap: pick,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FocusRingTile(
          key: const ValueKey('household-leave'),
          child: ListTile(
            leading: const Icon(Icons.logout),
            iconColor: theme.colorScheme.error,
            textColor: theme.colorScheme.error,
            title: Text(l10n.leaveHousehold),
            enabled: !_busy,
            onTap: () => unawaited(_leave()),
          ),
        ),
      ],
    );
  }
}
