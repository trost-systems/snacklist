import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What the List tab shows of the hints: the „Erste Schritte“ card while it
/// is open, else at most one [hint]. Never both: they share one slot.
@immutable
class const HintsState({final Hint? hint, final Checklist? checklist}) {
  @override
  bool operator ==(Object other) =>
      other is HintsState && other.hint == hint && other.checklist == checklist;

  @override
  int get hashCode => Object.hash(hint, checklist);
}

/// The List tab's hints and checklist for one session (job 168b): feeds
/// the list's activity into the user's [UsageLog], picks at most one hint
/// per session with [nextHint], and keeps the log on the device.
class HintsCubit(
  final HintStore _store,
  final ListCubit _list, {
  required final HintPlatform platform,
  HouseholdKind? kind,
  final HintHost host = const HintHost(),
  final Analytics? analytics,

  /// The hints to pick from; [hints] by default.
  final List<Hint>? registry,
  DateTime Function()? clock,
}) extends Cubit<HintsState> {
  this : super(const HintsState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  late final _registry = registry ?? hints;
  final DateTime _startedAt = (clock ?? DateTime.now)();
  var _kind = kind;
  UsageLog? _log;
  UsageLog? _saved;
  var _firstSession = false;
  var _covered = false;
  var _listHidden = false;

  /// A hint or the checklist showed this session; the next hint waits for
  /// the next one.
  var _picked = false;
  Hint? _hint;
  Timer? _quiet;
  final _subscriptions = <StreamSubscription<Object?>>[];

  String get _userId => _list.userId;

  Future<void> load() async {
    final json = await _store.hintLog(_userId);
    if (isClosed) {
      return;
    }
    final now = _clock();
    _firstSession = json == null;
    _log = UsageLog.parse(json, now: now).activeOn(now);
    _subscriptions.addAll([
      _list.activity.listen(_heard),
      _list.stream.listen((_) => _update()),
    ]);
    final quiet = quietAfterStart - now.difference(_startedAt);
    if (quiet > Duration.zero) {
      _quiet = Timer(quiet, _update);
    }
    _update();
    unawaited(_probe());
  }

  /// What is on screen: a sheet, dialog or keyboard over the list, whether
  /// the List tab shows, and the household's kind (it may arrive late).
  void screen({
    required bool covered,
    required bool listHidden,
    required HouseholdKind? kind,
  }) {
    if (covered == _covered && listHidden == _listHidden && kind == _kind) {
      return;
    }
    _covered = covered;
    _listHidden = listHidden;
    _kind = kind;
    _update();
  }

  /// X on the hint: never again.
  void dismiss() {
    if ((_hint, _log) case (final hint?, final log?)) {
      _hint = null;
      _log = log.dismissed(hint.id, _clock());
      _track('hint_dismissed', {'hint_id': hint.id.wire});
      _update();
    }
  }

  /// The hint's button: the app opens what it is about.
  void act() {
    if ((_hint, _log) case (final hint?, final log?)) {
      _hint = null;
      _log = log.acted(hint.id);
      _track('hint_acted', {'hint_id': hint.id.wire});
      _update();
    }
  }

  /// X on the checklist: gone for this household, as the gesture card was.
  void dismissChecklist() {
    if (state.checklist case final checklist?) {
      _track('checklist_dismissed', {'open_steps': checklist.open});
      _list.dismissHint();
    }
  }

  void _heard(ListActivity activity) {
    if (_log case final log?) {
      _log = switch (activity) {
        OwnItemAdded(:final source, :final withAmount) => [
          if (source == AddSource.typed) Signal.typedAdd,
          if (source == AddSource.typed && !withAmount) Signal.plainTypedAdd,
          if (source == AddSource.spoken) Signal.micUsed,
          if (withAmount &&
              (source == AddSource.typed || source == AddSource.spoken))
            Signal.amountAdd,
        ].fold<UsageLog>(log, (log, signal) => log.record(signal)),
        ItemEdited() => log.record(Signal.itemEdited),
        CategoriesReordered() => log.record(Signal.categoryReorder),
        TripCompleted() => log.record(Signal.shopDone),
      };
      _update();
    }
  }

  /// Asks the host once per session for what the list cannot see, while a
  /// hint or the checklist still waits for it.
  Future<void> _probe() async {
    for (final (signal, probe) in [
      (Signal.assistantConnected, host.assistantConnected),
      (Signal.widgetPlaced, host.widgetPlaced),
    ]) {
      if (probe == null || !_waitsFor(signal)) {
        continue;
      }
      final bool found;
      try {
        found = await probe();
      } on Object {
        continue;
      }
      if (isClosed) {
        return;
      }
      if (found) {
        _log = _log?.note(signal);
        _update();
      }
    }
  }

  bool _waitsFor(Signal signal) {
    final log = _log;
    if (log == null || log.saw(signal)) {
      return false;
    }
    return (signal == Signal.assistantConnected &&
            (_checklist(log)?.has(ChecklistStep.assistant) ?? false)) ||
        _registry.any(
          (hint) =>
              hint.retiredBy == signal &&
              hint.offered(platform, canAddHousehold: host.canAddHousehold) &&
              !hint.doneIn(log),
        );
  }

  /// The checklist unless the user hid it in this household.
  Checklist? _checklist(UsageLog log) => _list.state.prefs.hintDismissed
      ? null
      : Checklist.of(log, kind: _kind, owner: _owner);

  /// A member list without the user (not loaded yet) counts as theirs.
  bool get _owner =>
      _list.state.catalog.members
          .where((m) => m.id == _userId)
          .firstOrNull
          ?.role !=
      'member';

  void _update() {
    final listState = _list.state;
    if (isClosed || !listState.loaded) {
      return;
    }
    if (_log case final stored?) {
      final now = _clock();
      final catalog = listState.catalog;
      var log = stored;
      if (catalog.stores.isNotEmpty) {
        log = log.note(Signal.storeAdded);
      }
      if (catalog.members.length > 1) {
        log = log.note(Signal.memberJoined);
      }
      if (catalog.members.any((m) => m.id == _userId && m.role == 'owner')) {
        log = log.note(Signal.householdOwned);
      }
      final checklist = _checklist(log);
      for (final (:step, :done)
          in checklist?.entries ?? const <ChecklistEntry>[]) {
        if (done && step != ChecklistStep.started) {
          final reported = log.reporting(step.wire);
          if (!identical(reported, log)) {
            log = reported;
            _track('checklist_step_done', {'step': step.wire});
          }
        }
      }
      final open = checklist != null && checklist.open > 0;
      // The checklist took this session's slot: no card follows it.
      _picked |= open;
      if (_hint case final hint? when hint.usedIn(log)) {
        _hint = null;
      }
      if (!open && !_picked) {
        final context = HintContext(
          platform: platform,
          startedAt: _startedAt,
          firstSession: _firstSession,
          covered: _covered,
          listHidden: _listHidden,
          items: listState.items.values
              .where((i) => i.status == ItemStatus.active)
              .length,
          stores: catalog.stores.length,
          members: catalog.members.length,
          owner: _owner,
          kind: _kind,
          canAddHousehold: host.canAddHousehold,
        );
        if (nextHint(_registry, log, now, context) case final hint?) {
          _picked = true;
          _hint = hint;
          log = log.shown(hint.id, now);
          _track('hint_shown', {'hint_id': hint.id.wire});
        }
      }
      _log = log;
      if (!identical(log, _saved)) {
        _saved = log;
        unawaited(_store.saveHintLog(_userId, log.toJson()));
      }
      emit(open ? HintsState(checklist: checklist) : HintsState(hint: _hint));
    }
  }

  void _track(String event, Map<String, Object> properties) =>
      analytics?.track(event, properties);

  @override
  Future<void> close() async {
    _quiet?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await super.close();
  }
}
