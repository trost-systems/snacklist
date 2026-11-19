import 'dart:async';

import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Who an invite is for (docs/households/W2.md): one person for 7 days, or
/// a group link (owner and admins only) for up to 50 people and 30 days.
enum InviteKind() {
  person,
  group;

  static InviteKind parse(Object? kind) =>
      values.where((k) => k.name == kind).firstOrNull ?? person;
}

/// An open invite of one of the user's households.
@immutable
class const Invite({
  required final String id,
  required final String code,
  required final DateTime expiresAt,
  final InviteKind kind = InviteKind.person,

  /// How many may join with it: 1 for a person, up to 50 for a group.
  final int maxUses = 1,

  /// How many joined with it so far.
  final int useCount = 0,
}) {
  /// No one else can join with it.
  bool get full => useCount >= maxUses;
}

/// Someone who joined with an invite (`invite_joins`).
@immutable
class const InviteJoin({
  required final String userId,
  required final String displayName,
  required final DateTime joinedAt,
});

/// A household the user archived as its last member (job 43): no members,
/// its list and Snacklist Lifetime kept, until they re-enable it.
@immutable
class const ArchivedHousehold({
  required final String id,
  required final String name,
  required final DateTime archivedAt,
  required final bool unlocked,

  /// When it is deleted unless brought back: 24 months after archiving
  /// (the server's date). Null from a server before job 47.
  final DateTime? deletesAt,
});

/// What a code leads to, before joining (`preview_invite`).
sealed class const InvitePreview();

/// An open invite of the household [name], with what Snacklist Lifetime
/// means for joining it (job 43).
final class const InviteOpen(
  final String name, {
  final JoinLifetime lifetime = const JoinLifetime(),
}) extends InvitePreview;

/// Snacklist Lifetime around a join, as `preview_invite` tells it.
@immutable
class const JoinLifetime({
  /// The invite's household has it: nothing to buy there.
  final bool targetUnlocked = false,

  /// The user verified a purchase in the last 30 days that stands.
  final bool recentPurchase = false,
}) {
  /// Paid recently and moving into a household that has it anyway: the
  /// refund help is worth a link.
  bool get refundHelp => targetUnlocked && recentPurchase;
}

/// The user is in that household already: nothing to join.
final class const InviteMember(final String name) extends InvitePreview;

/// What a typed code leads to before signing in (`preview_invite_public`,
/// the public join page's answer, job 271): the same facts the join page
/// shows, or nothing.
sealed class const PublicInvite();

/// An open invite: the facts the join page shows (Legal N-112, N-151b).
final class const PublicInviteOpen({
  required final String household,

  /// The inviter's display name in full; null when their profile has no name
  /// of its own.
  required final String? inviter,
  required final int members,
  required final int openItems,
  required final bool premium,
}) extends PublicInvite;

/// Made up, expired, revoked, used or full: one answer for all, so a
/// guessed code tells nothing.
final class const PublicInviteUnavailable() extends PublicInvite;

/// Too many lookups from this client or of this code in the hour.
final class const PublicInviteRateLimited() extends PublicInvite;

/// The answer of `preview_invite_public` as a [PublicInvite], read like the
/// join page's `parsePreview`; an answer of another shape is
/// [HouseholdProblem.other], which the user can retry.
PublicInvite parsePublicInvite(Object? body) {
  final row = body is List ? body.firstOrNull : body;
  int? count(Object? n) => n is int && n >= 0 ? n : null;
  switch (row) {
    case {
      'status': 'ok',
      'household': final String household,
      'members': final Object? members,
      'open_items': final Object? openItems,
    }:
      final memberCount = count(members);
      final itemCount = count(openItems);
      if (memberCount != null && itemCount != null) {
        return PublicInviteOpen(
          household: household,
          inviter: switch (row['inviter']) {
            final String name when name.trim().isNotEmpty => name.trim(),
            _ => null,
          },
          members: memberCount,
          openItems: itemCount,
          premium: row['premium'] == true,
        );
      }
    case {'status': 'invalid' || 'full'}:
      return const PublicInviteUnavailable();
    case {'status': 'rate_limited'}:
      return const PublicInviteRateLimited();
  }
  throw const HouseholdError(HouseholdProblem.other);
}

