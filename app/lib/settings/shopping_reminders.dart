import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/design/word_wrap.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/settings/shopping_day.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// When a reminder comes, counted from its shopping day.
enum ReminderOffset(final int days) {
  dayBefore(-1),
  onTheDay(0);

  static ReminderOffset of(int days) =>
      values.firstWhere((offset) => offset.days == days);
}

/// What one reminder is: its shopping day (ISO weekday, 1 Monday to 7
/// Sunday), the day before or on the day, and the local time in minutes
/// after midnight. The server keeps each person's slots unique (SR-Q6).
@immutable
class const ReminderSlot({
  required final int weekday,
  required final ReminderOffset offset,
  required final int minute,
}) {
  /// A new reminder's sheet starts at the day before, 19:00 (SR-Q3); its
  /// day is the person's pick, and nothing is stored before Save.
  static const firstOffset = ReminderOffset.dayBefore;
  static const firstMinute = 19 * 60;

  /// The weekday it fires on: a Monday shop the day before fires Sunday.
  int get fireWeekday => (weekday - 1 + offset.days) % 7 + 1;

  /// When it next fires after [now] on this device's clock, the day it last
  /// went out ([sentOn]) skipped: saved at or after today's time, today
  /// counts as sent (SR-Q7). A day before at 00:30 fires the day before at
  /// 00:30, its real date (SR-Q11).
  DateTime nextFire(DateTime now, {DateTime? sentOn}) {
    for (var ahead = 0; ; ahead++) {
      final day = DateTime(now.year, now.month, now.day + ahead);
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      );
      if (day.weekday == fireWeekday &&
          at.isAfter(now) &&
          (sentOn == null || day.isAfter(sentOn))) {
        return at;
      }
    }
  }

  /// Whether [other] fires on the same days: same shopping day and offset,
  /// whatever the time.
  bool sameDaysAs(ReminderSlot other) =>
      weekday == other.weekday && offset == other.offset;

  /// Whether today's time of this reminder is already past at [now], so a
  /// save now skips today (SR-Q7).
  bool passedToday(DateTime now) =>
      now.weekday == fireWeekday && now.hour * 60 + now.minute >= minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderSlot &&
      other.weekday == weekday &&
      other.offset == offset &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(weekday, offset, minute);

  @override
  String toString() => '$weekday ${offset.name} $minute';
}

/// One of the signed-in person's reminders as the server has it.
@immutable
class const ShoppingReminder({
  required final String id,
  required final ReminderSlot slot,

  /// The local date it last went out; a save at or after its time today
  /// sets today.
  final DateTime? sentOn,
});

/// The date the server keeps as sent once [slot] is saved at [now] over
/// [before] (`update_shopping_reminder`): the old date only while the days
/// stay the same, and today once today's time has passed.
DateTime? sentAfterSave(
  ShoppingReminder? before,
  ReminderSlot slot,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final kept = before != null && before.slot.sameDaysAs(slot)
      ? before.sentOn
      : null;
  if (!slot.passedToday(now)) {
    return kept;
  }
  return kept != null && kept.isAfter(today) ? kept : today;
}

/// The most reminders a person may have (SR-Q9); the server refuses more.
const reminderLimit = 14;

/// Why the server refused a reminder.
enum ReminderRefusal() {
  duplicate,
  limit,
}

final class const ReminderRefused(final ReminderRefusal reason)
    implements Exception;

/// The person's reminders on the server (`shopping_reminders`, job 472,
/// docs/PUSH.md). Reads are the owner's rows; every write is an RPC.
abstract interface class ShoppingRemindersRepository() {
  Future<List<ShoppingReminder>> read();

  /// Throws [ReminderRefused] for a duplicate or a 15th reminder.
  Future<ShoppingReminder> add(
    ReminderSlot slot,
    String timeZone,
    String locale,
  );

  /// Throws [ReminderRefused] when [slot] is another reminder's.
  Future<ShoppingReminder> update(
    String id,
    ReminderSlot slot,
    String timeZone,
    String locale,
  );

