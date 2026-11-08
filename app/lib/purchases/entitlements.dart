import 'dart:async';

import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// What a household can have unlocked (`entitlements.kind`). Both products
/// grant premium; a later running-cost entitlement adds its own kind, which
/// never unlocks premium's features (docs/PURCHASES.md, "A second
/// entitlement").
enum Entitlement(final String wire) {
  premium('premium');

  /// Null for a kind this build does not know. `lifetime` is the kind's wire
  /// value before job 49's migration: it still reads as premium, so a row the
  /// migration has not reached yet keeps working. Remove the alias once that
  /// migration runs on every project the app talks to (it is in production
  /// with the job 49 deploy; DECISIONS 49.2).
  static Entitlement? parse(Object? wire) => wire == 'lifetime'
      ? premium
      : values.where((v) => v.wire == wire).firstOrNull;
}

/// How a row grants premium (`entitlements.premium_source`).
enum PremiumSource(final String wire) {
  yearly('yearly'),
  lifetime('lifetime'),

  /// A RevenueCat promotional grant (dashboard or API; testers' too): it ends
  /// at its `expires_at`, or never when that is null (docs/PURCHASES.md,
  /// "Free premium: RevenueCat promotional grants").
  promotional('promotional');

  /// Lifetime never ends and wins over a yearly plan. A promotional grant
  /// without end does too ([PremiumRow.endless]).
  bool get lasting => this == lifetime;

  static PremiumSource? parse(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull;
}

/// One premium row of the household, as members may read it (H-55).
@immutable
class const PremiumRow({
  required final PremiumSource source,

  /// Yearly and promotional: premium from this row ends here (a promotional
  /// grant without one never ends).
  final DateTime? expiresAt,

  /// Yearly only: the plan renews at [expiresAt].
  final bool? autoRenew,
}) {
  /// Never ends: Lifetime, a promotional grant without end.
  bool get endless =>
      source.lasting ||
      (source == PremiumSource.promotional && expiresAt == null);

  bool activeAt(DateTime now) => endless || (expiresAt?.isAfter(now) ?? false);
}

/// The household's premium at one moment: the server's rule
/// (`household_premium`) applied to the rows.
sealed class const Premium();

final class const NoPremium() extends Premium;

final class const ActivePremium(
  final PremiumSource source, {

  /// Yearly or promotional: the latest end of the active rows that end.
  final DateTime? expiresAt,

  /// Yearly: one of the active plans renews.
  final bool renews = false,
}) extends Premium {
  /// A promotional grant for testers or app review: without end, or to
  /// [testerGrantEnd] as `scripts/iap/promotional.ts grant` gives it. A beta
  /// household's grant ends before (Legal Review N-70).
  bool get testerGrant =>
      source == PremiumSource.promotional &&
      (expiresAt == null || !expiresAt!.isBefore(testerGrantEnd));
}

/// Where testers' and app review's promotional grants end
/// (`testerGrantEnd` in scripts/iap/promotional.ts).
final testerGrantEnd = DateTime.utc(2100);

/// What the household has unlocked, as its rows say. Nothing is gated by it
/// yet.
sealed class const EntitlementsState();

/// No household, or its rows could not be read yet (loading, offline).
final class const EntitlementsUnknown() extends EntitlementsState;

final class const EntitlementsKnown({
  required final String householdId,
  required final HouseholdUnlocks unlocks,
}) extends EntitlementsState;

/// A household's premium rows.
@immutable
class const HouseholdUnlocks({
  final List<PremiumRow> rows = const [],

  /// One of them is a RevenueCat promotional grant (testers, App and Play
  /// Review; 20261101150000_testers_via_revenuecat.sql): the household's
  /// events are internal, as the server's `household_internal` says.
  final bool tester = false,

  /// How many store purchases of Lifetime it has; two or more and the
  /// household paid twice, which only Apple or Google can refund.
  final int lifetimePurchases = 0,
}) {
  /// Lifetime or a promotional grant without end first (in that order); else
  /// the yearly plan or promotional grant that ends last, with its end; else
  /// none. The server's `household_premium`, row by row.
  Premium premiumAt(DateTime now) {
    final endless = {
      for (final r in rows)
        if (r.endless) r.source,
    };
    for (final source in const [
      PremiumSource.lifetime,
      PremiumSource.promotional,
    ]) {
      if (endless.contains(source)) {
        return ActivePremium(source);
      }
    }
    final ending = _ending(now);
    if (ending.isEmpty) {
      return const NoPremium();
    }
    // The latest end names it; on a tie the yearly plan (it renews).
    final last = ending.reduce(
      (a, b) =>
          b.expiresAt!.isAfter(a.expiresAt!) ||
              (b.expiresAt == a.expiresAt && b.source == PremiumSource.yearly)
          ? b
          : a,
    );
    return ActivePremium(
      last.source,
      expiresAt: last.expiresAt,
      renews:
          last.source == PremiumSource.yearly &&
          activeYearly(now).any((r) => r.autoRenew ?? false),
    );
  }

  /// The rows with an end that have not ended at [now].
  List<PremiumRow> _ending(DateTime now) => [
    for (final r in rows)
      if (!r.endless && r.activeAt(now)) r,
  ];

  /// The yearly plans that have not ended at [now].
  List<PremiumRow> activeYearly(DateTime now) => [
    for (final r in rows)
      if (r.source == PremiumSource.yearly && r.activeAt(now)) r,
  ];

  /// A yearly plan is still being billed: it has not ended and renews. True
  /// also next to Lifetime (bought while a yearly plan ran).
  bool yearlyBilledAt(DateTime now) =>
      activeYearly(now).any((r) => r.autoRenew ?? false);

  /// The next moment a yearly plan or promotional grant ends, after [now]:
  /// premium may change then without any row changing.
  DateTime? nextEndAfter(DateTime now) =>
      _ending(now)
          .map((r) => r.expiresAt!)
          .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
}

/// The household's `entitlements` rows. Only the server writes them.
abstract interface class EntitlementsSource() {
  Future<HouseholdUnlocks> unlocks(String householdId);