/// A member of a household, as `household_members_of` answers.
@immutable
class const HouseholdMember({
  required final String userId,
  required final String displayName,
  final HouseholdRole role = HouseholdRole.member,
});

/// What deciding on a join request came to (`decide_join_request`).
enum JoinRequestOutcome() {
  approved,
  declined,

  /// The requester withdrew it meanwhile.
  cancelled,

  /// The invite the request came with has no use left (a full group link,
  /// a used person invite): nobody joined and the request stays open.
  inviteFull,
}

/// Someone waiting to join a household that confirms joins (job 169b W3
/// M), as `household_join_requests` answers.
@immutable
class const PendingJoin({
  required final String id,
  required final String userId,
  required final String displayName,
});

/// Why a household or invite call failed, as the screens tell the user.
enum HouseholdProblem() {
  /// Made up, expired, revoked or used: one answer for all.
  invalidInvite,

  /// 10 failed codes in the last hour.
  tooManyAttempts,

  /// No answer from the server.
  offline,

  /// The user is in 20 households already (`public.household_cap()`): no more.
  tooManyHouseholds,

  /// The user is not (or no longer) in that household.
  notMember,

  /// Only the owner and admins may do that (a group link, removing).
  notAdmin,

  /// Only the owner names and un-names admins.
  notOwner,

  /// The owner can't be removed, nor an admin by another admin, nor
  /// oneself (that is leaving).
  cannotRemove,

  /// The server's archive switch is off: nothing was archived or changed.
  archiveDisabled,

  /// An admin declined the user's request to join this household in the
  /// last 24 hours: no new request until then.
  declinedRecently,

  /// Anything else the server refused.
  other,
}

/// A household or invite call that failed; never carries the code.
final class const HouseholdError(final HouseholdProblem problem)
    implements Exception {
  /// The server's status or Postgres message, e.g. `invalid_invite`.
  factory fromStatus(String status) => HouseholdError(switch (status) {
    'invalid_invite' => HouseholdProblem.invalidInvite,
    'too_many_attempts' => HouseholdProblem.tooManyAttempts,
    'too_many_households' => HouseholdProblem.tooManyHouseholds,
    'not_member' || 'not_a_member' => HouseholdProblem.notMember,
    'not_admin' => HouseholdProblem.notAdmin,
    'not_owner' => HouseholdProblem.notOwner,
    'cannot_remove_owner' ||
    'cannot_remove_admin' ||
    'cannot_remove_self' => HouseholdProblem.cannotRemove,
    'archive_disabled' => HouseholdProblem.archiveDisabled,
    'declined_recently' => HouseholdProblem.declinedRecently,
    _ => HouseholdProblem.other,
  });

  @override
  String toString() => 'HouseholdError(${problem.name})';
}

/// How long a household call may take before it counts as offline.
const householdTimeout = Duration(seconds: 15);

/// Runs a household RPC: a Postgres error becomes its [HouseholdError], no
/// answer (a timeout, a failed fetch on the web, a socket error) is
/// [HouseholdProblem.offline].
Future<T> householdCall<T>(Future<T> Function() call) async {
  try {
    return await call().timeout(householdTimeout);
  } on PostgrestException catch (e) {
    throw HouseholdError.fromStatus(e.message);
  } on HouseholdError {
    rethrow;
  } on Object {
    throw const HouseholdError(HouseholdProblem.offline);
  }
}

/// Invites of the user's households: make one, list the open ones, revoke
/// one, who joined with one, and look at a code before joining; a
/// household's members (remove one, name admins) and archived households.
abstract interface class InviteRepository() {
  /// A new invite of [kind]. A group link while one is open answers the
  /// open one.
  Future<Invite> create(
    String householdId, {
    InviteKind kind = InviteKind.person,
  });

  /// Open invites (not revoked or expired; a full group link included),
  /// newest first (`household_invites`).
  Future<List<Invite>> open(String householdId);

  Future<void> revoke(String inviteId);

  /// Who joined with [inviteId], first joined first (`invite_joins`).
  Future<List<InviteJoin>> joins(String inviteId);

  /// Removes [userId] from [householdId] (owner and admins).
  Future<void> removeMember(String householdId, String userId);

  /// Names [userId] an admin of [householdId] or takes it back (owner).
  Future<void> setRole(String householdId, String userId, HouseholdRole role);

  Future<InvitePreview> preview(String code);

