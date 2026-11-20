import 'dart:async';

import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/trip_signals.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Feeds [cubit]'s activity to the app's [ReviewPrompt] and asks it after
/// a completed trip of at least [minTicks] ticks, once the user has left
/// the list alone for [idle]: never while they type, speak or have a
/// dialog open. Without a [ReviewPrompt] above it, only shows [child].
///
/// Under [ReviewRules.v2] trip mode ([TripSignals] above it) moves the
/// moment (job 326): an emptied list waits for „Kaufst du gerade ein?“ and
/// asks only once it is answered „Nein“ (ST2), never while a trip runs
/// (SA1); a fresh trip summary left asks too (ST1).
class const ReviewPromptTrigger({
  required final ListCubit cubit,

  /// The list's dictation is listening.
  required final bool listening,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  static const idle = Duration(seconds: 3);
  static const minTicks = 3;

  /// How long the list may stay offline or failing (the server in trouble)
  /// with changes waiting, in the foreground, before it counts as a sync
  /// failure: a tick in a dead spot that the queue sends a moment later is
  /// not one, nor is a 503 the next retry gets past, nor offline with
  /// nothing to send or in the background.
  static const offlineGrace = Duration(seconds: 60);

  @override
  State<ReviewPromptTrigger> createState() => _ReviewPromptTriggerState();
}

class _ReviewPromptTriggerState() extends State<ReviewPromptTrigger> {
  ReviewPrompt? _prompt;
  TripSignals? _trips;
  Popups? _popups;
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final AppLifecycleListener _lifecycle;
  Timer? _due;

  /// The emptied list's moment, held while „Kaufst du gerade ein?“ is up:
  /// its answer decides.
  var _parked = false;
  Timer? _offline;
  var _foreground = true;
  var _visible = true;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _prompt = context.read<ReviewPrompt?>();
    _popups = Popups.maybeOf(context);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        if (!_foreground) {
          _drop();
        }
        _watchOffline();
      },
    );
    HardwareKeyboard.instance.addHandler(_onKey);
    // Every touch in the app, not only on the list: a tap on the tab bar
    // or the rail is the user acting too.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _follow(widget.cubit);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _acted();
    }
  }

  bool get _tripMoments => _prompt?.rules.tripMoments ?? false;

  @override
  void didUpdateWidget(ReviewPromptTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit) {
      _unfollow();
      _follow(widget.cubit);
    }
  }

  void _follow(ListCubit cubit) {
    final prompt = _prompt;
    if (prompt == null) {
      return;
    }
    // Read again with the household's list: its trips come with it.
    final trips = _trips = context.read<TripSignals?>();
    _subscriptions.addAll([
      cubit.activity.listen((activity) {
        switch (activity) {
          case OwnItemAdded():
            unawaited(prompt.itemAdded());
          case ItemEdited() || CategoriesReordered() || OwnItemTicked():
            break;
          case TripCompleted(:final ticked):
            unawaited(prompt.tripCompleted());
            if (ticked >= ReviewPromptTrigger.minTicks || prompt.forced) {
              _start();
            }
          case TripReopened():
            if (_tripMoments) {
              unawaited(prompt.tripReopened());
              _drop();
            }
        }
      }),
      if (trips != null)
        trips.signals.listen((signal) {
          switch (signal) {
            case TripSaveFailed():
              unawaited(prompt.setback());
            case TripQuestionClosed(:final declined) when _tripMoments:
              final pending = _parked || _due != null;
              _drop();
              if (pending && declined) {
                _start();
              }
            case TripSummaryLeft(:final bought, :final complete)
                when _tripMoments &&
                    complete &&
                    (bought >= ReviewPromptTrigger.minTicks || prompt.forced):
              _start();
            case TripQuestionClosed() || TripSummaryLeft():
              break;
          }
        }),
      // A queued write the server refused; a taken name or a change that
      // needs a connection is a message about the input, no sync failure.
      cubit.rejections
          .where((r) => r is ItemRejected || r is CatalogRejected)
          .listen((_) => unawaited(prompt.errorSeen())),
      cubit.stream.listen((_) => _watchOffline()),
    ]);
  }

  /// Runs the grace while the list cannot sync (offline, or the server in
  /// trouble) with changes waiting and the app is in the foreground;
  /// anything else stops it.
  void _watchOffline() {
    final list = widget.cubit.state;
    final failing =
        _foreground && list.trouble != null && list.pending.isNotEmpty;
    if (!failing) {
      _offline?.cancel();
      _offline = null;
    } else if (_offline == null) {
      final prompt = _prompt;
      _offline = Timer(ReviewPromptTrigger.offlineGrace, () {
        _offline = null;
        unawaited(prompt?.errorSeen());
      });
    }
  }

  void _unfollow() {
    _drop();
    _offline?.cancel();
    _offline = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _start() {
    _drop();
    _due = Timer(ReviewPromptTrigger.idle, _fire);
  }

  void _drop() {
    _due?.cancel();
    _due = null;
    _parked = false;
  }

  /// A touch or a key drops the waiting moment, unless it is the answer to
  /// „Kaufst du gerade ein?“, which decides it.
  void _acted() {
    if (_due != null && _tripMoments && (_trips?.asking ?? false)) {
      _parked = true;
    }
    _due?.cancel();
    _due = null;
  }

  /// A key up may be the end of the press that ticked.
  bool _onKey(KeyEvent event) {
    if (event is! KeyUpEvent) {
      _acted();
    }
    return false;
  }

  /// No retry: the next completed trip is the next chance.
  void _fire() {
    _due = null;
    if (_tripMoments) {
      // A trip runs (SA1): its summary is the moment.
      if (_trips?.running ?? false) {
        return;
      }
      if (_trips?.asking ?? false) {
        _parked = true;
        return;
      }
    }
    // The shell's Scaffold takes the keyboard out of the list's MediaQuery.
    // Another tab (the shell keeps the List branch mounted, offstage) or a
    // page pushed over the list: the user is somewhere else.
    if (!mounted ||
        !_visible ||
        !(_route?.isCurrent ?? true) ||
        View.of(context).viewInsets.bottom > 0 ||
        widget.listening ||
        (_popups?.open ?? false)) {
      return;
    }
    unawaited(_prompt?.requestIfDue());
  }

  @override
  void dispose() {
    _unfollow();
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _visible = TickerMode.valuesOf(context).enabled;
    _route = ModalRoute.of(context);
    return widget.child;
  }
}
