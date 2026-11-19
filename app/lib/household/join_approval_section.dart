import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/count_badge.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The household page's join approval (job 169b W3 M), for the owner and
/// admins only: the switch "Beitritte bestätigen" with one line under it,
/// and the join requests waiting, each with Aufnehmen and Ablehnen, their
/// count beside the title. Realtime brings new requests and takes the ones
/// another admin decided. [onApproved] hears each approval (a new member).
class const JoinApprovalSection({
  required final Household household,
  final VoidCallback? onApproved,
  super.key,
}) extends StatefulWidget {
  @override
  State<JoinApprovalSection> createState() => _JoinApprovalSectionState();
}

/// A request row's buttons: under the page's 48 dp, still a target with
/// the row's padding.
const _rowButton = 40.0;

class _JoinApprovalSectionState() extends State<JoinApprovalSection> {
  late final _invites = context.read<InviteRepository>();
  Future<void> Function()? _unwatch;
  List<PendingJoin>? _requests;
  var _failed = false;

  /// The switch's value while the server has not confirmed it.
  bool? _turning;

  /// Requests being decided.
  final _deciding = <String>{};

  /// Requests whose invite had no use left when approved: they wait for a
  /// new link.
  final _full = <String>{};

  bool get _manages => widget.household.role.manages;

  @override
  void initState() {
    super.initState();
    if (_manages) {
      unawaited(_load());
      _unwatch = _invites.watchJoinRequests(
        widget.household.id,
        () => unawaited(_load()),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_unwatch?.call());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final requests = await _invites.joinRequests(widget.household.id);
      if (mounted) {
        setState(() {
          _requests = requests;
          _failed = false;
        });
      }
    } on HouseholdError {
      if (mounted) {
        setState(() => _failed = _requests == null);
      }
    }
  }

  void _tell(HouseholdProblem problem) => Notices.of(context).showSnackBar(
    SnackBar(
      content: Text(
        householdProblemText(AppLocalizations.of(context), problem),
      ),
    ),
  );

  Future<void> _turn(bool on) async {
    final session = context.read<SessionCubit>();
    setState(() => _turning = on);
    try {
      await _invites.setJoinApproval(widget.household.id, on: on);
      await householdCall(session.refresh);
    } on HouseholdError catch (e) {
      if (mounted) {
        _tell(e.problem);
      }
    } finally {
      if (mounted) {
        setState(() => _turning = null);
      }
    }
  }

  Future<void> _decide(PendingJoin request, {required bool approve}) async {
    final session = context.read<SessionCubit>();
    final analytics = context.read<Analytics>();
    final view = View.of(context);
    final direction = Directionality.of(context);
    final full = AppLocalizations.of(context).joinRequestInviteFull;
    setState(() => _deciding.add(request.id));
    try {
      final decision = await _invites.decideJoinRequest(
        request.id,
        approve: approve,
      );
      if (decision == JoinRequestOutcome.inviteFull) {
        _full.add(request.id);
        unawaited(SemanticsService.sendAnnouncement(view, full, direction));
      } else {
        _full.remove(request.id);
      }
      if (decision
          case JoinRequestOutcome.approved || JoinRequestOutcome.declined) {
        analytics.track('join_request_decided', {'approved': approve});
      }
      if (decision == JoinRequestOutcome.approved) {
        widget.onApproved?.call();
        // The household's member count in the switcher.
        unawaited(session.refresh().catchError((Object _) {}));
      }
    } on HouseholdError catch (e) {
      if (mounted) {
        _tell(e.problem);
      }
    }
    await _load();
    if (mounted) {
      setState(() => _deciding.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_manages) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final requests = _requests;
    final on = _turning ?? widget.household.joinApproval;
    return Column(
      key: const ValueKey('join-approval'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(
          l10n.joinRequestsTitle,
          badge: switch (requests?.length) {
            final int n when n > 0 => HlCountBadge(
              n,
              key: const ValueKey('join-requests-count'),
              label: l10n.joinRequestsCount(n),
            ),
            _ => null,
          },
        ),
        HexSwitchTile(
          key: const ValueKey('join-approval-switch'),
          title: Text(l10n.joinApprovalToggle),
          value: on,
          onChanged: _turning == null ? (on) => unawaited(_turn(on)) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HlSpace.s4,
            0,
            HlSpace.s4,
            HlSpace.s2,
          ),
          child: Semantics(
            container: true,
            child: Text(
              l10n.joinApprovalHint,
              style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
            ),
          ),
        ),
        if (_failed)
          ListTile(
            key: const ValueKey('join-requests-failed'),
            title: Text(l10n.joinRequestsFailed),
          )
        else if (requests != null && requests.isEmpty && on)
          ListTile(
            key: const ValueKey('join-requests-none'),
            leading: const Icon(Icons.inbox_outlined),
            title: Text(
              l10n.joinRequestsNone,
              style: TextStyle(color: t.textMuted),
            ),
          )
        else if (requests != null)
          for (final request in requests) _row(l10n, request),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, PendingJoin request) {
    final busy = _deciding.contains(request.id);
    return ListTile(
      key: ValueKey('join-request-${request.id}'),
      horizontalTitleGap: HlSpace.s3,
      leading: const Icon(Icons.person_outline),
      title: Text(
        request.displayName.isEmpty
            ? l10n.householdMemberUnnamed
            : request.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _full.contains(request.id)
          ? Text(
              l10n.joinRequestInviteFull,
              key: ValueKey('join-request-full-${request.id}'),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: HlSpace.s1,
        children: [
          TextButton(
            key: ValueKey('join-request-decline-${request.id}'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, _rowButton),
              padding: const EdgeInsets.symmetric(horizontal: HlSpace.s2),
            ),
            onPressed: busy
                ? null
                : () => unawaited(_decide(request, approve: false)),
            child: Text(l10n.joinRequestDecline),
          ),
          FilledButton(
            key: ValueKey('join-request-approve-${request.id}'),
            // A row's action, not the page's: the name keeps its room.
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, _rowButton),
              padding: const EdgeInsets.symmetric(
                horizontal: HlHex.tip * _rowButton + HlSpace.s2,
              ),
            ),
            onPressed: busy
                ? null
                : () => unawaited(_decide(request, approve: true)),
            child: Text(l10n.joinRequestApprove),
          ),
        ],
      ),
    );
  }
}
