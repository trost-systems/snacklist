import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/home_widget/widget_payload.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:home_widget/home_widget.dart';

/// Where the widgets read from: the home_widget plugin on iOS and Android.
abstract interface class WidgetPublisher() {
  /// Stores [json] for the widgets and has them redraw.
  Future<void> publish(String json);
}

class const PluginWidgetPublisher() implements WidgetPublisher {
  /// Shared with the iOS extension (both entitlements files).
  static const appGroup = 'group.com.hummlist.app';
  static const key = 'hummlist_widget';

  /// The WidgetKit kind (`app/ios/HomeWidget/HomeWidget.swift`).
  static const iOSKind = 'HomeWidget';
  static const androidReceiver =
      'com.hummlist.app.widget.HummlistWidgetReceiver';

  @override
  Future<void> publish(String json) async {
    await HomeWidget.setAppGroupId(appGroup);
    await HomeWidget.saveWidgetData<String>(key, json);
    await HomeWidget.updateWidget(
      iOSName: iOSKind,
      qualifiedAndroidName: androidReceiver,
    );
  }
}

/// Whether one of the app's Home Screen widgets is placed, as WidgetKit or
/// Android's widget manager tell the plugin (job 168b's `home-widget`
/// hint).
Future<bool> homeWidgetPlaced() async =>
    (await HomeWidget.getInstalledWidgets()).isNotEmpty;

/// The sync on iOS and Android; the web and Linux have no widgets.
HomeWidgetSync? homeWidgetSyncFor({
  required bool web,
  required TargetPlatform platform,
}) =>
    !web &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.android)
    ? HomeWidgetSync(const PluginWidgetPublisher())
    : null;

/// Keeps the widgets' payload in step with the session and the household's
/// list: at most once per [debounce], only when it changed, and never a
/// list of another household than the session's.
class HomeWidgetSync(
  final WidgetPublisher _publisher, {
  final Duration debounce = const Duration(seconds: 1),
  DateTime Function()? clock,
}) {
  final DateTime Function() _clock = clock ?? DateTime.now;
  Session? _session;
  ({String householdId, ListState state})? _list;
  Timer? _timer;

  /// The last payload handed to the publisher, without its time.
  String? _sent;
  Future<void> _work = Future.value();

  /// Follows [session] from its current state on.
  StreamSubscription<Session> follow(StateStreamable<Session> session) {
    _sessionChanged(session.state);
    return session.stream.listen(_sessionChanged);
  }

  /// Follows the list of [householdId] from its current state on; the
  /// list scope cancels it with its cubit.
  StreamSubscription<ListState> followList(
    String householdId,
    StateStreamable<ListState> list,
  ) {
    void changed(ListState state) {
      _list = (householdId: householdId, state: state);
      _schedule();
    }

    changed(list.state);
    return list.stream.listen(changed);
  }

  /// Completes once every payload handed over so far is published.
  @visibleForTesting
  Future<void> get idle => _work;

  void _sessionChanged(Session session) {
    _session = session;
    _schedule();
  }

  void _schedule() => _timer ??= Timer(debounce, _send);

  WidgetPayload? get _wanted => switch (_session) {
    SignedOut() => const SignedOutPayload(),
    NeedsHousehold() => const NoHouseholdPayload(),
    InHousehold(:final household) => switch (_list) {
      (:final householdId, :final state)
          when householdId == household.id && state.loaded =>
        readyPayloadOf(state),
      _ => null,
    },
    SessionLoading() || null => null,
  };

  void _send() {
    _timer = null;
    final payload = _wanted;
    if (payload == null) {
      return;
    }
    final now = _clock();
    // Compared without the time: an unchanged list is not written again.
    final key = jsonEncode(
      payload.toJson(DateTime.fromMillisecondsSinceEpoch(0)),
    );
    if (key == _sent) {
      return;
    }
    _sent = key;
    final json = jsonEncode(payload.toJson(now));
    _work = _work.then((_) async {
      try {
        await _publisher.publish(json);
      } on Object {
        // A plugin error: the next change writes it again.
        if (_sent == key) {
          _sent = null;
        }
      }
    });
  }

  void close() => _timer?.cancel();
}
