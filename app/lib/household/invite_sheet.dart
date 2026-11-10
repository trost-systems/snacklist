import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr/qr.dart';

// The invite loop's building blocks (job 169b W2, docs/households/W2.md).
// The invite sheet is [InvitesScope] around [InvitePanel]; More's
// Einladungen puts the same two in a page. Onboarding (job 168) can take
// them one by one: [InvitesScope] holds the household's invites,
// [PersonInviteSection] makes and lists person invites, [GroupLinkSection]
// the group link with its QR code ([InviteQr]) and [InviteJoinsList] who
// joined with it. Each section reads the [InvitesCubit] above it.

/// Opens "Leute einladen" for [household] (one of the user's, not
/// necessarily the one shown) from [from], on the root navigator.
Future<void> showInviteSheet(
  BuildContext context,
  Household household, {
  required InviteContext from,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  showDragHandle: true,
  builder: (_) => InviteSheet(household: household, origin: from),
);

/// The invite sheet's content: its title, the household's name and
/// [InvitePanel].
class const InviteSheet({
  required final Household household,
  required final InviteContext origin,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    return SafeArea(
      child: InvitesScope(
        household: household,
        child: ListView(
          key: const ValueKey('invite-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            HlSpace.s5,
            0,
            HlSpace.s5,
            HlSpace.s5,
          ),
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.inviteSheetTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: HlSpace.s1),
            Text(
              household.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted),
            ),
            InvitePanel(household: household, origin: origin),
          ],
        ),
      ),
    );
  }
}