  /// Gone already is fine.
  Future<void> delete(String id);

  /// The device's zone and the app language on every reminder; never the
  /// days, times or what was sent.
  Future<void> refresh(String timeZone, String locale);
}

class const SupabaseShoppingRemindersRepository(final SupabaseClient _client)
    implements ShoppingRemindersRepository {
  @override
  Future<List<ShoppingReminder>> read() async {
    final rows = await _client
        .from('shopping_reminders')
        .select('id, shopping_weekday, offset_days, local_time, last_sent_on');
    return [for (final row in rows) _reminder(row)];
  }

  @override
  Future<ShoppingReminder> add(
    ReminderSlot slot,
    String timeZone,
    String locale,
  ) => _write('add_shopping_reminder', {
    ..._params(slot),
    'p_time_zone': timeZone,
    'p_locale': locale,
  });

  @override
  Future<ShoppingReminder> update(
    String id,
    ReminderSlot slot,
    String timeZone,
    String locale,
  ) => _write('update_shopping_reminder', {
    'p_id': id,
    ..._params(slot),
    'p_time_zone': timeZone,
    'p_locale': locale,
  });

  @override
  Future<void> delete(String id) async {
    await _client.rpc<void>('delete_shopping_reminder', params: {'p_id': id});
  }

  @override
  Future<void> refresh(String timeZone, String locale) async {
    await _client.rpc<void>(
      'refresh_shopping_day_reminder',
      params: {'p_time_zone': timeZone, 'p_locale': locale},
    );
  }

  static Map<String, Object> _params(ReminderSlot slot) => {
    'p_weekday': slot.weekday,
    'p_day_before': slot.offset == ReminderOffset.dayBefore,
    'p_minute': slot.minute,
  };

  Future<ShoppingReminder> _write(
    String function,
    Map<String, Object> params,
  ) async {
    try {
      final row = await _client.rpc<Map<String, Object?>>(
        function,
        params: params,
      );
      return _reminder(row);
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        '23505' => const ReminderRefused(ReminderRefusal.duplicate),
        '54000' => const ReminderRefused(ReminderRefusal.limit),
        _ => e,
      };
    }
  }

  static ShoppingReminder _reminder(Map<String, Object?> row) {
    final [hour, minute, ...] = (row['local_time']! as String)
        .split(':')
        .map(int.parse)
        .toList();
    return ShoppingReminder(
      id: row['id']! as String,
      slot: ReminderSlot(
        weekday: row['shopping_weekday']! as int,
        offset: ReminderOffset.of(row['offset_days']! as int),
        minute: hour * 60 + minute,
      ),
      sentOn: switch (row['last_sent_on']) {
        final String day => DateTime.parse(day),
        _ => null,
      },
    );
  }
}

/// What a save came to.
enum ReminderSaved() {
  saved,

  /// The OS refuses notifications; nothing was saved (SR-Q12).
  pushBlocked,
  duplicate,
  limit,

  /// The zone could not be read or the server did not take it.
  failed,
}

