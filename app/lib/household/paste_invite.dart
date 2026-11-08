import 'dart:async';

import 'package:family_groceries/analytics/events.dart' show JoinMethod;
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// "Einladung einfügen" on the start screens (job 169b W2): for someone
/// who installed the app from a store after getting a join link, which the
/// store did not carry over. Reads the clipboard only on this tap, takes a
/// join link (also inside a whole shared message) or a bare code, keeps it
/// like an opened link ([PendingInvite], method `paste`) and opens the join
/// flow: signed out, sign-in comes first and keeps it. Nothing usable:
/// says so. With [waiting] (an invite is kept already) it says that
/// instead of offering the button.
///
/// One self-contained widget, so the welcome screen (job 168 rebuilds it)
/// only places it.
class const PasteInvite({final String? waiting, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (waiting != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          l10n.invitePasteWaiting,
          key: const ValueKey('invite-paste-waiting'),
          textAlign: TextAlign.center,
        ),
      );
    }
    return TextButton.icon(
      key: const ValueKey('invite-paste'),
      icon: const Icon(Icons.content_paste),
      label: Text(l10n.invitePaste),
      onPressed: () => unawaited(_paste(context)),
    );
  }

  static Future<void> _paste(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final pending = context.read<PendingInvite>();
    final router = GoRouter.of(context);
    final String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      notices.showSnackBar(SnackBar(content: Text(l10n.invitePasteNothing)));
      return;
    }
    final code = text == null ? null : inviteCodeIn(text);
    if (code == null) {
      notices.showSnackBar(
        SnackBar(
          key: const ValueKey('invite-paste-nothing'),
          content: Text(l10n.invitePasteNothing),
        ),
      );
      return;
    }
    pending.remember(code, via: JoinMethod.paste);
    router.go(joinPath(code));
  }
}