  /// Calls [onChange] when a row may have changed, also after every
  /// (re)connect; returns the cancel.
  Future<void> Function() watch(String householdId, void Function() onChange);
}

/// Follows the session's household, app-wide. Premium is computed at read
/// time from the rows, like the server's check: a yearly plan's end turns it
/// off without any event, so the state is read again when one passes.
class Entitlements(
  final EntitlementsSource _source,
  final SessionCubit _session, {
  final DateTime Function() now = DateTime.now,
}) extends Cubit<EntitlementsState> {
  this : super(const EntitlementsUnknown()) {
    _follow(_session.state);
    _sessions = _session.stream.listen(_follow);
  }

  late final StreamSubscription<Session> _sessions;
  String? _householdId;

  /// The household whose rows these are: the one the session shows.
  String? get householdId => _householdId;
  Future<void> Function()? _unwatch;
  Timer? _nextEnd;

  /// Counts the reads started; only the latest one may emit, so an older
  /// read that finishes last never overwrites a newer one.
  var _reads = 0;

  /// The clock premium is computed with (a test's fake one).
  DateTime get clock => now();

  /// The household's premium now; null while unknown.
  Premium? get premium => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.premiumAt(now()),
    EntitlementsUnknown() => null,
  };

  /// The household has [entitlement] now; false while unknown.
  bool has(Entitlement entitlement) => premium is ActivePremium;