/// SR1's reads and writes (job 472). Opening the page asks nothing and
/// writes nothing but the zone of reminders that exist; the first Save asks
/// the OS for push, and a refusal saves nothing (Legal C2, SR-Q12).
class ShoppingReminders(
  final ShoppingRemindersRepository repository,
  final DeviceTimeZone timeZone,

  /// `PushRegistration.optIn`: true when notifications are on.
  final Future<bool> Function() optInToPush,

  /// `PushRegistration.resume`, then whether push is on here; never
  /// prompts.
  final Future<bool> Function() pushIsOn,

  /// `PushRegistration.forget`, for the last notification type gone.
  final Future<void> Function() forgetPush,

  /// Whether the household-add alert is on, so it still needs the token.
  final Future<bool> Function() householdAddOn, {

  /// The device's clock, for the next firing.
  final DateTime Function() now = DateTime.now,

  /// `ShoppingDayService.retryPendingClear`: a clear of the weekday chips
  /// that waited offline reaches the server before anything here.
  final Future<void> Function()? settlePendingClear,

  /// `ShoppingDayService.dropPendingClear`: a saved reminder supersedes a
  /// clear that still could not be sent.
  final Future<void> Function()? dropPendingClear,
}) {
  Future<void> _settle() async {
    try {
      await settlePendingClear?.call();
    } on Object {
      // Kept on the device; dropped by the next save that works.
    }
  }

  /// The person's reminders. With some saved and push on here, the device's
  /// zone and the app's language are saved again, quietly, for a person who
  /// moved; a device without push leaves them alone, so a tablet in another
  /// zone cannot move the phone's reminders.
  Future<List<ShoppingReminder>> load(String locale) async {
    await _settle();
    final reminders = await repository.read();
    if (reminders.isNotEmpty && await pushIsOn()) {
      unawaited(
        timeZone.name().then(
          (zone) => repository.refresh(zone, locale),
          onError: (Object _) {},
        ),
      );
    }
    return reminders;
  }

  /// Saves a new reminder, or [id]'s new slot.
  Future<(ReminderSaved, ShoppingReminder?)> save(
    ReminderSlot slot,
    String locale, {
    String? id,
  }) async {
    if (!await optInToPush()) {
      return (ReminderSaved.pushBlocked, null);
    }
    await _settle();
    try {
      final zone = await timeZone.name();
      final saved = await switch (id) {
        null => repository.add(slot, zone, locale),
        final id => repository.update(id, slot, zone, locale),
      };
      try {
        await dropPendingClear?.call();
      } on Object {
        // The clear was this account's older choice; at worst it is sent.
      }
      return (ReminderSaved.saved, saved);
    } on ReminderRefused catch (e) {
      return (
        switch (e.reason) {
          ReminderRefusal.duplicate => ReminderSaved.duplicate,
          ReminderRefusal.limit => ReminderSaved.limit,
        },
        null,
      );
    } on Object {
      return (ReminderSaved.failed, null);
    }
  }

  /// Deletes [id]; true once the server took it. The last reminder gone
  /// with the household-add alert off too is the last notification type,
  /// so the device then stops getting pushes, as after a sign-out (Legal
  /// N-436). [last] is what the page shows when the delete is sent; the
  /// server's rows decide, the page's guess only when they cannot be read.
  /// A delete the server refused changes nothing anywhere: the row comes
  /// back and the device keeps its push.
  Future<bool> delete(String id, {required bool last}) async {
    await _settle();
    try {
      await repository.delete(id);
    } on Object {
      return false;
    }
    final none = await repository.read().then(
      (left) => left.isEmpty,
      onError: (Object _) => last,
    );
    if (none && !await householdAddOn()) {
      try {
        await forgetPush();
      } on Object {
        // Forget catches up offline itself; the reminder is gone either way.
      }
    }
    return true;
  }
}

/// Benachrichtigungen & Erinnerungen' SR1 section with the
/// `push-shopping-reminders` flag (job 472): the person's reminders, each a
/// shopping day, the day before or on the day, and a time, and one add
/// button that opens the sheet. A save shows at once and goes back, with a
/// notice, when the OS or the server refuses it. Nothing shows on web or
/// without push in the build (no [ShoppingReminders]).
class const ShoppingRemindersSettings({super.key}) extends StatefulWidget {
  @override
  State<ShoppingRemindersSettings> createState() =>
      _ShoppingRemindersSettingsState();
}

/// A row on screen: the server's reminder, or one whose save is on its way
/// (`pending`).
typedef _Shown = ({ShoppingReminder reminder, bool pending});

