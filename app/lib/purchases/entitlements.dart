import 'dart:async';
import 'dart:math' show max;

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

/// One premium row, of the household as members may read it (H-55) or of
/// the signed-in user as only they may (`user_entitlements`, job 185).
@immutable
class const PremiumRow({
  required final PremiumSource source,

  /// Yearly and promotional: premium from this row ends here (a promotional
  /// grant without one never ends).
  final DateTime? expiresAt,

  /// Yearly only: the plan renews at [expiresAt].
  final bool? autoRenew,

  /// A row of the signed-in user's own `user_entitlements`.
  final bool own = false,
}) {
  /// Never ends: Lifetime, a promotional grant without end.
  bool get endless =>
      source.lasting ||
      (source == PremiumSource.promotional && expiresAt == null);

  bool activeAt(DateTime now) => endless || (expiresAt?.isAfter(now) ?? false);

  /// A promotional grant for good: without end, or to [testerGrantEnd]
  /// (RevenueCat's API needs an end).
  bool get forGood =>
      source == PremiumSource.promotional &&
      !(expiresAt?.isBefore(testerGrantEnd) ?? false);
}

/// Whose free unlock (a RevenueCat promotional grant) premium comes from.
enum FreeUnlock() {
  /// A beta household's grant with an end (Legal Review N-70).
  beta,

  /// Testers and app review: a household's grant for good.
  tester,

  /// A beta account's own grant for good (job 371): lifetime, as thanks for
  /// the beta.
  betaLifetime,
}

/// Premium in the shown household at one moment: the server's rule
/// (`household_premium`, `user_premium`) applied to the rows.
sealed class const Premium();

final class const NoPremium() extends Premium;

final class const ActivePremium(
  final PremiumSource source, {

  /// Yearly or promotional: the latest end of the active rows that end.
  final DateTime? expiresAt,

  /// Yearly: one of the active plans renews.
  final bool renews = false,

  /// Promotional: whose free unlock it is; null for any other source.
  final FreeUnlock? free,
}) extends Premium;

/// Where testers', app review's and beta accounts' promotional grants for
/// good end (`testerGrantEnd` in scripts/iap/promotional.ts).
final testerGrantEnd = DateTime.utc(2100);

/// What the signed-in user has unlocked in the shown household, as the rows
/// say. Nothing is gated by it yet.
sealed class const EntitlementsState();

/// No household, or the rows could not be read yet (loading, offline).
final class const EntitlementsUnknown() extends EntitlementsState;

final class const EntitlementsKnown({
  required final String householdId,
  required final Unlocks unlocks,
}) extends EntitlementsState;

