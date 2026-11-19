import 'dart:async';

import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Tells the user when an owner or admin decided on their join request
/// (job 169b W3 M): "Du bist jetzt in „Sommerfest“." (the session shows it
/// already) or that it was not accepted. Held like the removal notices while a
/// gate such as the analytics consent is on top, so it never covers its
/// buttons, and told once [router] is [atHome]. Goes around the app's
/// pages, under [NoticesHost].
class const JoinDecisionNotices({
  required final GoRouter router,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Long enough to read; nothing to undo.
  static const duration = Duration(seconds: 8);

  @override
  State<JoinDecisionNotices> createState() => _JoinDecisionNoticesState();
}

class _JoinDecisionNoticesState() extends State<JoinDecisionNotices> {
  late final StreamSubscription<JoinDecision> _decisions;

  /// Decided while a gate was on top, oldest first.
  final _held = <JoinDecision>[];

  @override
  void initState() {
    super.initState();
    _decisions = context.read<SessionCubit>().joinDecisions.listen((d) {
      _held.add(d);
      _tellLater();
    });
    widget.router.routerDelegate.addListener(_tellLater);
  }

  @override
  void didUpdateWidget(JoinDecisionNotices oldWidget) {
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
    final l10n = AppLocalizations.of(context);
    for (final decision in _held) {
      notices.showSnackBar(
        SnackBar(
          key: ValueKey(
            decision.approved
                ? 'join-request-approved'
                : 'join-request-declined',
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
    _held.clear();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_tellLater);
    unawaited(_decisions.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
