import 'dart:async';

import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/pop_if_current.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/currency_section.dart';
import 'package:family_groceries/household/household_actions.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/household/join_approval_section.dart';
import 'package:family_groceries/household/lists_section.dart';
import 'package:family_groceries/household/member_tiles.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/switcher_sheet.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_holds.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/list_tabs.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// One household's pages of the switcher sheet (job 229): its lists
/// ([HouseholdListsPage]), its members ([MembersPage]) and "Leute
/// einladen" ([InvitePage], job 242). Holds the household's list
/// ([ListHolds]) and its invites while one of them shows, so going between
/// them reloads nothing.
class const SwitcherHousehold({
  required final String userId,
  required final Household household,

  /// It is the household the list shows.
  required final bool shown,

  /// One of this household's pages.
  required final HouseholdPage page,
  required final ValueChanged<SwitcherPage> go,
  super.key,
}) extends StatefulWidget {
  @override
  State<SwitcherHousehold> createState() => _SwitcherHouseholdState();
}

class _SwitcherHouseholdState() extends State<SwitcherHousehold> {
  late final ListHolds _holds = context.read<ListHolds>();
  late final ListCubit _list;
  late final _invites = InvitesCubit(
    context.read<InviteRepository>(),
    widget.household.id,
  );

  /// Another household's refused list changes (renaming offline): only the
  /// shown list's scope tells its own.
  StreamSubscription<Rejected>? _rejections;

  @override
  void initState() {
    super.initState();
    _list = _holds.hold(widget.household.id);
    if (!widget.shown) {
      _rejections = _list.rejections.listen((rejection) {
        if (mounted) {
          Notices.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  rejectionText(AppLocalizations.of(context), rejection),
                ),
                persist: false,
              ),
            );
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_rejections?.cancel());
    _holds.release(widget.household.id);
    unawaited(_invites.close());
    super.dispose();
  }

  @override
  void didUpdateWidget(SwitcherHousehold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The invite page has its own (InvitesScope): the open invites count
    // again once it goes.
    if (oldWidget.page is InvitePage && widget.page is! InvitePage) {
      unawaited(_invites.reload());
    }
  }

  /// Set while leaving is being asked: a second tap opens no second dialog.
  var _asking = false;

  Future<void> _leave() async {
    if (_asking) {
      return;
    }
    _asking = true;
    // SessionCubit.leave emits the state without the household before its
    // reload: this page fades out of the sheet meanwhile.
    final sheet = ModalRoute.of(context);
    try {
      final left = await leaveHousehold(
        context,
        userId: widget.userId,
        household: widget.household,
        archiveOffered: Environment.householdArchive,
        run: (call) => tellRefusal(context, call),
      );
      if (left) {
        popRouteIfCurrent(sheet);
      }
    } finally {
      _asking = false;
    }
  }

  void _invite() => widget.go(InvitePage(widget.household.id));

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: _list),
      BlocProvider.value(value: _invites),
    ],
    child: AnimatedSwitcher(
      duration: hlMotion(context, HlDuration.short),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: switch (widget.page) {
        MembersPage() => _MembersView(
          key: const ValueKey('switcher-members-page'),
          userId: widget.userId,
          household: widget.household,
          invite: _invite,
        ),
        InvitePage() => InviteSheet(
          key: const ValueKey('switcher-invite-page'),
          household: widget.household,
          origin: InviteContext.switcher,
        ),
        HouseholdListsPage() => _ListsView(
          key: const ValueKey('switcher-lists-page'),
          household: widget.household,
          leave: _leave,
          shown: widget.shown,
          go: widget.go,
          invite: _invite,
        ),
      },
    ),
  );
}