  /// What [code] leads to, signed in or not, as the public join page shows
  /// it (`preview_invite_public`, rate-limited per client and per code).
  Future<PublicInvite> previewPublic(String code);

  /// The members of [householdId], oldest first (`household_members_of`).
  Future<List<HouseholdMember>> members(String householdId);

  /// Whether [householdId] has Snacklist Premium that ends when its last
  /// member leaves (`leaves_unlocked`).
  Future<bool> leavesUnlocked(String householdId);

  /// The user's archived households, newest first (`archived_households`).
  Future<List<ArchivedHousehold>> archived();

  /// Whether an invite to [householdId] makes a join request instead of a
  /// member (owner and admins, `set_join_approval`).
  Future<void> setJoinApproval(String householdId, {required bool on});

  /// The join requests waiting in [householdId], oldest first (owner and
  /// admins, `household_join_requests`).
  Future<List<PendingJoin>> joinRequests(String householdId);

  /// Lets [requestId]'s user in, or not (owner and admins).
  Future<JoinRequestOutcome> decideJoinRequest(
    String requestId, {
    required bool approve,
  });

  /// Calls [onChange] when a join request in [householdId] comes or goes,
  /// as far as realtime tells; returns the call that stops it.
  Future<void> Function() watchJoinRequests(
    String householdId,
    void Function() onChange,
  );

  /// Which of the invites [ids] were accepted, and the display name of who
  /// did (empty when they have none).
  Future<Map<String, String>> accepted(List<String> ids);

  /// Calls [onChange] whenever an invite of [householdId] changes (one is
  /// accepted), and once subscribed, so a change before then counts too.
  /// Returns the unsubscribe.
  Future<void> Function() watch(String householdId, void Function() onChange);
}

