import 'dart:convert';

import 'package:family_groceries/tips/hints.dart';
import 'package:flutter/foundation.dart';

/// What the app saw the user do, as far as the hints need it (job 168b).
/// [wire] is the stored name: never change or reuse one.
enum Signal(final String wire) {
  /// An item typed into the add field and taken as typed.
  typedAdd('typed_add'),

  /// A typed add without an amount.
  plainTypedAdd('plain_typed_add'),

  /// A typed or dictated add with an amount.
  amountAdd('amount_add'),

  /// The app's dictation added something.
  micUsed('mic_used'),

  /// A change saved in an item's edit sheet, which a hold opens.
  itemEdited('item_edited'),

  /// A category order changed: the default one or a store's.
  categoryReorder('category_reorder'),

  /// The household had a store.
  storeAdded('store_added'),

  /// The household had a second member.
  memberJoined('member_joined'),

  /// The user owned the household they were in.
  householdOwned('household_owned'),

  /// The user's tick emptied the list.
  shopDone('shop_done'),

  /// An AI assistant's grant, an MCP token or an API key existed.
  assistantConnected('assistant_connected'),

  /// A Home Screen widget was placed.
  widgetPlaced('widget_placed'),
}

/// One hint's history on this device.
@immutable
class const HintRecord({
  /// How many sessions showed it.
  final int shown = 0,
  final bool dismissed = false,

  /// Its action was tapped.
  final bool acted = false,
}) {
  HintRecord copyWith({int? shown, bool? dismissed, bool? acted}) => HintRecord(
    shown: shown ?? this.shown,
    dismissed: dismissed ?? this.dismissed,
    acted: acted ?? this.acted,
  );
}

