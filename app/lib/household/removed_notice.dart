import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tells the user when they are no longer in a household (job 169b W2):
/// removed in the last 30 days, that old invites won't bring them back
/// for 30 days (Legal N-114); else only that they are no longer a member.
/// The session already shows another household, or onboarding without
/// one. Goes around the app's pages, under [NoticesHost].
class const RemovedNotices({required final Widget child, super.key})
    extends StatefulWidget {
  /// Long enough to read three sentences; nothing to undo.
  static const duration = Duration(seconds: 15);

  /// Long enough to read one sentence.
  static const goneDuration = Duration(seconds: 8);

  @override
  State<RemovedNotices> createState() => _RemovedNoticesState();
}

class _RemovedNoticesState() extends State<RemovedNotices> {
  late final StreamSubscription<LostHousehold> _lost;

  @override
  void initState() {
    super.initState();
    _lost = context.read<SessionCubit>().lostHouseholds.listen(_tell);
  }

  void _tell(LostHousehold lost) {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    Notices.maybeOf(context)?.showSnackBar(
      lost.removed
          ? SnackBar(
              key: const ValueKey('household-removed'),
              duration: RemovedNotices.duration,
              content: Text(l10n.householdRemovedNotice(lost.name)),
            )
          : SnackBar(
              key: const ValueKey('household-gone'),
              duration: RemovedNotices.goneDuration,
              content: Text(l10n.householdGoneNotice(lost.name)),
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_lost.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
