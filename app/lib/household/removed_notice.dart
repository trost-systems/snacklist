import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Tells the user when they are no longer in a household (job 169b W2):
/// removed in the last 30 days, that old invites won't bring them back
/// for 30 days (Legal N-114); else only that they are no longer a member.
/// The session already shows another household, or onboarding without
/// one. Held while a gate is on top, such as the analytics consent asked
/// right after sign-in, and told once [router] is [atHome]. Goes around the
/// app's pages, under [NoticesHost].
class const RemovedNotices({
  required final GoRouter router,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Long enough to read three sentences; nothing to undo.
  static const duration = Duration(seconds: 15);

  /// Long enough to read one sentence.
  static const goneDuration = Duration(seconds: 8);

  @override
  State<RemovedNotices> createState() => _RemovedNoticesState();
}

class _RemovedNoticesState() extends State<RemovedNotices> {
  late final StreamSubscription<LostHousehold> _lost;

  /// Found while a gate was on top, oldest first.
  final _held = <LostHousehold>[];

  @override
  void initState() {
    super.initState();
    _lost = context.read<SessionCubit>().lostHouseholds.listen((lost) {
      _held.add(lost);
      _tellLater();
    });
    widget.router.routerDelegate.addListener(_tellLater);
  }

  @override
  void didUpdateWidget(RemovedNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_tellLater);
      widget.router.routerDelegate.addListener(_tellLater);
    }
  }

  /// At once, or after the frame when one is being built: the router
  /// notifies while it builds the next page.
  void _tellLater() {
    if (_held.isEmpty) {
      return;
    }
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      _tell();
    } else {
      binding.addPostFrameCallback((_) => _tell());
    }
  }

  void _tell() {
    final location = widget.router.routerDelegate.currentConfiguration;
    final notices = mounted ? Notices.maybeOf(context) : null;
    if (_held.isEmpty ||
        notices == null ||
        location.isEmpty ||
        !atHome(location.uri)) {
      return;
    }
    final session = context.read<SessionCubit>();
    final userId = switch (session.state) {
      InHousehold(:final userId) || NeedsHousehold(:final userId) => userId,
      _ => null,
    };
    final l10n = AppLocalizations.of(context);
    // Another user's, from before a sign-out, are not this one's to see.
    final told = [
      for (final lost in _held)
        if (lost.userId == userId) lost,
    ];
    _held.clear();
    for (final lost in told) {
      notices.showSnackBar(
        lost.removal == null
            ? SnackBar(
                key: const ValueKey('household-gone'),
                duration: RemovedNotices.goneDuration,
                content: Text(l10n.householdGoneNotice(lost.name)),
              )
            : SnackBar(
                key: const ValueKey('household-removed'),
                duration: RemovedNotices.duration,
                content: Text(l10n.householdRemovedNotice(lost.name)),
              ),
      );
    }
    if (userId != null) {
      unawaited(
        session.removalsTold(userId, [for (final l in told) ?l.removal]),
      );
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_tellLater);
    unawaited(_lost.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