/// The hints' memory, per user on the device (`DeviceCache`, job 168b):
/// signal counts, active days and each hint's showings, X and action. It is
/// the user's own "hide this", never sent anywhere. Every change returns a
/// new log; one that changes nothing returns this one.
@immutable
class const UsageLog({
  /// When this device first kept a log for the user.
  required final DateTime since,
  final Map<Signal, int> counts = const {},

  /// Days the app was opened, counted once per local calendar day.
  final int activeDays = 0,

  /// The last of them, `yyyy-mm-dd`.
  final String? lastActiveDay,
  final Map<HintId, HintRecord> hints = const {},

  /// When a hint showed for the first time, the last time one did.
  final DateTime? lastNew,

  /// X taps in a row, without an action tapped between them.
  final int dismissStreak = 0,

  /// No hint shows before then.
  final DateTime? pausedUntil,

  /// The checklist steps already sent as `checklist_step_done`.
  final Set<String> reported = const {},
}) {
  /// The stored log [json], or a fresh one from [now] when there is none or
  /// it cannot be read. Job 80's dismissed tips come as
  /// `{"dismissed": [ids]}` (`DeviceCache.hintLog`).
  factory parse(String? json, {required DateTime now}) {
    try {
      return switch (json == null ? null : jsonDecode(json)) {
        final Map<String, Object?> map => UsageLog._fromJson(map, now),
        _ => UsageLog(since: now),
      };
    } on FormatException {
      return UsageLog(since: now);
    }
  }

  factory _fromJson(Map<String, Object?> json, DateTime now) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    int number(Object? value) => value is int && value > 0 ? value : 0;
    final hints = <HintId, HintRecord>{
      if (json['hints'] case final Map<String, Object?> stored)
        for (final MapEntry(:key, :value) in stored.entries)
          if ((HintId.parse(key), value) case (
            final id?,
            final Map<String, Object?> record,
          ))
            id: HintRecord(
              shown: number(record['shown']),
              dismissed: record['dismissed'] == true,
              acted: record['acted'] == true,
            ),
      // Job 80 kept only the dismissed tips' ids.
      if (json['dismissed'] case final List<Object?> ids)
        for (final id in ids.map(HintId.parse).nonNulls)
          id: const HintRecord(dismissed: true),
    };
    return UsageLog(
      since: time(json['since']) ?? now,
      counts: {
        if (json['counts'] case final Map<String, Object?> counts)
          for (final signal in Signal.values)
            if (number(counts[signal.wire]) case final n when n > 0) signal: n,
      },
      activeDays: number(json['active_days']),
      lastActiveDay: json['last_active_day'] as String?,
      hints: hints,
      lastNew: time(json['last_new']),
      dismissStreak: number(json['dismiss_streak']),
      pausedUntil: time(json['paused_until']),
      reported: {
        if (json['reported'] case final List<Object?> steps)
          ...steps.whereType<String>(),
      },
    );
  }

  /// After this many X in a row every hint pauses for [pauseFor].
  static const pauseAfter = 3;
  static const pauseFor = Duration(days: 14);

  String toJson() => jsonEncode({
    'since': since.toUtc().toIso8601String(),
    'counts': {
      for (final MapEntry(:key, :value) in counts.entries) key.wire: value,
    },
    'active_days': activeDays,
    'last_active_day': lastActiveDay,
    'hints': {
      for (final MapEntry(:key, :value) in hints.entries)
        key.wire: {
          'shown': value.shown,
          'dismissed': value.dismissed,
          'acted': value.acted,
        },
    },
    'last_new': lastNew?.toUtc().toIso8601String(),
    'dismiss_streak': dismissStreak,
    'paused_until': pausedUntil?.toUtc().toIso8601String(),
    'reported': [...reported],
  });

  int count(Signal signal) => counts[signal] ?? 0;

  bool saw(Signal signal) => count(signal) > 0;

  HintRecord of(HintId id) => hints[id] ?? const HintRecord();

  UsageLog record(Signal signal) =>
      _with(counts: {...counts, signal: count(signal) + 1});

  /// [record] once: for what is a state, not an act.
  UsageLog note(Signal signal) => saw(signal) ? this : record(signal);

  /// Counts [now]'s local day as active, once.
  UsageLog activeOn(DateTime now) {
    final local = now.toLocal();
    final day = [
      local.year.toString().padLeft(4, '0'),
      local.month.toString().padLeft(2, '0'),
      local.day.toString().padLeft(2, '0'),
    ].join('-');
    return day == lastActiveDay
        ? this
        : _with(activeDays: activeDays + 1, lastActiveDay: day);
  }

  /// [id] showed in a session that began before [now].
  UsageLog shown(HintId id, DateTime now) {
    final record = of(id);
    return _with(
      hints: {
        ...hints,
        id: record.copyWith(shown: record.shown + 1),
      },
      lastNew: record.shown == 0 ? now : lastNew,
    );
  }

  /// X on [id]: never again, and the [pauseAfter]th X in a row pauses
  /// every hint.
  UsageLog dismissed(HintId id, DateTime now) {
    final streak = dismissStreak + 1;
    final pause = streak >= pauseAfter;
    return _with(
      hints: {...hints, id: of(id).copyWith(dismissed: true)},
      dismissStreak: pause ? 0 : streak,
      pausedUntil: pause ? now.add(pauseFor) : pausedUntil,
    );
  }

  /// [id]'s action tapped: it has done its job, and the X streak ends.
  UsageLog acted(HintId id) => _with(
    hints: {...hints, id: of(id).copyWith(acted: true)},
    dismissStreak: 0,
  );

  UsageLog reporting(String step) =>
      reported.contains(step) ? this : _with(reported: {...reported, step});

  UsageLog _with({
    Map<Signal, int>? counts,
    int? activeDays,
    String? lastActiveDay,
    Map<HintId, HintRecord>? hints,
    DateTime? lastNew,
    int? dismissStreak,
    DateTime? pausedUntil,
    Set<String>? reported,
  }) => UsageLog(
    since: since,
    counts: counts ?? this.counts,
    activeDays: activeDays ?? this.activeDays,
    lastActiveDay: lastActiveDay ?? this.lastActiveDay,
    hints: hints ?? this.hints,
    lastNew: lastNew ?? this.lastNew,
    dismissStreak: dismissStreak ?? this.dismissStreak,
    pausedUntil: pausedUntil ?? this.pausedUntil,
    reported: reported ?? this.reported,
  );
}

/// Where the hints' logs live: `DeviceCache` in the app.
abstract interface class HintStore() {
  /// [userId]'s log as [UsageLog.toJson] wrote it, or null for none.
  Future<String?> hintLog(String userId);

  Future<void> saveHintLog(String userId, String json);
}
