import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tells the user when an owner or admin decided on their join request
/// (job 169b W3 M): "Du bist jetzt in „Sommerfest“." (the session shows it
/// already) or that it was not accepted. Goes around the app's pages, under
/// [NoticesHost].
class const JoinDecisionNotices({required final Widget child, super.key})
    extends StatefulWidget {
  /// Long enough to read; nothing to undo.
  static const duration = Duration(seconds: 8);

  @override
  State<JoinDecisionNotices> createState() => _JoinDecisionNoticesState();
}

class _JoinDecisionNoticesState() extends State<JoinDecisionNotices> {
  late final StreamSubscription<JoinDecision> _decisions;

  @override
  void initState() {
    super.initState();
    _decisions = context.read<SessionCubit>().joinDecisions.listen(_tell);
  }

  void _tell(JoinDecision decision) {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    Notices.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: ValueKey(
          decision.approved ? 'join-request-approved' : 'join-request-declined',
        ),
        duration: JoinDecisionNotices.duration,
        content: Text(
          decision.approved
              ? l10n.joinApprovedNotice(decision.household)
              : l10n.joinDeclinedNotice(decision.household),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_decisions.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