class _ShoppingRemindersSettingsState()
    extends State<ShoppingRemindersSettings> {
  /// Null until the server answered.
  List<_Shown>? _shown;
  var _asked = false;
  var _drafts = 0;

  /// A first read that failed is tried again, so the section does not stay
  /// away for the rest of the visit.
  Timer? _again;

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  /// Saves reach the server one after another, in the order they were made.
  Future<void> _queue = Future.value();

  String _language(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'de' ? 'de' : 'en';

  Future<void> _load(ShoppingReminders service, String locale) async {
    try {
      final reminders = await service.load(locale);
      if (mounted) {
        setState(
          () => _shown = [
            for (final reminder in reminders)
              (reminder: reminder, pending: false),
          ],
        );
      }
    } on Object {
      _again = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() => _asked = false);
        }
      });
    }
  }

  void _replace(String id, _Shown? by) => setState(() {
    final shown = _shown!;
    final at = shown.indexWhere((row) => row.reminder.id == id);
    if (at == -1) {
      if (by != null) {
        shown.add(by);
      }
    } else if (by == null) {
      shown.removeAt(at);
    } else {
      shown[at] = by;
    }
  });

  Future<void> _open(
    ShoppingReminders service, [
    ShoppingReminder? editing,
  ]) async {
    final shown = _shown;
    if (shown == null) {
      return;
    }
    final choice = await showModalBottomSheet<_SheetChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _ReminderSheet(
        editing: editing,
        taken: (slot) => (_shown ?? const <_Shown>[]).any(
          (row) => row.reminder.id != editing?.id && row.reminder.slot == slot,
        ),
        now: service.now(),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    switch (choice) {
      case _Save(:final slot):
        _save(service, slot, editing);
      case _Delete():
        if (editing != null) {
          _delete(service, editing);
        }
    }
  }

  void _save(
    ShoppingReminders service,
    ReminderSlot slot,
    ShoppingReminder? before,
  ) {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final locale = _language(context);
    final format = _Formats.of(context);
    final id = before?.id ?? 'draft-${++_drafts}';
    final now = service.now();
    _replace(id, (
      reminder: ShoppingReminder(
        id: id,
        slot: slot,
        sentOn: sentAfterSave(before, slot, now),
      ),
      pending: true,
    ));
    _queue = _queue.then((_) async {
      final (result, saved) = await service
          .save(slot, locale, id: before?.id)
          .catchError((Object _) => (ReminderSaved.failed, null));
      if (!mounted) {
        return;
      }
      if (saved != null) {
        _replace(id, (reminder: saved, pending: false));
      } else {
        _replace(
          id,
          before == null ? null : (reminder: before, pending: false),
        );
      }
      // The server's answer decides, not the tap: a save that reached it
      // after today's time skips today too.
      final answered = service.now();
      final today = DateTime(answered.year, answered.month, answered.day);
      final sentBefore = before != null && before.slot.sameDaysAs(slot)
          ? before.sentOn
          : null;
      final skipped =
          saved != null &&
          saved.sentOn == today &&
          sentBefore != today &&
          slot.fireWeekday == today.weekday;
      final message = switch (result) {
        ReminderSaved.saved when skipped => l10n.reminderSkipsToday(
          format.time(slot.minute),
          format.when(slot.nextFire(answered, sentOn: saved.sentOn)),
        ),
        ReminderSaved.saved => null,
        ReminderSaved.pushBlocked => l10n.shoppingDayBlocked,
        ReminderSaved.duplicate => l10n.reminderDuplicate,
        ReminderSaved.limit => l10n.reminderLimit(reminderLimit),
        ReminderSaved.failed => l10n.catalogSaveFailed,
      };
      if (message != null) {
        notices.showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  void _delete(ShoppingReminders service, ShoppingReminder reminder) {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    _replace(reminder.id, null);
    _queue = _queue.then((_) async {
      // Decided when it is sent: an earlier delete that failed has put its
      // row back by then.
      final done = await service
          .delete(reminder.id, last: _shown?.isEmpty ?? true)
          .catchError((Object _) => false);
      if (!mounted || done) {
        return;
      }
      _replace(reminder.id, (reminder: reminder, pending: false));
      notices.showSnackBar(SnackBar(content: Text(l10n.catalogSaveFailed)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flag = context.select<Flags?, bool>(
      (flags) => flags?.isOn(shoppingRemindersFlag) ?? false,
    );
    final service = context.read<ShoppingReminders?>();
    if (!flag || service == null) {
      return const SizedBox.shrink();
    }
    if (!_asked) {
      _asked = true;
      unawaited(_load(service, _language(context)));
    }
    final shown = _shown;
    if (shown == null) {
      return const SizedBox.shrink();
    }
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final format = _Formats.of(context);
    final now = service.now();
    final full = shown.length >= reminderLimit;
    final rows = [...shown]
      ..sort((a, b) => _order(a.reminder.slot, b.reminder.slot));
    return Column(
      key: const ValueKey('shopping-reminders'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(
          l10n.remindersTitle,
          padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0),
        ),
        HlGroup(
          top: HlSpace.s2,
          children: [
            Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: HlWordWrapText(l10n.remindersHint),
            ),
            if (rows.isEmpty)
              Padding(
                key: const ValueKey('reminders-empty'),
                padding: const EdgeInsets.all(HlSpace.s3),
                child: HlWordWrapText(
                  l10n.remindersEmpty,
                  style: TextStyle(color: t.textMuted),
                ),
              ),
            for (final row in rows)
              _ReminderRow(
                row.reminder,
                format: format,
                now: now,
                onTap: row.pending
                    ? null
                    : () => unawaited(_open(service, row.reminder)),
              ),
            Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s2,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('reminder-add'),
                    onPressed: full ? null : () => unawaited(_open(service)),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.reminderAdd),
                  ),
                  if (full)
                    Text(
                      l10n.reminderLimit(reminderLimit),
                      key: const ValueKey('reminders-full'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shopping-day order: by day, then the day before's before the day's own,
/// each by time.
int _order(ReminderSlot a, ReminderSlot b) {
  int rank(ReminderSlot slot) =>
      slot.weekday * 2 * 24 * 60 +
      (slot.offset == ReminderOffset.dayBefore ? 0 : 24 * 60) +
      slot.minute;
  return rank(a) - rank(b);
}

/// Dates and times as the page shows them: a weekday's name, a time on the
/// device's clock (always 24 hours in German, the device's setting in
/// English; SR-Q10) and a real date with its time.
class const _Formats._(
  final String _tag,
  final MaterialLocalizations _material,
  final bool _always24,
) {
  factory of(BuildContext context) => _Formats._(
    Localizations.localeOf(context).toLanguageTag(),
    MaterialLocalizations.of(context),
    MediaQuery.alwaysUse24HourFormatOf(context),
  );

  /// 2024-01-01 was a Monday.
  DateTime _day(int weekday) => DateTime(2024, 1, weekday);

  String weekday(int weekday) => DateFormat.EEEE(_tag).format(_day(weekday));

  String weekdayShort(int weekday) =>
      DateFormat.E(_tag).format(_day(weekday)).replaceAll('.', '');

  String time(int minute) => _material.formatTimeOfDay(
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    alwaysUse24HourFormat: _always24,
  );

  bool get _twelveHours =>
      hourFormat(
        of: _material.timeOfDayFormat(alwaysUse24HourFormat: _always24),
      ) !=
      HourFormat.HH;

  String hour(int hour) {
    if (!_twelveHours) {
      return hour.toString().padLeft(2, '0');
    }
    final half = hour < 12
        ? _material.anteMeridiemAbbreviation
        : _material.postMeridiemAbbreviation;
    return '${hour % 12 == 0 ? 12 : hour % 12} $half';
  }

  String when(DateTime at) =>
      '${DateFormat.MMMEd(_tag).format(at)}, ${time(at.hour * 60 + at.minute)}';
}

class const _ReminderRow(
  final ShoppingReminder reminder, {
  required final _Formats format,
  required final DateTime now,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final slot = reminder.slot;
    final time = format.time(slot.minute);
    return ListTile(
      key: ValueKey('reminder-$slot'),
      contentPadding: const EdgeInsets.symmetric(horizontal: HlSpace.s3),
      leading: HlRowHex(switch (slot.offset) {
        ReminderOffset.dayBefore => Icons.bedtime_outlined,
        ReminderOffset.onTheDay => Icons.today_outlined,
      }, face: t.mintSoft),
      title: HlWordWrapText(format.weekday(slot.weekday)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HlWordWrapText(switch (slot.offset) {
            ReminderOffset.dayBefore => l10n.reminderLineDayBefore(time),
            ReminderOffset.onTheDay => l10n.reminderLineOnTheDay(time),
          }),
          HlWordWrapText(
            l10n.reminderNext(
              format.when(slot.nextFire(now, sentOn: reminder.sentOn)),
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// What the sheet was closed with.
sealed class const _SheetChoice();

final class const _Save(final ReminderSlot slot) extends _SheetChoice;

final class const _Delete() extends _SheetChoice;

/// The add and edit sheet: one shopping day (picked by the person; a new
/// reminder has none), the day before or on the day, and the time as an
/// hour and a five-minute chip. A new one starts at the day before, 19:00,
/// and nothing is stored until Save. A slot the person has already is
/// refused here, before it reaches the server.
class const _ReminderSheet({
  required final ShoppingReminder? editing,

  /// Whether another reminder has this slot now; asked on Save, so saves
  /// that settled while the sheet was open count.
  required final bool Function(ReminderSlot slot) taken,
  required final DateTime now,
}) extends StatefulWidget {
  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState() extends State<_ReminderSheet> {
  late int? _weekday = widget.editing?.slot.weekday;
  late var _offset = widget.editing?.slot.offset ?? ReminderSlot.firstOffset;
  late var _minute = widget.editing?.slot.minute ?? ReminderSlot.firstMinute;
  var _refused = false;

  ReminderSlot? get _slot => switch (_weekday) {
    final weekday? => ReminderSlot(
      weekday: weekday,
      offset: _offset,
      minute: _minute,
    ),
    null => null,
  };

  void _set(VoidCallback change) => setState(() {
    change();
    _refused = false;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final format = _Formats.of(context);
    final slot = _slot;
    final hour = _minute ~/ 60;
    final minute = _minute % 60;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: HlSpace.s4, bottom: HlSpace.s2),
      child: HlWordWrapText(text, style: theme.textTheme.titleSmall),
    );
    Widget chip({
      required Key key,
      required String text,
      required String semantics,
      required bool selected,
      required VoidCallback onSelected,
    }) => FocusRingChip(
      chip: ChoiceChip(
        key: key,
        label: Semantics(
          label: semantics,
          excludeSemantics: true,
          child: Text(text),
        ),
        selected: selected,
        // A check would widen the picked chip and move the others.
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      ),
    );
    // Save stays in reach below the scrolling fields, at any text size.
    return Column(
      key: const ValueKey('reminder-sheet'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              HlSpace.s5,
              0,
              HlSpace.s5,
              HlSpace.s3,
            ),
            children: [
              Semantics(
                header: true,
                child: HlWordWrapText(
                  widget.editing == null ? l10n.reminderNew : l10n.reminderEdit,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              label(l10n.reminderShoppingDay),
              Wrap(
                spacing: HlSpace.s2,
                runSpacing: HlSpace.s2,
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    chip(
                      key: ValueKey('reminder-day-$weekday'),
                      text: format.weekdayShort(weekday),
                      semantics: format.weekday(weekday),
                      selected: _weekday == weekday,
                      onSelected: () => _set(() => _weekday = weekday),
                    ),
                ],
              ),
              label(l10n.reminderWhen),
              HexSegmented<ReminderOffset>(
                key: const ValueKey('reminder-offset'),
                label: l10n.reminderWhen,
                stackWhenTight: true,
                value: _offset,
                onChanged: (offset) => _set(() => _offset = offset),
                segments: [
                  HexSegment(
                    value: ReminderOffset.dayBefore,
                    label: l10n.reminderDayBefore,
                    key: const ValueKey('reminder-day-before'),
                  ),
                  HexSegment(
                    value: ReminderOffset.onTheDay,
                    label: l10n.reminderOnTheDay,
                    key: const ValueKey('reminder-on-the-day'),
                  ),
                ],
              ),
              label(l10n.reminderTime),
              Text(
                format.time(_minute),
                key: const ValueKey('reminder-time'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: HlSpace.s2),
              Wrap(
                spacing: HlSpace.s2,
                runSpacing: HlSpace.s2,
                children: [
                  for (var h = 0; h < 24; h++)
                    chip(
                      key: ValueKey('reminder-hour-$h'),
                      text: format.hour(h),
                      semantics: '${l10n.reminderHour} ${format.hour(h)}',
                      selected: hour == h,
                      onSelected: () => _set(() => _minute = h * 60 + minute),
                    ),
                ],
              ),
              const SizedBox(height: HlSpace.s3),
              Wrap(
                spacing: HlSpace.s2,
                runSpacing: HlSpace.s2,
                children: [
                  for (var m = 0; m < 60; m += 5)
                    chip(
                      key: ValueKey('reminder-minute-$m'),
                      text: ':${_two(m)}',
                      semantics: '${l10n.reminderMinute} ${_two(m)}',
                      selected: minute == m,
                      onSelected: () => _set(() => _minute = hour * 60 + m),
                    ),
                ],
              ),
              if (slot != null) ...[
                const SizedBox(height: HlSpace.s4),
                Text(
                  l10n.reminderNext(
                    format.when(
                      slot.nextFire(
                        widget.now,
                        sentOn: sentAfterSave(widget.editing, slot, widget.now),
                      ),
                    ),
                  ),
                  key: const ValueKey('reminder-sheet-next'),
                  style: TextStyle(color: t.textMuted),
                ),
              ],
              if (_refused) ...[
                const SizedBox(height: HlSpace.s3),
                Text(
                  l10n.reminderDuplicate,
                  key: const ValueKey('reminder-sheet-duplicate'),
                  style: TextStyle(color: t.error),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HlSpace.s5,
            HlSpace.s3,
            HlSpace.s5,
            HlSpace.s5,
          ),
          child: _ActionPair(
            labels: [
              if (widget.editing == null) l10n.cancel else l10n.delete,
              l10n.save,
            ],
            children: [
              SizedBox(
                width: double.infinity,
                child: widget.editing == null
                    ? OutlinedButton(
                        key: const ValueKey('reminder-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: HlWordWrapText(l10n.cancel),
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey('reminder-delete'),
                        onPressed: () =>
                            Navigator.of(context).pop(const _Delete()),
                        icon: const Icon(Icons.delete_outline),
                        label: HlWordWrapText(l10n.delete),
                      ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('reminder-save'),
                  onPressed: slot == null
                      ? null
                      : () {
                          if (widget.taken(slot)) {
                            setState(() => _refused = true);
                          } else {
                            Navigator.of(context).pop(_Save(slot));
                          }
                        },
                  child: HlWordWrapText(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The sheet's two buttons side by side, or, when a label would not fit
/// half the width at the reader's text size, one above the other at full
/// width, so neither label breaks inside a word (Peter: menus and their
/// pages wrap at twice the text size).
class const _ActionPair({
  required final List<String> labels,
  required final List<Widget> children,
}) extends StatelessWidget {
  /// A button's room besides its label: its insets and an icon.
  static const _chrome = 72.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.labelLarge!;
      final half = (constraints.maxWidth - HlSpace.s3) / 2;
      final fits = labels.every((label) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width + _chrome <= half;
      });
      return fits
          ? Row(
              spacing: HlSpace.s3,
              children: [for (final child in children) Expanded(child: child)],
            )
          : Column(spacing: HlSpace.s2, children: children);
    },
  );
}

String _two(int n) => n.toString().padLeft(2, '0');
