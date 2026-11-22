import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The user's newest detected trip while the first-trip card is unseen.
@immutable
class const FirstDetectedTrip({
  required final String id,
  required final String householdId,

  /// Null for a trip without a store.
  required final String? storeName,
});

/// Trip detection for the signed-in person (job 352, `my_trip_detection`):
/// whether it is on, and whether the first-trip card was seen.
@immutable
class const TripDetection({
  required final bool on,
  required final bool cardSeen,
  final FirstDetectedTrip? firstTrip,
}) {
  /// Throws a [FormatException] for an answer of another shape.
  factory fromJson(Object? json) {
    if (json case {'on': final bool on, 'card_seen': final bool seen}) {
      return TripDetection(
        on: on,
        cardSeen: seen,
        firstTrip: switch (json['first_trip']) {
          {'id': final String id, 'household_id': final String household} &&
              final Map<String, Object?> trip =>
            FirstDetectedTrip(
              id: id,
              householdId: household,
              storeName: trip['store_name'] as String?,
            ),
          _ => null,
        },
      );
    }
    throw FormatException('my_trip_detection: unexpected answer', json);
  }

  TripDetection copyWith({bool? on, bool? cardSeen}) => TripDetection(
    on: on ?? this.on,
    cardSeen: cardSeen ?? this.cardSeen,
    firstTrip: firstTrip,
  );

  /// The trip the first-trip card names, while it is unseen.
  FirstDetectedTrip? get card => cardSeen ? null : firstTrip;
}

/// Trip detection's door to the backend. A failure throws.
abstract interface class TripDetectionRepository() {
  Future<TripDetection> fetch();

  /// `set_trip_detection`: off forgets the person's unfrozen detected trips.
  Future<void> setOn({required bool on});

  /// `seen_detected_trip_card`.
  Future<void> seenCard();
}

class SupabaseTripDetection(final SupabaseClient _client)
    implements TripDetectionRepository {
  @override
  Future<TripDetection> fetch() async =>
      TripDetection.fromJson(await _client.rpc<Object?>('my_trip_detection'));

  @override
  Future<void> setOn({required bool on}) async {
    await _client.rpc<void>('set_trip_detection', params: {'p_on': on});
  }

  @override
  Future<void> seenCard() async {
    await _client.rpc<void>('seen_detected_trip_card');
  }
}

/// What the person's trip detection is; null until the server answered.
class TripDetectionCubit(
  /// Looked up at the first call: with the flag off none is made.
  final TripDetectionRepository Function() _find, {

  /// The `learned-order` flag: off, nothing is read.
  required final bool Function() enabled,
}) extends Cubit<TripDetection?> {
  this : super(null);

  late final _repo = _find();

  /// Counts [setOn]s: a read that started before the last one answers
  /// from before it.
  var _switches = 0;

  /// Reads it again; a failure keeps what is known.
  Future<void> refresh() async {
    if (!enabled()) {
      return;
    }
    final switches = _switches;
    try {
      final detection = await _repo.fetch();
      if (!isClosed && switches == _switches) {
        emit(detection);
      }
    } on Object {
      return;
    }
  }

  /// The settings switch: shown at once, back as it was when the server
  /// did not take it. Whether it did.
  Future<bool> setOn({required bool on}) async {
    final before = state;
    if (before == null) {
      return false;
    }
    _switches++;
    emit(before.copyWith(on: on));
    try {
      await _repo.setOn(on: on);
      return true;
    } on Object {
      if (!isClosed) {
        emit(before);
      }
      return false;
    }
  }

  /// The first-trip card's „Ansehen“ or „Verstanden“: it goes at once and
  /// for good; a failed call shows it again on the next read.
  Future<void> seenCard() async {
    if (state case final detection?) {
      emit(detection.copyWith(cardSeen: true));
    }
    try {
      await _repo.seenCard();
    } on Object {
      return;
    }
  }
}

/// The list's card after the person's first detected trip, once (job 352).
class const DetectedTripCard({
  required final String? storeName,
  required final VoidCallback onView,
  required final VoidCallback onDone,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
      child: Semantics(
        container: true,
        child: HlSticker(
          key: const ValueKey('detected-card'),
          depth: StickerDepth.s,
          color: t.mintSoft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HlSpace.s3,
              HlSpace.s3,
              HlSpace.s3,
              HlSpace.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s1,
              children: [
                // Its own node: merged into the card's container, the
                // whole card became the header (a banner landmark on web).
                Semantics(
                  container: true,
                  header: true,
                  child: Text(switch (storeName) {
                    final store? => l10n.detectedCardTitle(store),
                    null => l10n.detectedCardTitleNoStore,
                  }, style: HlType.title.copyWith(color: t.text)),
                ),
                Text(
                  l10n.detectedCardBody,
                  style: HlType.body.copyWith(color: t.textMuted),
                ),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: HlSpace.s2,
                  children: [
                    TextButton(
                      key: const ValueKey('detected-card-view'),
                      onPressed: onView,
                      child: Text(l10n.detectedCardView),
                    ),
                    FilledButton(
                      key: const ValueKey('detected-card-done'),
                      onPressed: onDone,
                      child: Text(l10n.detectedCardGotIt),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Einstellungen' section with the switch „Einkäufe aus meinen Häkchen
/// erkennen“ (job 352): with the `learned-order` flag, once the server told
/// whether it is on. Still unknown when it opens (the start's read failed),
/// it asks once more.
class const DetectTripsSettings({super.key}) extends StatefulWidget {
  @override
  State<DetectTripsSettings> createState() => _DetectTripsSettingsState();
}

class _DetectTripsSettingsState() extends State<DetectTripsSettings> {
  var _asked = false;

  Future<void> _set(TripDetectionCubit detection, {required bool on}) async {
    final notices = Notices.of(context);
    final failed = AppLocalizations.of(context).catalogSaveFailed;
    if (!await detection.setOn(on: on)) {
      notices.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final flag = context.select<Flags?, bool>(
      (flags) => flags?.isOn(learnedOrderFlag) ?? false,
    );
    final detection = context.watch<TripDetectionCubit?>();
    final on = detection?.state?.on;
    if (!flag || detection == null || on == null) {
      if (flag && detection != null && !_asked) {
        _asked = true;
        unawaited(detection.refresh());
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(
          l10n.settingsTrips,
          padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0),
        ),
        HlGroup(
          top: HlSpace.s2,
          children: [
            HexSwitchTile(
              key: const ValueKey('settings-detect-trips'),
              leading: HlRowHex(Icons.route_outlined, face: t.surfaceSunken),
              title: Text(l10n.detectTrips),
              subtitle: Text(l10n.detectTripsHint),
              isThreeLine: true,
              value: on,
              onChanged: (on) => unawaited(_set(detection, on: on)),
            ),
          ],
        ),
      ],
    );
  }
}