/// The premium rows that count in one household for the signed-in user: the
/// household's and the user's own (a purchase bound to the user unlocks
/// premium in every household they are in; job 185). Other members never
/// read the user's rows (RLS), so it is premium for the buyer only.
@immutable
class const Unlocks({
  final List<PremiumRow> rows = const [],

  /// One of them is a RevenueCat promotional grant (testers, App and Play
  /// Review; 20261101150000_testers_via_revenuecat.sql): the events are
  /// internal, as the server's `household_internal` and `user_internal` say.
  final bool tester = false,

  /// The most store purchases of Lifetime one owner (the household, the
  /// user) has; two or more and that owner paid twice, which only Apple or
  /// Google can refund.
  final int lifetimePurchases = 0,

  /// A row is a store purchase (yearly or Lifetime), not only promotional
  /// grants: someone paid, so refund help applies (Legal Review N-346).
  final bool purchased = false,

  /// Each owner's yearly plans: one owner's two running at once were bought
  /// from two store accounts. The household's plan next to the user's is
  /// not.
  final List<List<PremiumRow>> yearlyByOwner = const [],
}) {
  /// The household's [Unlocks] and the user's [own]: premium over all rows,
  /// paying twice per owner.
  Unlocks merge(Unlocks own) => Unlocks(
    rows: [...rows, ...own.rows],
    tester: tester || own.tester,
    lifetimePurchases: max(lifetimePurchases, own.lifetimePurchases),
    purchased: purchased || own.purchased,
    yearlyByOwner: [...yearlyByOwner, ...own.yearlyByOwner],
  );

  /// Premium from the user's own rows only (`user_premium`): what the
  /// integration gate counts. A household's plan or grant is not in it.
  Premium ownPremiumAt(DateTime now) => Unlocks(
    rows: [
      for (final r in rows)
        if (r.own) r,
    ],
  ).premiumAt(now);

  /// One owner has two yearly plans running at [now].
  bool twoYearlyAt(DateTime now) => yearlyByOwner.any(
    (plans) => plans.where((r) => r.activeAt(now)).length >= 2,
  );

  /// Lifetime or a promotional grant without end first (in that order); else
  /// the yearly plan or promotional grant that ends last, with its end; else
  /// none. The server's `household_premium` and `user_premium`, row by row.
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
        return ActivePremium(source, free: _freeAt(source, now));
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
      free: _freeAt(last.source, now),
    );
  }

  /// Whose free unlock premium from [source] is: the user's own grant for
  /// good first, then a household's for good, else a beta household's.
  FreeUnlock? _freeAt(PremiumSource source, DateTime now) {
    if (source != PremiumSource.promotional) {
      return null;
    }
    final forGood = [
      for (final r in rows)
        if (r.forGood && r.activeAt(now)) r,
    ];
    return forGood.any((r) => r.own)
        ? FreeUnlock.betaLifetime
        : forGood.isNotEmpty
        ? FreeUnlock.tester
        : FreeUnlock.beta;
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

/// The household's `entitlements` rows and the user's own
/// `user_entitlements` rows. Only the server writes them.
abstract interface class EntitlementsSource() {
  /// Both kinds of rows, read together: premium shows only once both are
  /// known.
  Future<Unlocks> unlocks(String householdId, String userId);

  /// Calls [onChange] when a row of either may have changed, also after
  /// every (re)connect; returns the cancel.
  Future<void> Function() watch(
    String householdId,
    String userId,
    void Function() onChange,
  );
}

/// The household the session shows and its signed-in user.
typedef _Scope = ({String household, String user});

/// Follows the session's household and user, app-wide. Premium is computed
/// at read time from the rows, like the server's check: a yearly plan's end
/// turns it off without any event, so the state is read again when one
/// passes.
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
  _Scope? _scope;

  /// The household whose rows these are: the one the session shows.
  String? get householdId => _scope?.household;
  Future<void> Function()? _unwatch;
  Timer? _nextEnd;

  /// Counts the reads started; only the latest one may emit, so an older
  /// read that finishes last never overwrites a newer one.
  var _reads = 0;

  /// The clock premium is computed with (a test's fake one).
  DateTime get clock => now();

  /// Premium in the shown household now; null while unknown.
  Premium? get premium => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.premiumAt(now()),
    EntitlementsUnknown() => null,
  };

  /// The signed-in user's own premium now; null while unknown. Premium
  /// belongs to the account (Terms §6): the integration gate and Buy go by
  /// this, not by [premium], which also counts the household's rows.
  Premium? get ownPremium => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.ownPremiumAt(now()),
    EntitlementsUnknown() => null,
  };

  /// [entitlement] is unlocked in the shown household now; false while
  /// unknown.
  bool has(Entitlement entitlement) => premium is ActivePremium;

  /// The household, or the user, bought Lifetime more than once; false
  /// while unknown.
  bool get boughtLifetimeTwice => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.lifetimePurchases >= 2,
    EntitlementsUnknown() => false,
  };

  /// The household, or the user, has a store purchase; false while unknown
  /// and for promotional grants only.
  bool get purchased => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.purchased,
    EntitlementsUnknown() => false,
  };

  /// Two yearly plans of the household, or of the user, run at once (bought
  /// from two store accounts); false while unknown.
  bool get twoYearlyPlans => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.twoYearlyAt(now()),
    EntitlementsUnknown() => false,
  };

  /// A yearly plan of the household, or of the user, is still billed; false
  /// while unknown.
  bool get yearlyBilled => switch (state) {
    EntitlementsKnown(:final unlocks) => unlocks.yearlyBilledAt(now()),
    EntitlementsUnknown() => false,
  };

  /// Whether to offer [plan] of [entitlement] for sale: only when neither the
  /// household nor the user is known to have it. Without premium both plans;
  /// with an active yearly plan only Lifetime (the upgrade; never a second
  /// yearly plan, H-84); with Lifetime or a promotional grant (testers' too)
  /// nothing. While unknown (loading, offline) the answer is no, so no member
  /// pays twice. Every paywall entry point asks this, never [has].
  bool canOffer(Entitlement entitlement, PremiumPlan plan) =>
      switch (ownPremium) {
        null => false,
        NoPremium() => true,
        ActivePremium(source: PremiumSource.yearly) =>
          plan == PremiumPlan.lifetime,
        ActivePremium() => false,
      };

  void _follow(Session session) {
    final scope = switch (session) {
      InHousehold(:final household, :final userId) => (
        household: household.id,
        user: userId,
      ),
      _ => null,
    };
    if (scope == _scope) {
      return;
    }
    _scope = scope;
    unawaited(_unwatch?.call());
    _unwatch = null;
    _nextEnd?.cancel();
    emit(const EntitlementsUnknown());
    if (scope != null) {
      _unwatch = _source.watch(
        scope.household,
        scope.user,
        () => unawaited(refresh()),
      );
      unawaited(refresh());
    }
  }

  /// Reads the rows again; offline it keeps what it knew, and emits it again
  /// so that listeners compute premium at the new clock (a plan may have
  /// ended since).
  Future<void> refresh() async {
    final scope = _scope;
    if (scope == null) {
      return;
    }
    final read = ++_reads;
    Unlocks unlocks;
    try {
      unlocks = await _source.unlocks(scope.household, scope.user);
    } on Object {
      // The next (re)connect reads again. What is known is this scope's:
      // following another one forgets it.
      if (state case EntitlementsKnown(unlocks: final last)) {
        unlocks = last;
      } else {
        return;
      }
    }
    if (!isClosed && read == _reads && scope == _scope) {
      emit(EntitlementsKnown(householdId: scope.household, unlocks: unlocks));
      _wakeAtNextEnd(unlocks);
    }
  }

  /// RevenueCat's EXPIRATION updates the row and Realtime reads it again;
  /// this covers one that never arrives, for an end within a day. Later ends
  /// are rescheduled by any read before them (every reconnect reads).
  void _wakeAtNextEnd(Unlocks unlocks) {
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
/// dropped. One owner's rows: the household's and the user's share these
/// columns, each read on its own and joined with [Unlocks.merge]; [own]
/// marks the user's.
Unlocks unlocksOf(List<Map<String, dynamic>> rows, {bool own = false}) {
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
            own: own,
          ),
          null => null,
        },
        // No end (null): the grant never ends.
        PremiumSource.promotional => switch (row['expires_at']) {
          null => PremiumRow(source: PremiumSource.promotional, own: own),
          final at => switch (DateTime.tryParse('$at')) {
            final DateTime end => PremiumRow(
              source: PremiumSource.promotional,
              expiresAt: end,
              own: own,
            ),
            null => null,
          },
        },
        PremiumSource.lifetime => PremiumRow(
          source: PremiumSource.lifetime,
          own: own,
        ),
        null => null,
      },
  ];
  return Unlocks(
    rows: parsed,
    yearlyByOwner: [
      [
        for (final r in parsed)
          if (r.source == PremiumSource.yearly) r,
      ],
    ],
    tester: rows.any((row) => row['source'] == 'promotional'),
    lifetimePurchases: premium
        .where(
          (row) =>
              row['source'] == 'purchase' &&
              (row['premium_source'] ?? 'lifetime') == 'lifetime',
        )
        .length,
    purchased: premium.any((row) => row['source'] == 'purchase'),
  );
}

