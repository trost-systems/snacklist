import 'dart:async';

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Feeds [cubit]'s activity to the app's [ReviewPrompt] and asks it after
/// a completed trip of at least [minTicks] ticks, once the user has left
/// the list alone for [idle]: never while they type, speak or have a
/// dialog open. Without a [ReviewPrompt] above it, only shows [child].
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
  Popups? _popups;
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final AppLifecycleListener _lifecycle;
  Timer? _due;
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
          _cancel();
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
      _cancel();
    }
  }

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
    _subscriptions.addAll([
      cubit.activity.listen((activity) {
        switch (activity) {
          case OwnItemAdded():
            unawaited(prompt.itemAdded());
          case ItemEdited() || CategoriesReordered():
            break;
          case TripCompleted(:final ticked):
            unawaited(prompt.tripCompleted());
            if (ticked >= ReviewPromptTrigger.minTicks || prompt.forced) {
              _due?.cancel();
              _due = Timer(ReviewPromptTrigger.idle, _fire);
            }
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
    _cancel();
    _offline?.cancel();
    _offline = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _cancel() {
    _due?.cancel();
    _due = null;
  }

  /// A key up may be the end of the press that ticked.
  bool _onKey(KeyEvent event) {
    if (event is! KeyUpEvent) {
      _cancel();
    }
    return false;
  }

  /// No retry: the next completed trip is the next chance.
  void _fire() {
    _due = null;
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
