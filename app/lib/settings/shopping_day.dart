import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The shopping days of the signed-in person's reminder, as ISO weekdays
/// (1 Monday to 7 Sunday); none means the reminder is off (job 378,
/// docs/PUSH.md, "Shopping-day reminder").
abstract interface class ShoppingDayRepository() {
  Future<Set<int>> read();

  /// Saves the device's zone and the app language again, leaving the days
  /// and what was already sent alone.
  Future<void> refresh(String timeZone, String locale);

  /// Saves [weekdays] with the zone and language the server sends by; none
  /// switches the reminder off.
  Future<void> save(Set<int> weekdays, String timeZone, String locale);
}

class const SupabaseShoppingDayRepository(final SupabaseClient _client)
    implements ShoppingDayRepository {
  @override
  Future<Set<int>> read() async {
    final rows = await _client
        .from('shopping_day_reminders')
        .select('weekdays')
        .limit(1);
    return switch (rows) {
      [{'weekdays': final List<Object?> days}] => {
        for (final day in days)
          if (day is int) day,
      },
      _ => {},
    };
  }

  @override
  Future<void> refresh(String timeZone, String locale) async {
    await _client.rpc<void>(
      'refresh_shopping_day_reminder',
      params: {'p_time_zone': timeZone, 'p_locale': locale},
    );
  }

  @override
  Future<void> save(Set<int> weekdays, String timeZone, String locale) async {
    await _client.rpc<void>(
      'set_shopping_day_reminder',
      params: {
        'p_weekdays': weekdays.toList()..sort(),
        'p_time_zone': timeZone,
        'p_locale': locale,
      },
    );
  }
}

/// The IANA zone of this device, `Europe/Berlin` and the like.
abstract interface class DeviceTimeZone() {
  Future<String> name();
}

class const FlutterDeviceTimeZone() implements DeviceTimeZone {
  @override
  Future<String> name() async => ianaZone(
    (await FlutterTimezone.getLocalTimezone()).identifier,
    DateTime.now().timeZoneOffset,
  );
}

/// [id] when it is an IANA zone (`Europe/Berlin`, `UTC`); a device that
/// reports a bare offset (`GMT+01:00`) gets the fixed-offset zone of its
/// current [offset] (`Etc/GMT-1`, the sign is inverted in the IANA names).
/// Throws for an offset of no whole hour.
String ianaZone(String id, Duration offset) {
  if (id == 'UTC' || RegExp(r'^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$').hasMatch(id)) {
    return id;
  }
  if (offset.inMinutes % 60 != 0) {
    throw FormatException('no IANA zone for this device', id);
  }
  final hours = offset.inHours;
  return hours == 0
      ? 'Etc/UTC'
      : 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
}

/// What the server has, and whether this device gets the pushes for it.
@immutable
class const ShoppingDayLoad({
  required final Set<int> saved,
  required final bool pushOn,
}) {
  /// The weekdays as the chips show them.
  Set<int> get shown => pushOn ? saved : {};

  /// [saved] with [weekday] toggled when push is on here; with push off
  /// here a pick turns the reminder on for this device and adds the day to
  /// what the person already had, so a second device cannot wipe it.
  Set<int> toggled(int weekday) => pushOn && saved.contains(weekday)
      ? ({...saved}..remove(weekday))
      : {...saved, weekday};
}

/// What a tap on a weekday came to.
enum ShoppingDaySaved() {
  saved,

  /// The OS refuses notifications; nothing was saved.
  pushBlocked,

  /// The zone could not be read or the server did not take it.
  failed,
}

