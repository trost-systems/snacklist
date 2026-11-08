import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What deleting the account does to one of the user's households.
sealed class const HouseholdFate();

/// Others stay in [householdName] with the whole list.
final class const FateKept(
  final String householdName,
  final List<String> otherMemberNames,
) extends HouseholdFate;

/// The user is the last member, so [householdName] goes too.
final class const FateDeleted(
  final String householdName, {

  /// It has Hummlist Premium now, which ends with it (`leaves_unlocked`).
  final bool unlocked = false,
}) extends HouseholdFate;

/// A household the user archived (job 43). It has no members, so it is
/// deleted with the account (DECISIONS 43.11).
@immutable
class const ArchivedFate(final String name, {final bool unlocked = false});

/// Everything deleting the account takes with it besides the account.
@immutable
class const AccountFate(
  /// One per household the user is in; none without a household.
  final List<HouseholdFate> households, {
  final List<ArchivedFate> archived = const [],
}) {
  /// The households deleted with the account that have Hummlist Premium.
  Iterable<FateDeleted> get deletedPremium =>
      households.whereType<FateDeleted>().where((h) => h.unlocked);

  /// Hummlist Premium of some household ends with the account.
  bool get endsPremium =>
      deletedPremium.isNotEmpty || archived.any((a) => a.unlocked);
}

/// Whether the server revoked the app's Sign in with Apple grant.
enum AppleUnlink(final String wire) {
  revoked('revoked'),
  notLinked('not_linked'),

  /// No authorization code reached the server (web, Android, a failed
  /// re-authorization): the user removes the app in the iPhone's settings.
  manual('manual');

  static AppleUnlink parse(Object? wire) => values.firstWhere(
    (v) => v.wire == wire,
    // The account is gone either way; the hint is the safe answer.
    orElse: () => manual,
  );
}

@immutable
class const AccountDeleted(final AppleUnlink apple);

/// Nothing was deleted.
sealed class const AccountError() implements Exception;

final class const AccountOffline() extends AccountError;

/// The server refused or failed; [code] is its `error` field or the HTTP
/// status.
final class const AccountFailed(final String code) extends AccountError;

/// The user closed Apple's re-authorization sheet.
final class const AppleReauthCanceled() extends AccountError;

/// Parses an exception from the Supabase client.
AccountError accountErrorOf(Object error) => switch (error) {
  AccountError() => error,
  // Thrown by functions_client when the request never got an answer.
  FunctionsFetchException() => const AccountOffline(),
  FunctionException(details: {'error': final String code}) => AccountFailed(
    code,
  ),
  FunctionException(:final status) => AccountFailed('$status'),
  PostgrestException(:final code, :final message) => AccountFailed(
    code ?? message,
  ),
  // package:http on web and native (where it also implements
  // SocketException) when the server is unreachable.
  ClientException() || TimeoutException() => const AccountOffline(),
  _ => AccountFailed('${error.runtimeType}'),
};

/// A fresh Sign in with Apple authorization code, or null when none can be
/// had. Throws [SocialSignInCanceled] when the user backs out.
typedef AppleAuthorizationCode = Future<String?> Function();

/// The account section's only door to the backend.
abstract interface class AccountRepository() {
  /// The signed-in user's email address, or null when the sign-in has none.
  String? get email;

  /// Throws [AccountError].
  Future<AccountFate> fate();

  /// Deletes the account on the server, re-authorizing with Apple first
  /// where that is possible. Throws [AccountError]; then nothing was
  /// deleted.
  Future<AccountDeleted> delete();

  /// Everything the server keeps about the user, as indented JSON. Throws
  /// [AccountError].
  Future<String> export();
}

class SupabaseAccountRepository(
  final SupabaseClient _client, {

  /// Only where the platform's own Apple dialog exists (iOS).
  final AppleAuthorizationCode? _appleCode,

  /// The wait before the one retry of a delete the edge gateway dropped.
  final Duration _retryDelay = const Duration(seconds: 1),
}) implements AccountRepository {
  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  Future<AccountFate> fate() => _guard(() async {
    final (households, archived) = await (
      _householdFates(),
      _client.rpc<List<dynamic>>('archived_households'),
    ).wait;
    return AccountFate(
      households,
      archived: [
        for (final row in archived.cast<Map<String, dynamic>>())
          ArchivedFate(
            row['name']! as String,
            unlocked: row['unlocked'] == true,
          ),
      ],
    );
  });

  /// Each household's fate: kept for its other members, or deleted with
  /// its last one.
  Future<List<HouseholdFate>> _householdFates() async {
    final userId = _client.auth.currentUser?.id;
    final rows = await _client.rpc<List<dynamic>>('my_households');
    return await Future.wait([
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row case {'id': final String id, 'name': final String name})
          _fateOf(id, name, userId),
    ]);
  }

  Future<HouseholdFate> _fateOf(String id, String name, String? userId) async {
    final members = await _client.rpc<List<dynamic>>(
      'household_members_of',
      params: {'p_household': id},
    );
    final others = <String>[
      for (final row in members.whereType<Map<String, dynamic>>())
        if (row['user_id'] != userId)
          switch (row['display_name']) {
            final String name => name,
            _ => '',
          },
    ];
    if (others.isEmpty) {
      return FateDeleted(
        name,
        unlocked: await _client.rpc<bool>(
          'leaves_unlocked',
          params: {'p_household': id},
        ),
      );
    }
    return FateKept(name, [...others.where((n) => n.isNotEmpty)]);
  }

  @override
  Future<AccountDeleted> delete() => _guard(() async {
    final code = await _appleAuthorizationCode();
    final body = {'apple_authorization_code': ?code};
    FunctionResponse response;
    try {
      response = await _client.functions.invoke('account/delete', body: body);
    } on FunctionException catch (e) {
      if (!_droppedByGateway(e)) {
        rethrow;
      }
      // The edge runtime sometimes drops a call (an empty 503 on a cold
      // worker). The endpoint is idempotent: if the first call did delete,
      // the retry answers 200 all the same.
      await Future<void>.delayed(_retryDelay);
      response = await _client.functions.invoke('account/delete', body: body);
    }
    return switch (response.data) {
      {'deleted': true, 'apple': final Object? apple} => AccountDeleted(
        AppleUnlink.parse(apple),
      ),
      _ => throw const AccountFailed('bad_response'),
    };
  });

  @override
  Future<String> export() => _guard(() async {
    final data = await _client.rpc<Object?>('export_my_data');
    return const JsonEncoder.withIndent('  ').convert(data);
  });

  Future<String?> _appleAuthorizationCode() async {
    final appleCode = _appleCode;
    final linked =
        _client.auth.currentUser?.identities?.any(
          (i) => i.provider == 'apple',
        ) ??
        false;
    if (appleCode == null || !linked) {
      return null;
    }
    try {
      return await appleCode();
    } on SocialSignInCanceled {
      throw const AppleReauthCanceled();
    }
  }

  /// A gateway error, not one of the handler's answers, which always carry
  /// a JSON `error`.
  static bool _droppedByGateway(FunctionException e) =>
      const {502, 503, 504, 546}.contains(e.status) &&
      e.details is! Map<String, Object?>;

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object catch (e) {
      throw accountErrorOf(e);
    }
  }
}