  /// The household bought Lifetime more than once; false while unknown.
  bool get boughtLifetimeTwice => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.lifetimePurchases >= 2,
    EntitlementsUnknown() => false,
  };

  /// Two yearly plans run at once (bought from two store accounts); false
  /// while unknown.
  bool get twoYearlyPlans => switch (state) {
    EntitlementsKnown(:final unlocks) =>
      unlocks.activeYearly(now()).length >= 2,
    EntitlementsUnknown() => false,
  };

  /// A yearly plan of the household is still billed; false while unknown.
  bool get yearlyBilled => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.yearlyBilledAt(now()),
    EntitlementsUnknown() => false,
  };

  /// Whether to offer [plan] of [entitlement] for sale: only when the
  /// household is known not to have it. Without premium both plans; with an
  /// active yearly plan only Lifetime (the upgrade; never a second yearly
  /// plan, H-84); with Lifetime or a promotional grant (testers' too)
  /// nothing. While unknown (loading, offline) the answer is no, so no member
  /// pays twice. Every paywall entry point asks this, never [has].
  bool canOffer(Entitlement entitlement, PremiumPlan plan) => switch (premium) {
    null => false,
    NoPremium() => true,
    ActivePremium(source: PremiumSource.yearly) => plan == PremiumPlan.lifetime,
    ActivePremium() => false,
  };

  void _follow(Session session) {
    final householdId = switch (session) {
      InHousehold(:final household) => household.id,
      _ => null,
    };
    if (householdId == _householdId) {
      return;
    }
    _householdId = householdId;
    unawaited(_unwatch?.call());
    _unwatch = null;
    _nextEnd?.cancel();
    emit(const EntitlementsUnknown());
    if (householdId != null) {
      _unwatch = _source.watch(householdId, () => unawaited(refresh()));
      unawaited(refresh());
    }
  }

  /// Reads the household's rows again; offline it keeps what it knew, and
  /// emits it again so that listeners compute premium at the new clock (a
  /// plan may have ended since).
  Future<void> refresh() async {
    final householdId = _householdId;
    if (householdId == null) {
      return;
    }
    final read = ++_reads;
    HouseholdUnlocks unlocks;
    try {
      unlocks = await _source.unlocks(householdId);
    } on Object {
      // The next (re)connect reads again.
      if (state
          case EntitlementsKnown(householdId: final known, unlocks: final last)
          when known == householdId) {
        unlocks = last;
      } else {
        return;
      }
    }
    if (!isClosed && read == _reads && householdId == _householdId) {
      emit(EntitlementsKnown(householdId: householdId, unlocks: unlocks));
      _wakeAtNextEnd(unlocks);
    }
  }

  /// RevenueCat's EXPIRATION updates the row and Realtime reads it again;
  /// this covers one that never arrives, for an end within a day. Later ends
  /// are rescheduled by any read before them (every reconnect reads).
  void _wakeAtNextEnd(HouseholdUnlocks unlocks) {
    _nextEnd?.cancel();
    final at = now();
    final end = unlocks.nextEndAfter(at);
    if (end != null && end.difference(at) <= const Duration(days: 1)) {
      _nextEnd = Timer(
        end.difference(at) + const Duration(seconds: 1),
        () => unawaited(refresh()),
      );
    }
  }

  @override
  Future<void> close() async {
    _nextEnd?.cancel();
    await _sessions.cancel();
    await _unwatch?.call();
    await super.close();
  }
}

/// The rows this build understands, whether one is a promotional grant, and
/// how many are Lifetime purchases. A row without `premium_source` (a server
/// before job 49) is Lifetime; one with a source this build does not know is
/// dropped.
HouseholdUnlocks unlocksOf(List<Map<String, dynamic>> rows) {
  final premium = [
    for (final row in rows)
      if (Entitlement.parse(row['kind']) == Entitlement.premium) row,
  ];
  final parsed = [
    for (final row in premium)
      // A later server's kind (null here) unlocks nothing in this build.
      ?switch (switch (row['premium_source']) {
        null => PremiumSource.lifetime,
        final wire => PremiumSource.parse(wire),
      }) {
        PremiumSource.yearly => switch (DateTime.tryParse(
          '${row['expires_at']}',
        )) {
          final DateTime end => PremiumRow(
            source: PremiumSource.yearly,
            expiresAt: end,
            autoRenew: row['auto_renew'] == true,
          ),
          null => null,
        },
        // No end (null): the grant never ends.
        PremiumSource.promotional => switch (row['expires_at']) {
          null => const PremiumRow(source: PremiumSource.promotional),
          final at => switch (DateTime.tryParse('$at')) {
            final DateTime end => PremiumRow(
              source: PremiumSource.promotional,
              expiresAt: end,
            ),
            null => null,
          },
        },
        PremiumSource.lifetime => const PremiumRow(
          source: PremiumSource.lifetime,
        ),
        null => null,
      },
  ];
  return HouseholdUnlocks(
    rows: parsed,
    tester: rows.any((row) => row['source'] == 'promotional'),
    lifetimePurchases: premium
        .where(
          (row) =>
              row['source'] == 'purchase' &&
              (row['premium_source'] ?? 'lifetime') == 'lifetime',
        )
        .length,
  );
}

class const SupabaseEntitlementsSource(final SupabaseClient _client)
    implements EntitlementsSource {
  @override
  Future<HouseholdUnlocks> unlocks(String householdId) async {
    final rows = await _client.rest
        .from('entitlements')
        .select('kind, source, premium_source, expires_at, auto_renew')
        .eq('household_id', householdId);
    return unlocksOf(rows);
  }

  @override
  Future<void> Function() watch(String householdId, void Function() onChange) {
    final channel = _client.channel('entitlements:$householdId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'entitlements',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'household_id',
          value: householdId,
        ),
        callback: (_) => onChange(),
      )
      // A yearly plan's renewal, cancellation or expiry updates its row.
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'entitlements',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'household_id',
          value: householdId,
        ),
        callback: (_) => onChange(),
      )
      // Delete events cannot be filtered; another household's costs a read.
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'entitlements',
        callback: (_) => onChange(),
      )
      ..subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          onChange();
        }
      });
    return () async {
      await _client.removeChannel(channel);
    };
  }
}