/// The reminder's reads and writes. A day picked asks for push first (the
/// OS prompt comes from here, never at start), then saves the days with
/// the device's time zone.
class ShoppingDayService(
  final ShoppingDayRepository repository,
  final DeviceTimeZone timeZone,

  /// `PushRegistration.optIn`: true when notifications are on.
  final Future<bool> Function() optInToPush,

  /// `PushRegistration.resume`, then whether push is on here: registers
  /// this device again where it still can, and never prompts.
  final Future<bool> Function() pushIsOn,

  /// `PushRegistration.forget`: the path a sign-out takes (docs/PUSH.md),
  /// for the last notification type turned off (Legal N-401, N-436).
  final Future<void> Function() forgetPush,

  /// Whether the household-add alert is on, so it still needs the token.
  final Future<bool> Function() householdAddOn, {

  /// A clear the server did not take, kept on the device with the account
  /// it belongs to, and sent again at the next start or sign-in of that
  /// account until the server takes it (Legal N-439, as for the alert).
  final Future<({String userId, String language})?> Function()? readPending,
  final Future<void> Function(({String userId, String language})?)?
  writePending,
}) {
  String? _userId;
  StreamSubscription<Session>? _sessions;
  Future<void>? _retry;

  /// Follows the signed-in account, so a pending clear is sent again for it
  /// (never for another account's) at each start and sign-in.
  void follow(StateStreamable<Session> session) {
    _follow(session.state);
    _sessions = session.stream.listen(_follow);
  }

  void _follow(Session session) {
    final user = switch (session) {
      InHousehold(:final userId) || NeedsHousehold(:final userId) => userId,
      SignedOut() => null,
      SessionLoading() => _userId,
    };
    if (user != _userId) {
      _userId = user;
      if (user != null) {
        unawaited(retryPendingClear());
      }
    }
  }

  Future<void> close() async {
    await _sessions?.cancel();
  }

  /// Sends a clear this account made while the server could not be reached,
  /// and forgets it once the server took it.
  Future<void> retryPendingClear() =>
      _retry ??= _retryOnce().whenComplete(() => _retry = null);

  Future<void> _retryOnce() async {
    final user = _userId;
    final pending = await readPending?.call();
    if (user == null || pending == null || pending.userId != user) {
      return;
    }
    try {
      // A clear needs no zone: the row goes, so a device whose zone cannot be
      // read still sends it.
      await repository.save({}, 'UTC', pending.language);
    } on Object {
      return;
    }
    await writePending?.call(null);
  }

  /// The person's saved weekdays (they are per person, not per device) and
  /// whether this device gets pushes. With push off here (signed out and in
  /// again, notifications refused since) the section shows no days, so it
  /// never promises a reminder that cannot come, but it keeps the saved ones
  /// for the next pick. With days saved and push on, the device's zone and
  /// the app's language are saved again, quietly, for a person who moved or
  /// switched language.
  Future<ShoppingDayLoad> load(String locale) async {
    await retryPendingClear();
    final saved = await repository.read();
    if (saved.isEmpty) {
      return ShoppingDayLoad(saved: saved, pushOn: true);
    }
    if (!await pushIsOn()) {
      return ShoppingDayLoad(saved: saved, pushOn: false);
    }
    unawaited(
      timeZone.name().then(
        (zone) => repository.refresh(zone, locale),
        onError: (Object _) {},
      ),
    );
    return ShoppingDayLoad(saved: saved, pushOn: true);
  }

  /// Whether any weekday is picked; false when it cannot be read, so the
  /// household-add alert's off takes the device off push rather than leave
  /// the token of a phone that cannot be asked (Legal N-436, N-401).
  Future<bool> hasDays() async {
    try {
      return (await repository.read()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<ShoppingDaySaved> save(Set<int> weekdays, String locale) async {
    // A retry still in flight must not land after this save.
    await _retry;
    if (weekdays.isNotEmpty && !await optInToPush()) {
      return ShoppingDaySaved.pushBlocked;
    }
    final last = weekdays.isEmpty && !await householdAddOn();
    if (last) {
      // No reminder left and the household-add alert off too: the last
      // notification type, so the device stops getting pushes, as after a
      // sign-out (offline catch-up included; Legal N-436). Before the save,
      // so a clear that cannot reach the server still takes this device off
      // push, as the alert's off does.
      try {
        await forgetPush();
      } on Object {
        // The save below still tells the server.
      }
    }
    final user = _userId;
    try {
      await repository.save(weekdays, await timeZone.name(), locale);
      await writePending?.call(null);
    } on Object {
      if (last && user != null) {
        await writePending?.call((userId: user, language: locale));
      }
      return ShoppingDaySaved.failed;
    }
    return ShoppingDaySaved.saved;
  }
}

/// Mitteilungen' section „Einkaufstag-Erinnerung“ (job 378, its own More
/// page since job 463) with the `push-shopping-day` flag: a chip for each
/// weekday; the evening before each picked one at 19:00 local the server
/// sends a push. A tap moves the chip at once; a save the server or the OS
/// refuses puts it back, with a notice. Nothing shows on web or without
/// push in the build (no [ShoppingDayService]).
class const ShoppingDaySettings({super.key}) extends StatefulWidget {
  @override
  State<ShoppingDaySettings> createState() => _ShoppingDaySettingsState();
}

class _ShoppingDaySettingsState() extends State<ShoppingDaySettings> {
  /// Null until the server answered; the read is made once the section
  /// shows.
  ShoppingDayLoad? _state;

  /// What the server last took, which a refused save goes back to.
  ShoppingDayLoad? _saved;
  var _asked = false;

  /// Picks reach the server one after another, each with the days shown
  /// when it was made; [_taps] tells the last one.
  Future<Object?> _queue = Future.value();
  var _taps = 0;

  Future<void> _load(ShoppingDayService service, String locale) async {
    try {
      final state = await service.load(locale);
      if (mounted) {
        setState(() => _state = _saved = state);
      }
    } on Object {
      _asked = false;
    }
  }

  Future<void> _toggle(ShoppingDayService service, int weekday) async {
    final before = _state;
    if (before == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final locale = _language(context);
    final after = ShoppingDayLoad(saved: before.toggled(weekday), pushOn: true);
    final tap = ++_taps;
    setState(() => _state = after);
    final saving = _queue
        .then((_) => service.save(after.saved, locale))
        .catchError((Object _) => ShoppingDaySaved.failed);
    _queue = saving;
    final result = await saving;
    if (!mounted) {
      return;
    }
    setState(() {
      if (result == ShoppingDaySaved.saved) {
        _saved = after;
      } else if (tap == _taps) {
        _state = _saved;
      }
    });
    switch (result) {
      case ShoppingDaySaved.saved:
        break;
      case ShoppingDaySaved.pushBlocked:
        notices.showSnackBar(SnackBar(content: Text(l10n.shoppingDayBlocked)));
      case ShoppingDaySaved.failed:
        notices.showSnackBar(SnackBar(content: Text(l10n.catalogSaveFailed)));
    }
  }

  /// The language the server writes the reminder in: German, else English.
  String _language(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'de' ? 'de' : 'en';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flag = context.select<Flags?, bool>(
      (flags) => flags?.isOn(shoppingDayFlag) ?? false,
    );
    final service = context.read<ShoppingDayService?>();
    if (!flag || service == null) {
      return const SizedBox.shrink();
    }
    if (!_asked) {
      _asked = true;
      unawaited(_load(service, _language(context)));
    }
    final days = _state?.shown;
    if (days == null) {
      return const SizedBox.shrink();
    }
    final tag = Localizations.localeOf(context).toLanguageTag();
    // 2024-01-01 was a Monday.
    DateTime day(int weekday) => DateTime(2024, 1, weekday);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(
          l10n.shoppingDayTitle,
          padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0),
        ),
        HlGroup(
          top: HlSpace.s2,
          children: [
            Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.shoppingDayHint),
                  const SizedBox(height: HlSpace.s3),
                  Wrap(
                    spacing: HlSpace.s2,
                    runSpacing: HlSpace.s2,
                    children: [
                      for (var weekday = 1; weekday <= 7; weekday++)
                        FilterChip(
                          key: ValueKey('shopping-day-$weekday'),
                          // The chip keeps its own button and selected
                          // semantics; only its words are the full name.
                          label: Semantics(
                            label: DateFormat.EEEE(tag).format(day(weekday)),
                            excludeSemantics: true,
                            child: Text(
                              DateFormat.E(tag)
                                  .format(day(weekday))
                                  .replaceAll('.', ''),
                            ),
                          ),
                          selected: days.contains(weekday),
                          onSelected: (_) =>
                              unawaited(_toggle(service, weekday)),
                        ),
                    ],
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