class SupabaseInviteRepository(final SupabaseClient _client)
    implements InviteRepository {
  @override
  Future<Invite> create(
    String householdId, {
    InviteKind kind = InviteKind.person,
  }) => householdCall(() async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'create_invite',
      params: {'p_household': householdId, 'p_kind': kind.name},
    );
    return _invite(row);
  });

  @override
  Future<List<Invite>> open(String householdId) => householdCall(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'household_invites',
      params: {'p_household': householdId},
    );
    return [
      for (final row in rows.whereType<Map<String, dynamic>>()) _invite(row),
    ];
  });

  @override
  Future<List<InviteJoin>> joins(String inviteId) => householdCall(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'invite_joins',
      params: {'p_invite': inviteId},
    );
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row case {
          'user_id': final String userId,
          'joined_at': final String joinedAt,
        })
          InviteJoin(
            userId: userId,
            displayName: switch (row['display_name']) {
              final String name => name,
              _ => '',
            },
            joinedAt: DateTime.parse(joinedAt),
          ),
    ];
  });

  @override
  Future<void> removeMember(String householdId, String userId) => householdCall(
    () => _client.rpc<void>(
      'remove_member',
      params: {'p_household': householdId, 'p_user': userId},
    ),
  );

  @override
  Future<void> setRole(String householdId, String userId, HouseholdRole role) =>
      householdCall(
        () => _client.rpc<void>(
          'set_member_role',
          params: {
            'p_household': householdId,
            'p_user': userId,
            'p_role': role.name,
          },
        ),
      );

  @override
  Future<void> revoke(String inviteId) => householdCall(
    () => _client.rpc<void>('revoke_invite', params: {'p_invite': inviteId}),
  );

  @override
  Future<InvitePreview> preview(String code) => householdCall(() async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'preview_invite',
      params: {'p_code': code},
    );
    return switch (result) {
      {'status': 'ok', 'name': final String name} => InviteOpen(
        name,
        lifetime: JoinLifetime(
          targetUnlocked: result['unlocked'] == true,
          recentPurchase: result['recent_purchase'] == true,
        ),
      ),
      {'status': 'member', 'name': final String name} => InviteMember(name),
      {'status': final String status} => throw HouseholdError.fromStatus(
        status,
      ),
      _ => throw const HouseholdError(HouseholdProblem.other),
    };
  });

  @override
  Future<PublicInvite> previewPublic(String code) => householdCall(
    () async => parsePublicInvite(
      await _client.rpc<Object?>(
        'preview_invite_public',
        params: {'p_code': code},
      ),
    ),
  );

  @override
  Future<List<HouseholdMember>> members(String householdId) =>
      householdCall(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'household_members_of',
          params: {'p_household': householdId},
        );
        return [
          for (final row in rows.whereType<Map<String, dynamic>>())
            if (row case {'user_id': final String userId})
              HouseholdMember(
                userId: userId,
                displayName: switch (row['display_name']) {
                  final String name => name,
                  _ => '',
                },
                role: HouseholdRole.parse(row['role']),
              ),
        ];
      });

  @override
  Future<bool> leavesUnlocked(String householdId) => householdCall(
    () => _client.rpc<bool>(
      'leaves_unlocked',
      params: {'p_household': householdId},
    ),
  );

  @override
  Future<List<ArchivedHousehold>> archived() => householdCall(() async {
    final rows = await _client.rpc<List<dynamic>>('archived_households');
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        ArchivedHousehold(
          id: row['id']! as String,
          name: row['name']! as String,
          archivedAt: DateTime.parse(row['archived_at']! as String),
          unlocked: row['unlocked'] == true,
          deletesAt: switch (row['deletes_at']) {
            final String at => DateTime.parse(at),
            _ => null,
          },
        ),
    ];
  });

  @override
  Future<void> setJoinApproval(String householdId, {required bool on}) =>
      householdCall(
        () => _client.rpc<void>(
          'set_join_approval',
          params: {'p_household': householdId, 'p_on': on},
        ),
      );

  @override
  Future<List<PendingJoin>> joinRequests(String householdId) =>
      householdCall(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'household_join_requests',
          params: {'p_household': householdId},
        );
        return [
          for (final row in rows.whereType<Map<String, dynamic>>())
            if (row case {'id': final String id, 'user_id': final String user})
              PendingJoin(
                id: id,
                userId: user,
                displayName: switch (row['display_name']) {
                  final String name => name,
                  _ => '',
                },
              ),
        ];
      });

  @override
  Future<JoinRequestOutcome> decideJoinRequest(
    String requestId, {
    required bool approve,
  }) => householdCall(() async {
    final answer = await _client.rpc<Map<String, dynamic>>(
      'decide_join_request',
      params: {'p_request': requestId, 'p_approve': approve},
    );
    return switch (answer['status']) {
      'approved' => JoinRequestOutcome.approved,
      'declined' => JoinRequestOutcome.declined,
      'cancelled' => JoinRequestOutcome.cancelled,
      'invite_full' => JoinRequestOutcome.inviteFull,
      _ => throw const HouseholdError(HouseholdProblem.other),
    };
  });

  @override
  Future<void> Function() watchJoinRequests(
    String householdId,
    void Function() onChange,
  ) {
    final channel = _client.channel('join_requests:$householdId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'join_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'household_id',
          value: householdId,
        ),
        callback: (_) => onChange(),
      )
      ..subscribe();
    return () async {
      await _client.removeChannel(channel);
    };
  }

  @override
  Future<Map<String, String>> accepted(List<String> ids) =>
      householdCall(() async {
        if (ids.isEmpty) {
          return const {};
        }
        final rows = await _client.rest
            .from('invites')
            .select('id, used_by')
            .inFilter('id', ids)
            .not('used_at', 'is', null);
        final users = [
          ...rows.map<Object?>((row) => row['used_by']).whereType<String>(),
        ];
        final names = users.isEmpty
            ? const <String, String>{}
            : {
                for (final row
                    in await _client.rest
                        .from('profiles')
                        .select('id, display_name')
                        .inFilter('id', users))
                  row['id'] as String: row['display_name'] as String? ?? '',
              };
        return {
          for (final row in rows)
            row['id'] as String: names[row['used_by']] ?? '',
        };
      });

  @override
  Future<void> Function() watch(String householdId, void Function() onChange) {
    final channel = _client.channel('invites:$householdId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'invites',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'household_id',
          value: householdId,
        ),
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

  static Invite _invite(Map<String, dynamic> row) => Invite(
    id: row['id']! as String,
    code: row['code']! as String,
    expiresAt: DateTime.parse(row['expires_at']! as String),
    kind: InviteKind.parse(row['kind']),
    maxUses: switch (row['max_uses']) {
      final int n => n,
      _ => 1,
    },
    useCount: switch (row['use_count']) {
      final int n => n,
      _ => 0,
    },
  );
}