/// The household's page: its name with "Einladen", the members row, its
/// lists (long-press then drag orders them) and "Neue Liste". A tap on a
/// list shows it, in this household.
class const _ListsView({
  required final Household household,
  required final Future<void> Function() leave,
  required final bool shown,
  required final ValueChanged<SwitcherPage> go,
  required final VoidCallback invite,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final cubit = context.read<ListCubit>();
    final state = context.watch<ListCubit>().state;
    final openInvites = context.select<InvitesCubit, int>(
      (c) => c.state.people.length,
    );
    final lists = state.catalog.lists;
    final items = state.allItems;
    int open(HouseholdList list) => state
        .onList(items, list.id)
        .values
        .where((i) => i.status == ItemStatus.active)
        .length;
    final openAll = state.loaded
        ? items.values.where((i) => i.status == ItemStatus.active).length
        : household.openCount;
    final showing = shown ? state.shownList?.id : null;

    void pick(HouseholdList list) {
      final session = context.read<SessionCubit>();
      cubit.showList(list.id);
      Navigator.of(context).pop();
      unawaited(session.switchTo(household.id));
    }

    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverList.list(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                24,
                HlSpace.s2,
                HlSpace.s4,
                HlSpace.s2,
              ),
              child: Row(
                spacing: HlSpace.s3,
                children: [
                  Expanded(
                    child: Column(
                      key: const ValueKey('switcher-household-name'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            household.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          l10n.householdOpenItems(openAll),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: t.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('switcher-rename'),
                    tooltip: l10n.householdRenameTitle,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => unawaited(
                      renameHousehold(
                        context,
                        household,
                        run: (call) => tellRefusal(context, call),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('switcher-invite'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                    ),
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(l10n.switcherInvite),
                    onPressed: invite,
                  ),
                ],
              ),
            ),
            ListTile(
              key: const ValueKey('switcher-members'),
              leading: sheetHex(context, Icons.group_outlined, t.surfaceSunken),
              title: Text(
                [
                  l10n.householdMembers(household.memberCount),
                  if (openInvites > 0) l10n.switcherOpenInvites(openInvites),
                ].join(' · '),
              ),
              trailing: Icon(Icons.chevron_right, color: t.textMuted),
              onTap: () => go(MembersPage(household.id)),
            ),
            HlSectionLabel(l10n.listsTitle),
            if (!state.loaded)
              const Padding(
                padding: EdgeInsets.all(HlSpace.s4),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
        SliverReorderableList(
          itemCount: lists.length,
          proxyDecorator: liftedRow,
          onReorderItem: (from, to) =>
              unawaited(cubit.moveList(lists[from].id, to)),
          itemBuilder: (context, i) {
            final list = lists[i];
            final name = listName(list, l10n);
            final on = list.id == showing;
            return ReorderableRow(
              key: ValueKey(list.id),
              index: i,
              count: lists.length,
              move: (to) => unawaited(cubit.moveList(list.id, to)),
              child: ListTile(
                key: ValueKey('switcher-list-${list.id}'),
                minTileHeight: 56,
                leading: sheetHex(
                  context,
                  Icons.checklist,
                  on ? t.honeySoft : t.surfaceSunken,
                ),
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(l10n.householdOpenItems(open(list))),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (on)
                      Icon(
                        Icons.check,
                        key: const ValueKey('switcher-list-current'),
                        color: t.text,
                        semanticLabel: l10n.householdCurrent,
                      ),
                    PopupMenuButton<_ListAction>(
                      key: ValueKey('switcher-list-actions-${list.id}'),
                      tooltip: l10n.listActions(name),
                      useRootNavigator: true,
                      onSelected: (action) => unawaited(switch (action) {
                        _ListAction.rename => renameList(context, cubit, list),
                        _ListAction.delete => deleteList(
                          context,
                          cubit,
                          list,
                          open: open(list),
                        ),
                      }),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          key: const ValueKey('list-rename'),
                          value: _ListAction.rename,
                          child: Text(l10n.householdRename),
                        ),
                        if (lists.length > 1)
                          PopupMenuItem(
                            key: const ValueKey('list-delete'),
                            value: _ListAction.delete,
                            child: Text(l10n.delete),
                          ),
                      ],
                    ),
                  ],
                ),
                selected: on,
                onTap: () => pick(list),
              ),
            );
          },
        ),
        SliverList.list(
          children: [
            ListTile(
              key: const ValueKey('switcher-list-new'),
              leading: sheetHex(context, Icons.add, t.surfaceSunken),
              title: Text(l10n.listNew),
              onTap: () => unawaited(addList(context)),
            ),
            const CurrencySection(),
            JoinApprovalSection(household: household),
            const SizedBox(height: HlSpace.s3),
            ListTile(
              key: const ValueKey('switcher-leave'),
              leading: const Icon(Icons.logout),
              iconColor: theme.colorScheme.error,
              textColor: theme.colorScheme.error,
              title: Text(l10n.leaveHousehold),
              onTap: () => unawaited(leave()),
            ),
            const SizedBox(height: HlSpace.s3),
          ],
        ),
      ],
    );
  }
}

enum _ListAction() {
  rename,
  delete,
}

/// The members page: its members with what the user may do to them
/// ([MemberTiles]), "Leute einladen", and the open person invites, each
/// withdrawn with "Widerrufen".
class const _MembersView({
  required final String userId,
  required final Household household,
  required final VoidCallback invite,
  super.key,
}) extends StatefulWidget {
  @override
  State<_MembersView> createState() => _MembersViewState();
}

class _MembersViewState() extends State<_MembersView> {
  late Future<List<HouseholdMember>> _members = _load();
  var _busy = false;

  Future<List<HouseholdMember>> _load() =>
      context.read<InviteRepository>().members(widget.household.id);

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final invites = context.watch<InvitesCubit>();
    final household = widget.household;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: HlSpace.s3),
      children: [
        HouseholdSheetTitle(l10n.householdMembersTitle),
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
                _members = _load();
              }),
            ),
            AsyncSnapshot(hasError: true) => ListTile(
              key: const ValueKey('household-members-failed'),
              title: Text(l10n.householdMembersFailed),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(HlSpace.s4),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ),
        ListTile(
          key: const ValueKey('switcher-members-invite'),
          leading: sheetHex(
            context,
            Icons.person_add_outlined,
            t.surfaceSunken,
          ),
          title: Text(l10n.inviteSheetTitle),
          trailing: Icon(Icons.chevron_right, color: t.textMuted),
          onTap: widget.invite,
        ),
        if (invites.state.people case final people when people.isNotEmpty) ...[
          HlSectionLabel(l10n.switcherOpenInvitesTitle),
          for (final invite in people)
            ListTile(
              key: ValueKey('switcher-open-invite-${invite.id}'),
              leading: sheetHex(context, Icons.mail_outline, t.surfaceSunken),
              title: Text('${l10n.inviteCodeLabel} ${invite.code}'),
              subtitle: Text(
                l10n.inviteValidUntil(
                  invite.expiresAt.toLocal(),
                  invite.expiresAt.toLocal(),
                ),
              ),
              trailing: TextButton(
                key: ValueKey('switcher-invite-revoke-${invite.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: invites.state.busy
                    ? null
                    : () => unawaited(invites.revoke(invite)),
                child: Semantics(
                  label: l10n.inviteRevokeLabel(invite.code),
                  excludeSemantics: true,
                  child: Text(l10n.inviteRevoke),
                ),
              ),
            ),
        ],
        if (invites.state.problem case final problem?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ProblemText(
              householdProblemText(l10n, problem),
              key: const ValueKey('switcher-invites-problem'),
            ),
          ),
      ],
    );
  }
}