class const SupabaseEntitlementsSource(final SupabaseClient _client)
    implements EntitlementsSource {
  static const _columns =
      'kind, source, premium_source, expires_at, auto_renew';

  @override
  Future<Unlocks> unlocks(String householdId, String userId) async {
    final (household, own) = await (
      _client.rest
          .from('entitlements')
          .select(_columns)
          .eq('household_id', householdId),
      _client.rest
          .from('user_entitlements')
          .select(_columns)
          .eq('user_id', userId),
    ).wait;
    return unlocksOf(household).merge(unlocksOf(own, own: true));
  }

  @override
  Future<void> Function() watch(
    String householdId,
    String userId,
    void Function() onChange,
  ) {
    final channel = _client.channel('entitlements:$householdId:$userId');
    for (final (table, column, value) in [
      ('entitlements', 'household_id', householdId),
      ('user_entitlements', 'user_id', userId),
    ]) {
      final filter = PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: column,
        value: value,
      );
      channel
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (_) => onChange(),
        )
        // A yearly plan's renewal, cancellation or expiry updates its row.
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (_) => onChange(),
        )
        // Delete events cannot be filtered; another's costs a read.
        ..onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: table,
          callback: (_) => onChange(),
        );
    }
    channel
      // The join is confirmed before the server's Postgres listener runs; a
      // row written in between arrives only through the read on "Subscribed
      // to PostgreSQL".
      ..onSystemEvents((payload) {
        final Object? system = payload;
        if (system case {'extension': 'postgres_changes', 'status': 'ok'}) {
          onChange();
        }
      })
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
