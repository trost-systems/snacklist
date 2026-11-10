import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/web_share.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

/// Where an invite was handed out, for `invite_sent`'s `context`.
enum InviteContext() {
  /// Step 3, right after creating the household.
  onboarding,

  /// More's Einladungen.
  settings,

  /// The invite sheet from a household's row in the switcher (job 169b).
  switcher,

  /// The invite sheet from the household page (job 169b).
  household,
}

/// How an invite was handed out, for `invite_sent`'s `channel`.
enum InviteChannel(final String wire) {
  shareSheet('share_sheet'),
  copyLink('copy_link'),
  copyCode('copy_code'),
}

/// The share sheet (iOS, Android, Web Share) and the clipboard. Tests pass
/// their own.
abstract interface class InviteSharer() {
  /// Whether [share] opens a system sheet here; otherwise the invite offers
  /// copying only.
  bool get canShare;

  Future<void> share(String text, {Rect? origin});

  Future<void> copy(String text);
}

class PlatformInviteSharer() implements InviteSharer {
  @override
  bool get canShare => shareSheetAvailable();

  @override
  Future<void> share(String text, {Rect? origin}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          // iPad anchors the share popover here.
          sharePositionOrigin: origin,
          // No mailto: link where there is no sheet; the card offers copying.
          mailToFallbackEnabled: false,
        ),
      );
    } on Object {
      // No sheet after all (the web asks for a fresh tap): the card with
      // the code, the link and the copy buttons stays on screen.
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// The link of invite [code]: the page's origin on the web, APP_URL in the
/// apps (https://app.snacklist.app, which opens the installed app through
/// universal links and App Links). Null in a build without APP_URL.
String? inviteLink(String code) {
  final base = kIsWeb ? webRoot : Environment.appUrl;
  return base.isEmpty ? null : '$base${joinPath(code)}';
}

/// What the share sheet sends, in the app's language, worded for who
/// shops in [household] (its kind): the link and the code, which can be
/// typed after installing the app. The user sends it; Snacklist never does
/// (N-18).
String inviteShareText(
  AppLocalizations l10n,
  String code,
  Household household,
) => switch (inviteLink(code)) {
  final link? => l10n.inviteShareKind(
    household.kind?.name ?? 'other',
    household.name,
    link,
    code,
  ),
  null => l10n.inviteShareTextCodeOnly(code),
};

/// What anyone with an invite link sees on the public join page (Legal
/// N-112): plain muted text beside the controls that make or share one,
/// never inside a pill or button.
class const InviteJoinPageHint({
  final TextAlign textAlign = TextAlign.start,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).inviteJoinPageHint,
      key: const ValueKey('invite-join-page-hint'),
      textAlign: textAlign,
      style: theme.textTheme.bodySmall?.copyWith(
        color: SnacklistColors.of(theme.brightness).textMuted,
      ),
    );
  }
}

/// One invite: its code and link, how long it is valid, and the ways to
/// hand it out. Each way is one `invite_sent`; the code and the link never
/// go to analytics.
class const InviteCard({
  required final Invite invite,
  required final Household household,
  required final InviteContext origin,

  /// More's Einladungen: revoke this invite.
  final VoidCallback? onRevoke,

  /// Accepted while the screen is open (job 168b): who joined, empty when
  /// they have no name; null while open.
  final String? joinedBy,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sharer = context.read<InviteSharer>();
    final link = inviteLink(invite.code);
    final until = invite.expiresAt.toLocal();
    return Card.outlined(
      key: ValueKey('invite-${invite.code}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One node "Code ABCD2345" for screen readers (and e2e).
            Semantics(
              container: true,
              label: '${l10n.inviteCodeLabel} ${invite.code}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.inviteCodeLabel, style: theme.textTheme.labelLarge),
                  Text(
                    invite.code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
            // Own nodes, so screen readers (and the web's DOM) read each
            // line instead of one label for the whole card.
            if (link != null) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.inviteLinkLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(link, key: const ValueKey('invite-link')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Semantics(
              container: true,
              child: Text(
                l10n.inviteValidUntil(until, until),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            if (joinedBy case final name?)
              Semantics(
                key: const ValueKey('invite-joined'),
                container: true,
                liveRegion: true,
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    Expanded(
                      child: Text(
                        name.trim().isEmpty
                            ? l10n.inviteJoined
                            : l10n.inviteJoinedName(name.trim()),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (sharer.canShare)
                    Builder(
                      builder: (button) => FilledButton.icon(
                        key: const ValueKey('invite-share'),
                        icon: const Icon(Icons.ios_share),
                        label: Text(l10n.share),
                        onPressed: () => unawaited(
                          shareInvite(button, invite, household, origin),
                        ),
                      ),
                    ),
                  if (link != null)
                    OutlinedButton.icon(
                      key: const ValueKey('invite-copy-link'),
                      icon: const Icon(Icons.link),
                      label: Text(l10n.copyLink),
                      onPressed: () => unawaited(
                        _copy(context, link, InviteChannel.copyLink),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('invite-copy-code'),
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.copyCode),
                    onPressed: () => unawaited(
                      _copy(context, invite.code, InviteChannel.copyCode),
                    ),
                  ),
                  if (onRevoke != null)
                    TextButton.icon(
                      key: const ValueKey('invite-revoke'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.block),
                      label: Semantics(
                        label: l10n.inviteRevokeLabel(invite.code),
                        excludeSemantics: true,
                        child: Text(l10n.inviteRevoke),
                      ),
                      onPressed: onRevoke,
                    ),
                ],
              ),
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
    final messenger = Notices.of(context);
    trackInviteSent(context.read<Analytics>(), channel, origin, invite.kind);
    await context.read<InviteSharer>().copy(text);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          channel == InviteChannel.copyLink ? l10n.linkCopied : l10n.codeCopied,
        ),
      ),
    );
  }
}

/// Opens the share sheet with [invite]'s text for [household], anchored at
/// [button] (the iPad's popover), and counts it once.
Future<void> shareInvite(
  BuildContext button,
  Invite invite,
  Household household,
  InviteContext origin,
) async {
  final sharer = button.read<InviteSharer>();
  final text = inviteShareText(
    AppLocalizations.of(button),
    invite.code,
    household,
  );
  final box = button.findRenderObject() as RenderBox?;
  trackInviteSent(
    button.read<Analytics>(),
    InviteChannel.shareSheet,
    origin,
    invite.kind,
  );
  await sharer.share(
    text,
    origin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  );
}

void trackInviteSent(
  Analytics analytics,
  InviteChannel channel,
  InviteContext origin,
  InviteKind kind,
) => analytics.track('invite_sent', {
  'channel': channel.wire,
  'context': origin.name,
  'kind': kind.name,
});