/// Holds [household]'s invites for the widgets below ([InvitesCubit]):
/// loads them and polls uses and who joined while it is on screen and the
/// app is in the front. A tab switch keeps the More branch mounted but
/// turns its tickers off, so [TickerMode] says whether it is shown.
class const InvitesScope({
  required final Household household,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  @override
  State<InvitesScope> createState() => _InvitesScopeState();
}

class _InvitesScopeState() extends State<InvitesScope> {
  late final _cubit = InvitesCubit(
    context.read<InviteRepository>(),
    widget.household.id,
  );
  late final AppLifecycleListener _lifecycle;
  var _shown = false;
  var _inFront = _visible(WidgetsBinding.instance.lifecycleState);

  /// Inactive still shows the app (a blurred browser window, a call
  /// banner); hidden and paused don't.
  static bool _visible(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _inFront = _visible(state);
        _poll();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _poll();
  }

  void _poll() {
    if (_shown && _inFront) {
      _cubit.startPolling();
    } else {
      _cubit.stopPolling();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _cubit, child: widget.child);
}

/// Everything the invite sheet offers for [household]: that Premium covers
/// everyone (moment 5), what the join page shows, a person invite (any
/// member), and the group link with who joined (owner and admins).
class const InvitePanel({
  required final Household household,
  required final InviteContext origin,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = context.select<InvitesCubit, HouseholdProblem?>(
      (c) => c.state.problem,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (household.premium) ...[
          const SizedBox(height: HlSpace.s4),
          const _PremiumNote(),
        ],
        const SizedBox(height: HlSpace.s3),
        const InviteJoinPageHint(),
        PersonInviteSection(household: household, origin: origin),
        if (household.role.manages) ...[
          GroupLinkSection(household: household, origin: origin),
          const InviteJoinsList(),
        ],
        if (problem != null)
          ProblemText(
            householdProblemText(l10n, problem),
            key: const ValueKey('invites-problem'),
          ),
      ],
    );
  }
}

/// Section labels inside the panel: flush with its text.
const _labelPadding = EdgeInsets.fromLTRB(0, HlSpace.s5, 0, HlSpace.s2);

/// "Premium gilt für alle im Haushalt.": one mint line, so the inviter can
/// say it.
class const _PremiumNote() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    return DecoratedBox(
      key: const ValueKey('invite-premium'),
      decoration: BoxDecoration(
        color: t.mintSoft,
        borderRadius: const BorderRadius.all(Radius.circular(HlRadius.s)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HlSpace.s3),
        child: Row(
          spacing: HlSpace.s3,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 20, color: t.text),
            Expanded(
              child: Text(
                AppLocalizations.of(context).invitePremiumShared,
                style: theme.textTheme.bodyMedium?.copyWith(color: t.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A person invite: "Neue Einladung" makes one (the apps open the share
/// sheet at once), and each open one shows as an [InviteCard] to share,
/// copy or revoke.
class const PersonInviteSection({
  required final Household household,
  required final InviteContext origin,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<InvitesCubit>().state;
    final cubit = context.read<InvitesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(l10n.invitePersonTitle, padding: _labelPadding),
        Text(l10n.invitePersonBody),
        const SizedBox(height: HlSpace.s3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const ValueKey('invite-new'),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(l10n.newInvite),
            onPressed: state.busy
                ? null
                : () => unawaited(_create(context, household, origin)),
          ),
        ),
        if (state.invites == null)
          const Padding(
            padding: EdgeInsets.all(HlSpace.s4),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final invite in state.people) ...[
            const SizedBox(height: HlSpace.s3),
            InviteCard(
              invite: invite,
              household: household,
              origin: origin,
              onRevoke: state.busy
                  ? null
                  : () => unawaited(cubit.revoke(invite)),
            ),
          ],
      ],
    );
  }

  /// The apps open the share sheet once the invite exists; the web waits
  /// for a tap on Teilen (Web Share needs a fresh tap).
  static Future<void> _create(
    BuildContext section,
    Household household,
    InviteContext origin,
  ) async {
    final invite = await section.read<InvitesCubit>().create();
    if (invite != null &&
        !kIsWeb &&
        section.mounted &&
        section.read<InviteSharer>().canShare) {
      await shareInvite(section, invite, household, origin);
    }
  }
}

/// The group link (owner and admins): made on a tap; then its QR code, how
/// many joined of how many, until when, share and copy, "Neuen Link
/// erstellen" and "Link widerrufen" (both confirmed). A full link offers a
/// new one; a revoked one says so.
class const GroupLinkSection({
  required final Household household,
  required final InviteContext origin,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<InvitesCubit>().state;
    final cubit = context.read<InvitesCubit>();
    final busy = state.busy || state.invites == null;
    // Beside the active link a quiet text button; for a full or revoked
    // one the way on.
    Widget renew({required bool confirm}) {
      void onPressed() => unawaited(_renew(context, cubit, confirm: confirm));
      const key = ValueKey('invite-group-renew');
      const icon = Icon(Icons.refresh);
      final label = Text(l10n.inviteGroupRenew);
      return confirm
          ? TextButton.icon(
              key: key,
              icon: icon,
              label: label,
              onPressed: busy ? null : onPressed,
            )
          : OutlinedButton.icon(
              key: key,
              icon: icon,
              label: label,
              onPressed: busy ? null : onPressed,
            );
    }

    return Column(
      key: const ValueKey('invite-group'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(l10n.inviteGroupTitle, padding: _labelPadding),
        Text(l10n.inviteGroupBody),
        const SizedBox(height: HlSpace.s3),
        ...switch (state.group) {
          GroupLinkNone() => [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const ValueKey('invite-group-create'),
                icon: const Icon(Icons.qr_code_2),
                label: Text(l10n.inviteGroupCreate),
                onPressed: busy
                    ? null
                    : () => unawaited(cubit.create(kind: InviteKind.group)),
              ),
            ),
          ],
          GroupLinkActive(:final invite) => [
            _GroupLinkCard(
              invite: invite,
              household: household,
              origin: origin,
            ),
            const SizedBox(height: HlSpace.s3),
            Wrap(
              spacing: HlSpace.s2,
              runSpacing: HlSpace.s2,
              children: [
                renew(confirm: true),
                TextButton.icon(
                  key: const ValueKey('invite-group-revoke'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.block),
                  label: Text(l10n.inviteGroupRevoke),
                  onPressed: busy
                      ? null
                      : () => unawaited(_revoke(context, cubit, invite)),
                ),
              ],
            ),
          ],
          GroupLinkFull(:final invite) => [
            _GroupLinkCard(
              invite: invite,
              household: household,
              origin: origin,
            ),
            const SizedBox(height: HlSpace.s3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: renew(confirm: false),
            ),
          ],
          GroupLinkRevoked() => [
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.inviteGroupRevoked,
                key: const ValueKey('invite-group-revoked'),
              ),
            ),
            const SizedBox(height: HlSpace.s3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: renew(confirm: false),
            ),
          ],
        },
      ],
    );
  }

  static Future<void> _revoke(
    BuildContext context,
    InvitesCubit cubit,
    Invite invite,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (await _confirm(
      context,
      key: 'invite-group-revoke-dialog',
      title: l10n.inviteGroupRevokeTitle,
      body: l10n.inviteGroupRevokeBody,
      action: l10n.inviteGroupRevokeConfirm,
      danger: true,
    )) {
      await cubit.revoke(invite);
    }
  }

  static Future<void> _renew(
    BuildContext context,
    InvitesCubit cubit, {
    required bool confirm,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (!confirm ||
        await _confirm(
          context,
          key: 'invite-group-renew-dialog',
          title: l10n.inviteGroupRenewTitle,
          body: l10n.inviteGroupRenewBody,
          action: l10n.inviteGroupRenew,
          danger: false,
        )) {
      await cubit.renewGroup();
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String key,
    required String title,
    required String body,
    required String action,
    required bool danger,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: ValueKey(key),
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(AppLocalizations.of(dialog).cancel),
            ),
            FilledButton(
              key: ValueKey('$key-confirm'),
              style: danger ? dangerButtonStyle(dialog) : null,
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

/// The group link on a sticker: its QR code beside how many joined, until
/// when, and its code; under it the ways to hand it out.
class const _GroupLinkCard({
  required final Invite invite,
  required final Household household,
  required final InviteContext origin,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final sharer = context.read<InviteSharer>();
    final link = inviteLink(invite.code);
    final until = invite.expiresAt.toLocal();
    return HlSticker(
      key: ValueKey('invite-group-${invite.code}'),
      child: Padding(
        padding: const EdgeInsets.all(HlSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s4,
              children: [
                // Without APP_URL (a local build) the code stands in.
                InviteQr(
                  link ?? invite.code,
                  semanticLabel: l10n.inviteGroupQr,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.inviteGroupUses(invite.useCount, invite.maxUses),
                        key: const ValueKey('invite-group-uses'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: HlSpace.s1),
                      Text(
                        invite.full
                            ? l10n.inviteGroupFull
                            : l10n.inviteValidUntil(until, until),
                        key: invite.full
                            ? const ValueKey('invite-group-full')
                            : null,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: invite.full ? t.text : t.textMuted,
                        ),
                      ),
                      const SizedBox(height: HlSpace.s3),
                      Semantics(
                        container: true,
                        label: '${l10n.inviteCodeLabel} ${invite.code}',
                        excludeSemantics: true,
                        child: Text(
                          invite.code,
                          style: theme.textTheme.titleMedium?.copyWith(
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!invite.full) ...[
              const SizedBox(height: HlSpace.s4),
              // Full width and stacked: side by side, "Link kopieren" and
              // "Code kopieren" wrapped to two rows of different widths.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: HlSpace.s2,
                children: [
                  if (sharer.canShare)
                    Builder(
                      builder: (button) => FilledButton.icon(
                        key: const ValueKey('invite-group-share'),
                        icon: const Icon(Icons.ios_share),
                        label: Text(l10n.share),
                        onPressed: () => unawaited(
                          shareInvite(button, invite, household, origin),
                        ),
                      ),
                    ),
                  if (link != null)
                    OutlinedButton.icon(
                      key: const ValueKey('invite-group-copy-link'),
                      icon: const Icon(Icons.link),
                      label: Text(l10n.copyLink),
                      onPressed: () => unawaited(
                        _copy(context, link, InviteChannel.copyLink),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('invite-group-copy-code'),
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.copyCode),
                    onPressed: () => unawaited(
                      _copy(context, invite.code, InviteChannel.copyCode),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    String text,
    InviteChannel channel,
  ) async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    trackInviteSent(context.read<Analytics>(), channel, origin, invite.kind);
    await context.read<InviteSharer>().copy(text);
    notices.showSnackBar(
      SnackBar(
        content: Text(
          channel == InviteChannel.copyLink ? l10n.linkCopied : l10n.codeCopied,
        ),
      ),
    );
  }
}

/// [data] as a QR code, [size] square: navy modules on a white plate with
/// the four-module quiet zone, in dark mode too (scanners need the
/// contrast).
class const InviteQr(
  final String data, {
  required final String semanticLabel,
  final double size = 112,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: semanticLabel,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(HlRadius.s)),
      ),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          key: const ValueKey('invite-qr'),
          painter: _QrPainter(
            QrImage(QrCode(payload: QrPayload.fromString(data))),
            SnacklistColors.of(Brightness.light).text,
          ),
        ),
      ),
    ),
  );
}

class _QrPainter(final QrImage _image, final Color _color)
    extends CustomPainter {
  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = _image.moduleCount;
    final module = size.shortestSide / (count + 2 * _quiet);
    final paint = Paint()
      ..color = _color
      ..isAntiAlias = false;
    final path = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (_image.isDark(row, col)) {
          path.addRect(
            Rect.fromLTWH(
              (col + _quiet) * module,
              (row + _quiet) * module,
              // A hair over, so neighbours meet without seams.
              module + 0.5,
              module + 0.5,
            ),
          );
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old._image != _image || old._color != _color;
}

/// "Wer ist beigetreten": who joined with the group link shown, with the
/// day; nothing while there is no group link.
class const InviteJoinsList({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final state = context.watch<InvitesCubit>().state;
    if (state.group is GroupLinkNone) {
      return const SizedBox.shrink();
    }
    final joins = state.joins;
    return Column(
      key: const ValueKey('invite-joins'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(l10n.inviteJoinsTitle, padding: _labelPadding),
        if (joins == null)
          const SizedBox.shrink()
        else if (joins.isEmpty)
          Text(
            l10n.inviteJoinsEmpty,
            key: const ValueKey('invite-joins-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted),
          )
        else
          for (final join in joins)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HlSpace.s2),
              child: Row(
                spacing: HlSpace.s3,
                children: [
                  Icon(Icons.person_outline, size: 20, color: t.textMuted),
                  Expanded(
                    child: Text(
                      join.displayName.isEmpty
                          ? l10n.householdMemberUnnamed
                          : join.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l10n.inviteJoinedOn(join.joinedAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
