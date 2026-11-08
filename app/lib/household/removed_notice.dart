import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tells the user when someone removed them from a household (job 169b
/// W2): "Du bist nicht mehr Mitglied von „Zuhause“." The session already
/// shows another household, or onboarding without one. Goes around the
/// app's pages, under [NoticesHost].
class const RemovedNotices({required final Widget child, super.key})
    extends StatefulWidget {
  /// Long enough to read; nothing to undo.
  static const duration = Duration(seconds: 8);

  @override
  State<RemovedNotices> createState() => _RemovedNoticesState();
}

class _RemovedNoticesState() extends State<RemovedNotices> {
  late final StreamSubscription<Household> _removals;

  @override
  void initState() {
    super.initState();
    _removals = context.read<SessionCubit>().removals.listen(_tell);
  }

  void _tell(Household household) {
    if (!mounted) {
      return;
    }
    Notices.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: const ValueKey('household-removed'),
        duration: RemovedNotices.duration,
        content: Text(
          AppLocalizations.of(context).householdRemovedNotice(household.name),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_removals.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
